<#
.SYNOPSIS
    IT 311 Final Lab - monochrome control panel (zero dependencies).
.DESCRIPTION
    A strictly black-and-white Windows Forms launcher that reads and writes
    config.psd1, builds the VirtualBox VM, packs lab_scripts.iso, and copies
    the guest command to the clipboard.
.NOTES
    Run through Start_Lab_UI.bat, or:
    powershell -NoProfile -STA -ExecutionPolicy Bypass -File launcher.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:ScriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    (Get-Location).ProviderPath
} else {
    $PSScriptRoot
}
$script:ConfigPath = Join-Path $script:ScriptRoot 'config.psd1'
$script:IsWindowsHost = ($env:OS -eq 'Windows_NT')
$script:GuestCommand = 'Set-ExecutionPolicy Bypass -Scope Process -Force; D:\2_configure_server.ps1'

$script:Ink = [System.Drawing.Color]::FromArgb(0, 0, 0)
$script:Paper = [System.Drawing.Color]::FromArgb(255, 255, 255)

$script:RunQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
$script:ActiveProcess = $null
$script:ExitSeenAt = $null
$script:StreamLogPath = $null
$script:StreamLogRead = 0
$script:StreamExitSeenAt = $null
$script:ActionButtons = @()

$script:GuideSteps = @(
    @{
        Title = 'STEP 1 OF 9 - WHAT YOU NEED'
        Body = 'Before exam day, make sure all of these are true:

- VirtualBox is installed (this PC: D:\VirtualBox\VBoxManage.exe).
- The Windows Server 2022 ISO is in D:\SAM_LAB (SERVER_EVAL_x64FRE_en-us.iso).
- The toolkit files are in D:\SAM_LAB.
- You know your section number (e.g. 3106).
- You know your department names, passwords, folders, and file names from the sheet.

Read the instruction sheet once before touching the PC.
Write down the exact VM name, server name, printer name, and share names.
Spelling counts for grading.'
    }
    @{
        Title = 'STEP 2 OF 9 - EDIT CONFIG.PSD1'
        Body = 'Open the GUI: double-click Start_Lab_UI.bat
Or edit D:\SAM_LAB\config.psd1 in Notepad.

Fields to fill:
  VMName              = Lab_Exam_VM
  RAM_MB              = 4096
  Disk_GB             = 30
  NetMode             = bridged
  BridgeAdapter       = (leave blank)
  ISOPath             = (leave blank to auto-detect the newest *.iso in this folder)
  ServerName          = Lab-Server-01  (max 15 chars, no spaces)
  SectionAdminPassword= 3106@BatStateU
  BaseSharePath       = C:\Shares
  Departments:
    IT       password Tech#Dept2026   folder IT_Share      file it.txt
    HR       password People#Dept2026 folder HR_Share      file hr.txt
    Manager  password Lead#Dept2026   folder Manager_Share file manager.txt
  PublicShare         folder Public_Share  file public.txt
  PrinterPort         = LPT1:
  PrinterName         = Office-Printer

Click SAVE CONFIG. Then click PACK ISO.'
    }
    @{
        Title = 'STEP 3 OF 9 - BUILD THE VM'
        Body = 'Click "1. BUILD VM" in the launcher.
Or run: powershell -ExecutionPolicy Bypass -File .\1_build_vm.ps1 -Start

The builder creates the VM, sets RAM/disk/network, attaches the ISO.
It does NOT auto-install Windows. You install Windows yourself.

The builder prints a PASS/FAIL verification summary (RAM, VDI, network, ISO).'
    }
    @{
        Title = 'STEP 4 OF 9 - INSTALL WINDOWS SERVER 2022 (MANUAL)'
        Body = '1. Start the VM in VirtualBox.
2. Press any key to boot from CD.
3. Choose language, click Next, Install now.
4. IMPORTANT: select "Windows Server 2022 Standard Evaluation (Desktop Experience)".
   Do NOT pick Server Core.
5. Accept license, click Next.
6. Custom install, select the disk, Next.
7. Wait for install and reboot.
8. Set Administrator password: 3106@BatStateU
9. Log in as Administrator.'
    }
    @{
        Title = 'STEP 5 OF 9 - RUN THE GUEST SCRIPT (TASKS 3-6)'
        Body = '5a. Mount lab_scripts.iso in the guest
  Devices -> Optical Drives -> Choose disk image -> lab_scripts.iso

5b. First run (renames server, then reboots)
  Open PowerShell as Administrator in the guest.
  Set-ExecutionPolicy Bypass -Scope Process -Force
  D:\2_configure_server.ps1
  Press Y when asked to reboot. Script exits. This is normal.

5c. Second run (after reboot, completes everything)
  Log in as Administrator.
  Re-mount lab_scripts.iso.
  Open PowerShell as Administrator.
  Set-ExecutionPolicy Bypass -Scope Process -Force
  D:\2_configure_server.ps1
  This creates users, shares, ACLs, printer, and verifies.'
    }
    @{
        Title = 'STEP 6 OF 9 - MANUAL VERIFICATION (YOU MUST DO)'
        Body = '6.1 Log in once as IT, HR, and Manager.
     (Windows creates their profile folders on first login.)

6.2 Re-run D:\2_configure_server.ps1 after those logins
     so shortcuts land in the real profile folders.

6.3 Check each user Desktop:
     - Each user sees ONLY their own share shortcut.
     - Each user sees the Public_Share shortcut.
     - No other department shortcuts.

6.4 Test "Access is denied":
     Log in as IT. Open \\Lab-Server-01\HR_Share
     -> must show "Access is denied."
     Repeat for Manager_Share.

6.5 Check the printer:
     Open \\Lab-Server-01 -> Office-Printer should appear.

6.6 Check credential files:
     C:\Shares\IT_Share\it.txt          -> Tech#Dept2026
     C:\Shares\HR_Share\hr.txt          -> People#Dept2026
     C:\Shares\Manager_Share\manager.txt -> Lead#Dept2026
     C:\Shares\Public_Share\public.txt  -> public info

6.7 Leave the VM running. Raise your hand.'
    }
    @{
        Title = 'STEP 7 OF 9 - COMMON MISTAKES (AVOID)'
        Body = '- Wrong VM name or OS type -> use Windows2022_64
- RAM under 2048 or disk under 20 GB
- Network not bridged
- Letting VirtualBox auto-install Windows
- Picking Server Core instead of Desktop Experience
- Server name over 15 chars or with spaces
- Creating shares before rename
- Losing Admin/SYSTEM access on folders
- Leaking department shortcuts to public desktop
- Double extensions like it.txt.txt
- Leaving "must change password" ON
- Not applying password policy
- Printer not shared
- Shutting down the VM before grading'
    }
    @{
        Title = 'STEP 8 OF 9 - TROUBLESHOOTING'
        Body = 'VBoxManage not found -> install VirtualBox or add to PATH
VM already exists -> use -Recreate or delete in VirtualBox
ISO build fails -> rerun 3_pack_iso.ps1
config parse error -> check quotes
Guest script access denied -> run PowerShell as Administrator
Shortcuts missing -> log in as each user, rerun guest script
Printer driver fails -> script retries with Windows x64 automatically'
    }
    @{
        Title = 'STEP 9 OF 9 - QUICK REFERENCE'
        Body = 'VM NAME:        Lab_Exam_VM
RAM:            4096 MB
DISK:           30 GB dynamic
NETWORK:        Bridged
SERVER NAME:    Lab-Server-01
ADMIN PASSWORD: 3106@BatStateU
BASE SHARE:     C:\Shares
PRINTER:        Office-Printer on LPT1:

DEPARTMENTS
  IT       Tech#Dept2026   IT_Share      it.txt
  HR       People#Dept2026 HR_Share      hr.txt
  Manager  Lead#Dept2026   Manager_Share manager.txt
  Public                   Public_Share  public.txt

GUEST COMMAND (run as Admin in guest):
  Set-ExecutionPolicy Bypass -Scope Process -Force
  D:\2_configure_server.ps1
  (run twice: before reboot, then after)

FINAL: leave VM running, raise hand.'
    }
)

trap {
    $message = ($_ | Out-String)
    try {
        $log = Join-Path $script:ScriptRoot 'launcher_error.log'
        [System.IO.File]::AppendAllText($log, ((Get-Date -Format 's') + '  ' + $message + [Environment]::NewLine))
    } catch { }
    try {
        [void][System.Windows.Forms.MessageBox]::Show($message, 'IT 311 Launcher')
    } catch { }
    exit 1
}

[System.Windows.Forms.Application]::EnableVisualStyles()

function New-UiFont {
    param([single]$Size, [string]$Style = 'Regular')
    return [System.Drawing.Font]::new('Consolas', $Size, [System.Drawing.FontStyle]$Style, [System.Drawing.GraphicsUnit]::Point)
}

$script:FontBody = New-UiFont 9.75
$script:FontSmall = New-UiFont 8.25
$script:FontSmallBold = New-UiFont 8.25 'Bold'
$script:FontBold = New-UiFont 9.75 'Bold'
$script:FontSection = New-UiFont 10.5 'Bold'
$script:FontTitle = New-UiFont 15 'Bold'

# ---------------------------------------------------------------------------
#  Form shell
# ---------------------------------------------------------------------------
$form = [System.Windows.Forms.Form]::new()
$form.Text = 'IT 311 // LAB CONTROL PANEL'
$form.BackColor = $script:Paper
$form.ForeColor = $script:Ink
$form.Font = $script:FontBody
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.MaximizeBox = $true
$form.MinimizeBox = $true
$form.KeyPreview = $true

$workArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$formWidth = [Math]::Min(1020, [Math]::Max(880, $workArea.Width - 60))
$formHeight = [Math]::Min(980, [Math]::Max(640, $workArea.Height - 60))
$form.ClientSize = [System.Drawing.Size]::new($formWidth, $formHeight)
$form.MinimumSize = [System.Drawing.Size]::new(900, 620)

$grid = [System.Windows.Forms.TableLayoutPanel]::new()
$grid.Dock = [System.Windows.Forms.DockStyle]::Fill
$grid.ColumnCount = 1
$grid.RowCount = 2
$grid.BackColor = $script:Paper
[void]$grid.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))
[void]$grid.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))
[void]$grid.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Absolute, 170))
$form.Controls.Add($grid)

$script:scroll = [System.Windows.Forms.Panel]::new()
$script:scroll.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:scroll.AutoScroll = $true
$script:scroll.BackColor = $script:Paper
$script:scroll.AutoScrollMinSize = [System.Drawing.Size]::new(990, 752)
$grid.Controls.Add($script:scroll, 0, 0)

$console = [System.Windows.Forms.Panel]::new()
$console.Dock = [System.Windows.Forms.DockStyle]::Fill
$console.BackColor = $script:Paper
$console.Padding = [System.Windows.Forms.Padding]::new(24, 6, 24, 12)
$grid.Controls.Add($console, 0, 1)

$consoleHeader = [System.Windows.Forms.Panel]::new()
$consoleHeader.Dock = [System.Windows.Forms.DockStyle]::Top
$consoleHeader.Height = 30
$consoleHeader.BackColor = $script:Paper
$console.Controls.Add($consoleHeader)

$lblConsole = [System.Windows.Forms.Label]::new()
$lblConsole.Text = 'CONSOLE OUTPUT'
$lblConsole.Font = $script:FontSection
$lblConsole.ForeColor = $script:Ink
$lblConsole.BackColor = $script:Paper
$lblConsole.Dock = [System.Windows.Forms.DockStyle]::Left
$lblConsole.Width = 300
$lblConsole.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblConsole.AutoSize = $false
$consoleHeader.Controls.Add($lblConsole)

# ---------------------------------------------------------------------------
#  Helpers
# ---------------------------------------------------------------------------
function New-Label {
    param(
        [System.Windows.Forms.Control]$Parent = $script:scroll,
        [string]$Text = '',
        [int]$X = 0,
        [int]$Y = 0,
        [int]$W = 100,
        [int]$H = 18,
        [System.Drawing.Font]$Font = $script:FontBody,
        [string]$Align = 'MiddleLeft'
    )
    $label = [System.Windows.Forms.Label]::new()
    $label.Text = $Text
    $label.Location = [System.Drawing.Point]::new($X, $Y)
    $label.Size = [System.Drawing.Size]::new($W, $H)
    $label.Font = $Font
    $label.BackColor = $script:Paper
    $label.ForeColor = $script:Ink
    $label.TextAlign = $Align
    $label.AutoSize = $false
    $label.UseMnemonic = $false
    $Parent.Controls.Add($label)
    return $label
}

function New-Rule {
    param([int]$Y, [int]$X = 24, [int]$W = 962)
    $rule = [System.Windows.Forms.Panel]::new()
    $rule.Location = [System.Drawing.Point]::new($X, $Y)
    $rule.Size = [System.Drawing.Size]::new($W, 1)
    $rule.BackColor = $script:Ink
    $script:scroll.Controls.Add($rule)
}

function New-SectionHeader {
    param([int]$Y, [string]$Text)
    [void](New-Label -Text $Text -X 24 -Y $Y -W 700 -H 18 -Font $script:FontSection)
    New-Rule -Y ($Y + 20)
}

function New-TextBox {
    param(
        [string]$Text = '',
        [int]$X = 0,
        [int]$Y = 0,
        [int]$W = 200,
        [switch]$Password,
        [int]$MaxLength = 0
    )
    $box = [System.Windows.Forms.TextBox]::new()
    $box.Text = $Text
    $box.Location = [System.Drawing.Point]::new($X, $Y)
    $box.Width = $W
    $box.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $box.BackColor = $script:Paper
    $box.ForeColor = $script:Ink
    $box.Font = $script:FontBody
    if ($MaxLength -gt 0) { $box.MaxLength = $MaxLength }
    if ($Password) { $box.UseSystemPasswordChar = $true }
    $script:scroll.Controls.Add($box)
    return $box
}

function New-Combo {
    param(
        [string[]]$Items = @(),
        [string]$Selected = '',
        [int]$X = 0,
        [int]$Y = 0,
        [int]$W = 160
    )
    $combo = [System.Windows.Forms.ComboBox]::new()
    $combo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $combo.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $combo.BackColor = $script:Paper
    $combo.ForeColor = $script:Ink
    $combo.Font = $script:FontBody
    $combo.Location = [System.Drawing.Point]::new($X, $Y)
    $combo.Width = $W
    foreach ($item in $Items) { [void]$combo.Items.Add($item) }
    if (-not [string]::IsNullOrWhiteSpace($Selected) -and -not $combo.Items.Contains($Selected)) {
        [void]$combo.Items.Add($Selected)
    }
    if (-not [string]::IsNullOrWhiteSpace($Selected)) {
        $combo.SelectedItem = $Selected
    } elseif ($combo.Items.Count -gt 0) {
        $combo.SelectedIndex = 0
    }
    $script:scroll.Controls.Add($combo)
    return $combo
}

function New-MonoButton {
    param(
        [string]$Text,
        [int]$X = 0,
        [int]$Y = 0,
        [int]$W = 200,
        [int]$H = 38,
        [switch]$Small,
        [System.Windows.Forms.Control]$Parent = $script:scroll
    )
    $button = [System.Windows.Forms.Button]::new()
    $button.Text = $Text
    $button.Location = [System.Drawing.Point]::new($X, $Y)
    $button.Size = [System.Drawing.Size]::new($W, $H)
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderColor = $script:Ink
    $button.FlatAppearance.BorderSize = 1
    $button.FlatAppearance.MouseOverBackColor = $script:Ink
    $button.FlatAppearance.MouseDownBackColor = $script:Ink
    $button.BackColor = $script:Paper
    $button.ForeColor = $script:Ink
    $button.Font = if ($Small) { $script:FontSmallBold } else { $script:FontBold }
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.UseVisualStyleBackColor = $false
    $button.add_MouseEnter({
            if ($this.Enabled) {
                $this.BackColor = $script:Ink
                $this.ForeColor = $script:Paper
            }
        })
    $button.add_MouseLeave({
            $this.BackColor = $script:Paper
            $this.ForeColor = $script:Ink
        })
    $Parent.Controls.Add($button)
    return $button
}

function Add-LogLine {
    param([string]$Text)
    if ($null -eq $script:rtbLog) { return }
    $script:rtbLog.AppendText([string]$Text + "`r`n")
    if ($script:rtbLog.TextLength -gt 300000) {
        $script:rtbLog.Select(0, 100000)
        $script:rtbLog.SelectedText = ''
    }
    $script:rtbLog.SelectionStart = $script:rtbLog.TextLength
    $script:rtbLog.ScrollToCaret()
}

function Append-LogRaw {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return }
    $script:rtbLog.AppendText($Text)
    if ($script:rtbLog.TextLength -gt 300000) {
        $script:rtbLog.Select(0, 100000)
        $script:rtbLog.SelectedText = ''
    }
    $script:rtbLog.SelectionStart = $script:rtbLog.TextLength
    $script:rtbLog.ScrollToCaret()
}

function Read-SharedText {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    $stream = $null
    $reader = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)
        return $reader.ReadToEnd()
    } catch {
        return ''
    } finally {
        if ($reader) { try { $reader.Dispose() } catch { } }
        if ($stream) { try { $stream.Dispose() } catch { } }
    }
}

function Add-LogBanner {
    param([string]$Title)
    Add-LogLine ''
    Add-LogLine ('=' * 70)
    Add-LogLine ('  ' + $Title + '  //  ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    Add-LogLine ('=' * 70)
}

function Set-Status {
    param([string]$Text, [bool]$IsError = $false)
    if ($null -eq $script:lblStatus) { return }
    $script:lblStatus.Text = $Text
    if ($IsError) {
        $script:lblStatus.BackColor = $script:Ink
        $script:lblStatus.ForeColor = $script:Paper
    } else {
        $script:lblStatus.BackColor = $script:Paper
        $script:lblStatus.ForeColor = $script:Ink
    }
}

function Set-ActionButtonsEnabled {
    param([bool]$Enabled)
    foreach ($button in $script:ActionButtons) {
        if ($button) { $button.Enabled = $Enabled }
    }
}

# ---------------------------------------------------------------------------
#  Header
# ---------------------------------------------------------------------------
[void](New-Label -Text 'IT 311 // LAB CONTROL PANEL' -X 24 -Y 14 -W 800 -H 30 -Font $script:FontTitle)
[void](New-Label -Text ('config: ' + $script:ConfigPath) -X 24 -Y 46 -W 900 -H 16 -Font $script:FontSmall)
[void](New-Label -Text 'monochrome  |  no dependencies  |  windows forms' -X 24 -Y 64 -W 600 -H 16 -Font $script:FontSmall)
$btnGuide = New-MonoButton -Text 'GUIDE' -X 900 -Y 14 -W 80 -H 30 -Small
New-Rule -Y 84

# ---------------------------------------------------------------------------
#  01 - Virtual machine
# ---------------------------------------------------------------------------
New-SectionHeader -Y 94 -Text '01 / VIRTUAL MACHINE'

[void](New-Label -Text 'VM NAME' -X 24 -Y 124 -W 110 -H 24)
$tbVMName = New-TextBox -X 140 -Y 123 -W 220

[void](New-Label -Text 'RAM (MB)' -X 400 -Y 124 -W 80 -H 24)
$tbRAM = New-TextBox -X 484 -Y 123 -W 110

[void](New-Label -Text 'DISK (GB)' -X 640 -Y 124 -W 80 -H 24)
$tbDisk = New-TextBox -X 724 -Y 123 -W 110

[void](New-Label -Text 'NETWORK' -X 24 -Y 162 -W 80 -H 24)
$comboNet = New-Combo -Items @('bridged', 'nat', 'hostonly', 'intnet') -X 140 -Y 161 -W 170

[void](New-Label -Text 'BRIDGE ADAPTER' -X 350 -Y 162 -W 140 -H 24)
$tbBridge = New-TextBox -X 492 -Y 161 -W 330
[void](New-Label -Text 'leave blank to auto-detect the active physical NIC' -X 492 -Y 188 -W 420 -H 16 -Font $script:FontSmall)

[void](New-Label -Text 'ISO PATH' -X 24 -Y 208 -W 80 -H 24)
$tbISO = New-TextBox -X 140 -Y 207 -W 560
$btnBrowse = New-MonoButton -Text 'BROWSE...' -X 712 -Y 205 -W 130 -H 28 -Small

# ---------------------------------------------------------------------------
#  02 - Server identity
# ---------------------------------------------------------------------------
New-SectionHeader -Y 246 -Text '02 / SERVER IDENTITY'

[void](New-Label -Text 'SERVER NAME' -X 24 -Y 276 -W 120 -H 24)
$tbServerName = New-TextBox -X 152 -Y 275 -W 260 -MaxLength 40
$script:lblServerFeedback = New-Label -Text 'SERVER NAME  0/15  |  ENTER A NAME' -X 428 -Y 274 -W 540 -H 26 -Font $script:FontSmall
$script:lblServerFeedback.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$script:lblServerFeedback.Padding = [System.Windows.Forms.Padding]::new(8, 0, 8, 0)
$script:lblServerFeedback.BackColor = $script:Ink
$script:lblServerFeedback.ForeColor = $script:Paper

[void](New-Label -Text 'SECTION ADMIN PASSWORD' -X 24 -Y 312 -W 190 -H 24)
$tbAdminPassword = New-TextBox -X 222 -Y 311 -W 300 -Password
[void](New-Label -Text '<section>@BatStateU   e.g. 3106@BatStateU' -X 536 -Y 314 -W 440 -H 20 -Font $script:FontSmall)

# ---------------------------------------------------------------------------
#  03 - File shares
# ---------------------------------------------------------------------------
New-SectionHeader -Y 350 -Text '03 / FILE SHARES'

[void](New-Label -Text 'BASE SHARE PATH' -X 24 -Y 380 -W 160 -H 24)
$tbBaseShare = New-TextBox -X 192 -Y 379 -W 320
[void](New-Label -Text 'e.g. C:\Shares' -X 524 -Y 382 -W 300 -H 20 -Font $script:FontSmall)

[void](New-Label -Text 'DEPARTMENT' -X 24 -Y 412 -W 120 -H 16 -Font $script:FontSmallBold)
[void](New-Label -Text 'FOLDER NAME' -X 180 -Y 412 -W 280 -H 16 -Font $script:FontSmallBold)
[void](New-Label -Text 'FILE NAME' -X 500 -Y 412 -W 280 -H 16 -Font $script:FontSmallBold)

[void](New-Label -Text 'IT' -X 24 -Y 428 -W 120 -H 24 -Font $script:FontBold)
$tbITFolder = New-TextBox -X 180 -Y 427 -W 300
$tbITFile = New-TextBox -X 500 -Y 427 -W 280

[void](New-Label -Text 'HR' -X 24 -Y 462 -W 120 -H 24 -Font $script:FontBold)
$tbHRFolder = New-TextBox -X 180 -Y 461 -W 300
$tbHRFile = New-TextBox -X 500 -Y 461 -W 280

[void](New-Label -Text 'MANAGER' -X 24 -Y 496 -W 120 -H 24 -Font $script:FontBold)
$tbMgrFolder = New-TextBox -X 180 -Y 495 -W 300
$tbMgrFile = New-TextBox -X 500 -Y 495 -W 280

[void](New-Label -Text 'PUBLIC' -X 24 -Y 530 -W 120 -H 24 -Font $script:FontBold)
$tbPubFolder = New-TextBox -X 180 -Y 529 -W 300
$tbPubFile = New-TextBox -X 500 -Y 529 -W 280

[void](New-Label -Text 'Credential files are written as <name>.txt automatically when no extension is given. Department passwords are preserved.' -X 24 -Y 564 -W 900 -H 16 -Font $script:FontSmall)

# ---------------------------------------------------------------------------
#  04 - Printer
# ---------------------------------------------------------------------------
New-SectionHeader -Y 592 -Text '04 / PRINTER'

[void](New-Label -Text 'PRINTER PORT' -X 24 -Y 622 -W 120 -H 24)
$comboPort = New-Combo -Items @('LPT1:', 'FILE:') -X 150 -Y 621 -W 150

[void](New-Label -Text 'PRINTER NAME' -X 330 -Y 622 -W 120 -H 24)
$tbPrinterName = New-TextBox -X 456 -Y 621 -W 280

# ---------------------------------------------------------------------------
#  Actions and status
# ---------------------------------------------------------------------------
$btnSave = New-MonoButton -Text '[ SAVE CONFIG ]' -X 24 -Y 664 -W 226 -H 40
$btnBuild = New-MonoButton -Text '[ 1. BUILD VM ]' -X 262 -Y 664 -W 226 -H 40
$btnPack = New-MonoButton -Text '[ 2. PACK ISO ]' -X 500 -Y 664 -W 226 -H 40
$btnCopy = New-MonoButton -Text '[ 3. COPY GUEST COMMAND ]' -X 738 -Y 664 -W 226 -H 40
$script:ActionButtons = @($btnSave, $btnBuild, $btnPack)

$script:lblStatus = New-Label -Text 'Starting...' -X 24 -Y 716 -W 962 -H 28
$script:lblStatus.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$script:lblStatus.Padding = [System.Windows.Forms.Padding]::new(8, 0, 8, 0)

# ---------------------------------------------------------------------------
#  Console log
# ---------------------------------------------------------------------------
$btnClear = New-MonoButton -Text 'CLEAR' -X 0 -Y 0 -W 90 -H 26 -Small -Parent $consoleHeader
$btnClear.Dock = [System.Windows.Forms.DockStyle]::Right

$script:rtbLog = [System.Windows.Forms.RichTextBox]::new()
$script:rtbLog.Dock = [System.Windows.Forms.DockStyle]::Fill
$script:rtbLog.BackColor = $script:Ink
$script:rtbLog.ForeColor = $script:Paper
$script:rtbLog.Font = New-UiFont 9
$script:rtbLog.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$script:rtbLog.ReadOnly = $true
$script:rtbLog.WordWrap = $false
$script:rtbLog.DetectUrls = $false
$script:rtbLog.HideSelection = $false
$script:rtbLog.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$console.Controls.Add($script:rtbLog)

# ---------------------------------------------------------------------------
#  Config.psd1 read / write
# ---------------------------------------------------------------------------
function ConvertTo-PsString {
    param([AllowEmptyString()][string]$Value)
    if ($null -eq $Value) { $Value = '' }
    return "'" + $Value.Replace("'", "''") + "'"
}

function Set-ConfigLine {
    param([string]$Text, [string]$Key, [string]$Literal)
    $pattern = '(?m)^([ \t]*' + [regex]::Escape($Key) + '[ \t]*=[ \t]*)([^\r\n]*)$'
    $rx = [regex]::new($pattern)
    if (-not $rx.IsMatch($Text)) { throw "config.psd1 is missing the '$Key' key." }
    $evaluator = { param($m) $m.Groups[1].Value + $Literal }.GetNewClosure()
    return $rx.Replace($Text, [System.Text.RegularExpressions.MatchEvaluator]$evaluator)
}

function Set-ConfigDepartment {
    param([string]$Text, [string]$Dept, [string]$Folder, [string]$File)
    $pattern = "(?m)^([ \t]*" + [regex]::Escape($Dept) + "[ \t]*=[ \t]*@\{[^\r\n]*?FolderName[ \t]*=[ \t]*)'[^']*'([^\r\n]*?FileName[ \t]*=[ \t]*)'[^']*'"
    $rx = [regex]::new($pattern)
    if (-not $rx.IsMatch($Text)) { throw "config.psd1 is missing the '$Dept' department entry." }
    $folderLiteral = ConvertTo-PsString $Folder
    $fileLiteral = ConvertTo-PsString $File
    $evaluator = {
        param($m)
        $m.Groups[1].Value + $folderLiteral + $m.Groups[2].Value + $fileLiteral
    }.GetNewClosure()
    return $rx.Replace($Text, [System.Text.RegularExpressions.MatchEvaluator]$evaluator)
}

function Set-ConfigPublicShare {
    param([string]$Text, [string]$Folder, [string]$File)
    $pattern = "(?ms)^([ \t]*PublicShare[ \t]*=[ \t]*@\{.*?FolderName[ \t]*=[ \t]*)'[^']*'(.*?FileName[ \t]*=[ \t]*)'[^']*'"
    $rx = [regex]::new($pattern)
    if (-not $rx.IsMatch($Text)) { throw "config.psd1 is missing the 'PublicShare' entry." }
    $folderLiteral = ConvertTo-PsString $Folder
    $fileLiteral = ConvertTo-PsString $File
    $evaluator = {
        param($m)
        $m.Groups[1].Value + $folderLiteral + $m.Groups[2].Value + $fileLiteral
    }.GetNewClosure()
    return $rx.Replace($Text, [System.Text.RegularExpressions.MatchEvaluator]$evaluator)
}

function Get-ConfigString {
    param($Config, [string]$Key)
    if ($null -eq $Config) { return '' }
    if ($Config -is [System.Collections.IDictionary] -and $Config.Contains($Key)) {
        if ($null -eq $Config[$Key]) { return '' }
        return [string]$Config[$Key]
    }
    return ''
}

function Get-NameProblem {
    param([string]$Value, [string]$Label)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "$Label cannot be empty." }
    if ($Value.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) {
        return "$Label contains invalid characters."
    }
    return $null
}

function Get-ServerNameState {
    param([string]$Name)
    $value = if ($null -eq $Name) { '' } else { $Name }
    $issues = @()
    if ([string]::IsNullOrWhiteSpace($value)) {
        $issues += 'enter a name'
    } else {
        if ($value.Length -gt 15) { $issues += 'over 15 characters' }
        if ($value -notmatch '^[A-Za-z0-9-]+$') { $issues += 'use letters, numbers, hyphens only' }
        if ($value -match '^\d+$') { $issues += 'cannot be only numbers' }
        if ($value -match '^-|-$') { $issues += 'no leading or trailing hyphen' }
        if ($value -match '^-+$') { $issues += 'cannot be only hyphens' }
    }
    return [pscustomobject]@{
        Ok      = ($issues.Count -eq 0)
        Message = ($issues -join '; ')
        Length  = $value.Length
    }
}

function Update-ServerNameFeedback {
    if ($null -eq $script:lblServerFeedback) { return }
    $state = Get-ServerNameState $tbServerName.Text
    if ($state.Ok) {
        $script:lblServerFeedback.Text = ('SERVER NAME  {0}/15  |  VALID' -f $state.Length)
        $script:lblServerFeedback.BackColor = $script:Paper
        $script:lblServerFeedback.ForeColor = $script:Ink
    } else {
        $script:lblServerFeedback.Text = ('SERVER NAME  {0}/15  |  {1}' -f $state.Length, $state.Message.ToUpperInvariant())
        $script:lblServerFeedback.BackColor = $script:Ink
        $script:lblServerFeedback.ForeColor = $script:Paper
    }
}

function Save-ConfigFromForm {
    $vmName = $tbVMName.Text.Trim()
    $serverName = $tbServerName.Text.Trim()
    $adminPassword = $tbAdminPassword.Text
    $baseShare = $tbBaseShare.Text.Trim()
    $printerName = $tbPrinterName.Text.Trim()
    $printerPort = [string]$comboPort.SelectedItem
    $netMode = [string]$comboNet.SelectedItem

    $ram = 0
    $disk = 0
    $ramOk = [int]::TryParse($tbRAM.Text.Trim(), [ref]$ram)
    $diskOk = [int]::TryParse($tbDisk.Text.Trim(), [ref]$disk)

    $problems = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($vmName)) { $problems.Add('VM Name cannot be empty.') }
    if (-not $ramOk -or $ram -le 0) { $problems.Add('RAM must be a positive whole number of MB.') }
    if (-not $diskOk -or $disk -le 0) { $problems.Add('Disk must be a positive whole number of GB.') }
    if ([string]::IsNullOrWhiteSpace($netMode)) { $problems.Add('Choose a network mode.') }
    $serverState = Get-ServerNameState $serverName
    if (-not $serverState.Ok) { $problems.Add('Server name: ' + $serverState.Message + '.') }
    if ([string]::IsNullOrEmpty($adminPassword)) { $problems.Add('Section admin password cannot be empty.') }
    if ([string]::IsNullOrWhiteSpace($baseShare)) {
        $problems.Add('Base share path cannot be empty.')
    } elseif ($baseShare.IndexOfAny([System.IO.Path]::GetInvalidPathChars()) -ge 0) {
        $problems.Add('Base share path contains invalid characters.')
    }
    if ([string]::IsNullOrWhiteSpace($printerPort)) { $problems.Add('Choose a printer port.') }
    $printerProblem = Get-NameProblem $printerName 'Printer name'
    if ($printerProblem) { $problems.Add($printerProblem) }

    $pairs = @(
        @('IT folder', $tbITFolder.Text.Trim()),
        @('IT file', $tbITFile.Text.Trim()),
        @('HR folder', $tbHRFolder.Text.Trim()),
        @('HR file', $tbHRFile.Text.Trim()),
        @('Manager folder', $tbMgrFolder.Text.Trim()),
        @('Manager file', $tbMgrFile.Text.Trim()),
        @('Public folder', $tbPubFolder.Text.Trim()),
        @('Public file', $tbPubFile.Text.Trim())
    )
    foreach ($pair in $pairs) {
        $problem = Get-NameProblem $pair[1] $pair[0]
        if ($problem) { $problems.Add($problem) }
    }

    if ($problems.Count -gt 0) {
        Add-LogLine ('[save] Blocked: ' + $problems[0])
        Set-Status ('Fix before saving: ' + $problems[0]) $true
        return $false
    }

    $tempPath = Join-Path $script:ScriptRoot ('.config_validate_' + [guid]::NewGuid().ToString('N') + '.psd1')
    try {
        $text = [System.IO.File]::ReadAllText($script:ConfigPath)
        $text = Set-ConfigLine $text 'VMName' (ConvertTo-PsString $vmName)
        $text = Set-ConfigLine $text 'RAM_MB' ([string]$ram)
        $text = Set-ConfigLine $text 'Disk_GB' ([string]$disk)
        $text = Set-ConfigLine $text 'NetMode' (ConvertTo-PsString $netMode)
        $text = Set-ConfigLine $text 'BridgeAdapter' (ConvertTo-PsString $tbBridge.Text.Trim())
        $text = Set-ConfigLine $text 'ISOPath' (ConvertTo-PsString $tbISO.Text.Trim())
        $text = Set-ConfigLine $text 'ServerName' (ConvertTo-PsString $serverName)
        $text = Set-ConfigLine $text 'SectionAdminPassword' (ConvertTo-PsString $adminPassword)
        $text = Set-ConfigLine $text 'BaseSharePath' (ConvertTo-PsString $baseShare)
        $text = Set-ConfigLine $text 'PrinterPort' (ConvertTo-PsString $printerPort)
        $text = Set-ConfigLine $text 'PrinterName' (ConvertTo-PsString $printerName)
        $text = Set-ConfigDepartment $text 'IT' $tbITFolder.Text.Trim() $tbITFile.Text.Trim()
        $text = Set-ConfigDepartment $text 'HR' $tbHRFolder.Text.Trim() $tbHRFile.Text.Trim()
        $text = Set-ConfigDepartment $text 'Manager' $tbMgrFolder.Text.Trim() $tbMgrFile.Text.Trim()
        $text = Set-ConfigPublicShare $text $tbPubFolder.Text.Trim() $tbPubFile.Text.Trim()

        [System.IO.File]::WriteAllText($tempPath, $text, (New-Object System.Text.UTF8Encoding($true)))
        $parsed = Import-PowerShellDataFile -Path $tempPath
        if ([string]$parsed.VMName -ne $vmName) { throw 'Validation did not read back the new VM name.' }
        if ([int]$parsed.RAM_MB -ne $ram) { throw 'Validation did not read back the new RAM value.' }

        Move-Item -LiteralPath $tempPath -Destination $script:ConfigPath -Force
        Add-LogLine ('[save] Wrote ' + $script:ConfigPath)
        $note = ''
        if ($adminPassword -notmatch '^\d{4}@BatStateU$') {
            $note = '  |  WARNING: password is not <section>@BatStateU'
            Add-LogLine '[save] WARNING: Section admin password does not look like <section>@BatStateU.'
        }
        Set-Status ('Saved config.psd1  |  ' + $vmName + '  |  ' + $ram + ' MB  |  ' + $disk + ' GB' + $note) ($note -ne '')
        return $true
    } catch {
        Add-LogLine ('[save] ERROR: ' + $_.Exception.Message)
        Set-Status ('Save failed: ' + $_.Exception.Message) $true
        return $false
    } finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Load-ConfigIntoForm {
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) {
        Add-LogLine ('[load] config.psd1 not found: ' + $script:ConfigPath)
        Set-Status 'config.psd1 not found. Fill in the form and press Save Config.' $true
        Update-ServerNameFeedback
        return
    }
    try {
        $cfg = Import-PowerShellDataFile -Path $script:ConfigPath
    } catch {
        Add-LogLine ('[load] ' + $_.Exception.Message)
        Set-Status 'config.psd1 could not be read. See console.' $true
        Update-ServerNameFeedback
        return
    }

    $tbVMName.Text = Get-ConfigString $cfg 'VMName'
    $tbRAM.Text = Get-ConfigString $cfg 'RAM_MB'
    $tbDisk.Text = Get-ConfigString $cfg 'Disk_GB'
    $tbBridge.Text = Get-ConfigString $cfg 'BridgeAdapter'
    $tbISO.Text = Get-ConfigString $cfg 'ISOPath'
    $tbServerName.Text = Get-ConfigString $cfg 'ServerName'
    $tbAdminPassword.Text = Get-ConfigString $cfg 'SectionAdminPassword'
    $tbBaseShare.Text = Get-ConfigString $cfg 'BaseSharePath'
    $tbPrinterName.Text = Get-ConfigString $cfg 'PrinterName'

    $netMode = Get-ConfigString $cfg 'NetMode'
    if ($netMode) {
        if (-not $comboNet.Items.Contains($netMode)) { [void]$comboNet.Items.Add($netMode) }
        $comboNet.SelectedItem = $netMode
    }
    $printerPort = Get-ConfigString $cfg 'PrinterPort'
    if ($printerPort) {
        if (-not $comboPort.Items.Contains($printerPort)) { [void]$comboPort.Items.Add($printerPort) }
        $comboPort.SelectedItem = $printerPort
    }

    $departments = $cfg.Departments
    if ($departments) {
        $it = $departments['IT']
        if ($it) {
            $tbITFolder.Text = Get-ConfigString $it 'FolderName'
            $tbITFile.Text = Get-ConfigString $it 'FileName'
        }
        $hr = $departments['HR']
        if ($hr) {
            $tbHRFolder.Text = Get-ConfigString $hr 'FolderName'
            $tbHRFile.Text = Get-ConfigString $hr 'FileName'
        }
        $manager = $departments['Manager']
        if ($manager) {
            $tbMgrFolder.Text = Get-ConfigString $manager 'FolderName'
            $tbMgrFile.Text = Get-ConfigString $manager 'FileName'
        }
    }
    $publicShare = $cfg.PublicShare
    if ($publicShare) {
        $tbPubFolder.Text = Get-ConfigString $publicShare 'FolderName'
        $tbPubFile.Text = Get-ConfigString $publicShare 'FileName'
    }

    Update-ServerNameFeedback
    Add-LogLine ('[load] Loaded ' + $script:ConfigPath)
    Set-Status 'Loaded config.psd1. Review the values, then Save or run a task.' $false
}

# ---------------------------------------------------------------------------
#  Process streaming
# ---------------------------------------------------------------------------
function Get-PowerShellExe {
    foreach ($name in @('powershell.exe', 'powershell', 'pwsh.exe', 'pwsh')) {
        $candidate = Join-Path $PSHOME $name
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    $command = Get-Command powershell, pwsh -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    return $null
}

function Find-PythonCommand {
    foreach ($name in @('python3', 'python')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }
    return $null
}

function Start-StreamingProcess {
    param([string]$FileName, [string]$Arguments, [string]$Banner)
    if ($script:ActiveProcess) {
        Set-Status 'A task is already running. Wait for it to finish.' $true
        return
    }

    $script:StreamLogPath = Join-Path $env:TEMP ('lab_stream_' + [guid]::NewGuid().ToString('N') + '.log')
    $script:StreamLogRead = 0
    $script:StreamExitSeenAt = $null
    if (Test-Path -LiteralPath $script:StreamLogPath) {
        Remove-Item -LiteralPath $script:StreamLogPath -Force -ErrorAction SilentlyContinue
    }

    $command = '"' + $FileName + '" ' + $Arguments + ' > "' + $script:StreamLogPath + '" 2>&1'
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    if ($script:IsWindowsHost) {
        $psi.FileName = 'cmd.exe'
        $psi.Arguments = '/c "' + $command + '"'
    } else {
        $psi.FileName = 'sh'
        $psi.Arguments = '-c "' + $command + '"'
    }
    $psi.WorkingDirectory = $script:ScriptRoot
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    if (-not $process.Start()) { throw ('Could not start ' + $FileName) }

    $script:ActiveProcess = $process
    Set-ActionButtonsEnabled $false
    Add-LogBanner $Banner
    Add-LogLine ('> ' + $FileName + ' ' + $Arguments)
    Set-Status ($Banner + ' started - streaming output below.') $false
    if (-not $logTimer.Enabled) { $logTimer.Start() }
}

function Complete-ActiveProcess {
    $process = $script:ActiveProcess
    if (-not $process) { return }
    $code = 0
    try { $code = $process.ExitCode } catch { $code = 0 }
    try { $process.Dispose() } catch { }
    $script:ActiveProcess = $null
    $script:ExitSeenAt = $null
    $script:StreamExitSeenAt = $null
    Set-ActionButtonsEnabled $true
    if ($script:StreamLogPath -and (Test-Path -LiteralPath $script:StreamLogPath)) {
        Remove-Item -LiteralPath $script:StreamLogPath -Force -ErrorAction SilentlyContinue
    }
    $script:StreamLogPath = $null
    $script:StreamLogRead = 0
    Add-LogLine ''
    if ($code -eq 0) {
        Add-LogLine '== FINISHED WITH EXIT CODE 0 =='
        Set-Status 'Finished successfully (exit 0).' $false
    } else {
        Add-LogLine ('== FINISHED WITH EXIT CODE ' + $code + ' ==')
        Set-Status ('Finished with errors (exit ' + $code + '). See console.') $true
    }
}

# ---------------------------------------------------------------------------
#  Actions
# ---------------------------------------------------------------------------
function Invoke-BuildAction {
    if ($script:ActiveProcess) {
        Set-Status 'A task is already running. Wait for it to finish.' $true
        return
    }
    if (-not (Save-ConfigFromForm)) { return }
    try {
        if ($script:IsWindowsHost) {
            $exe = Get-PowerShellExe
            if (-not $exe) { Set-Status 'powershell.exe was not found.' $true; return }
            $target = Join-Path $script:ScriptRoot '1_build_vm.ps1'
            Start-StreamingProcess -FileName $exe -Arguments ('-NoProfile -ExecutionPolicy Bypass -File "' + $target + '"') -Banner 'TASK 01 - BUILD VM'
        } else {
            $bash = Get-Command bash -ErrorAction SilentlyContinue
            if (-not $bash) { Set-Status 'bash was not found on this system.' $true; return }
            $target = Join-Path $script:ScriptRoot '1_build_vm.sh'
            Start-StreamingProcess -FileName $bash.Source -Arguments ('"' + $target + '"') -Banner 'TASK 01 - BUILD VM (bash)'
        }
    } catch {
        Add-LogLine ('[launcher] ' + $_.Exception.Message)
        Set-ActionButtonsEnabled $true
        Set-Status ('Could not start the build: ' + $_.Exception.Message) $true
    }
}

function Invoke-PackAction {
    if ($script:ActiveProcess) {
        Set-Status 'A task is already running. Wait for it to finish.' $true
        return
    }
    if (-not (Save-ConfigFromForm)) { return }
    try {
        if ($script:IsWindowsHost) {
            $exe = Get-PowerShellExe
            if (-not $exe) { Set-Status 'powershell.exe was not found.' $true; return }
            $target = Join-Path $script:ScriptRoot '3_pack_iso.ps1'
            Start-StreamingProcess -FileName $exe -Arguments ('-NoProfile -ExecutionPolicy Bypass -File "' + $target + '"') -Banner 'TASK 02 - PACK ISO'
        } else {
            $python = Find-PythonCommand
            if (-not $python) { Set-Status 'python3/python was not found; use 3_pack_iso.ps1 instead.' $true; return }
            $target = Join-Path $script:ScriptRoot '3_pack_iso.py'
            Start-StreamingProcess -FileName $python -Arguments ('"' + $target + '"') -Banner 'TASK 02 - PACK ISO (python)'
        }
    } catch {
        Add-LogLine ('[launcher] ' + $_.Exception.Message)
        Set-ActionButtonsEnabled $true
        Set-Status ('Could not start ISO packing: ' + $_.Exception.Message) $true
    }
}

function Copy-GuestCommand {
    try {
        [System.Windows.Forms.Clipboard]::SetText($script:GuestCommand)
        Add-LogLine ('[clipboard] ' + $script:GuestCommand)
        Set-Status 'Guest command copied to the clipboard.' $false
        return
    } catch {
        Add-LogLine ('[clipboard] ' + $_.Exception.Message)
    }
    $exe = Get-PowerShellExe
    if ($script:IsWindowsHost -and $exe) {
        try {
            $escaped = $script:GuestCommand.Replace("'", "''")
            & $exe -NoProfile -STA -Command ("Set-Clipboard -Value '" + $escaped + "'") | Out-Null
            Add-LogLine ('[clipboard] ' + $script:GuestCommand)
            Set-Status 'Guest command copied to the clipboard.' $false
            return
        } catch { }
    }
    Set-Status 'Clipboard was busy. Press the button again.' $true
}

# ---------------------------------------------------------------------------
#  In-app beginner guide viewer
# ---------------------------------------------------------------------------
function Show-GuideDialog {
    $steps = $script:GuideSteps
    if (-not $steps -or $steps.Count -eq 0) {
        Set-Status 'Beginner guide is empty.' $true
        return
    }

    $script:_guideStepIndex = 0

    $dlg = [System.Windows.Forms.Form]::new()
    $dlg.Text = 'BEGINNER GUIDE - IT 311 FINAL LAB'
    $dlg.BackColor = $script:Paper
    $dlg.ForeColor = $script:Ink
    $dlg.Font = $script:FontBody
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $dlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dlg.ClientSize = [System.Drawing.Size]::new(760, 560)
    $dlg.MinimumSize = [System.Drawing.Size]::new(520, 400)

    $header = [System.Windows.Forms.Panel]::new()
    $header.Dock = [System.Windows.Forms.DockStyle]::Top
    $header.Height = 46
    $header.BackColor = $script:Paper
    $dlg.Controls.Add($header)

    $lblTitle = [System.Windows.Forms.Label]::new()
    $lblTitle.Text = 'BEGINNER GUIDE'
    $lblTitle.Font = $script:FontSection
    $lblTitle.ForeColor = $script:Ink
    $lblTitle.BackColor = $script:Paper
    $lblTitle.Location = [System.Drawing.Point]::new(16, 10)
    $lblTitle.Size = [System.Drawing.Size]::new(400, 26)
    $lblTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $header.Controls.Add($lblTitle)

    $lblStep = [System.Windows.Forms.Label]::new()
    $lblStep.Font = $script:FontSmallBold
    $lblStep.ForeColor = $script:Ink
    $lblStep.BackColor = $script:Paper
    $lblStep.Location = [System.Drawing.Point]::new(520, 14)
    $lblStep.Size = [System.Drawing.Size]::new(220, 20)
    $lblStep.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
    $header.Controls.Add($lblStep)

    $ruleTop = [System.Windows.Forms.Panel]::new()
    $ruleTop.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $ruleTop.Height = 1
    $ruleTop.BackColor = $script:Ink
    $header.Controls.Add($ruleTop)

    $box = [System.Windows.Forms.RichTextBox]::new()
    $box.ReadOnly = $true
    $box.WordWrap = $true
    $box.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
    $box.DetectUrls = $false
    $box.BackColor = $script:Paper
    $box.ForeColor = $script:Ink
    $box.Font = New-UiFont 9.5
    $box.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $box.Dock = [System.Windows.Forms.DockStyle]::Fill
    $dlg.Controls.Add($box)

    $accent = [System.Windows.Forms.Panel]::new()
    $accent.Dock = [System.Windows.Forms.DockStyle]::Left
    $accent.Width = 6
    $accent.BackColor = $script:Ink
    $dlg.Controls.Add($accent)

    $footer = [System.Windows.Forms.Panel]::new()
    $footer.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $footer.Height = 50
    $footer.BackColor = $script:Paper
    $ruleBottom = [System.Windows.Forms.Panel]::new()
    $ruleBottom.Dock = [System.Windows.Forms.DockStyle]::Top
    $ruleBottom.Height = 1
    $ruleBottom.BackColor = $script:Ink
    $footer.Controls.Add($ruleBottom)
    $dlg.Controls.Add($footer)

    $btnBack = [System.Windows.Forms.Button]::new()
    $btnBack.Text = '< BACK'
    $btnBack.Location = [System.Drawing.Point]::new(16, 10)
    $btnBack.Size = [System.Drawing.Size]::new(110, 30)
    $btnBack.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnBack.FlatAppearance.BorderColor = $script:Ink
    $btnBack.FlatAppearance.BorderSize = 1
    $btnBack.BackColor = $script:Paper
    $btnBack.ForeColor = $script:Ink
    $btnBack.Font = $script:FontBold
    $btnBack.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnBack.add_MouseEnter({ if ($this.Enabled) { $this.BackColor = $script:Ink; $this.ForeColor = $script:Paper } })
    $btnBack.add_MouseLeave({ $this.BackColor = $script:Paper; $this.ForeColor = $script:Ink })
    $footer.Controls.Add($btnBack)

    $btnNext = [System.Windows.Forms.Button]::new()
    $btnNext.Text = 'NEXT >'
    $btnNext.Location = [System.Drawing.Point]::new(330, 10)
    $btnNext.Size = [System.Drawing.Size]::new(110, 30)
    $btnNext.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnNext.FlatAppearance.BorderColor = $script:Ink
    $btnNext.FlatAppearance.BorderSize = 1
    $btnNext.BackColor = $script:Ink
    $btnNext.ForeColor = $script:Paper
    $btnNext.Font = $script:FontBold
    $btnNext.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnNext.add_MouseEnter({ if ($this.Enabled) { $this.BackColor = $script:Paper; $this.ForeColor = $script:Ink } })
    $btnNext.add_MouseLeave({ $this.BackColor = $script:Ink; $this.ForeColor = $script:Paper })
    $footer.Controls.Add($btnNext)

    $btnClose = [System.Windows.Forms.Button]::new()
    $btnClose.Text = 'CLOSE'
    $btnClose.Location = [System.Drawing.Point]::new(630, 10)
    $btnClose.Size = [System.Drawing.Size]::new(110, 30)
    $btnClose.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnClose.FlatAppearance.BorderColor = $script:Ink
    $btnClose.FlatAppearance.BorderSize = 1
    $btnClose.BackColor = $script:Paper
    $btnClose.ForeColor = $script:Ink
    $btnClose.Font = $script:FontBold
    $btnClose.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnClose.add_MouseEnter({ if ($this.Enabled) { $this.BackColor = $script:Ink; $this.ForeColor = $script:Paper } })
    $btnClose.add_MouseLeave({ $this.BackColor = $script:Paper; $this.ForeColor = $script:Ink })
    $btnClose.add_Click({ $dlg.Close() })
    $footer.Controls.Add($btnClose)

    $refresh = {
        $step = $steps[$script:_guideStepIndex]
        $box.Text = $step.Title + "`r`n" + ("=" * 56) + "`r`n`r`n" + $step.Body
        $box.SelectionStart = 0
        $box.ScrollToCaret()
        $lblStep.Text = ('Step {0} of {1}' -f ($script:_guideStepIndex + 1), $steps.Count)
        $btnBack.Enabled = ($script:_guideStepIndex -gt 0)
        if ($script:_guideStepIndex -eq $steps.Count - 1) {
            $btnNext.Text = 'FINISH'
            $btnNext.BackColor = $script:Paper
            $btnNext.ForeColor = $script:Ink
        } else {
            $btnNext.Text = 'NEXT >'
            $btnNext.BackColor = $script:Ink
            $btnNext.ForeColor = $script:Paper
        }
    }

    $btnBack.add_Click({
        if ($script:_guideStepIndex -gt 0) {
            $script:_guideStepIndex--
            & $refresh
        }
    })
    $btnNext.add_Click({
        if ($script:_guideStepIndex -lt $steps.Count - 1) {
            $script:_guideStepIndex++
            & $refresh
        } else {
            $dlg.Close()
        }
    })

    & $refresh
    [void]$dlg.ShowDialog($form)
    $dlg.Dispose()
}

# ---------------------------------------------------------------------------
#  Timer and events
# ---------------------------------------------------------------------------
$logTimer = [System.Windows.Forms.Timer]::new()
$logTimer.Interval = 120
$logTimer.add_Tick({
        try {
            if ($script:StreamLogPath -and (Test-Path -LiteralPath $script:StreamLogPath)) {
                $content = Read-SharedText -Path $script:StreamLogPath
                if ($content.Length -gt $script:StreamLogRead) {
                    $chunk = $content.Substring($script:StreamLogRead)
                    $script:StreamLogRead = $content.Length
                    Append-LogRaw $chunk
                }
            }
            if ($script:ActiveProcess) {
                if ($script:ActiveProcess.HasExited) {
                    if ($null -eq $script:StreamExitSeenAt) {
                        $script:StreamExitSeenAt = [DateTime]::UtcNow
                    } elseif (([DateTime]::UtcNow - $script:StreamExitSeenAt).TotalMilliseconds -gt 800) {
                        if ($script:StreamLogPath -and (Test-Path -LiteralPath $script:StreamLogPath)) {
                            $content = Read-SharedText -Path $script:StreamLogPath
                            if ($content.Length -gt $script:StreamLogRead) {
                                $chunk = $content.Substring($script:StreamLogRead)
                                $script:StreamLogRead = $content.Length
                                Append-LogRaw $chunk
                            }
                        }
                        Complete-ActiveProcess
                    }
                } else {
                    $script:StreamExitSeenAt = $null
                }
            }
        } catch {
            Add-LogLine ('[launcher] ' + $_.Exception.Message)
        }
    })

$btnSave.add_Click({ [void](Save-ConfigFromForm) })
$btnBuild.add_Click({ Invoke-BuildAction })
$btnPack.add_Click({ Invoke-PackAction })
$btnCopy.add_Click({ Copy-GuestCommand })

$btnGuide.add_Click({
        Show-GuideDialog
        Set-Status 'Beginner guide closed.' $false
    })
$btnClear.add_Click({
        $script:rtbLog.Clear()
        Set-Status 'Console cleared.' $false
    })

$btnBrowse.add_Click({
        $dialog = [System.Windows.Forms.OpenFileDialog]::new()
        try {
            $dialog.Title = 'Select the Windows Server 2022 ISO'
            $dialog.Filter = 'ISO images (*.iso)|*.iso|All files (*.*)|*.*'
            $dialog.CheckFileExists = $true
            $current = $tbISO.Text.Trim()
            if ($current) {
                $parent = Split-Path -Parent $current
                if ($parent -and (Test-Path -LiteralPath $parent)) {
                    $dialog.InitialDirectory = $parent
                } else {
                    $dialog.InitialDirectory = $script:ScriptRoot
                }
            } else {
                $dialog.InitialDirectory = $script:ScriptRoot
            }
            if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $tbISO.Text = $dialog.FileName
                Set-Status 'ISO path selected. Press Save Config to keep it.' $false
            }
        } finally {
            $dialog.Dispose()
        }
    })

$tbServerName.add_TextChanged({ Update-ServerNameFeedback })

$form.add_KeyDown({
        param($sender, $eventArgs)
        if ($eventArgs.Control -and $eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::S) {
            [void](Save-ConfigFromForm)
            $eventArgs.SuppressKeyPress = $true
        } elseif ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::F5) {
            Invoke-BuildAction
            $eventArgs.SuppressKeyPress = $true
        } elseif ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::F6) {
            Invoke-PackAction
            $eventArgs.SuppressKeyPress = $true
        }
    })

$form.add_FormClosing({
        param($sender, $eventArgs)
        if ($script:ActiveProcess) {
            $eventArgs.Cancel = $true
            Set-Status 'A task is still running. Wait for it to finish before closing.' $true
        }
    })

$form.add_Shown({
        Load-ConfigIntoForm
        $tbVMName.Focus()
    })

$logTimer.Start()
[void]$form.ShowDialog()
$logTimer.Stop()
$form.Dispose()
