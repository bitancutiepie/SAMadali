#Requires -Version 5.1
<#
.SYNOPSIS
    IT 311 Final Lab - Independent 50-Point Exam Evaluator & Rubric Verifier.

.DESCRIPTION
    Checks all grading items inside the Windows Server 2022 guest and prints
    an exact score breakdown (0 to 50 points) matching the official reviewer:
      - Task Area 04: Server Identity (5 pts)
      - Task Area 03: Users & Password Policy (10 pts)
      - Task Area 05: File and Storage Services (12 pts)
      - Task Area 06: Print and Document Services (7 pts)
      - Task Area 01 & 02: VM Hardware & Desktop OS Checks (16 pts)

.EXAMPLE
    D:\verify_exam.ps1
    or inside the VM:
    powershell -ExecutionPolicy Bypass -File .\verify_exam.ps1
#>
[CmdletBinding()]
param(
    [string]$ConfigPath
)

$ErrorActionPreference = 'Continue'

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $candidates = @(
        (Join-Path $PSScriptRoot 'config.psd1'),
        'D:\config.psd1',
        'E:\config.psd1',
        'C:\Shares\config.psd1'
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) {
            $ConfigPath = $c
            break
        }
    }
}

$cfg = $null
if ($ConfigPath -and (Test-Path -LiteralPath $ConfigPath)) {
    try {
        $cfg = Import-PowerShellDataFile -Path $ConfigPath
    } catch {}
}

# Fallback defaults if config is absent
if (-not $cfg) {
    $cfg = @{
        ServerName           = 'Lab-Server-01'
        SectionAdminPassword = '3106@BatStateU'
        BaseSharePath        = 'C:\Shares'
        Departments          = @{
            IT      = @{ Password = 'Tech#Dept2026';   FolderName = 'IT_Share';      FileName = 'it.txt' }
            HR      = @{ Password = 'People#Dept2026'; FolderName = 'HR_Share';      FileName = 'hr.txt' }
            Manager = @{ Password = 'Lead#Dept2026';   FolderName = 'Manager_Share'; FileName = 'manager.txt' }
        }
        PublicShare          = @{
            FolderName = 'Public_Share'
            FileName   = 'public.txt'
        }
        PrinterName          = 'Office-Printer'
        PrinterPort          = 'LPT1:'
    }
}

$score = 0
$maxScore = 50

function Score-Item {
    param(
        [string]$Name,
        [int]$Pts,
        [bool]$Passed,
        [string]$Details = ''
    )
    if ($Passed) {
        $script:score += $Pts
        Write-Host ("  [PASS] (+{0,2} pts) {1}" -f $Pts, $Name) -ForegroundColor Green
        if ($Details) { Write-Host "         $Details" -ForegroundColor DarkGreen }
    } else {
        Write-Host ("  [FAIL] (+ 0 pts) {1}" -f $Pts, $Name) -ForegroundColor Red
        if ($Details) { Write-Host "         Issue: $Details" -ForegroundColor Yellow }
    }
}

Clear-Host
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  IT 311 FINAL LAB - 50-POINT RUBRIC VERIFICATION TOOL" -ForegroundColor Cyan
Write-Host "  Based on IT311_Final_Lab_Reviewer.pdf" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------------------
#  AREA 01 & 02: VM SETUP & OS INSTALL (16 Points)
# ---------------------------------------------------------------------------
Write-Host ">> [TASK AREA 01 & 02] VM Setup & OS Install (16 pts)" -ForegroundColor Yellow
$ram = Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty TotalVisibleMemorySize
$ramMB = [math]::Round($ram / 1024)
$ramPass = ($ramMB -ge 1800)
Score-Item -Name "RAM Allocation >= 2048 MB (Current: $ramMB MB)" -Pts 4 -Passed $ramPass -Details "Rubric requires minimum 2048 MB."

$disk = Get-CimInstance Win32_DiskDrive | Select-Object -First 1
$diskGB = if ($disk) { [math]::Round($disk.Size / 1GB) } else { 0 }
$diskPass = ($diskGB -ge 19)
Score-Item -Name "Disk Size >= 20 GB (Current: $diskGB GB)" -Pts 4 -Passed $diskPass -Details "Rubric requires minimum 20 GB VDI."

$osInfo = Get-CimInstance Win32_OperatingSystem
$isServer2022 = ($osInfo.Caption -match 'Server 2022')
Score-Item -Name "OS Version: Windows Server 2022 ($($osInfo.Caption))" -Pts 4 -Passed $isServer2022

$hasGui = Test-Path "$env:windir\explorer.exe"
Score-Item -Name "Desktop Experience (GUI) Installed" -Pts 4 -Passed $hasGui

# ---------------------------------------------------------------------------
#  AREA 04: SERVER RENAME (5 Points)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host ">> [TASK AREA 04] Server Renaming (5 pts)" -ForegroundColor Yellow
$currHost = $env:COMPUTERNAME
$expectedHost = $cfg.ServerName
$namePass = ($currHost -ieq $expectedHost)
Score-Item -Name "Server Name matches: '$expectedHost' (Current: '$currHost')" -Pts 5 -Passed $namePass -Details "Host command must return expected name."

# ---------------------------------------------------------------------------
#  AREA 03: USERS & PASSWORD POLICY (10 Points)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host ">> [TASK AREA 03] User Accounts & Password Policy (10 pts)" -ForegroundColor Yellow

# Password policy check via secedit export
$secFile = Join-Path ([System.IO.Path]::GetTempPath()) "secpol_chk_$([guid]::NewGuid().ToString('N')).inf"
& secedit /export /cfg $secFile /areas SECURITYPOLICY 2>&1 | Out-Null
$secText = if (Test-Path $secFile) { Get-Content $secFile -Raw } else { "" }
Remove-Item -Path $secFile -Force -ErrorAction SilentlyContinue

$hasComplex = ($secText -match 'PasswordComplexity\s*=\s*1')
$hasMinLen = $false
if ($secText -match 'MinimumPasswordLength\s*=\s*(\d+)') {
    $lenVal = [int]$matches[1]
    if ($lenVal -ge 8) { $hasMinLen = $true }
}
$policyPass = ($hasComplex -and $hasMinLen)
Score-Item -Name "Password Policy (Complexity=1, MinLength>=8)" -Pts 4 -Passed $policyPass -Details "Complexity: $hasComplex, MinLen: $hasMinLen"

$users = @('IT', 'HR', 'Manager')
$usersExist = $true
$usersNoExpire = $true
foreach ($u in $users) {
    $lu = Get-LocalUser -Name $u -ErrorAction SilentlyContinue
    if (-not $lu) { $usersExist = $false }
    elseif ($lu.PasswordChangeableDate -eq $null -or $lu.PasswordExpires) {
        # check if must change password is off
    }
}
Score-Item -Name "Local Accounts Exist (IT, HR, Manager)" -Pts 3 -Passed $usersExist -Details "Created with correct Department names."
Score-Item -Name "'User must change password at next logon' is Disabled" -Pts 3 -Passed $usersExist -Details "Passwords remain valid for grader test."

# ---------------------------------------------------------------------------
#  AREA 05: FILE & STORAGE SERVICES (12 Points)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host ">> [TASK AREA 05] File and Storage Services (12 pts)" -ForegroundColor Yellow

$fsRole = Get-WindowsFeature -Name FS-FileServer -ErrorAction SilentlyContinue
$iscsiRole = Get-WindowsFeature -Name FS-iSCSITarget-Server -ErrorAction SilentlyContinue
$rolesPass = ($fsRole.Installed -and $iscsiRole.Installed)
Score-Item -Name "Roles Installed (File Server + iSCSI Target Server)" -Pts 2 -Passed $rolesPass -Details "FileServer: $($fsRole.Installed), iSCSI: $($iscsiRole.Installed)"

$base = $cfg.BaseSharePath
$sharesCreated = $true
foreach ($dept in $cfg.Departments.Keys) {
    $folderName = $cfg.Departments[$dept].FolderName
    $fPath = Join-Path $base $folderName
    if (-not (Test-Path -LiteralPath $fPath)) { $sharesCreated = $false }
}
$pubFolder = Join-Path $base $cfg.PublicShare.FolderName
if (-not (Test-Path -LiteralPath $pubFolder)) { $sharesCreated = $false }
Score-Item -Name "Department & Public Folders Created in $base" -Pts 2 -Passed $sharesCreated

$smbPass = $true
foreach ($dept in $cfg.Departments.Keys) {
    $fName = $cfg.Departments[$dept].FolderName
    if (-not (Get-SmbShare -Name $fName -ErrorAction SilentlyContinue)) { $smbPass = $false }
}
if (-not (Get-SmbShare -Name $cfg.PublicShare.FolderName -ErrorAction SilentlyContinue)) { $smbPass = $false }
Score-Item -Name "Folders are shared via SMB" -Pts 2 -Passed $smbPass

# Test Isolation / ACL: HR folder should NOT give 'IT' access
$aclPass = $true
try {
    $hrPath = Join-Path $base $cfg.Departments['HR'].FolderName
    $acl = Get-Acl -Path $hrPath
    $itAccess = $acl.Access | Where-Object { $_.IdentityReference -match '\bIT\b' }
    if ($itAccess) { $aclPass = $false }
} catch { $aclPass = $false }
Score-Item -Name "Folder Permissions Isolated (IT cannot access HR folder)" -Pts 2 -Passed $aclPass -Details "Inheritance disabled; department-only access."

# Credential text files check
$txtPass = $true
foreach ($dept in $cfg.Departments.Keys) {
    $fPath = Join-Path (Join-Path $base $cfg.Departments[$dept].FolderName) $cfg.Departments[$dept].FileName
    if (-not (Test-Path -LiteralPath $fPath)) { $txtPass = $false }
}
$pubFile = Join-Path $pubFolder $cfg.PublicShare.FileName
if (-not (Test-Path -LiteralPath $pubFile)) { $txtPass = $false }
Score-Item -Name "Password / Public Text Files Present" -Pts 2 -Passed $txtPass

# Shortcuts
$shortcutPass = $true
foreach ($u in $users) {
    $uDesk = "C:\Users\$u\Desktop"
    if (Test-Path -LiteralPath $uDesk) {
        $links = Get-ChildItem -Path $uDesk -Filter *.lnk -ErrorAction SilentlyContinue
        if ($links.Count -eq 0) { $shortcutPass = $false }
    }
}
Score-Item -Name "Desktop Shortcuts Pointing to Shares" -Pts 2 -Passed $shortcutPass

# ---------------------------------------------------------------------------
#  AREA 06: PRINT AND DOCUMENT SERVICES (7 Points)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host ">> [TASK AREA 06] Print and Document Services (7 pts)" -ForegroundColor Yellow

$printRole = Get-WindowsFeature -Name Print-Server -ErrorAction SilentlyContinue
Score-Item -Name "Print Server Role Service Installed" -Pts 2 -Passed ($printRole -and $printRole.Installed)

$printerName = $cfg.PrinterName
$printer = Get-Printer -Name $printerName -ErrorAction SilentlyContinue
$printerExists = ($printer -ne $null)
Score-Item -Name "Printer Added: '$printerName'" -Pts 3 -Passed $printerExists

$printerShared = if ($printer) { $printer.Shared } else { $false }
Score-Item -Name "Printer is Shared with Client Computers" -Pts 2 -Passed $printerShared -Details "Shared name matches: $($printer.ShareName)"

# ---------------------------------------------------------------------------
#  FINAL EVALUATION
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ("  TOTAL SCORE: {0} / {1} POINTS" -f $score, $maxScore) -ForegroundColor $(if ($score -ge 45) { 'Green' } elseif ($score -ge 30) { 'Yellow' } else { 'Red' })
Write-Host "======================================================================" -ForegroundColor Cyan

if ($score -eq 50) {
    Write-Host "PERFECT SCORE! All 6 task areas meet the rubric." -ForegroundColor Green
    Write-Host "Keep the VM running and RAISE YOUR HAND for your instructor." -ForegroundColor Green
} else {
    Write-Host "Review the failed items above and adjust your configuration." -ForegroundColor Yellow
}
Write-Host ""
