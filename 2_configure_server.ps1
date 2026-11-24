#Requires -Version 5.1
<#
.SYNOPSIS
    IT 311 Final Lab - Task Areas 03-06 inside Windows Server 2022.

.DESCRIPTION
    Reads config.psd1 and performs, in the reviewer's recommended order:
      1. Rename the server (and stop for the required reboot)
      2. Enable password complexity / minimum length 8
      3. Create IT, HR, Manager local users
      4. Install File Server + iSCSI Target Server role services
      5. Create folders, SMB shares, NTFS ACLs, credential text files, shortcuts
      6. Install Print Server, add and share the printer
      7. Run the page-11 verification commands and automated ACL checks

    The script is idempotent: it is safe to run again after the rename reboot,
    and safe to run a second time to refresh files and shortcuts after users
    have logged in once.

.PARAMETER ConfigPath
    Path to config.psd1. Defaults to the copy next to this script (the ISO root).

.PARAMETER AutoReboot
    Reboot without prompting if the server name is wrong. Intended for
    unattended practice runs; omit it on exam day so you can confirm first.

.EXAMPLE
    Set-ExecutionPolicy Bypass -Scope Process -Force
    D:\2_configure_server.ps1

.NOTES
    Run as Administrator inside the Windows Server 2022 guest.
    No internet, domain, or Guest Additions are required.
#>
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$AutoReboot
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $PSScriptRoot 'config.psd1'
}

# ===========================================================================
#  Output helpers
# ===========================================================================
function Write-Banner {
    param([string]$Text)
    Write-Host ''
    Write-Host ('=' * 78) -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ('=' * 78) -ForegroundColor Cyan
}

function Write-StepHeader {
    param([string]$Number, [string]$Text)
    Write-Host ''
    Write-Host ("[STEP $Number] $Text") -ForegroundColor Yellow
    Write-Host ('-' * 78) -ForegroundColor DarkGray
}

function Write-Ok {
    param([string]$Text)
    Write-Host "  [ OK ] $Text" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Text)
    Write-Host "  [WARN] $Text" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Text)
    Write-Host "  [FAIL] $Text" -ForegroundColor Red
}

function Write-Info {
    param([string]$Text)
    Write-Host "         $Text" -ForegroundColor Gray
}

# ===========================================================================
#  Configuration loading and validation
# ===========================================================================
function Import-LabConfig {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        # Helpful fallback when the script is started from another drive.
        $fallback = Join-Path $PSScriptRoot 'config.psd1'
        if ($fallback -ne $Path -and (Test-Path -LiteralPath $fallback -PathType Leaf)) {
            $Path = $fallback
        } else {
            throw "config.psd1 not found at '$Path'. Copy config.psd1 next to this script or pass -ConfigPath."
        }
    }

    $config = Import-PowerShellDataFile -Path $Path
    foreach ($key in @(
        'ServerName', 'SectionAdminPassword', 'BaseSharePath',
        'Departments', 'PublicShare', 'PrinterPort', 'PrinterName'
    )) {
        if (-not $config.ContainsKey($key)) { throw "config.psd1 is missing required key '$key'." }
    }

    $serverName = [string]$config.ServerName
    if ($serverName.Length -gt 15) { throw "ServerName '$serverName' is longer than 15 characters." }
    if ($serverName -notmatch '^[A-Za-z0-9-]+$') { throw "ServerName '$serverName' may contain only letters, numbers, and hyphens." }
    if ($serverName -match '^[0-9]+$') { throw "ServerName '$serverName' cannot be all numbers." }
    if ($serverName -match '^-+$') { throw "ServerName '$serverName' cannot be only hyphens." }

    $sectionPassword = [string]$config.SectionAdminPassword
    if ($sectionPassword -notmatch '^\d{4}@BatStateU$') {
        Write-Warn "SectionAdminPassword '$sectionPassword' does not look like <section>@BatStateU (for example 3106@BatStateU). Confirm it matches your section."
    }

    if (-not ([string]$config.BaseSharePath).Trim()) { throw 'BaseSharePath cannot be blank.' }
    if (-not [System.IO.Path]::IsPathRooted([string]$config.BaseSharePath)) {
        throw "BaseSharePath must be an absolute path, for example C:\Shares."
    }

    if (-not $config.Departments -or $config.Departments.Count -eq 0) {
        throw 'config.psd1 must define at least one department.'
    }

    $invalidPathChars = [System.IO.Path]::GetInvalidFileNameChars()
    foreach ($dept in @($config.Departments.Keys)) {
        $entry = $config.Departments[$dept]
        if ([string]$dept -notmatch '^[A-Za-z][A-Za-z0-9_-]{0,19}$') {
            throw "Department username '$dept' is invalid. Use letters/numbers, maximum 20 characters."
        }
        foreach ($field in @('Password', 'FolderName', 'FileName')) {
            if (-not $entry.ContainsKey($field) -or -not ([string]$entry[$field]).Trim()) {
                throw "Department '$dept' is missing a non-empty '$field' value."
            }
        }
        if (([string]$entry.FolderName).IndexOfAny($invalidPathChars) -ge 0) {
            throw "Department '$dept' FolderName contains invalid path characters."
        }
        if (([string]$entry.FileName).IndexOfAny($invalidPathChars) -ge 0) {
            throw "Department '$dept' FileName contains invalid path characters."
        }
        if (([string]$entry.Password).Length -lt 8) {
            throw "Department '$dept' password is shorter than the enforced 8-character minimum."
        }
    }

    if (-not $config.PublicShare.ContainsKey('FolderName') -or
        -not $config.PublicShare.ContainsKey('FileName')) {
        throw 'PublicShare must contain FolderName and FileName.'
    }
    if (-not ([string]$config.PrinterPort).Trim()) { throw 'PrinterPort cannot be blank.' }
    if (-not ([string]$config.PrinterName).Trim()) { throw 'PrinterName cannot be blank.' }

    return $config
}

# ===========================================================================
#  Generic helpers
# ===========================================================================
function Ensure-Folder {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-TextFileName {
    param([string]$Name)
    if ($Name -match '\.txt$') { return $Name }
    return ($Name + '.txt')
}

function Invoke-NativeProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    # Windows PowerShell 5.1 can convert native stderr into a terminating error
    # when ErrorActionPreference is Stop. Native tools such as secedit/icacls may
    # write harmless progress or warning text to stderr, so capture under Continue.
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $FilePath @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    return [pscustomobject]@{ Output = @($output); ExitCode = $exitCode }
}

# ===========================================================================
#  Task 03 - password policy through secedit (works on Server Core too)
# ===========================================================================
function Set-SecEditValue {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $pattern = '(?ims)^\[' + [regex]::Escape($Section) + '\][ \t]*\r?\n(?<body>.*?)(?=^\[|\z)'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { throw "Section [$Section] was not found in the exported security policy." }

    $body = $match.Groups['body'].Value
    $keyPattern = '(?im)^([ \t]*' + [regex]::Escape($Key) + '[ \t]*=[ \t]*)[^\r\n]*'
    if ([regex]::IsMatch($body, $keyPattern)) {
        $newBody = [regex]::Replace($body, $keyPattern, ('${1}' + $Value), 1)
    } else {
        $newBody = $Key + ' = ' + $Value + "`r`n" + $body
    }

    $start = $match.Groups['body'].Index
    $length = $match.Groups['body'].Length
    return $Text.Substring(0, $start) + $newBody + $Text.Substring($start + $length)
}

function Set-StrongPasswordPolicy {
    $exportPath = Join-Path $env:TEMP 'IT311_secpol_before.inf'
    $applyPath  = Join-Path $env:TEMP 'IT311_secpol_apply.inf'
    $verifyPath = Join-Path $env:TEMP 'IT311_secpol_after.inf'
    $database   = Join-Path $env:TEMP 'IT311_secpol.sdb'
    $logPath    = Join-Path $env:TEMP 'IT311_secpol.log'

    $exportResult = Invoke-NativeProcess -FilePath 'secedit.exe' -Arguments @('/export', '/cfg', $exportPath, '/areas', 'SECURITYPOLICY')
    if ($exportResult.ExitCode -ne 0) {
        throw ("secedit /export failed (exit $($exportResult.ExitCode)).`n" + (($exportResult.Output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine))
    }

    $text = [System.IO.File]::ReadAllText($exportPath, [System.Text.Encoding]::Unicode)
    $text = Set-SecEditValue -Text $text -Section 'System Access' -Key 'PasswordComplexity' -Value '1'
    $text = Set-SecEditValue -Text $text -Section 'System Access' -Key 'MinimumPasswordLength' -Value '8'
    [System.IO.File]::WriteAllText($applyPath, $text, [System.Text.Encoding]::Unicode)

    $applyResult = Invoke-NativeProcess -FilePath 'secedit.exe' -Arguments @('/configure', '/db', $database, '/cfg', $applyPath, '/areas', 'SECURITYPOLICY', '/overwrite', '/log', $logPath)
    if ($applyResult.ExitCode -ne 0) {
        throw ("secedit /configure failed (exit $($applyResult.ExitCode)). See log: $logPath`n" + (($applyResult.Output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine))
    }
    Write-Ok 'Exported, modified, and applied the local security policy.'

    $gpResult = Invoke-NativeProcess -FilePath 'gpupdate.exe' -Arguments @('/force')
    if ($gpResult.ExitCode -ne 0) {
        Write-Warn "gpupdate /force returned exit $($gpResult.ExitCode). Continuing; policy was applied with secedit."
    } else {
        Write-Ok 'gpupdate /force completed.'
    }

    $verifyResult = Invoke-NativeProcess -FilePath 'secedit.exe' -Arguments @('/export', '/cfg', $verifyPath, '/areas', 'SECURITYPOLICY')
    if ($verifyResult.ExitCode -ne 0) { throw "secedit /export verification failed (exit $($verifyResult.ExitCode))." }
    $verified = [System.IO.File]::ReadAllText($verifyPath, [System.Text.Encoding]::Unicode)

    $complexityOk = $verified -match '(?im)^[ \t]*PasswordComplexity[ \t]*=[ \t]*1[ \t]*$'
    $minMatch = [regex]::Match($verified, '(?im)^[ \t]*MinimumPasswordLength[ \t]*=[ \t]*(\d+)')
    $minimum = if ($minMatch.Success) { [int]$minMatch.Groups[1].Value } else { -1 }

    if (-not $complexityOk) { throw 'Password complexity did not apply. Check secpol.msc > Account Policies > Password Policy.' }
    if ($minimum -lt 8) { throw "Minimum password length is $minimum, expected at least 8." }
    Write-Ok "Verified: PasswordComplexity = 1, MinimumPasswordLength = $minimum."
}

# ===========================================================================
#  Task 03 - local department users
# ===========================================================================
function Clear-MustChangePassword {
    param([Parameter(Mandatory = $true)][string]$UserName)
    $computer = [ADSI]("WinNT://{0},computer" -f $env:COMPUTERNAME)
    $user = $computer.Children.Find($UserName, 'user')
    if (-not $user) { throw "ADSI could not find local user '$UserName'." }
    $user.PasswordExpired = 0
    $user.SetInfo()
}

function Ensure-DepartmentUser {
    param(
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )

    $secure = ConvertTo-SecureString -String $Password -AsPlainText -Force
    $existing = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue

    if (-not $existing) {
        New-LocalUser -Name $UserName `
            -Password $secure `
            -FullName ("{0} Department" -f $UserName) `
            -Description ("IT311 Final Lab - {0} department account" -f $UserName) `
            -PasswordNeverExpires `
            -AccountNeverExpires `
            -ErrorAction Stop | Out-Null
        Write-Ok "Created local user '$UserName'."
    } else {
        Set-LocalUser -Name $UserName -Password $secure -PasswordNeverExpires $true -ErrorAction Stop
        Write-Ok "User '$UserName' already existed; password reset to config.psd1 value."
    }

    Enable-LocalUser -Name $UserName -ErrorAction Stop
    Clear-MustChangePassword -UserName $UserName

    $verified = Get-LocalUser -Name $UserName -ErrorAction Stop
    if (-not $verified.Enabled) { throw "User '$UserName' is still disabled." }
    if ($verified.PasswordExpires -ne $null) { throw "User '$UserName' still has a password expiry date." }

    $computer = [ADSI]("WinNT://{0},computer" -f $env:COMPUTERNAME)
    $adsiUser = $computer.Children.Find($UserName, 'user')
    if ([int]$adsiUser.PasswordExpired -ne 0) {
        throw "User '$UserName' still has 'must change password at next logon' set."
    }
    Write-Ok "Verified '$UserName': enabled, password never expires, must-change is off."
}

# ===========================================================================
#  Task 05 - Windows features
# ===========================================================================
function Ensure-WindowsFeature {
    param([Parameter(Mandatory = $true)][string[]]$Names)

    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($name in $Names) {
        $feature = Get-WindowsFeature -Name $name -ErrorAction Stop
        if (-not $feature.Installed) { $missing.Add($name) }
    }

    if ($missing.Count -eq 0) {
        Write-Ok ("Already installed: {0}" -f ($Names -join ', '))
        return
    }

    Write-Info ("Installing: {0}" -f ($missing -join ', '))
    $result = Install-WindowsFeature -Name @($missing) -IncludeManagementTools -ErrorAction Stop
    if ($result -and $result.Success -eq $false) {
        throw ("Install-WindowsFeature failed for: {0}" -f ($missing -join ', '))
    }
    if ($result -and $result.RestartNeeded -and ([string]$result.RestartNeeded) -ne 'No') {
        Write-Warn "Windows reports a restart is needed after installing $($missing -join ', '). Finish the script, then reboot and re-run if anything is missing."
    }
    foreach ($name in $Names) {
        $check = Get-WindowsFeature -Name $name
        if (-not $check.Installed) { throw "Feature '$name' is not installed after Install-WindowsFeature." }
    }
    Write-Ok ("Installed and verified: {0}" -f ($Names -join ', '))
}

# ===========================================================================
#  Task 05 - SMB shares
# ===========================================================================
function Ensure-EveryoneFullShareAccess {
    param([Parameter(Mandatory = $true)][string]$ShareName)

    $access = @(Get-SmbShareAccess -Name $ShareName -ErrorAction Stop)
    $everyone = @($access | Where-Object { $_.AccountName -match '(?i)^(Everyone|WORLD)$' })
    if ($everyone.Count -eq 0) {
        Grant-SmbShareAccess -Name $ShareName -AccountName 'Everyone' -AccessRight Full -Force -Confirm:$false | Out-Null
        Write-Ok "Share '$ShareName': granted Everyone Full Control."
        return
    }
    if (-not ($everyone | Where-Object { $_.AccessRight -eq 'Full' })) {
        Revoke-SmbShareAccess -Name $ShareName -AccountName 'Everyone' -Force -Confirm:$false | Out-Null
        Grant-SmbShareAccess -Name $ShareName -AccountName 'Everyone' -AccessRight Full -Force -Confirm:$false | Out-Null
        Write-Ok "Share '$ShareName': updated Everyone to Full Control."
    }
}

function Ensure-SmbShare {
    param(
        [Parameter(Mandatory = $true)][string]$ShareName,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $share = Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue
    if ($share) {
        $existingPath = ([string]$share.Path).TrimEnd('\')
        $wantedPath = $Path.TrimEnd('\')
        if ($existingPath -ine $wantedPath) {
            Write-Warn "Share '$ShareName' points to '$existingPath'; recreating it for '$wantedPath'."
            Remove-SmbShare -Name $ShareName -Force -Confirm:$false
            $share = $null
        }
    }

    if (-not $share) {
        New-SmbShare -Name $ShareName -Path $Path -FullAccess 'Everyone' `
            -Description ("IT311 Final Lab - {0}" -f $ShareName) -ErrorAction Stop | Out-Null
        Write-Ok "Created SMB share '\\$env:COMPUTERNAME\$ShareName' -> $Path."
    } else {
        Write-Ok "SMB share '$ShareName' already exists at $Path."
    }

    Ensure-EveryoneFullShareAccess -ShareName $ShareName
}

# ===========================================================================
#  Task 05 - NTFS ACLs with icacls
# ===========================================================================
$script:BroadPrincipals = @('Users', 'Everyone', 'Authenticated Users', 'INTERACTIVE', 'CREATOR OWNER')

function Invoke-IcaclsChecked {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Action
    )
    $result = Invoke-NativeProcess -FilePath 'icacls.exe' -Arguments (@($Path) + $Arguments)
    if ($result.ExitCode -ne 0) {
        $rendered = ($result.Output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
        throw ("icacls $Action failed for '$Path' (exit $($result.ExitCode)).`n$rendered")
    }
}

function Set-LockedFolderAcl {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$AllowedUsers
    )

    Invoke-IcaclsChecked -Path $Path -Action 'disable inheritance' -Arguments @('/inheritance:d')

    foreach ($principal in $script:BroadPrincipals) {
        # Absence is fine; ignore icacls' "not found" output.
        $null = Invoke-NativeProcess -FilePath 'icacls.exe' -Arguments @($Path, '/remove:g', $principal)
        $null = Invoke-NativeProcess -FilePath 'icacls.exe' -Arguments @($Path, '/remove:d', $principal)
    }
    Write-Ok "Disabled inheritance and removed Users/Everyone/broad principals on '$Path'."

    foreach ($entry in @('Administrators:(OI)(CI)F', 'SYSTEM:(OI)(CI)F')) {
        Invoke-IcaclsChecked -Path $Path -Action "grant $entry" -Arguments @('/grant:r', $entry)
    }
    foreach ($user in $AllowedUsers) {
        Invoke-IcaclsChecked -Path $Path -Action "grant $user Modify" -Arguments @('/grant:r', ("{0}:(OI)(CI)M" -f $user))
    }
    Write-Ok ("NTFS ACL set: Administrators/SYSTEM Full, {0} Modify." -f ($AllowedUsers -join ', '))
}

# ===========================================================================
#  Task 05 - credential text files
# ===========================================================================
function Write-DepartmentTextFile {
    param(
        [Parameter(Mandatory = $true)][string]$Folder,
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][string]$Department,
        [Parameter(Mandatory = $true)][string]$Password
    )

    $filePath = Join-Path $Folder $FileName
    $doublePath = Join-Path $Folder ($FileName + '.txt')
    if (Test-Path -LiteralPath $doublePath) {
        Remove-Item -LiteralPath $doublePath -Force -ErrorAction SilentlyContinue
        Write-Warn "Removed stale double-extension file: $doublePath"
    }

    $lines = @(
        "IT311 Final Lab - $Department Department Share",
        '',
        "Username: $Department",
        "Password: $Password",
        '',
        "This folder is restricted to the $Department department account.",
        'Administrators and SYSTEM keep Full Control.'
    )
    Set-Content -LiteralPath $filePath -Value $lines -Encoding ASCII -Force
    Write-Ok "Wrote credentials file: $filePath"
}

function Write-PublicTextFile {
    param(
        [Parameter(Mandatory = $true)][string]$Folder,
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)]$Config
    )

    $filePath = Join-Path $Folder $FileName
    $doublePath = Join-Path $Folder ($FileName + '.txt')
    if (Test-Path -LiteralPath $doublePath) {
        Remove-Item -LiteralPath $doublePath -Force -ErrorAction SilentlyContinue
        Write-Warn "Removed stale double-extension file: $doublePath"
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('IT311 Final Lab - Public Share')
    $lines.Add('')
    $lines.Add('All department accounts can access this folder.')
    $lines.Add('')
    foreach ($dept in @($Config.Departments.Keys | Sort-Object)) {
        $lines.Add(('{0,-10} {1}' -f $dept, $Config.Departments[$dept].Password))
    }
    $lines.Add('')
    $lines.Add('Administrators and SYSTEM keep Full Control.')
    Set-Content -LiteralPath $filePath -Value @($lines) -Encoding ASCII -Force
    Write-Ok "Wrote public credentials file: $filePath"
}

# ===========================================================================
#  Task 05 - shortcuts
# ===========================================================================
function New-NetworkShortcut {
    param(
        [Parameter(Mandatory = $true)][string]$ShortcutPath,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $parent = Split-Path -Parent $ShortcutPath
    Ensure-Folder -Path $parent

    $shell = New-Object -ComObject WScript.Shell
    try {
        $shortcut = $shell.CreateShortcut($ShortcutPath)
        $shortcut.TargetPath = $TargetPath
        $shortcut.Description = $Description
        $shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,3"
        $shortcut.Save()
        Write-Ok "Shortcut: $ShortcutPath -> $TargetPath"
    } finally {
        if ($shortcut) { try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut) | Out-Null } catch { } }
        try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null } catch { }
    }
}

function Get-UserProfileInfo {
    param([Parameter(Mandatory = $true)][string]$UserName)

    $user = Get-LocalUser -Name $UserName -ErrorAction Stop
    $profile = Get-CimInstance -ClassName Win32_UserProfile -ErrorAction SilentlyContinue |
        Where-Object { $_.SID -eq $user.SID.Value } |
        Select-Object -First 1

    if ($profile -and $profile.LocalPath) {
        return [pscustomobject]@{ Path = [string]$profile.LocalPath; Registered = $true }
    }
    return [pscustomobject]@{ Path = (Join-Path 'C:\Users' $UserName); Registered = $false }
}

# ===========================================================================
#  Task 06 - printer
# ===========================================================================
function Ensure-Printer {
    param(
        [Parameter(Mandatory = $true)][string]$PrinterName,
        [Parameter(Mandatory = $true)][string]$PortName
    )

    $driverName = 'Generic / Text Only'
    Import-Module PrintManagement -ErrorAction Stop

    $spooler = Get-Service -Name Spooler -ErrorAction SilentlyContinue
    if ($spooler -and $spooler.Status -ne 'Running') {
        Start-Service -Name Spooler -ErrorAction Stop
        Write-Ok 'Started the Print Spooler service.'
    }

    $driver = Get-PrinterDriver -Name $driverName -ErrorAction SilentlyContinue
    if (-not $driver) {
        try {
            Add-PrinterDriver -Name $driverName -ErrorAction Stop
            Write-Ok "Added printer driver '$driverName'."
        } catch {
            $driver = Get-PrinterDriver -Name $driverName -ErrorAction SilentlyContinue
            if ($driver) {
                Write-Warn "Printer driver '$driverName' was already registered."
            } else {
                Write-Warn "Add-PrinterDriver without environment failed; retrying as Windows x64."
                Add-PrinterDriver -Name $driverName -PrinterEnvironment 'Windows x64' -ErrorAction Stop
                Write-Ok "Added printer driver '$driverName' (Windows x64)."
            }
        }
    } else {
        Write-Ok "Printer driver '$driverName' is already present."
    }

    $port = Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue
    if (-not $port) {
        try {
            Add-PrinterPort -Name $PortName -ErrorAction Stop
            Write-Ok "Created printer port '$PortName'."
        } catch {
            # LPT1: and FILE: are built-in ports and may not appear until used.
            Write-Warn "Add-PrinterPort '$PortName' did not create a new port; Add-Printer will use the built-in port."
        }
    } else {
        Write-Ok "Printer port '$PortName' is already present."
    }

    $printer = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
    if (-not $printer) {
        Add-Printer -Name $PrinterName -DriverName $driverName -PortName $PortName -ErrorAction Stop
        Write-Ok "Added printer '$PrinterName' on port '$PortName'."
    } else {
        if ($printer.DriverName -ne $driverName -or $printer.PortName -ne $PortName) {
            Set-Printer -Name $PrinterName -DriverName $driverName -PortName $PortName -ErrorAction Stop
            Write-Ok "Updated existing printer '$PrinterName' driver/port."
        } else {
            Write-Ok "Printer '$PrinterName' already exists with the correct driver and port."
        }
    }

    Set-Printer -Name $PrinterName -Shared $true -ShareName $PrinterName -ErrorAction Stop
    Write-Ok "Printer '$PrinterName' is shared with share name '$PrinterName'."

    $verified = Get-Printer -Name $PrinterName -ErrorAction Stop
    if (-not $verified.Shared) { throw "Printer '$PrinterName' is not shared." }
    if ($verified.ShareName -ne $PrinterName) { throw "Printer share name is '$($verified.ShareName)', expected '$PrinterName'." }
}

# ===========================================================================
#  Verification helpers
# ===========================================================================
function Get-AceSid {
    param($Ace)
    try {
        return $Ace.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value
    } catch {
        return $null
    }
}

function Test-AclAllow {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Sids,
        [switch]$RequireModify,
        [switch]$RequireFullControl
    )

    $acl = Get-Acl -LiteralPath $Path
    $modifyMask = [int][System.Security.AccessControl.FileSystemRights]::Modify
    $fullMask = [int][System.Security.AccessControl.FileSystemRights]::FullControl

    foreach ($ace in $acl.Access) {
        if ($ace.AccessControlType -ne 'Allow') { continue }
        $sid = Get-AceSid -Ace $ace
        if (-not $sid -or ($Sids -notcontains $sid)) { continue }
        $rights = [int]$ace.FileSystemRights
        if ($RequireFullControl) {
            if (($rights -band $fullMask) -eq $fullMask) { return $true }
            continue
        }
        if ($RequireModify) {
            if (($rights -band $modifyMask) -eq $modifyMask) { return $true }
            continue
        }
        return $true
    }
    return $false
}

function Get-UserSid {
    param([Parameter(Mandatory = $true)][string]$UserName)
    $user = Get-LocalUser -Name $UserName -ErrorAction Stop
    return $user.SID.Value
}

function Test-UserDeniedOnFolder {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$UserName
    )

    $sid = Get-UserSid -UserName $UserName
    $implicitSids = @(
        $sid,
        'S-1-5-32-545',  # BUILTIN\Users
        'S-1-1-0',       # Everyone
        'S-1-5-11',      # Authenticated Users
        'S-1-5-4'        # INTERACTIVE
    )
    $badAces = @()
    $acl = Get-Acl -LiteralPath $Path
    foreach ($ace in $acl.Access) {
        if ($ace.AccessControlType -ne 'Allow') { continue }
        $aceSid = Get-AceSid -Ace $ace
        if ($aceSid -and ($implicitSids -contains $aceSid)) {
            $badAces += ("{0} -> {1}" -f $ace.IdentityReference, $ace.FileSystemRights)
        }
    }
    return [pscustomobject]@{
        Denied  = ($badAces.Count -eq 0)
        BadAces = $badAces
    }
}

function Get-ShortcutTarget {
    param([Parameter(Mandatory = $true)][string]$ShortcutPath)
    $shell = New-Object -ComObject WScript.Shell
    try {
        $shortcut = $shell.CreateShortcut($ShortcutPath)
        $target = [string]$shortcut.TargetPath
        return $target
    } finally {
        if ($shortcut) { try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut) | Out-Null } catch { } }
        try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null } catch { }
    }
}

# ===========================================================================
#  Main configuration routine
# ===========================================================================
function Invoke-LabConfiguration {
    param([Parameter(Mandatory = $true)]$Config)

    $serverName    = [string]$Config.ServerName
    $baseSharePath = [string]$Config.BaseSharePath
    $departments   = $Config.Departments
    $publicShare   = $Config.PublicShare
    $printerName   = [string]$Config.PrinterName
    $printerPort   = [string]$Config.PrinterPort
    $failures      = New-Object System.Collections.Generic.List[string]

    # -----------------------------------------------------------------------
    # STEP 1 - Task 04: Rename FIRST
    # -----------------------------------------------------------------------
    Write-StepHeader '1' 'Task Area 04 - Rename the server (must happen before shares/shortcuts)'
    $currentName = $env:COMPUTERNAME
    if ($currentName -ne $serverName) {
        Write-Warn "Current computer name is '$currentName'; required name is '$serverName'."
        Rename-Computer -NewName $serverName -Force -ErrorAction Stop
        Write-Ok "Rename queued. The name changes only after a restart."

        if ($AutoReboot) {
            Write-Warn '-AutoReboot specified. Restarting now.'
            Restart-Computer -Force -Confirm:$false
            return 10
        }

        $answer = Read-Host 'Restart now to apply the server name? [Y/n]'
        if ([string]::IsNullOrWhiteSpace($answer) -or $answer -match '^(?i)y(es)?$') {
            Write-Host '  Restarting now. After Windows starts, remount the ISO if needed and run this script again.' -ForegroundColor Yellow
            Restart-Computer -Force -Confirm:$false
            return 10
        }

        Write-Warn 'Not restarting. Shares and shortcuts are intentionally skipped so \\OLDNAME\share paths cannot break.'
        Write-Info 'Restart manually, then run this script again from the ISO.'
        return 10
    }

    Write-Ok "Computer name already matches '$serverName'."
    Write-Info 'Continuing without a reboot; all share paths will use the final name.'

    # -----------------------------------------------------------------------
    # STEP 2 - Task 03: Password policy BEFORE users
    # -----------------------------------------------------------------------
    Write-StepHeader '2' 'Task Area 03 - Enforce password complexity and minimum length 8'
    Set-StrongPasswordPolicy

    # -----------------------------------------------------------------------
    # STEP 3 - Task 03: Department users
    # -----------------------------------------------------------------------
    Write-StepHeader '3' 'Task Area 03 - Create IT, HR, and Manager local accounts'
    foreach ($dept in @($departments.Keys)) {
        Ensure-DepartmentUser -UserName ([string]$dept) -Password ([string]$departments[$dept].Password)
    }

    # -----------------------------------------------------------------------
    # STEP 4 - Task 05: File and Storage role services
    # -----------------------------------------------------------------------
    Write-StepHeader '4' 'Task Area 05 - Install File Server and iSCSI Target Server'
    Ensure-WindowsFeature -Names @('FS-FileServer', 'FS-iSCSITarget-Server')

    # -----------------------------------------------------------------------
    # STEP 5 - Task 05: folders, shares, NTFS ACLs
    # -----------------------------------------------------------------------
    Write-StepHeader '5' 'Task Area 05 - Create folders, SMB shares, and NTFS permissions'

    Ensure-Folder -Path $baseSharePath
    Write-Ok "Base folder exists: $baseSharePath"

    $folderPaths = @{}
    foreach ($dept in @($departments.Keys)) {
        $deptFolder = Join-Path $baseSharePath ([string]$departments[$dept].FolderName)
        Ensure-Folder -Path $deptFolder
        $folderPaths[$dept] = $deptFolder
        Write-Ok "Department folder exists: $deptFolder"
    }

    $publicFolder = Join-Path $baseSharePath ([string]$publicShare.FolderName)
    Ensure-Folder -Path $publicFolder
    Write-Ok "Public folder exists: $publicFolder"

    # Share every folder with Everyone Full at the SMB layer; NTFS does the locking.
    foreach ($dept in @($departments.Keys)) {
        Ensure-SmbShare -ShareName ([string]$departments[$dept].FolderName) -Path $folderPaths[$dept]
    }
    Ensure-SmbShare -ShareName ([string]$publicShare.FolderName) -Path $publicFolder

    # Lock each department folder to its own account.
    foreach ($dept in @($departments.Keys)) {
        Set-LockedFolderAcl -Path $folderPaths[$dept] -AllowedUsers @([string]$dept)
    }

    # Public folder: all three department accounts, no broad principals.
    Set-LockedFolderAcl -Path $publicFolder -AllowedUsers @($departments.Keys)

    # -----------------------------------------------------------------------
    # STEP 6 - Task 05: credential text files
    # -----------------------------------------------------------------------
    Write-StepHeader '6' 'Task Area 05 - Create password text files (single .txt extension)'
    foreach ($dept in @($departments.Keys)) {
        $fileName = Get-TextFileName -Name ([string]$departments[$dept].FileName)
        Write-DepartmentTextFile -Folder $folderPaths[$dept] -FileName $fileName `
            -Department ([string]$dept) -Password ([string]$departments[$dept].Password)
    }
    $publicFileName = Get-TextFileName -Name ([string]$publicShare.FileName)
    Write-PublicTextFile -Folder $publicFolder -FileName $publicFileName -Config $Config

    # -----------------------------------------------------------------------
    # STEP 7 - Task 05: desktop shortcuts
    # -----------------------------------------------------------------------
    Write-StepHeader '7' 'Task Area 05 - Create per-user and public desktop shortcuts'

    $publicDesktop = 'C:\Users\Public\Desktop'
    Ensure-Folder -Path $publicDesktop

    foreach ($dept in @($departments.Keys)) {
        $profileInfo = Get-UserProfileInfo -UserName ([string]$dept)
        if (-not $profileInfo.Registered) {
            Write-Warn "No loaded profile found for '$dept'. Creating $($profileInfo.Path)\Desktop."
            Write-Info 'Log in once as this user, then re-run this script so the shortcut lands in the real profile folder.'
        }
        $desktop = Join-Path $profileInfo.Path 'Desktop'
        Ensure-Folder -Path $desktop
        $shortcutPath = Join-Path $desktop ([string]$departments[$dept].FolderName + '.lnk')
        $target = ('\\{0}\{1}' -f $serverName, [string]$departments[$dept].FolderName)
        New-NetworkShortcut -ShortcutPath $shortcutPath -TargetPath $target `
            -Description ("{0} department share" -f $dept)

        # Defensive cleanup: a department shortcut must never live in Public Desktop.
        $leak = Join-Path $publicDesktop ([string]$departments[$dept].FolderName + '.lnk')
        if (Test-Path -LiteralPath $leak) {
            Remove-Item -LiteralPath $leak -Force
            Write-Warn "Removed leaked public-desktop shortcut: $leak"
        }
    }

    $publicShortcut = Join-Path $publicDesktop ([string]$publicShare.FolderName + '.lnk')
    $publicTarget = ('\\{0}\{1}' -f $serverName, [string]$publicShare.FolderName)
    New-NetworkShortcut -ShortcutPath $publicShortcut -TargetPath $publicTarget `
        -Description 'Public share for all departments'

    # -----------------------------------------------------------------------
    # STEP 8 - Task 06: Print Server role and printer
    # -----------------------------------------------------------------------
    Write-StepHeader '8' 'Task Area 06 - Install Print Server, add and share the printer'
    Ensure-WindowsFeature -Names @('Print-Server')
    Ensure-Printer -PrinterName $printerName -PortName $printerPort

    # -----------------------------------------------------------------------
    # STEP 9 - Verification
    # -----------------------------------------------------------------------
    Write-StepHeader '9' 'FINAL VERIFICATION - page 11 commands plus automated ACL checks'

    Write-Host ''
    Write-Host '  Exact commands from page 11 of the reviewer:' -ForegroundColor White
    Write-Host '    PS C:\> hostname'
    Write-Host '    PS C:\> Get-LocalUser'
    Write-Host '    PS C:\> Get-WindowsFeature | Where Installed'
    Write-Host '    PS C:\> Get-SmbShare'
    Write-Host '    PS C:\> Get-Printer'
    Write-Host ''

    Write-Host 'PS C:\> hostname' -ForegroundColor Cyan
    & hostname
    Write-Host ''

    Write-Host 'PS C:\> Get-LocalUser' -ForegroundColor Cyan
    Get-LocalUser | Format-Table Name, Enabled, PasswordRequired, PasswordExpires -AutoSize | Out-String | Write-Host
    Write-Host ''

    Write-Host 'PS C:\> Get-WindowsFeature | Where Installed' -ForegroundColor Cyan
    Get-WindowsFeature | Where-Object { $_.Installed } |
        Format-Table Name, InstallState -AutoSize | Out-String | Write-Host
    Write-Host ''

    Write-Host 'PS C:\> Get-SmbShare' -ForegroundColor Cyan
    Get-SmbShare | Format-Table Name, Path, Description -AutoSize | Out-String | Write-Host
    Write-Host ''

    Write-Host 'PS C:\> Get-Printer' -ForegroundColor Cyan
    Get-Printer | Format-Table Name, DriverName, PortName, Shared, ShareName -AutoSize | Out-String | Write-Host

    # ---- automated checks -------------------------------------------------
    $adminSid = 'S-1-5-32-544'
    $systemSid = 'S-1-5-18'

    if ($env:COMPUTERNAME -eq $serverName) {
        Write-Ok "Hostname matches config: $serverName"
    } else {
        Write-Fail "Hostname is '$env:COMPUTERNAME', expected '$serverName'"
        $failures.Add('Hostname')
    }

    foreach ($dept in @($departments.Keys)) {
        $user = Get-LocalUser -Name ([string]$dept) -ErrorAction SilentlyContinue
        if (-not $user) {
            Write-Fail "Local user '$dept' is missing"
            $failures.Add("User $dept")
        } elseif (-not $user.Enabled) {
            Write-Fail "Local user '$dept' is disabled"
            $failures.Add("User $dept disabled")
        } else {
            Write-Ok "Local user '$dept' exists and is enabled"
        }
    }

    foreach ($feature in @('FS-FileServer', 'FS-iSCSITarget-Server', 'Print-Server')) {
        $state = Get-WindowsFeature -Name $feature
        if ($state.Installed) {
            Write-Ok "Role service installed: $feature"
        } else {
            Write-Fail "Role service missing: $feature"
            $failures.Add("Feature $feature")
        }
    }

    foreach ($dept in @($departments.Keys)) {
        $shareName = [string]$departments[$dept].FolderName
        $share = Get-SmbShare -Name $shareName -ErrorAction SilentlyContinue
        if (-not $share) {
            Write-Fail "SMB share '$shareName' is missing"
            $failures.Add("Share $shareName")
        } elseif (([string]$share.Path).TrimEnd('\') -ine $folderPaths[$dept].TrimEnd('\')) {
            Write-Fail "SMB share '$shareName' points to '$($share.Path)', expected '$($folderPaths[$dept])'"
            $failures.Add("Share path $shareName")
        } else {
            Write-Ok "SMB share '$shareName' exists at the correct path"
        }

        $adminOk = Test-AclAllow -Path $folderPaths[$dept] -Sids @($adminSid) -RequireFullControl
        $systemOk = Test-AclAllow -Path $folderPaths[$dept] -Sids @($systemSid) -RequireFullControl
        $userSid = (Get-LocalUser -Name ([string]$dept) -ErrorAction SilentlyContinue).SID.Value
        $modifyOk = $false
        if ($userSid) { $modifyOk = Test-AclAllow -Path $folderPaths[$dept] -Sids @($userSid) -RequireModify }

        if ($adminOk -and $systemOk -and $modifyOk) {
            Write-Ok "NTFS '$($departments[$dept].FolderName)': Administrators/SYSTEM Full, $dept Modify"
        } else {
            Write-Fail "NTFS ACL incomplete on '$($departments[$dept].FolderName)' (Admin=$adminOk System=$systemOk ${dept}Modify=$modifyOk)"
            $failures.Add("ACL $dept")
        }
    }

    $publicShareObj = Get-SmbShare -Name ([string]$publicShare.FolderName) -ErrorAction SilentlyContinue
    if ($publicShareObj) {
        Write-Ok "SMB share '$($publicShare.FolderName)' exists"
    } else {
        Write-Fail "SMB share '$($publicShare.FolderName)' is missing"
        $failures.Add('Public share')
    }
    foreach ($dept in @($departments.Keys)) {
        $publicSid = (Get-LocalUser -Name ([string]$dept) -ErrorAction SilentlyContinue).SID.Value
        if ($publicSid -and (Test-AclAllow -Path $publicFolder -Sids @($publicSid) -RequireModify)) {
            Write-Ok "NTFS Public_Share: $dept has Modify"
        } else {
            Write-Fail "NTFS Public_Share: $dept is missing Modify"
            $failures.Add("Public ACL $dept")
        }
    }
    if ((Test-AclAllow -Path $publicFolder -Sids @($adminSid) -RequireFullControl) -and
        (Test-AclAllow -Path $publicFolder -Sids @($systemSid) -RequireFullControl)) {
        Write-Ok 'NTFS Public_Share: Administrators/SYSTEM Full Control'
    } else {
        Write-Fail 'NTFS Public_Share is missing Administrators/SYSTEM Full Control'
        $failures.Add('Public ACL admin')
    }

    # Automated NTFS access check: IT must be denied HR.
    $departmentNames = @($departments.Keys)
    if (($departmentNames -contains 'IT') -and ($departmentNames -contains 'HR')) {
        $hrFolder = $folderPaths['HR']
        $denial = Test-UserDeniedOnFolder -Path $hrFolder -UserName 'IT'
        if ($denial.Denied) {
            Write-Ok "NTFS ACCESS CHECK PASSED: IT has no Allow ACE on '$hrFolder' (Users/Everyone/Authenticated Users are absent)."
            Write-Info 'IT will receive "Access is denied" when opening \\SERVER\HR_Share. Confirm once by logging in as IT.'
        } else {
            Write-Fail ("NTFS ACCESS CHECK FAILED: IT still has access to HR via: {0}" -f ($denial.BadAces -join '; '))
            $failures.Add('IT can access HR')
        }
    }

    # Text files
    foreach ($dept in @($departments.Keys)) {
        $fileName = Get-TextFileName -Name ([string]$departments[$dept].FileName)
        $path = Join-Path $folderPaths[$dept] $fileName
        if (Test-Path -LiteralPath $path) {
            $content = Get-Content -LiteralPath $path -Raw
            if ($content -match [regex]::Escape([string]$departments[$dept].Password)) {
                Write-Ok "Credential file OK: $path"
            } else {
                Write-Fail "Credential file does not contain the department password: $path"
                $failures.Add("File content $dept")
            }
        } else {
            Write-Fail "Credential file missing: $path"
            $failures.Add("File $dept")
        }
    }
    $publicFile = Join-Path $publicFolder $publicFileName
    if (Test-Path -LiteralPath $publicFile) {
        $publicContent = Get-Content -LiteralPath $publicFile -Raw
        $allPresent = $true
        foreach ($dept in @($departments.Keys)) {
            if ($publicContent -notmatch [regex]::Escape([string]$departments[$dept].Password)) { $allPresent = $false }
        }
        if ($allPresent) {
            Write-Ok "Public credential file OK: $publicFile"
        } else {
            Write-Fail "Public credential file is missing one or more department passwords: $publicFile"
            $failures.Add('Public file content')
        }
    } else {
        Write-Fail "Public credential file missing: $publicFile"
        $failures.Add('Public file')
    }

    # Shortcuts
    foreach ($dept in @($departments.Keys)) {
        $profileInfo = Get-UserProfileInfo -UserName ([string]$dept)
        $lnk = Join-Path (Join-Path $profileInfo.Path 'Desktop') ([string]$departments[$dept].FolderName + '.lnk')
        $expected = ('\\{0}\{1}' -f $serverName, [string]$departments[$dept].FolderName)
        if (Test-Path -LiteralPath $lnk) {
            $actual = Get-ShortcutTarget -ShortcutPath $lnk
            if ($actual -ieq $expected) {
                Write-Ok "Shortcut OK: $lnk -> $actual"
            } else {
                Write-Fail "Shortcut target is '$actual', expected '$expected'"
                $failures.Add("Shortcut $dept")
            }
        } else {
            Write-Fail "Shortcut missing: $lnk"
            $failures.Add("Shortcut $dept")
        }
    }
    $publicLnk = Join-Path $publicDesktop ([string]$publicShare.FolderName + '.lnk')
    $expectedPublic = ('\\{0}\{1}' -f $serverName, [string]$publicShare.FolderName)
    if (Test-Path -LiteralPath $publicLnk) {
        $actualPublic = Get-ShortcutTarget -ShortcutPath $publicLnk
        if ($actualPublic -ieq $expectedPublic) {
            Write-Ok "Public shortcut OK: $publicLnk -> $actualPublic"
        } else {
            Write-Fail "Public shortcut target is '$actualPublic', expected '$expectedPublic'"
            $failures.Add('Public shortcut target')
        }
    } else {
        Write-Fail "Public shortcut missing: $publicLnk"
        $failures.Add('Public shortcut')
    }

    # Printer
    $printer = Get-Printer -Name $printerName -ErrorAction SilentlyContinue
    if ($printer) {
        if ($printer.Shared -and $printer.ShareName -eq $printerName) {
            Write-Ok "Printer '$printerName' exists and is shared as '$($printer.ShareName)'"
        } else {
            Write-Fail "Printer '$printerName' exists but is not shared with the exact share name"
            $failures.Add('Printer share')
        }
        if ($printer.PortName -eq $printerPort) {
            Write-Ok "Printer port is '$printerPort'"
        } else {
            Write-Fail "Printer port is '$($printer.PortName)', expected '$printerPort'"
            $failures.Add('Printer port')
        }
    } else {
        Write-Fail "Printer '$printerName' is missing"
        $failures.Add('Printer')
    }

    # ---- final summary ----------------------------------------------------
    Write-Host ''
    Write-Host ('=' * 78) -ForegroundColor Cyan
    if ($failures.Count -eq 0) {
        Write-Host '  ALL AUTOMATED CHECKS PASSED' -ForegroundColor Green
        Write-Host ''
        Write-Host '  MANUAL CHECKS STILL REQUIRED (grader watches these):' -ForegroundColor Yellow
        Write-Host '   1. Log in once as IT, HR, and Manager. Confirm each desktop has ONLY its own share shortcut.'
        Write-Host '   2. As IT, open \\SERVER\HR_Share and confirm "Access is denied". Then check HR -> IT_Share.'
        Write-Host '   3. Confirm the Public_Share shortcut appears for every user and opens for all three.'
        Write-Host '   4. Browse to \\SERVER and confirm the printer appears beside the shared folders.'
        Write-Host '   5. If you logged in after this script ran, re-run it so shortcuts are in the real profiles.'
        Write-Host '   6. Leave the VM running. Raise your hand. Do not delete or shut down anything.'
    } else {
        Write-Host ("  {0} CHECK(S) FAILED - FIX BEFORE RAISING YOUR HAND" -f $failures.Count) -ForegroundColor Red
        foreach ($failure in $failures) { Write-Host ("   - {0}" -f $failure) -ForegroundColor Red }
        Write-Host ''
        Write-Host '  Re-run the script after fixing config.psd1 or the failing item. It is idempotent.'
    }
    Write-Host ('=' * 78) -ForegroundColor Cyan

    if ($failures.Count -gt 0) { return 1 }
    return 0
}

# ===========================================================================
#  Entry point
# ===========================================================================
$exitCode = 1
$transcriptStarted = $false
$logDirectory = 'C:\LabConfig'

try {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'This script must be run as Administrator inside Windows Server 2022.'
    }

    if (-not (Test-Path -LiteralPath $logDirectory)) {
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    }
    try {
        $logPath = Join-Path $logDirectory ('configure_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        Start-Transcript -Path $logPath -Append | Out-Null
        $transcriptStarted = $true
    } catch {
        Write-Warn "Could not start transcript: $($_.Exception.Message)"
    }

    Write-Banner 'IT 311 FINAL LAB - SERVER CONFIGURATION (TASK AREAS 03-06)'
    Write-Host "  Script : $PSCommandPath"
    Write-Host "  Config : $ConfigPath"
    Write-Host "  Computer: $env:COMPUTERNAME"
    Write-Host "  Date    : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

    $config = Import-LabConfig -Path $ConfigPath
    Write-Ok "Configuration loaded: server '$($config.ServerName)', base share '$($config.BaseSharePath)'."
    Write-Info ("Departments: {0}" -f (@($config.Departments.Keys) -join ', '))
    Write-Info "Printer: $($config.PrinterName) on $($config.PrinterPort)"

    $exitCode = Invoke-LabConfiguration -Config $config
}
catch {
    Write-Host ''
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    if ($_.InvocationInfo -and $_.InvocationInfo.PositionMessage) {
        Write-Host $_.InvocationInfo.PositionMessage -ForegroundColor DarkGray
    }
    $exitCode = 1
}
finally {
    if ($transcriptStarted) {
        try { Stop-Transcript | Out-Null } catch { }
    }
}

exit $exitCode
