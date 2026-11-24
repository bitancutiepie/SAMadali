#Requires -Version 5.1
<#
.SYNOPSIS
    IT 311 Final Lab - build lab_scripts.iso for the guest optical drive.

.DESCRIPTION
    Packages config.psd1 and 2_configure_server.ps1 into lab_scripts.iso in this
    folder. The ISO is created with Windows' built-in IMAPI2FS COM component, so
    no oscdimg, mkisofs, Administrator rights, internet, or Guest Additions are
    required. If IMAPI2FS is unavailable, the script falls back to oscdimg,
    mkisofs, or genisoimage when installed.

.PARAMETER OutputPath
    Destination ISO. Defaults to lab_scripts.iso next to this script.

.PARAMETER ConfigPath
    Source config.psd1. Defaults to the copy next to this script.

.PARAMETER ServerScriptPath
    Source guest script. Defaults to 2_configure_server.ps1 next to this script.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\3_pack_iso.ps1
#>
[CmdletBinding()]
param(
    [string]$OutputPath,
    [string]$ConfigPath,
    [string]$ServerScriptPath
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $PSScriptRoot 'lab_scripts.iso' }
if ([string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath = Join-Path $PSScriptRoot 'config.psd1' }
if ([string]::IsNullOrWhiteSpace($ServerScriptPath)) { $ServerScriptPath = Join-Path $PSScriptRoot '2_configure_server.ps1' }

function Write-Step {
    param([string]$Text)
    Write-Host ''
    Write-Host ">> $Text" -ForegroundColor Yellow
}

function Write-Ok {
    param([string]$Text)
    Write-Host "   [ OK ] $Text" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Text)
    Write-Host "   [WARN] $Text" -ForegroundColor Yellow
}

function Test-PowerShellSyntax {
    param([Parameter(Mandatory = $true)][string]$Path)

    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        $messages = ($errors | ForEach-Object { "  line $($_.Extent.StartLineNumber): $($_.Message)" }) -join [Environment]::NewLine
        throw "PowerShell syntax errors in '$Path':`n$messages"
    }
}

function Find-ExternalIsoTool {
    $candidates = @(
        (Get-Command 'oscdimg.exe' -ErrorAction SilentlyContinue | Select-Object -First 1),
        (Get-Command 'mkisofs' -ErrorAction SilentlyContinue | Select-Object -First 1),
        (Get-Command 'genisoimage' -ErrorAction SilentlyContinue | Select-Object -First 1)
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and $candidate.Source) { return $candidate.Source }
    }
    foreach ($known in @(
        'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe',
        'C:\Program Files\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe'
    )) {
        if (Test-Path -LiteralPath $known) { return $known }
    }
    return $null
}

function New-IsoWithImapi {
    param(
        [Parameter(Mandatory = $true)][string]$SourceFolder,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    if (-not ('IT311IsoWriter' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

public static class IT311IsoWriter
{
    public static void Write(object imageStream, string path)
    {
        IStream stream = (IStream)imageStream;
        IntPtr readPtr = Marshal.AllocHGlobal(4);
        try
        {
            using (FileStream file = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.None))
            {
                byte[] buffer = new byte[2048 * 64];
                int read;
                do
                {
                    stream.Read(buffer, buffer.Length, readPtr);
                    read = Marshal.ReadInt32(readPtr);
                    if (read > 0) { file.Write(buffer, 0, read); }
                }
                while (read > 0);
            }
        }
        finally
        {
            Marshal.FreeHGlobal(readPtr);
            Marshal.ReleaseComObject(stream);
        }
    }
}
'@ -ErrorAction Stop
    }

    $fileSystemImage = $null
    $resultImage = $null
    try {
        $fileSystemImage = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
        $fileSystemImage.FileSystemsToCreate = 3   # ISO9660 + Joliet
        $fileSystemImage.VolumeName = 'LAB_SCRIPTS'
        # Add each file directly to the ISO root. AddTree would create an extra
        # folder named after the staging directory, breaking D:\2_configure_server.ps1.
        foreach ($file in @(Get-ChildItem -LiteralPath $SourceFolder -File)) {
            $stream = $null
            try {
                # IMAPI2FS AddFile requires (name, IStream); ADODB.Stream is a
                # built-in Windows IStream implementation.
                $stream = New-Object -ComObject ADODB.Stream
                $stream.Type = 1   # adTypeBinary
                $stream.Open()
                $stream.LoadFromFile($file.FullName)
                $fileSystemImage.Root.AddFile($file.Name, $stream)
            } finally {
                if ($stream) {
                    try { $stream.Close() } catch { }
                    try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($stream) | Out-Null } catch { }
                }
            }
        }
        $resultImage = $fileSystemImage.CreateResultImage()
        [IT311IsoWriter]::Write($resultImage.ImageStream, $DestinationPath)
    } finally {
        if ($resultImage) {
            try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($resultImage) | Out-Null } catch { }
        }
        if ($fileSystemImage) {
            try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($fileSystemImage) | Out-Null } catch { }
        }
    }
}

function New-IsoWithExternalTool {
    param(
        [Parameter(Mandatory = $true)][string]$Tool,
        [Parameter(Mandatory = $true)][string]$SourceFolder,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    $leaf = [System.IO.Path]::GetFileName($Tool)
    Write-Warn "Falling back to external ISO tool: $Tool"
    if ($leaf -match 'oscdimg') {
        $output = & $Tool -m -o -u2 -udfver102 -lLAB_SCRIPTS $SourceFolder $DestinationPath 2>&1
    } else {
        $output = & $Tool -J -R -V LAB_SCRIPTS -o $DestinationPath $SourceFolder 2>&1
    }
    if ($LASTEXITCODE -ne 0) {
        throw ("$leaf failed (exit $LASTEXITCODE):`n" + (($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine))
    }
}

function Assert-IsoContents {
    param([Parameter(Mandatory = $true)][string]$IsoPath)

    $sevenZip = Get-Command '7z.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $sevenZip) {
        foreach ($known in @('C:\Program Files\7-Zip\7z.exe', 'C:\Program Files (x86)\7-Zip\7z.exe')) {
            if (Test-Path -LiteralPath $known) {
                $sevenZip = [pscustomobject]@{ Source = $known }
                break
            }
        }
    }
    if (-not $sevenZip) {
        Write-Warn '7-Zip not found; skipping ISO content listing. The IMAPI2 write itself was validated.'
        return
    }

    $listing = (& $sevenZip.Source l -ba $IsoPath 2>&1 | ForEach-Object { [string]$_ })
    $found = @{}
    foreach ($line in $listing) {
        $text = $line.Trim()
        if (-not $text) { continue }
        $name = ($text -split '\s+')[-1]
        foreach ($wanted in @('config.psd1', '2_configure_server.ps1')) {
            if ($name -ieq $wanted) { $found[$wanted] = $true }
            elseif ($name -imatch ('[\\/]' + [regex]::Escape($wanted) + '$')) {
                throw "ISO verification failed: '$wanted' is inside a subfolder ($name), not at the ISO root."
            }
        }
    }
    $missing = @()
    foreach ($name in @('config.psd1', '2_configure_server.ps1')) {
        if (-not $found.ContainsKey($name)) { $missing += $name }
    }
    if ($missing.Count -gt 0) {
        throw ("ISO verification failed; missing from image root: {0}" -f ($missing -join ', '))
    }
    Write-Ok 'ISO contents verified with 7-Zip: config.psd1 and 2_configure_server.ps1 are at the root.'
}

try {
    Write-Host ''
    Write-Host '======================================================================' -ForegroundColor Cyan
    Write-Host '  IT 311 - PACK GUEST FILES INTO lab_scripts.iso' -ForegroundColor Cyan
    Write-Host '======================================================================' -ForegroundColor Cyan

    foreach ($source in @($ConfigPath, $ServerScriptPath)) {
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Required source file not found: $source"
        }
    }

    Write-Step 'Validating config.psd1 and 2_configure_server.ps1'
    $config = Import-PowerShellDataFile -Path $ConfigPath
    foreach ($key in @('VMName', 'ServerName', 'Departments', 'PublicShare', 'PrinterName', 'PrinterPort')) {
        if (-not $config.ContainsKey($key)) { throw "config.psd1 is missing required key '$key'." }
    }
    Test-PowerShellSyntax -Path $ConfigPath
    Test-PowerShellSyntax -Path $ServerScriptPath
    Write-Ok 'Configuration imports and both files parse without syntax errors.'

    $outputFull = [System.IO.Path]::GetFullPath($OutputPath)
    $outputDir = Split-Path -Parent $outputFull
    if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    $staging = Join-Path ([System.IO.Path]::GetTempPath()) ('it311_iso_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    $temporaryIso = $outputFull + '.tmp'

    try {
        Copy-Item -LiteralPath $ConfigPath -Destination (Join-Path $staging 'config.psd1') -Force
        Copy-Item -LiteralPath $ServerScriptPath -Destination (Join-Path $staging '2_configure_server.ps1') -Force
        Write-Ok 'Staged config.psd1 and 2_configure_server.ps1.'

        if (Test-Path -LiteralPath $temporaryIso) { Remove-Item -LiteralPath $temporaryIso -Force }

        Write-Step 'Creating ISO9660/Joliet image'
        $isoCreated = $false
        try {
            New-IsoWithImapi -SourceFolder $staging -DestinationPath $temporaryIso
            $isoCreated = $true
            Write-Ok 'ISO created with built-in IMAPI2FS.'
        } catch {
            Write-Warn "Built-in IMAPI2FS failed: $($_.Exception.Message)"
        }

        if (-not $isoCreated) {
            $external = Find-ExternalIsoTool
            if (-not $external) {
                throw 'Could not create the ISO: IMAPI2FS failed and oscdimg/mkisofs/genisoimage was not found.'
            }
            New-IsoWithExternalTool -Tool $external -SourceFolder $staging -DestinationPath $temporaryIso
            $isoCreated = $true
            Write-Ok "ISO created with $external."
        }

        if (-not (Test-Path -LiteralPath $temporaryIso)) { throw 'ISO file was not created.' }
        $size = (Get-Item -LiteralPath $temporaryIso).Length
        if ($size -lt 4096) { throw "ISO file is suspiciously small ($size bytes)." }

        Move-Item -LiteralPath $temporaryIso -Destination $outputFull -Force
        Write-Ok ("Created {0} ({1:N0} bytes)." -f $outputFull, $size)

        Write-Step 'Verifying ISO contents'
        Assert-IsoContents -IsoPath $outputFull

        Write-Host ''
        Write-Host '  READY - mount this ISO in the guest optical drive:' -ForegroundColor Green
        Write-Host ("    Host file: {0}" -f $outputFull)
        Write-Host '    VirtualBox GUI: Devices > Optical Drives > Choose/Create a disk image...'
        Write-Host ("    Or CLI: VBoxManage storageattach `"{0}`" --storagectl `"IDE`" --port 1 --device 0 --type dvddrive --medium `"{1}`"" -f $config.VMName, $outputFull)
        Write-Host ''
        Write-Host '  Inside Windows Server (replace D: with the mounted drive letter):' -ForegroundColor Cyan
        Write-Host '    Set-ExecutionPolicy Bypass -Scope Process -Force'
        Write-Host '    D:\2_configure_server.ps1'
    } finally {
        if (Test-Path -LiteralPath $staging) {
            Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $temporaryIso) {
            Remove-Item -LiteralPath $temporaryIso -Force -ErrorAction SilentlyContinue
        }
    }

    exit 0
}
catch {
    Write-Host ''
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
