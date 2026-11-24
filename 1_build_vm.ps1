#Requires -Version 5.1
<#
.SYNOPSIS
    IT 311 Final Lab - Task Area 01: build the VirtualBox VM from config.psd1.

.DESCRIPTION
    Creates and registers a Windows Server 2022 VM with the exact RAM, dynamic VDI,
    network mode and ISO attachment required by the reviewer. It deliberately does
    NOT use VBoxManage unattended installation, so Windows Setup lets you choose
    "(Desktop Experience)" and type the Administrator password yourself.

.PARAMETER ConfigPath
    Path to config.psd1. Defaults to the copy next to this script.

.PARAMETER Recreate
    Delete and rebuild the VM if it already exists. Destructive.

.PARAMETER Start
    Start the VM in the GUI after all checks pass.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\1_build_vm.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\1_build_vm.ps1 -Recreate -Start
#>
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$Recreate,
    [switch]$Start
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $PSScriptRoot 'config.psd1'
}

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
function Write-Header {
    param([string]$Text)
    Write-Host ''
    Write-Host ('=' * 74) -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ('=' * 74) -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Text)
    Write-Host ''
    Write-Host ">> $Text" -ForegroundColor Yellow
}

function Write-Ok {
    param([string]$Text)
    Write-Host "   [ OK ] $Text" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Text)
    Write-Host "   [FAIL] $Text" -ForegroundColor Red
}

function Write-Info {
    param([string]$Text)
    Write-Host "   $Text" -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
# Locate VBoxManage (PATH, registry, env var, known install folders)
# ---------------------------------------------------------------------------
function Resolve-VBoxManage {
    $command = Get-Command 'VBoxManage.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command -and $command.Source) { return [string]$command.Source }

    $candidates = New-Object System.Collections.Generic.List[string]
    if ($env:VBOX_MSI_INSTALL_PATH) {
        $candidates.Add((Join-Path $env:VBOX_MSI_INSTALL_PATH 'VBoxManage.exe'))
    }
    foreach ($key in @(
        'HKLM:\SOFTWARE\Oracle\VirtualBox',
        'HKLM:\SOFTWARE\WOW6432Node\Oracle\VirtualBox'
    )) {
        $item = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        if ($item -and $item.InstallDir) {
            $candidates.Add((Join-Path $item.InstallDir 'VBoxManage.exe'))
        }
    }
    $candidates.Add('C:\Program Files\Oracle\VirtualBox\VBoxManage.exe')
    $candidates.Add('D:\VirtualBox\VBoxManage.exe')
    $candidates.Add('C:\Program Files (x86)\Oracle\VirtualBox\VBoxManage.exe')

    foreach ($path in $candidates) {
        if ($path -and (Test-Path -LiteralPath $path)) { return [string]$path }
    }

    throw 'VBoxManage.exe was not found. Install Oracle VirtualBox, or add VBoxManage to PATH, then re-run this script.'
}

# ---------------------------------------------------------------------------
# Run VBoxManage and fail loudly on a non-zero exit code
# ---------------------------------------------------------------------------
function Invoke-VBox {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    # VBoxManage writes progress/warnings to stderr. With $ErrorActionPreference
    # set to Stop, Windows PowerShell 5.1 can turn that harmless output into a
    # terminating NativeCommandError, so capture it under Continue temporarily.
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $script:VBoxManage @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }

    if ($exitCode -ne 0) {
        $rendered = ($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
        throw ("VBoxManage {0} failed (exit {1}).{2}{3}" -f ($Arguments -join ' '), $exitCode, [Environment]::NewLine, $rendered)
    }
    return $output
}

# ---------------------------------------------------------------------------
# VirtualBox host interface discovery
# ---------------------------------------------------------------------------
function Get-BridgedInterfaces {
    $text = (@(Invoke-VBox @('list', 'bridgedifs')) | ForEach-Object { [string]$_ }) -join "`n"
    $chunks = [regex]::Split($text, '(?m)(?=^Name:)')
    foreach ($chunk in $chunks) {
        if ($chunk -notmatch '(?m)^Name:\s*(.+?)\s*$') { continue }
        $name = $Matches[1]
        $status = ''
        $mac = ''
        $wireless = ''
        if ($chunk -match '(?m)^Status:\s*(.+?)\s*$')            { $status = $Matches[1] }
        if ($chunk -match '(?m)^HardwareAddress:\s*([0-9A-Fa-f:]+)') { $mac = $Matches[1] }
        if ($chunk -match '(?m)^Wireless:\s*(.+?)\s*$')          { $wireless = $Matches[1] }
        [pscustomobject]@{
            Name     = $name
            Status   = $status
            Mac      = $mac
            Wireless = $wireless
        }
    }
}

function Get-HostOnlyInterfaces {
    $text = (@(Invoke-VBox @('list', 'hostonlyifs')) | ForEach-Object { [string]$_ }) -join "`n"
    $chunks = [regex]::Split($text, '(?m)(?=^Name:)')
    foreach ($chunk in $chunks) {
        if ($chunk -notmatch '(?m)^Name:\s*(.+?)\s*$') { continue }
        $name = $Matches[1]
        $status = ''
        if ($chunk -match '(?m)^Status:\s*(.+?)\s*$') { $status = $Matches[1] }
        [pscustomobject]@{ Name = $name; Status = $status }
    }
}

function Resolve-BridgeAdapter {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Requested,
        [Parameter(Mandatory = $true)]$Bridged
    )

    if ($Requested) {
        $exact = @($Bridged | Where-Object { $_.Name -ieq $Requested }) | Select-Object -First 1
        if ($exact) { return [string]$exact.Name }

        # Allow the Windows adapter friendly name (e.g. "Wi-Fi") as well.
        $netAdapter = Get-NetAdapter -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ieq $Requested -or $_.InterfaceDescription -ieq $Requested } |
            Select-Object -First 1
        if ($netAdapter) {
            $mac = ($netAdapter.MacAddress -replace '[-:]', '').ToUpperInvariant()
            $match = @($Bridged | Where-Object {
                $_.Name -ieq $netAdapter.InterfaceDescription -or
                (($_.Mac -replace ':', '').ToUpperInvariant() -eq $mac -and $mac -ne '')
            }) | Select-Object -First 1
            if ($match) { return [string]$match.Name }
        }

        $available = (@($Bridged | ForEach-Object { "  - $($_.Name)" }) -join [Environment]::NewLine)
        throw ("BridgeAdapter '{0}' is not a VirtualBox bridged interface.{1}Available interfaces:{1}{2}" -f $Requested, [Environment]::NewLine, $available)
    }

    # Auto-detect: prefer the physical NIC that owns the host's default route.
    $virtualPattern = 'VirtualBox|VMware|Hyper-V|Loopback|TAP-|Npcap|VPN'
    $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch $virtualPattern
    })

    $defaultIndexes = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty InterfaceIndex -ErrorAction SilentlyContinue)

    $ordered = New-Object System.Collections.Generic.List[object]
    foreach ($adapter in $adapters) {
        if ($defaultIndexes -contains $adapter.ifIndex) { $ordered.Add($adapter) }
    }
    foreach ($adapter in $adapters) {
        if (-not ($defaultIndexes -contains $adapter.ifIndex)) { $ordered.Add($adapter) }
    }

    foreach ($adapter in $ordered) {
        $mac = ($adapter.MacAddress -replace '[-:]', '').ToUpperInvariant()
        $match = @($Bridged | Where-Object {
            $_.Name -ieq $adapter.InterfaceDescription -or
            (($_.Mac -replace ':', '').ToUpperInvariant() -eq $mac -and $mac -ne '' -and $mac -ne '000000000000')
        }) | Select-Object -First 1
        if ($match -and $match.Status -ieq 'Up') {
            Write-Info "Auto-detected host NIC: $($adapter.Name) -> VirtualBox bridge '$($match.Name)'"
            return [string]$match.Name
        }
    }

    $upStreams = @($Bridged | Where-Object { $_.Status -ieq 'Up' -and $_.Name -notmatch 'VirtualBox' })
    if ($upStreams.Count -eq 1) {
        Write-Info "Auto-detected only active bridge: $($upStreams[0].Name)"
        return [string]$upStreams[0].Name
    }
    if ($upStreams.Count -eq 0) {
        throw 'No active physical host NIC was found for bridged networking. Connect a network adapter or set NetMode = ''nat'' in config.psd1.'
    }

    $available = (@($upStreams | ForEach-Object { "  - $($_.Name)" }) -join [Environment]::NewLine)
    throw ("Could not choose between multiple active bridges. Set BridgeAdapter in config.psd1 to one of:{0}{1}" -f [Environment]::NewLine, $available)
}

# ---------------------------------------------------------------------------
# Path helpers
# ---------------------------------------------------------------------------
function Resolve-IsoPath {
    param([string]$ConfiguredPath)

    if ($ConfiguredPath -and $ConfiguredPath.Trim()) {
        $expanded = [Environment]::ExpandEnvironmentVariables($ConfiguredPath.Trim())
        if (-not [System.IO.Path]::IsPathRooted($expanded)) {
            $expanded = Join-Path $PSScriptRoot $expanded
        }
        if (-not (Test-Path -LiteralPath $expanded -PathType Leaf)) {
            throw "ISOPath does not exist: $expanded`nFix ISOPath in config.psd1."
        }
        return (Resolve-Path -LiteralPath $expanded).Path
    }

    $isos = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.iso' -File -ErrorAction SilentlyContinue |
        Sort-Object Length -Descending)
    if ($isos.Count -eq 0) {
        throw "ISOPath is blank and no .iso file was found in $PSScriptRoot. Put the Windows Server 2022 ISO here or set ISOPath in config.psd1."
    }
    if ($isos.Count -gt 1) {
        $serverIsos = @($isos | Where-Object { $_.Name -match 'SERVER|2022|Windows' })
        if ($serverIsos.Count -eq 1) { return $serverIsos[0].FullName }
        $listing = (@($isos | ForEach-Object { "  - $($_.FullName)" }) -join [Environment]::NewLine)
        throw ("Multiple ISO files found. Set ISOPath in config.psd1 to the correct one:{0}{1}" -f [Environment]::NewLine, $listing)
    }
    return $isos[0].FullName
}

function Get-DefaultMachineFolder {
    $properties = @(Invoke-VBox @('list', 'systemproperties'))
    foreach ($line in $properties) {
        $text = [string]$line
        if ($text -match '^Default machine folder:\s*(.+?)\s*$') {
            return $Matches[1]
        }
    }
    return (Join-Path $env:USERPROFILE 'VirtualBox VMs')
}

function Get-RegisteredDiskUuid {
    param([Parameter(Mandatory = $true)][string]$Path)

    $uuid = ''
    foreach ($line in @(Invoke-VBox @('list', 'hdds'))) {
        $text = [string]$line
        if ($text -match '^UUID:\s+(.+?)\s*$') { $uuid = $Matches[1]; continue }
        if ($text -match '^Location:\s+(.+?)\s*$') {
            if ($Matches[1] -ieq $Path) { return $uuid }
        }
    }
    return $null
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
try {
    Write-Header 'IT 311 FINAL LAB - TASK AREA 01: VIRTUAL MACHINE BUILDER'

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "Configuration file not found: $ConfigPath"
    }
    $config = Import-PowerShellDataFile -Path $ConfigPath

    foreach ($required in @('VMName', 'RAM_MB', 'Disk_GB', 'NetMode', 'ISOPath', 'ServerName')) {
        if (-not $config.ContainsKey($required)) { throw "config.psd1 is missing required key '$required'." }
    }

    $vmName  = [string]$config.VMName
    $ramMb   = [int]$config.RAM_MB
    $diskGb  = [int]$config.Disk_GB
    $netMode = ([string]$config.NetMode).Trim().ToLowerInvariant()

    if (-not $vmName.Trim()) { throw 'VMName cannot be blank.' }
    if ($ramMb -lt 2048) {
        throw "RAM_MB = $ramMb is below the rubric minimum of 2048 MB. Use 4096 for the recommended value."
    }
    if ($diskGb -lt 20) {
        throw "Disk_GB = $diskGb is below the rubric minimum of 20 GB. Use 30 for the recommended value."
    }
    if (@('nat', 'bridged', 'hostonly', 'intnet') -notcontains $netMode) {
        throw "NetMode '$netMode' is invalid. Use nat, bridged, hostonly, or intnet."
    }

    $script:VBoxManage = Resolve-VBoxManage
    Write-Ok "VBoxManage: $script:VBoxManage"
    $version = (@(Invoke-VBox @('--version')) -join ' ').Trim()
    Write-Ok "VirtualBox version: $version"

    # Verify this VirtualBox build knows Windows Server 2022.
    $ostypes = @(Invoke-VBox @('list', 'ostypes'))
    $hasOstype = @($ostypes | Where-Object { [string]$_ -match '^ID / Description:\s*Windows2022_64\b' }).Count -gt 0
    if (-not $hasOstype) {
        throw "This VirtualBox build does not list 'Windows2022_64'. Update VirtualBox, or set --ostype to Windows2019_64 manually (older builds)."
    }
    Write-Ok 'Guest OS type available: Windows2022_64 (Windows Server 2022 64-bit)'

    $isoPath = Resolve-IsoPath -ConfiguredPath ([string]$config.ISOPath)
    if (-not ($isoPath -match '\.iso$')) { throw "ISOPath is not an .iso file: $isoPath" }
    Write-Ok "ISO: $isoPath"
    if ($isoPath -notmatch 'SERVER|2022|Windows') {
        Write-Info 'Warning: ISO filename does not contain SERVER/2022/Windows. Confirm it is the Windows Server 2022 image.'
    }

    $machineFolder = Get-DefaultMachineFolder
    if (-not (Test-Path -LiteralPath $machineFolder)) {
        New-Item -ItemType Directory -Path $machineFolder -Force | Out-Null
    }
    $vmFolder = Join-Path $machineFolder $vmName
    $vdiPath = Join-Path $vmFolder ($vmName + '.vdi')

    # ------------------------------------------------------------------
    # Existing VM handling
    # ------------------------------------------------------------------
    $vmList = @(Invoke-VBox @('list', 'vms') | ForEach-Object { [string]$_ })
    $exists = @($vmList | Where-Object { $_ -match ('^"' + [regex]::Escape($vmName) + '"') }).Count -gt 0

    if ($exists) {
        if (-not $Recreate) {
            throw ("VM '$vmName' already exists. Run with -Recreate to delete and rebuild it, or delete it in VirtualBox Manager first.`nVM folder: $vmFolder")
        }
        Write-Step "Removing existing VM '$vmName' (-Recreate)"
        $stateLines = @(Invoke-VBox @('showvminfo', $vmName, '--machinereadable'))
        $state = ''
        foreach ($line in $stateLines) {
            if ([string]$line -match '^VMState="?(.+?)"?$') { $state = $Matches[1]; break }
        }
        if ($state -and $state -ne 'poweroff' -and $state -ne 'aborted') {
            throw "VM '$vmName' is currently '$state'. Shut it down completely before using -Recreate."
        }
        Invoke-VBox @('unregistervm', $vmName, '--delete') | Out-Null
        Write-Ok "Existing VM removed."
    }

    $registeredDiskUuid = Get-RegisteredDiskUuid -Path $vdiPath
    if ($registeredDiskUuid) {
        if (-not $Recreate) {
            throw "Disk '$vdiPath' is still registered in VirtualBox's media registry (UUID $registeredDiskUuid). Re-run with -Recreate to remove the orphaned disk."
        }
        Write-Step "Removing orphaned VDI registration $registeredDiskUuid"
        try {
            Invoke-VBox @('closemedium', 'disk', $registeredDiskUuid, '--delete') | Out-Null
        } catch {
            Invoke-VBox @('closemedium', 'disk', $registeredDiskUuid) | Out-Null
            if (Test-Path -LiteralPath $vdiPath) { Remove-Item -LiteralPath $vdiPath -Force }
        }
        Write-Ok 'Orphaned VDI registration removed.'
    }

    if (Test-Path -LiteralPath $vdiPath) {
        if ($Recreate) {
            Remove-Item -LiteralPath $vdiPath -Force
            Write-Ok "Removed stale VDI from a previous partial run: $vdiPath"
        } else {
            throw "Disk already exists and is not part of a registered VM: $vdiPath`nMove or delete it, or re-run with -Recreate, then re-run."
        }
    }

    # ------------------------------------------------------------------
    # Create and register VM (never uses unattended install)
    # ------------------------------------------------------------------
    Write-Step "Creating VM '$vmName' (ostype Windows2022_64, RAM ${ramMb} MB)"
    Invoke-VBox @(
        'createvm', '--name', $vmName, '--ostype', 'Windows2022_64',
        '--register', '--basefolder', $machineFolder
    ) | Out-Null
    Write-Ok 'VM created and registered.'

    Invoke-VBox @(
        'modifyvm', $vmName,
        '--memory', [string]$ramMb,
        '--cpus', '2',
        '--vram', '128',
        '--ioapic', 'on',
        '--boot1', 'dvd',
        '--boot2', 'disk',
        '--boot3', 'none',
        '--boot4', 'none',
        '--clipboard-mode', 'bidirectional',
        '--draganddrop', 'bidirectional'
    ) | Out-Null
    Write-Ok "Memory set to $ramMb MB, boot order DVD first, and clipboard bidirectional."

    # ------------------------------------------------------------------
    # Network
    # ------------------------------------------------------------------
    Write-Step "Configuring Adapter 1 ($netMode)"
    switch ($netMode) {
        'nat' {
            Invoke-VBox @('modifyvm', $vmName, '--nic1', 'nat', '--nictype1', '82540EM') | Out-Null
            Write-Ok 'Adapter 1: NAT'
        }
        'bridged' {
            $bridged = @(Get-BridgedInterfaces)
            if ($bridged.Count -eq 0) { throw 'No VirtualBox bridged interfaces were reported by this host.' }
            $bridgeName = Resolve-BridgeAdapter -Requested ([string]$config.BridgeAdapter) -Bridged $bridged
            Invoke-VBox @(
                'modifyvm', $vmName,
                '--nic1', 'bridged',
                '--bridgeadapter1', $bridgeName,
                '--nictype1', '82540EM'
            ) | Out-Null
            Write-Ok "Adapter 1: Bridged Adapter -> $bridgeName"
        }
        'hostonly' {
            $hostOnly = @(Get-HostOnlyInterfaces)
            $up = @($hostOnly | Where-Object { $_.Status -ieq 'Up' }) | Select-Object -First 1
            if (-not $up) { $up = @($hostOnly) | Select-Object -First 1 }
            if (-not $up) {
                throw 'No VirtualBox host-only adapter exists. Create one in VirtualBox Manager > Tools > Network Manager, then re-run.'
            }
            Invoke-VBox @(
                'modifyvm', $vmName,
                '--nic1', 'hostonly',
                '--hostonlyadapter1', $up.Name,
                '--nictype1', '82540EM'
            ) | Out-Null
            Write-Ok "Adapter 1: Host-only Adapter -> $($up.Name)"
        }
        'intnet' {
            Invoke-VBox @(
                'modifyvm', $vmName,
                '--nic1', 'intnet',
                '--intnet1', 'intnet',
                '--nictype1', '82540EM'
            ) | Out-Null
            Write-Ok 'Adapter 1: Internal Network -> intnet'
        }
    }

    # ------------------------------------------------------------------
    # Dynamic VDI + controllers + ISO
    # ------------------------------------------------------------------
    $sizeMb = [int64]$diskGb * 1024
    Write-Step "Creating dynamic VDI ($diskGb GB = $sizeMb MB)"
    Invoke-VBox @(
        'createmedium', 'disk',
        '--filename', $vdiPath,
        '--size', [string]$sizeMb,
        '--format', 'VDI',
        '--variant', 'Standard'
    ) | Out-Null
    Write-Ok "VDI created: $vdiPath"

    Write-Step 'Attaching SATA disk controller and IDE optical drive'
    Invoke-VBox @(
        'storagectl', $vmName,
        '--name', 'SATA',
        '--add', 'sata',
        '--controller', 'IntelAhci',
        '--portcount', '4',
        '--bootable', 'on'
    ) | Out-Null
    Invoke-VBox @(
        'storageattach', $vmName,
        '--storagectl', 'SATA',
        '--port', '0',
        '--device', '0',
        '--type', 'hdd',
        '--medium', $vdiPath
    ) | Out-Null

    Invoke-VBox @(
        'storagectl', $vmName,
        '--name', 'IDE',
        '--add', 'ide',
        '--controller', 'PIIX4',
        '--bootable', 'on'
    ) | Out-Null
    Invoke-VBox @(
        'storageattach', $vmName,
        '--storagectl', 'IDE',
        '--port', '1',
        '--device', '0',
        '--type', 'dvddrive',
        '--medium', $isoPath
    ) | Out-Null
    Write-Ok 'ISO attached to the optical drive (no unattended installation used).'

    # ------------------------------------------------------------------
    # Read back every graded value and assert it
    # ------------------------------------------------------------------
    Write-Step 'Reading back VM configuration from VirtualBox'
    $raw = @(Invoke-VBox @('showvminfo', $vmName, '--machinereadable'))
    $info = @{}
    foreach ($line in $raw) {
        $text = [string]$line
        $equals = $text.IndexOf('=')
        if ($equals -lt 1) { continue }
        $key = $text.Substring(0, $equals).Trim().Trim('"')
        $value = $text.Substring($equals + 1).Trim()
        if ($value.StartsWith('"') -and $value.EndsWith('"') -and $value.Length -ge 2) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        # --machinereadable escapes Windows backslashes (C:\\path).
        $value = $value.Replace('\\', '\')
        $info[$key] = $value
    }

    $diskCapacityMb = $null
    $mediumInfo = @(Invoke-VBox @('showmediuminfo', 'disk', $vdiPath))
    foreach ($line in $mediumInfo) {
        if ([string]$line -match '^Capacity:\s+(\d+)\s+MBytes') {
            $diskCapacityMb = [int64]$Matches[1]
            break
        }
    }

    $attachedIso = ''
    if ($info.ContainsKey('IDE-1-0')) { $attachedIso = [string]$info['IDE-1-0'] }
    if (-not $attachedIso -and $info.ContainsKey('IDE-0-1')) { $attachedIso = [string]$info['IDE-0-1'] }

    $nicActual = ''
    if ($info.ContainsKey('nic1')) { $nicActual = [string]$info['nic1'] }
    $bridgeActual = ''
    if ($info.ContainsKey('bridgeadapter1')) { $bridgeActual = [string]$info['bridgeadapter1'] }
    $hostOnlyActual = ''
    if ($info.ContainsKey('hostonlyadapter1')) { $hostOnlyActual = [string]$info['hostonlyadapter1'] }
    $memoryActual = ''
    if ($info.ContainsKey('memory')) { $memoryActual = [string]$info['memory'] }

    Write-Host ''
    Write-Host '  ---------------------------------------------------------------' -ForegroundColor DarkCyan
    Write-Host '  VM SUMMARY (from VBoxManage showvminfo)' -ForegroundColor White
    Write-Host '  ---------------------------------------------------------------' -ForegroundColor DarkCyan
    Write-Host ("  VM name ............ {0}" -f $vmName)
    Write-Host ("  Guest OS type ...... {0}" -f $info['ostype'])
    Write-Host ("  RAM ................ {0} MB" -f $memoryActual)
    Write-Host ("  CPUs ............... {0}" -f $info['cpus'])
    Write-Host ("  VDI disk ........... {0} ({1} MB capacity, dynamic)" -f $vdiPath, $diskCapacityMb)
    Write-Host ("  SATA controller .... {0} (disk attached: {1})" -f $info['storagecontrollername0'], $info['SATA-0-0'])
    Write-Host ("  Optical drive ...... {0}" -f $info['storagecontrollername1'])
    Write-Host ("  ISO attached ....... {0}" -f $attachedIso)
    Write-Host ("  Network Adapter 1 .. {0}" -f $nicActual)
    if ($nicActual -eq 'bridged') { Write-Host ("  Bridged to ......... {0}" -f $bridgeActual) }
    if ($nicActual -eq 'hostonly') { Write-Host ("  Host-only to ....... {0}" -f $hostOnlyActual) }
    Write-Host ("  Boot order ......... {0}, {1}" -f $info['boot1'], $info['boot2'])
    Write-Host '  ---------------------------------------------------------------' -ForegroundColor DarkCyan

    $failures = New-Object System.Collections.Generic.List[string]

    if ($memoryActual -eq [string]$ramMb) {
        Write-Ok "RAM is exactly $ramMb MB."
    } else {
        Write-Fail "RAM mismatch: expected $ramMb MB, found '$memoryActual'."
        $failures.Add('RAM')
    }

    if ($null -ne $diskCapacityMb -and $diskCapacityMb -ge $sizeMb) {
        Write-Ok "VDI capacity is $diskCapacityMb MB (>= $sizeMb MB required)."
    } else {
        Write-Fail "VDI capacity check failed (found '$diskCapacityMb' MB, expected >= $sizeMb MB)."
        $failures.Add('Disk')
    }

    if ($attachedIso -and ($attachedIso -ieq $isoPath)) {
        Write-Ok 'ISO is attached to the optical drive.'
    } else {
        Write-Fail "ISO is not attached as expected (found '$attachedIso')."
        $failures.Add('ISO')
    }

    if ($nicActual -eq $netMode) {
        Write-Ok "Network Adapter 1 is '$netMode'."
    } else {
        Write-Fail "Network Adapter 1 is '$nicActual', expected '$netMode'."
        $failures.Add('Network')
    }

    if ($info['ostype'] -eq 'Windows2022_64' -or $info['ostype'] -match '^Windows Server 2022') {
        Write-Ok "Guest OS type is Windows Server 2022 (Windows2022_64): $($info['ostype'])"
    } else {
        Write-Fail "Guest OS type is '$($info['ostype'])', expected Windows Server 2022 (Windows2022_64)."
        $failures.Add('GuestOS')
    }

    if ($attachedIso -match '\.iso$') {
        Write-Ok 'No unattended installation was used; Windows Setup will ask for the edition and password.'
    }

    if ($failures.Count -gt 0) {
        Write-Host ''
        Write-Fail ('VM validation failed: ' + ($failures -join ', '))
        exit 1
    }

    Write-Host ''
    Write-Host '  ALL TASK AREA 01 CHECKS PASSED' -ForegroundColor Green
    Write-Host ''
    Write-Host '  NEXT (manual OS install - Task Area 02):' -ForegroundColor Cyan
    Write-Host '   1. Start the VM and press a key to boot from the ISO.'
    Write-Host '   2. Choose language > Install now.'
    Write-Host '   3. Select an edition with "(Desktop Experience)" - NOT Server Core.'
    Write-Host '   4. Accept license > Custom install > select the unallocated disk > Next.'
    Write-Host ("   5. Set the Administrator password to: {0}" -f $config.SectionAdminPassword)
    Write-Host '   6. Log in with Host key + Del (Right Ctrl + Del by default).'
    Write-Host ''

    if ($Start) {
        Write-Step "Starting '$vmName' in the VirtualBox GUI"
        Invoke-VBox @('startvm', $vmName, '--type', 'gui') | Out-Null
        Write-Ok 'VM start command sent.'
    }
    exit 0
}
catch {
    Write-Host ''
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
