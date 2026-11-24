<#
.SYNOPSIS
    IT 311 Final Lab Manager - One-Click Auto-Pilot & Hands-On Exam Companion.
.DESCRIPTION
    A streamlined, zero-friction ReaLTaiizor Dark Glass & Clay interface:
      - TAB 1: ONE-CLICK AUTO-PILOT & CONFIG
        Fill in your exam details (or leave defaults) and press one big button:
        [▶ START FULL LAB AUTO-PILOT]
        This automatically saves config -> builds the VM -> packs the scripts ISO ->
        attaches both ISOs -> powers on the VM -> launches VirtualBox UI!
      - TAB 2: IN-VM STEP-BY-STEP HANDS-ON GUIDE
        Crystal-clear, noob-proof instructions for what to do inside the VM:
        1. Install Windows Server (Pick Desktop Experience, set admin password)
        2. Run the 1-line Guest Script (copies to clipboard with 1 click)
        3. Verify all 50 points using the built-in verify_exam.ps1
      - TAB 3: 100% MANUAL CHEAT SHEET & QUICK RUN COMMANDS
        Exact Win+R shortcuts (sysdm.cpl, secpol.msc, lusrmgr.msc, printmanagement.msc)
        and step-by-step procedures if proctor forbids running scripts.
      - TAB 4: 29-STEP REVIEWER RUBRIC CHECKLIST
        Interactive interactive checklist matching Pages 11-13 of the reviewer.
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

# Load ReaLTaiizor
$taiizorDll = Join-Path $script:ScriptRoot 'ReaLTaiizor.dll'
if (Test-Path -LiteralPath $taiizorDll) {
    Add-Type -Path $taiizorDll
} else {
    throw "ReaLTaiizor.dll not found in $script:ScriptRoot"
}

[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------------------------------------------------------------------------
#  Paths & Commands
# ---------------------------------------------------------------------------
$script:ConfigPath = Join-Path $script:ScriptRoot 'config.psd1'
$script:IsWindowsHost = ($env:OS -eq 'Windows_NT')
$script:GuestCommand = 'Set-ExecutionPolicy Bypass -Scope Process -Force; D:\2_configure_server.ps1'
$script:VerifyCommand = 'Set-ExecutionPolicy Bypass -Scope Process -Force; D:\verify_exam.ps1'

$script:ActiveProcess = $null
$script:StreamLogPath = $null
$script:StreamLogRead = 0
$script:StreamExitSeenAt = $null
$script:PipelineQueue = @()

# ---------------------------------------------------------------------------
#  Color Palette (ReaLTaiizor Dark Glass & Clay)
# ---------------------------------------------------------------------------
$script:ColVoid        = [System.Drawing.Color]::FromArgb(17, 19, 24)       # Deep charcoal dark
$script:ColDeepGlass   = [System.Drawing.Color]::FromArgb(24, 27, 34)       # Surface
$script:ColClayCard    = [System.Drawing.Color]::FromArgb(30, 34, 44)       # Elevated card
$script:ColBorderGlass = [System.Drawing.Color]::FromArgb(60, 68, 86)       # Subtle border
$script:ColPureWhite   = [System.Drawing.Color]::FromArgb(255, 255, 255)   # White
$script:ColFrostWhite  = [System.Drawing.Color]::FromArgb(235, 240, 248)   # Text
$script:ColMutedGray   = [System.Drawing.Color]::FromArgb(148, 163, 184)   # Slate 400
$script:ColActiveGreen = [System.Drawing.Color]::FromArgb(34, 197, 94)     # Bright Green

# Fonts
function New-AppFont {
    param([single]$Size, [string]$Style = 'Regular')
    return [System.Drawing.Font]::new('Segoe UI', $Size, [System.Drawing.FontStyle]$Style, [System.Drawing.GraphicsUnit]::Point)
}

function New-CodeFont {
    param([single]$Size, [string]$Style = 'Regular')
    return [System.Drawing.Font]::new('Consolas', $Size, [System.Drawing.FontStyle]$Style, [System.Drawing.GraphicsUnit]::Point)
}

$script:FontBrand   = New-AppFont 8 'Bold'
$script:FontTitle   = New-AppFont 13 'Bold'
$script:FontTab     = New-AppFont 9.5 'Bold'
$script:FontSection = New-AppFont 10.5 'Bold'
$script:FontBody    = New-AppFont 9 'Regular'
$script:FontBold    = New-AppFont 9 'Bold'
$script:FontSmall   = New-AppFont 8.25 'Regular'
$script:FontCode    = New-CodeFont 9 'Regular'
$script:FontCodeBig = New-CodeFont 10 'Bold'
$script:FontHeroBtn = New-AppFont 12 'Bold'

# ---------------------------------------------------------------------------
#  Main Form Shell (ReaLTaiizor CrownForm)
# ---------------------------------------------------------------------------
$form = [ReaLTaiizor.Forms.CrownForm]::new()
$form.Text = 'IT 311 Final Lab Suite — One-Click Auto-Pilot Edition'
$form.BackColor = $script:ColVoid
$form.ForeColor = $script:ColFrostWhite
$form.Font = $script:FontBody
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.MinimumSize = [System.Drawing.Size]::new(1060, 750)
$form.ClientSize = [System.Drawing.Size]::new(1100, 780)

# Header
$pnlHeader = [System.Windows.Forms.Panel]::new()
$pnlHeader.Dock = [System.Windows.Forms.DockStyle]::Top
$pnlHeader.Height = 65
$pnlHeader.BackColor = $script:ColDeepGlass

$lblBrand = [System.Windows.Forms.Label]::new()
$lblBrand.Text = 'IT 311: SYSTEM ADMINISTRATION  //  FINAL LAB EXAM (50 POINTS)'
$lblBrand.ForeColor = $script:ColMutedGray
$lblBrand.Font = $script:FontBrand
$lblBrand.Location = [System.Drawing.Point]::new(20, 10)
$lblBrand.Size = [System.Drawing.Size]::new(550, 16)
[void]$pnlHeader.Controls.Add($lblBrand)

$lblTitle = [System.Windows.Forms.Label]::new()
$lblTitle.Text = 'Full Auto-Pilot Exam Provisioning & Interactive Guide'
$lblTitle.ForeColor = $script:ColPureWhite
$lblTitle.Font = $script:FontTitle
$lblTitle.Location = [System.Drawing.Point]::new(18, 26)
$lblTitle.Size = [System.Drawing.Size]::new(650, 26)
[void]$pnlHeader.Controls.Add($lblTitle)

$lblStatusBadge = [System.Windows.Forms.Label]::new()
$lblStatusBadge.Text = '● READY FOR AUTO-PILOT'
$lblStatusBadge.ForeColor = $script:ColActiveGreen
$lblStatusBadge.Font = New-AppFont 9.5 'Bold'
$lblStatusBadge.Size = [System.Drawing.Size]::new(270, 24)
$lblStatusBadge.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
[void]$pnlHeader.Controls.Add($lblStatusBadge)

# Reposition badge on resize
$pnlHeader.add_Resize({
    $lblStatusBadge.Location = [System.Drawing.Point]::new($pnlHeader.ClientSize.Width - $lblStatusBadge.Width - 20, 20)
})
$lblStatusBadge.Location = [System.Drawing.Point]::new($pnlHeader.ClientSize.Width - $lblStatusBadge.Width - 20, 20)

# Tab Strip (ReaLTaiizor PoisonTabControl)
$tabSteps = [ReaLTaiizor.Controls.PoisonTabControl]::new()
$tabSteps.Dock = [System.Windows.Forms.DockStyle]::Fill
$tabSteps.Theme = [ReaLTaiizor.Enum.Poison.ThemeStyle]::Dark
$tabSteps.Style = [ReaLTaiizor.Enum.Poison.ColorStyle]::White
$tabSteps.Font = $script:FontTab
$tabSteps.Padding = [System.Drawing.Point]::new(14, 8)

# Add controls to form in correct z-order (TabControl first, then Header docked to top)
[void]$form.Controls.Add($tabSteps)
[void]$form.Controls.Add($pnlHeader)

# Create 4 Streamlined Tabs
$tab1 = [System.Windows.Forms.TabPage]::new(); $tab1.Text = '  ⚡ 1. Auto-Pilot & Config  '; $tab1.BackColor = $script:ColVoid
$tab2 = [System.Windows.Forms.TabPage]::new(); $tab2.Text = '  📖 2. In-VM Hands-On Guide  '; $tab2.BackColor = $script:ColVoid
$tab3 = [System.Windows.Forms.TabPage]::new(); $tab3.Text = '  🛡 3. 100% Manual Cheat Sheet  '; $tab3.BackColor = $script:ColVoid
$tab4 = [System.Windows.Forms.TabPage]::new(); $tab4.Text = '  📋 4. 29-Step Rubric Checklist  '; $tab4.BackColor = $script:ColVoid

[void]$tabSteps.TabPages.Add($tab1)
[void]$tabSteps.TabPages.Add($tab2)
[void]$tabSteps.TabPages.Add($tab3)
[void]$tabSteps.TabPages.Add($tab4)

# Card creation helper
function New-TaiizorCard {
    param([int]$X, [int]$Y, [int]$W, [int]$H, [System.Windows.Forms.Control]$Parent)
    $p = [System.Windows.Forms.Panel]::new()
    $p.Location = [System.Drawing.Point]::new($X, $Y)
    $p.Size = [System.Drawing.Size]::new($W, $H)
    $p.BackColor = $script:ColClayCard
    $p.ForeColor = $script:ColFrostWhite
    $p.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $p.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $p.add_Paint({
        param($s, $e)
        $pen = [System.Drawing.Pen]::new($script:ColBorderGlass, 1)
        $e.Graphics.DrawRectangle($pen, 0, 0, $s.Width - 1, $s.Height - 1)
        $pen.Dispose()
    })
    if ($Parent) { [void]$Parent.Controls.Add($p) }
    return $p
}

function New-TaiizorButton {
    param(
        [string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H,
        $Parent, $Font = $null
    )
    $btn = [ReaLTaiizor.Controls.CrownButton]::new()
    $btn.Text = $Text
    $btn.Location = [System.Drawing.Point]::new($X, $Y)
    $btn.Size = [System.Drawing.Size]::new($W, $H)
    $btn.Font = if ($Font) { $Font } else { $script:FontBold }
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    if ($Parent) { [void]$Parent.Controls.Add($btn) }
    return $btn
}

# ===========================================================================
#  TAB 1: ONE-CLICK AUTO-PILOT & CONFIGURATION
# ===========================================================================
# Hero One-Click Master Control Card
$cardHero = New-TaiizorCard -X 16 -Y 12 -W 1040 -H 105 -Parent $tab1

$lblHeroTitle = [System.Windows.Forms.Label]::new()
$lblHeroTitle.Text = 'HOST AUTO-PILOT ENGINE'
$lblHeroTitle.Font = $script:FontSection
$lblHeroTitle.ForeColor = $script:ColPureWhite
$lblHeroTitle.Location = [System.Drawing.Point]::new(16, 10)
$lblHeroTitle.Size = [System.Drawing.Size]::new(350, 20)
[void]$cardHero.Controls.Add($lblHeroTitle)

# VM Manager Dropdown & Actions in Hero Card
[void]([System.Windows.Forms.Label]::new() | ForEach-Object { $_.Text = 'VM MANAGER:'; $_.Font = $script:FontBold; $_.ForeColor = $script:ColMutedGray; $_.Location = [System.Drawing.Point]::new(370, 10); $_.Size = [System.Drawing.Size]::new(90, 20); $cardHero.Controls.Add($_); $_ })
$comboVmList = [ReaLTaiizor.Controls.CrownComboBox]::new(); $comboVmList.Location = [System.Drawing.Point]::new(465, 8); $comboVmList.Size = [System.Drawing.Size]::new(200, 24); [void]$cardHero.Controls.Add($comboVmList)
$btnRefreshVms = New-TaiizorButton -Text 'SCAN' -X 675 -Y 7 -W 65 -H 26 -Parent $cardHero -Font $script:FontSmall
$btnDeleteSelectedVm = New-TaiizorButton -Text 'UNINSTALL VM' -X 748 -Y 7 -W 120 -H 26 -Parent $cardHero -Font $script:FontSmall

$lblHeroDesc = [System.Windows.Forms.Label]::new()
$lblHeroDesc.Text = 'Click the Master button below to execute everything on your laptop: Save Config -> Build VM -> Pack Scripts ISO -> Launch VirtualBox!'
$lblHeroDesc.Font = $script:FontSmall
$lblHeroDesc.ForeColor = $script:ColMutedGray
$lblHeroDesc.Location = [System.Drawing.Point]::new(16, 30)
$lblHeroDesc.Size = [System.Drawing.Size]::new(700, 16)
[void]$cardHero.Controls.Add($lblHeroDesc)

$btnMasterStart = New-TaiizorButton -Text '▶ START FULL LAB AUTO-PILOT (BUILD, PACK & LAUNCH VM)' -X 16 -Y 50 -W 500 -H 44 -Parent $cardHero -Font $script:FontHeroBtn
$btnStepBuild = New-TaiizorButton -Text '1. BUILD VM ONLY' -X 526 -Y 54 -W 160 -H 36 -Parent $cardHero
$btnStepPack = New-TaiizorButton -Text '2. PACK ISO ONLY' -X 694 -Y 54 -W 160 -H 36 -Parent $cardHero
$btnOpenVbox = New-TaiizorButton -Text '3. OPEN VIRTUALBOX' -X 862 -Y 54 -W 160 -H 36 -Parent $cardHero

# Configuration Card
$cardConfig = New-TaiizorCard -X 16 -Y 124 -W 1040 -H 230 -Parent $tab1

$lblCfgHeader = [System.Windows.Forms.Label]::new()
$lblCfgHeader.Text = 'EXAM CONFIGURATION (VERIFY OR EDIT BEFORE STARTING)'
$lblCfgHeader.Font = $script:FontSection
$lblCfgHeader.ForeColor = $script:ColPureWhite
$lblCfgHeader.Location = [System.Drawing.Point]::new(16, 8)
$lblCfgHeader.Size = [System.Drawing.Size]::new(500, 20)
[void]$cardConfig.Controls.Add($lblCfgHeader)

# Row 1: Section, Admin Pass, Server Name, VM Name
[void]([System.Windows.Forms.Label]::new() | ForEach-Object { $_.Text = 'CLASS SECTION:'; $_.Font = $script:FontBold; $_.ForeColor = $script:ColMutedGray; $_.Location = [System.Drawing.Point]::new(16, 36); $_.Size = [System.Drawing.Size]::new(110, 20); $cardConfig.Controls.Add($_); $_ })
$comboSection = [ReaLTaiizor.Controls.CrownComboBox]::new(); $comboSection.Items.AddRange(@('IT 3106 (3106@BatStateU)', 'IT 3107 (3107@BatStateU)', 'IT 3108 (3108@BatStateU)', 'Custom...')); $comboSection.SelectedIndex = 0; $comboSection.Location = [System.Drawing.Point]::new(130, 34); $comboSection.Size = [System.Drawing.Size]::new(200, 24); [void]$cardConfig.Controls.Add($comboSection)

[void]([System.Windows.Forms.Label]::new() | ForEach-Object { $_.Text = 'ADMIN PASS:'; $_.Font = $script:FontBold; $_.ForeColor = $script:ColMutedGray; $_.Location = [System.Drawing.Point]::new(350, 36); $_.Size = [System.Drawing.Size]::new(90, 20); $cardConfig.Controls.Add($_); $_ })
$tbAdminPass = [ReaLTaiizor.Controls.CrownTextBox]::new(); $tbAdminPass.Text = '3106@BatStateU'; $tbAdminPass.Location = [System.Drawing.Point]::new(445, 34); $tbAdminPass.Size = [System.Drawing.Size]::new(180, 24); [void]$cardConfig.Controls.Add($tbAdminPass)

[void]([System.Windows.Forms.Label]::new() | ForEach-Object { $_.Text = 'SERVER NAME:'; $_.Font = $script:FontBold; $_.ForeColor = $script:ColMutedGray; $_.Location = [System.Drawing.Point]::new(645, 36); $_.Size = [System.Drawing.Size]::new(100, 20); $cardConfig.Controls.Add($_); $_ })
$tbServerName = [ReaLTaiizor.Controls.CrownTextBox]::new(); $tbServerName.Text = 'Lab-Server-01'; $tbServerName.Location = [System.Drawing.Point]::new(750, 34); $tbServerName.Size = [System.Drawing.Size]::new(270, 24); [void]$cardConfig.Controls.Add($tbServerName)

# Row 2: VM Specs (RAM, Disk, Network, Bridge, ISO)
[void]([System.Windows.Forms.Label]::new() | ForEach-Object { $_.Text = 'VM NAME:'; $_.Font = $script:FontBold; $_.ForeColor = $script:ColMutedGray; $_.Location = [System.Drawing.Point]::new(16, 70); $_.Size = [System.Drawing.Size]::new(110, 20); $cardConfig.Controls.Add($_); $_ })
$tbVMName = [ReaLTaiizor.Controls.CrownTextBox]::new(); $tbVMName.Text = 'Lab_Exam_VM'; $tbVMName.Location = [System.Drawing.Point]::new(130, 68); $tbVMName.Size = [System.Drawing.Size]::new(200, 24); [void]$cardConfig.Controls.Add($tbVMName)

[void]([System.Windows.Forms.Label]::new() | ForEach-Object { $_.Text = 'RAM (MB):'; $_.Font = $script:FontBold; $_.ForeColor = $script:ColMutedGray; $_.Location = [System.Drawing.Point]::new(350, 70); $_.Size = [System.Drawing.Size]::new(90, 20); $cardConfig.Controls.Add($_); $_ })
$tbRAM = [ReaLTaiizor.Controls.CrownTextBox]::new(); $tbRAM.Text = '4096'; $tbRAM.Location = [System.Drawing.Point]::new(445, 68); $tbRAM.Size = [System.Drawing.Size]::new(75, 24); [void]$cardConfig.Controls.Add($tbRAM)

[void]([System.Windows.Forms.Label]::new() | ForEach-Object { $_.Text = 'DISK (GB):'; $_.Font = $script:FontBold; $_.ForeColor = $script:ColMutedGray; $_.Location = [System.Drawing.Point]::new(535, 70); $_.Size = [System.Drawing.Size]::new(75, 20); $cardConfig.Controls.Add($_); $_ })
$tbDisk = [ReaLTaiizor.Controls.CrownTextBox]::new(); $tbDisk.Text = '30'; $tbDisk.Location = [System.Drawing.Point]::new(615, 68); $tbDisk.Size = [System.Drawing.Size]::new(60, 24); [void]$cardConfig.Controls.Add($tbDisk)

[void]([System.Windows.Forms.Label]::new() | ForEach-Object { $_.Text = 'NETWORK:'; $_.Font = $script:FontBold; $_.ForeColor = $script:ColMutedGray; $_.Location = [System.Drawing.Point]::new(690, 70); $_.Size = [System.Drawing.Size]::new(70, 20); $cardConfig.Controls.Add($_); $_ })
$comboNet = [ReaLTaiizor.Controls.CrownComboBox]::new(); $comboNet.Items.AddRange(@('bridged', 'nat', 'hostonly', 'intnet')); $comboNet.SelectedIndex = 0; $comboNet.Location = [System.Drawing.Point]::new(765, 68); $comboNet.Size = [System.Drawing.Size]::new(100, 24); [void]$cardConfig.Controls.Add($comboNet)

[void]([System.Windows.Forms.Label]::new() | ForEach-Object { $_.Text = 'PORT:'; $_.Font = $script:FontBold; $_.ForeColor = $script:ColMutedGray; $_.Location = [System.Drawing.Point]::new(880, 70); $_.Size = [System.Drawing.Size]::new(50, 20); $cardConfig.Controls.Add($_); $_ })
$comboPort = [ReaLTaiizor.Controls.CrownComboBox]::new(); $comboPort.Items.AddRange(@('LPT1:', 'FILE:')); $comboPort.SelectedIndex = 0; $comboPort.Location = [System.Drawing.Point]::new(935, 68); $comboPort.Size = [System.Drawing.Size]::new(85, 24); [void]$cardConfig.Controls.Add($comboPort)

# Row 3: Bridge & ISO
[void]([System.Windows.Forms.Label]::new() | ForEach-Object { $_.Text = 'BRIDGE NIC:'; $_.Font = $script:FontBold; $_.ForeColor = $script:ColMutedGray; $_.Location = [System.Drawing.Point]::new(16, 104); $_.Size = [System.Drawing.Size]::new(110, 20); $cardConfig.Controls.Add($_); $_ })
$tbBridge = [ReaLTaiizor.Controls.CrownTextBox]::new(); $tbBridge.Text = ''; $tbBridge.Location = [System.Drawing.Point]::new(130, 102); $tbBridge.Size = [System.Drawing.Size]::new(200, 24); [void]$cardConfig.Controls.Add($tbBridge)

[void]([System.Windows.Forms.Label]::new() | ForEach-Object { $_.Text = 'SERVER ISO:'; $_.Font = $script:FontBold; $_.ForeColor = $script:ColMutedGray; $_.Location = [System.Drawing.Point]::new(350, 104); $_.Size = [System.Drawing.Size]::new(90, 20); $cardConfig.Controls.Add($_); $_ })
$tbISO = [ReaLTaiizor.Controls.CrownTextBox]::new(); $tbISO.Text = ''; $tbISO.Location = [System.Drawing.Point]::new(445, 102); $tbISO.Size = [System.Drawing.Size]::new(490, 24); [void]$cardConfig.Controls.Add($tbISO)
$btnBrowseIso = New-TaiizorButton -Text 'BROWSE...' -X 945 -Y 101 -W 75 -H 26 -Parent $cardConfig -Font $script:FontSmall

# Row 4: Shares & Printer Summary
[void]([System.Windows.Forms.Label]::new() | ForEach-Object { $_.Text = 'BASE PATH:'; $_.Font = $script:FontBold; $_.ForeColor = $script:ColMutedGray; $_.Location = [System.Drawing.Point]::new(16, 138); $_.Size = [System.Drawing.Size]::new(110, 20); $cardConfig.Controls.Add($_); $_ })
$tbBasePath = [ReaLTaiizor.Controls.CrownTextBox]::new(); $tbBasePath.Text = 'C:\Shares'; $tbBasePath.Location = [System.Drawing.Point]::new(130, 136); $tbBasePath.Size = [System.Drawing.Size]::new(200, 24); [void]$cardConfig.Controls.Add($tbBasePath)

[void]([System.Windows.Forms.Label]::new() | ForEach-Object { $_.Text = 'PRINTER:'; $_.Font = $script:FontBold; $_.ForeColor = $script:ColMutedGray; $_.Location = [System.Drawing.Point]::new(350, 138); $_.Size = [System.Drawing.Size]::new(90, 20); $cardConfig.Controls.Add($_); $_ })
$tbPrinterName = [ReaLTaiizor.Controls.CrownTextBox]::new(); $tbPrinterName.Text = 'Office-Printer'; $tbPrinterName.Location = [System.Drawing.Point]::new(445, 136); $tbPrinterName.Size = [System.Drawing.Size]::new(180, 24); [void]$cardConfig.Controls.Add($tbPrinterName)

# Department Folders & Files (Hidden behind clean defaults, visible for edit)
$tbITFolder = [ReaLTaiizor.Controls.CrownTextBox]::new(); $tbITFolder.Text = 'IT_Share'
$tbITFile   = [ReaLTaiizor.Controls.CrownTextBox]::new(); $tbITFile.Text = 'it.txt'
$tbHRFolder = [ReaLTaiizor.Controls.CrownTextBox]::new(); $tbHRFolder.Text = 'HR_Share'
$tbHRFile   = [ReaLTaiizor.Controls.CrownTextBox]::new(); $tbHRFile.Text = 'hr.txt'
$tbMgrFolder = [ReaLTaiizor.Controls.CrownTextBox]::new(); $tbMgrFolder.Text = 'Manager_Share'
$tbMgrFile   = [ReaLTaiizor.Controls.CrownTextBox]::new(); $tbMgrFile.Text = 'manager.txt'
$tbPubFolder = [ReaLTaiizor.Controls.CrownTextBox]::new(); $tbPubFolder.Text = 'Public_Share'
$tbPubFile   = [ReaLTaiizor.Controls.CrownTextBox]::new(); $tbPubFile.Text = 'public.txt'

$btnSaveAllConfig = New-TaiizorButton -Text 'SAVE CONFIG' -X 16 -Y 180 -W 150 -H 36 -Parent $cardConfig
$btnCopyCmdHero = New-TaiizorButton -Text 'COPY GUEST CMD' -X 174 -Y 180 -W 185 -H 36 -Parent $cardConfig
$btnCopyVerifyHero = New-TaiizorButton -Text 'COPY VERIFIER CMD' -X 367 -Y 180 -W 185 -H 36 -Parent $cardConfig
$btnDlVbox = New-TaiizorButton -Text 'GET VIRTUALBOX' -X 560 -Y 180 -W 175 -H 36 -Parent $cardConfig
$btnDlIso = New-TaiizorButton -Text 'GET SERVER ISO' -X 743 -Y 180 -W 175 -H 36 -Parent $cardConfig
$btnDlVbox.add_Click({ [System.Diagnostics.Process]::Start('https://www.virtualbox.org/wiki/Downloads') })
$btnDlIso.add_Click({ [System.Diagnostics.Process]::Start('https://www.microsoft.com/en-us/evalcenter/download-windows-server-2022') })

# Tooltips for user guidance on inputs and download buttons
$ttHelp = [System.Windows.Forms.ToolTip]::new()
$ttHelp.InitialDelay = 200
$ttHelp.AutoPopDelay = 10000
$ttHelp.SetToolTip($comboSection, 'Choose class section. Automatically presets the rubric SectionAdminPassword (<section>@BatStateU).')
$ttHelp.SetToolTip($tbAdminPass, 'Administrator password. Format: <section>@BatStateU (e.g. 3106@BatStateU).')
$ttHelp.SetToolTip($tbServerName, 'Target computer name (Task Area 04). Max 15 chars, alphanumeric and hyphens only (e.g. Lab-Server-01).')
$ttHelp.SetToolTip($tbVMName, 'VirtualBox virtual machine name (Task Area 01). Must match instruction sheet.')
$ttHelp.SetToolTip($tbRAM, 'VM memory in MB. Rubric minimum: 2048 MB. Recommended: 4096 MB.')
$ttHelp.SetToolTip($tbDisk, 'Dynamic VDI hard disk size in GB. Rubric minimum: 20 GB. Recommended: 30 GB.')
$ttHelp.SetToolTip($comboNet, 'Network mode. Must be "bridged" per rubric requirements.')
$ttHelp.SetToolTip($comboPort, 'Printer port for Office-Printer. Use LPT1: or FILE:.')
$ttHelp.SetToolTip($tbBridge, 'Leave blank to auto-detect your physical host network adapter.')
$ttHelp.SetToolTip($tbISO, 'Path to Windows Server 2022 evaluation ISO. Auto-detected if in project folder.')
$ttHelp.SetToolTip($tbBasePath, 'Base folder on guest C: drive where department shares are provisioned (C:\Shares).')
$ttHelp.SetToolTip($tbPrinterName, 'Name and share name of the printer (Task Area 06, Office-Printer).')
$ttHelp.SetToolTip($btnDlVbox, 'Open official Oracle VirtualBox download page in your browser.')
$ttHelp.SetToolTip($btnDlIso, 'Open official Microsoft Windows Server 2022 Evaluation download page.')

# Console Output Card
$cardLog = New-TaiizorCard -X 16 -Y 364 -W 1040 -H 240 -Parent $tab1
$cardLog.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$lblLogHeader = [System.Windows.Forms.Label]::new(); $lblLogHeader.Text = 'LIVE EXECUTION CONSOLE'; $lblLogHeader.Font = New-AppFont 9 'Bold'; $lblLogHeader.ForeColor = $script:ColMutedGray; $lblLogHeader.Location = [System.Drawing.Point]::new(16, 8); $lblLogHeader.Size = [System.Drawing.Size]::new(300, 20); [void]$cardLog.Controls.Add($lblLogHeader)
$btnClearLog = New-TaiizorButton -Text 'CLEAR' -X 945 -Y 6 -W 75 -H 24 -Parent $cardLog -Font $script:FontSmall
$btnClearLog.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnClearLog.add_Click({ $script:rtbLog.Clear() })

$script:rtbLog = [System.Windows.Forms.RichTextBox]::new(); $script:rtbLog.Location = [System.Drawing.Point]::new(16, 32); $script:rtbLog.Size = [System.Drawing.Size]::new(1004, 195); $script:rtbLog.BackColor = $script:ColDeepGlass; $script:rtbLog.ForeColor = $script:ColPureWhite; $script:rtbLog.Font = $script:FontCode; $script:rtbLog.ReadOnly = $true; $script:rtbLog.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$script:rtbLog.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
[void]$cardLog.Controls.Add($script:rtbLog)

# ===========================================================================
#  TAB 2: IN-VM STEP-BY-STEP HANDS-ON GUIDE
# ===========================================================================
$cardInVmGuide = New-TaiizorCard -X 16 -Y 12 -W 1040 -H 590 -Parent $tab2
$cardInVmGuide.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

$lblGuideTitle = [System.Windows.Forms.Label]::new()
$lblGuideTitle.Text = 'HANDS-ON GUIDE: WHAT YOU MUST DO INSIDE THE VIRTUAL MACHINE'
$lblGuideTitle.Font = $script:FontSection
$lblGuideTitle.ForeColor = $script:ColPureWhite
$lblGuideTitle.Location = [System.Drawing.Point]::new(16, 12)
$lblGuideTitle.Size = [System.Drawing.Size]::new(750, 22)
[void]$cardInVmGuide.Controls.Add($lblGuideTitle)

$rtbGuide = [System.Windows.Forms.RichTextBox]::new()
$rtbGuide.Location = [System.Drawing.Point]::new(16, 42)
$rtbGuide.Size = [System.Drawing.Size]::new(1004, 530)
$rtbGuide.Font = $script:FontCode
$rtbGuide.ReadOnly = $true
$rtbGuide.BackColor = $script:ColDeepGlass
$rtbGuide.ForeColor = $script:ColFrostWhite
$rtbGuide.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$rtbGuide.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
[void]$cardInVmGuide.Controls.Add($rtbGuide)

$rtbGuide.Text = @"
========================================================================================
  IT 311 FINAL LAB - IN-VM STEP-BY-STEP HANDS-ON GUIDE (34 PTS AUTOMATED + 16 MANUAL)
========================================================================================

STEP 1: INSTALL WINDOWS SERVER 2022 (8 pts)
  1. VirtualBox starts your VM automatically with both the Windows ISO and lab_scripts.iso.
  2. Click inside the VM window and immediately press ANY key to boot from CD/DVD.
  3. Language/Time/Keyboard -> Click 'Install now'.
  4. ⚠️ CRITICAL OS SELECTION:
     Select: 'Windows Server 2022 Standard Evaluation (Desktop Experience)'
     * Do NOT select Server Core (Server Core has no GUI and you will lose points!).
  5. Select 'Custom: Install Microsoft Server Operating System only (advanced)'.
  6. Select unallocated Drive 0 (30 GB) -> Click Next and wait for install.
  7. When prompted for Administrator Password:
     Enter your section password: 3106@BatStateU (or 3107@BatStateU / 3108@BatStateU).
  8. Log in: Press Host Key (Right Ctrl + Del) and enter your password.

STEP 2: RUN THE AUTOMATION SCRIPT INSIDE THE VM (34 pts)
  1. Open PowerShell as Administrator inside the VM.
  2. Paste this 1-line command (click 'COPY GUEST COMMAND' on Tab 1 to copy):
     Set-ExecutionPolicy Bypass -Scope Process -Force; D:\2_configure_server.ps1
  3. FIRST RUN (Task Area 04: Server Rename):
     - The script checks the hostname, renames it to 'Lab-Server-01', and prompts for reboot.
     - Press Y to reboot.
  4. SECOND RUN (Task Areas 03, 05, 06):
     - Log back in as Administrator.
     - Open PowerShell as Administrator again and run the same command:
       Set-ExecutionPolicy Bypass -Scope Process -Force; D:\2_configure_server.ps1
     - This automatically creates:
       • Password policy (Complexity ENABLED, Length 8)
       • Local Users: IT, HR, Manager with exact passwords from reviewer
       • File Server & iSCSI Target Server roles
       • C:\Shares\IT_Share, HR_Share, Manager_Share, Public_Share with isolated NTFS permissions
       • Credential text files (it.txt, hr.txt, manager.txt, public.txt)
       • Desktop shortcuts for each user
       • Print Server role, Generic driver on LPT1:, and shared 'Office-Printer'.

STEP 3: MANDATORY HANDS-ON VERIFICATION (BEFORE CALLING INSTRUCTOR)
  1. Sign out of Administrator -> Sign in once as IT, then HR, then Manager.
     (Windows only creates their user profile folders on first sign-in!).
  2. Re-run the guest script once more so desktop shortcuts land in their private Desktop folders.
  3. Test Access Denied:
     - While logged in as IT, open File Explorer -> type: \\Lab-Server-01\HR_Share
     - It MUST display 'Access is denied' (proves NTFS permissions work!).
  4. Run the 50-Point Exam Verifier:
     In PowerShell, run: D:\verify_exam.ps1
     Ensure it outputs: TOTAL SCORE: 50 / 50 POINTS!
  5. LEAVE VM RUNNING and raise your hand for your instructor!
========================================================================================
"@

# ===========================================================================
#  TAB 3: 100% MANUAL CHEAT SHEET (RUBRIC BACKUP)
# ===========================================================================
$cardManual = New-TaiizorCard -X 16 -Y 12 -W 1040 -H 590 -Parent $tab3
$cardManual.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$lblManTitle = [System.Windows.Forms.Label]::new(); $lblManTitle.Text = '100% MANUAL GUI STEPS & SHORTCUTS (IF AUTOMATION IS FORBIDDEN)'; $lblManTitle.Font = $script:FontSection; $lblManTitle.ForeColor = $script:ColPureWhite; $lblManTitle.Location = [System.Drawing.Point]::new(16, 12); $lblManTitle.Size = [System.Drawing.Size]::new(750, 22); [void]$cardManual.Controls.Add($lblManTitle)

$rtbCheat = [System.Windows.Forms.RichTextBox]::new(); $rtbCheat.Location = [System.Drawing.Point]::new(16, 42); $rtbCheat.Size = [System.Drawing.Size]::new(1004, 530); $rtbCheat.Font = $script:FontCode; $rtbCheat.ReadOnly = $true; $rtbCheat.BackColor = $script:ColDeepGlass; $rtbCheat.ForeColor = $script:ColFrostWhite; $rtbCheat.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$rtbCheat.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
[void]$cardManual.Controls.Add($rtbCheat)
$rtbCheat.Text = @"
========================================================================================
  IT 311 FINAL LAB - 100% MANUAL GUI STEP-BY-STEP CHEAT SHEET (50 POINTS)
========================================================================================

[FAST RUN COMMANDS] Press Win + R inside the VM:
  • sysdm.cpl            -> Rename Server (5 pts)
  • secpol.msc           -> Local Security Policy / Password Complexity (4 pts)
  • lusrmgr.msc          -> Local Users and Groups (6 pts)
  • printmanagement.msc  -> Print Management / Add Shared Printer (7 pts)

[TASK AREA 04: RENAME SERVER (5 pts)]
  1. Win + R -> sysdm.cpl -> Click 'Change...'
  2. Computer name: Lab-Server-01 (Max 15 characters, no spaces)
  3. Click OK -> Click 'Restart Now'.

[TASK AREA 03: PASSWORD POLICY & LOCAL USERS (10 pts)]
  1. Win + R -> secpol.msc -> Account Policies -> Password Policy:
     - Password must meet complexity requirements: ENABLED
     - Minimum password length: 8 characters
  2. Win + R -> lusrmgr.msc -> Users -> Right-click -> New User:
     - IT       (Pass: Tech#Dept2026)
     - HR       (Pass: People#Dept2026)
     - Manager  (Pass: Lead#Dept2026)
     * UNCHECK 'User must change password at next logon'
     * CHECK 'Password never expires'

[TASK AREA 05: FILE AND STORAGE SERVICES (12 pts)]
  1. Server Manager -> Manage -> Add Roles and Features:
     - File and Storage Services -> File and iSCSI Services:
       [X] File Server
       [X] iSCSI Target Server
  2. In File Explorer: Create C:\Shares
     Inside C:\Shares, create: IT_Share, HR_Share, Manager_Share, Public_Share
  3. For each department folder:
     - Properties -> Sharing -> Advanced Sharing -> Check 'Share this folder'
     - Properties -> Security -> Advanced -> Click 'Disable inheritance' -> Remove inherited permissions
     - Add: Administrators (Full Control), SYSTEM (Full Control), and its specific User (Modify)
     - Remove broad 'Users' group so other departments cannot access it!
  4. Credential files:
     - C:\Shares\IT_Share\it.txt         (contain: Tech#Dept2026)
     - C:\Shares\HR_Share\hr.txt         (contain: People#Dept2026)
     - C:\Shares\Manager_Share\manager.txt (contain: Lead#Dept2026)
     - C:\Shares\Public_Share\public.txt (contain: public info)
  5. Desktop shortcuts:
     In each C:\Users\<user>\Desktop, create a shortcut pointing to \\Lab-Server-01\<ShareName>.

[TASK AREA 06: PRINT AND DOCUMENT SERVICES (7 pts)]
  1. Server Manager -> Add Roles and Features -> [X] Print and Document Services -> Print Server
  2. Win + R -> printmanagement.msc -> Expand Print Servers -> Printers -> Right-click Add Printer:
     - Port: LPT1:
     - Driver: Generic / Text Only
     - Printer Name: Office-Printer
     - CHECK 'Share this printer' with share name: Office-Printer

========================================================================================
"@

# ===========================================================================
#  TAB 4: 29-STEP REVIEWER RUBRIC CHECKLIST (Pages 11, 12, 13)
# ===========================================================================
$cardRubric = New-TaiizorCard -X 16 -Y 12 -W 1040 -H 590 -Parent $tab4
$cardRubric.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$lblRubTitle = [System.Windows.Forms.Label]::new(); $lblRubTitle.Text = 'OFFICIAL 29-STEP EXAM-DAY RUBRIC CHECKLIST (PAGES 11, 12, 13)'; $lblRubTitle.Font = $script:FontSection; $lblRubTitle.ForeColor = $script:ColPureWhite; $lblRubTitle.Location = [System.Drawing.Point]::new(16, 12); $lblRubTitle.Size = [System.Drawing.Size]::new(750, 20); [void]$cardRubric.Controls.Add($lblRubTitle)

$clbRubric = [System.Windows.Forms.CheckedListBox]::new()
$clbRubric.Location = [System.Drawing.Point]::new(16, 40)
$clbRubric.Size = [System.Drawing.Size]::new(1004, 490)
$clbRubric.Font = New-AppFont 9.5 'Regular'
$clbRubric.CheckOnClick = $true
$clbRubric.BackColor = $script:ColDeepGlass
$clbRubric.ForeColor = $script:ColFrostWhite
$clbRubric.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$clbRubric.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
[void]$cardRubric.Controls.Add($clbRubric)

$lblScoreRubric = [System.Windows.Forms.Label]::new()
$lblScoreRubric.Text = 'Checked: 0 / 29 Steps Complete'
$lblScoreRubric.Font = New-AppFont 10 'Bold'
$lblScoreRubric.ForeColor = $script:ColPureWhite
$lblScoreRubric.Location = [System.Drawing.Point]::new(16, 545)
$lblScoreRubric.Size = [System.Drawing.Size]::new(350, 24)
$lblScoreRubric.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
[void]$cardRubric.Controls.Add($lblScoreRubric)

$rubricItems = @(
    "1. VirtualBox > New > type VM name > tick Skip Unattended Installation (Task Area 01)",
    "2. Type: Microsoft Windows, Version: Windows 2022 (64-bit) [Windows2022_64]",
    "3. RAM: 2048 MB or more (4096 MB recommended), new VDI disk 20 GB or more (30 GB)",
    "4. Settings > Network > Adapter 1 Attached to: Bridged Adapter",
    "5. Settings > Storage > Empty disc > Choose Windows Server 2022 ISO > Start VM",
    "6. Windows Setup: Install now > Select edition with (Desktop Experience)",
    "7. Custom install > Select unallocated Drive 0 > Next > Wait for install",
    "8. Set Administrator password: yoursection@BatStateU (e.g. 3106@BatStateU)",
    "9. Log in with Right Ctrl + Del as Administrator (Task Area 02)",
    "10. Server Manager > Local Server > Click Computer name > Change (Task Area 04)",
    "11. Type new server name (e.g. Lab-Server-01) > OK > Restart Now (hostname confirms)",
    "12. Win+R > secpol.msc > Password Policy: Complexity ENABLED, Minimum length 8",
    "13. Win+R > lusrmgr.msc > Users > New User (Task Area 03)",
    "14. Create IT, HR, Manager with exact passwords (Tech#Dept2026, People#Dept2026, Lead#Dept2026)",
    "15. UNTICK 'User must change password at next logon' > TICK 'Password never expires'",
    "16. Sign in once as each user (IT, HR, Manager) to create profile folders, then back as Administrator",
    "17. Server Manager > Add Roles and Features > File Server + iSCSI Target Server (Task Area 05)",
    "18. Create the three department folders and public folder in C:\Shares",
    "19. Each folder: Properties > Sharing > Advanced Sharing > Share this folder",
    "20. Security > Advanced > Disable inheritance > Convert into explicit permissions > Remove Users",
    "21. Add department user (Modify) + Administrators & SYSTEM (Full Control)",
    "22. Public folder: Add all three users (IT, HR, Manager) with Read/Write permissions",
    "23. New text file in each folder with passwords (it.txt, hr.txt, manager.txt, public.txt)",
    "24. Desktop shortcuts created in C:\Users\<user>\Desktop pointing to \\ServerName\Share",
    "25. Add Roles and Features > Print and Document Services > Print Server (Task Area 06)",
    "26. Tools > Print Management > Printers > Add Printer",
    "27. Use existing port (LPT1:) > Generic / Text Only driver",
    "28. Type printer name (Office-Printer) > TICK 'Share this printer' > Finish",
    "29. FINAL: VM still running, nothing deleted, raise hand for instructor evaluation!"
)

foreach ($item in $rubricItems) {
    [void]$clbRubric.Items.Add($item, $false)
}

$clbRubric.add_ItemCheck({
    param($s, $e)
    $curr = $clbRubric.CheckedItems.Count
    if ($e.NewValue -eq [System.Windows.Forms.CheckState]::Checked) { $curr++ } else { $curr-- }
    $lblScoreRubric.Text = "Checked: $curr / 29 Steps Complete"
    if ($curr -eq 29) {
        $lblScoreRubric.ForeColor = $script:ColActiveGreen
        $lblScoreRubric.Text = "Checked: 29 / 29 Steps Complete (100% EXAM READY!)"
    } else {
        $lblScoreRubric.ForeColor = $script:ColMutedGray
    }
})

# ---------------------------------------------------------------------------
#  Console Output & Process Streaming
# ---------------------------------------------------------------------------
function Add-LogLine {
    param([string]$Text)
    if ($null -eq $script:rtbLog -or $script:rtbLog.IsDisposed) { return }
    if ($script:rtbLog.InvokeRequired) {
        $script:rtbLog.Invoke([Action[string]]{ param($t) Add-LogLine $t }, $Text)
        return
    }
    $script:rtbLog.AppendText($Text + "`r`n")
    $script:rtbLog.SelectionStart = $script:rtbLog.TextLength
    $script:rtbLog.ScrollToCaret()
}

function Add-LogBanner {
    param([string]$Title)
    Add-LogLine ''
    Add-LogLine ('=' * 70)
    Add-LogLine ("  $Title  //  " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    Add-LogLine ('=' * 70)
}

function Read-SharedText {
    param([string]$Path)
    $stream = $null
    $reader = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)
        return $reader.ReadToEnd()
    } catch {
        return ''
    } finally {
        if ($reader) { try { $reader.Dispose() } catch {} }
        if ($stream) { try { $stream.Dispose() } catch {} }
    }
}

function Start-StreamingProcess {
    param(
        [string]$FileName,
        [string]$Arguments,
        [string]$Banner
    )
    Add-LogBanner $Banner
    $script:StreamLogPath = [System.IO.Path]::GetTempFileName()
    $script:StreamLogRead = 0
    $script:StreamExitSeenAt = $null

    $cmd = 'cmd.exe'
    $cmdArgs = '/c ""' + $FileName + '" ' + $Arguments + ' > "' + $script:StreamLogPath + '" 2>&1"'

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $cmd
    $psi.Arguments = $cmdArgs
    $psi.WorkingDirectory = $script:ScriptRoot
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $script:ActiveProcess = [System.Diagnostics.Process]::Start($psi)
    $lblStatusBadge.Text = '● RUNNING TASK...'
    $lblStatusBadge.ForeColor = $script:ColPureWhite
}

function Complete-ActiveProcess {
    if (-not $script:ActiveProcess) { return }
    $code = $script:ActiveProcess.ExitCode
    $script:ActiveProcess.Dispose()
    $script:ActiveProcess = $null

    if ($script:StreamLogPath -and (Test-Path -LiteralPath $script:StreamLogPath)) {
        try { Remove-Item -LiteralPath $script:StreamLogPath -Force } catch {}
    }
    $script:StreamLogPath = $null
    $script:StreamLogRead = 0
    $script:StreamExitSeenAt = $null

    if ($code -eq 0) {
        Add-LogLine '== SUCCESS: TASK FINISHED (EXIT CODE 0) =='
        $lblStatusBadge.Text = '● TASK FINISHED (SUCCESS)'
        $lblStatusBadge.ForeColor = $script:ColActiveGreen
        
        # Check if there is next task in pipeline
        if ($script:PipelineQueue.Count -gt 0) {
            $next = $script:PipelineQueue[0]
            $script:PipelineQueue = $script:PipelineQueue[1..($script:PipelineQueue.Count - 1)]
            & $next
        }
    } else {
        Add-LogLine ("== TASK FINISHED WITH ERROR (EXIT CODE $code) ==")
        $lblStatusBadge.Text = "● FINISHED WITH ERRORS ($code)"
        $lblStatusBadge.ForeColor = [System.Drawing.Color]::FromArgb(239, 68, 68)
        $script:PipelineQueue = @()
    }
}

# ---------------------------------------------------------------------------
#  Configuration Read & Save Functions
# ---------------------------------------------------------------------------
function Load-ConfigIntoForm {
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) { return }
    try {
        $cfg = Import-PowerShellDataFile -Path $script:ConfigPath
        if ($cfg.VMName) { $tbVMName.Text = [string]$cfg.VMName }
        if ($cfg.RAM_MB) { $tbRAM.Text = [string]$cfg.RAM_MB }
        if ($cfg.Disk_GB) { $tbDisk.Text = [string]$cfg.Disk_GB }
        if ($cfg.NetMode) {
            $idx = $comboNet.Items.IndexOf([string]$cfg.NetMode)
            if ($idx -ge 0) { $comboNet.SelectedIndex = $idx }
        }
        if ($cfg.BridgeAdapter) { $tbBridge.Text = [string]$cfg.BridgeAdapter }
        if ($cfg.ISOPath) { $tbISO.Text = [string]$cfg.ISOPath }
        if ($cfg.ServerName) { $tbServerName.Text = [string]$cfg.ServerName }
        if ($cfg.SectionAdminPassword) {
            $tbAdminPass.Text = [string]$cfg.SectionAdminPassword
            if ($cfg.SectionAdminPassword -match '^3106') { $comboSection.SelectedIndex = 0 }
            elseif ($cfg.SectionAdminPassword -match '^3107') { $comboSection.SelectedIndex = 1 }
            elseif ($cfg.SectionAdminPassword -match '^3108') { $comboSection.SelectedIndex = 2 }
            else { $comboSection.SelectedIndex = 3 }
        }
        if ($cfg.BaseSharePath) { $tbBasePath.Text = [string]$cfg.BaseSharePath }
        if ($cfg.Departments) {
            if ($cfg.Departments['IT']) {
                $tbITFolder.Text = [string]$cfg.Departments['IT'].FolderName
                $tbITFile.Text = [string]$cfg.Departments['IT'].FileName
            }
            if ($cfg.Departments['HR']) {
                $tbHRFolder.Text = [string]$cfg.Departments['HR'].FolderName
                $tbHRFile.Text = [string]$cfg.Departments['HR'].FileName
            }
            if ($cfg.Departments['Manager']) {
                $tbMgrFolder.Text = [string]$cfg.Departments['Manager'].FolderName
                $tbMgrFile.Text = [string]$cfg.Departments['Manager'].FileName
            }
        }
        if ($cfg.PublicShare) {
            $tbPubFolder.Text = [string]$cfg.PublicShare.FolderName
            $tbPubFile.Text = [string]$cfg.PublicShare.FileName
        }
        if ($cfg.PrinterPort) {
            $pIdx = $comboPort.Items.IndexOf([string]$cfg.PrinterPort)
            if ($pIdx -ge 0) { $comboPort.SelectedIndex = $pIdx }
        }
        if ($cfg.PrinterName) { $tbPrinterName.Text = [string]$cfg.PrinterName }
    } catch {
        Add-LogLine ('[config error] ' + $_.Exception.Message)
    }
}

function Save-ConfigFromForm {
    try {
        if (-not (Test-Path -LiteralPath $script:ConfigPath)) { return $false }
        $content = [System.IO.File]::ReadAllText($script:ConfigPath, [System.Text.Encoding]::UTF8)

        $vm = $tbVMName.Text.Trim()
        $ram = [int]$tbRAM.Text.Trim()
        $disk = [int]$tbDisk.Text.Trim()
        $net = [string]$comboNet.SelectedItem
        $bridge = $tbBridge.Text.Trim()
        $iso = $tbISO.Text.Trim()
        $srv = $tbServerName.Text.Trim()
        $pass = $tbAdminPass.Text.Trim()
        $base = $tbBasePath.Text.Trim()
        $itFold = $tbITFolder.Text.Trim(); $itFile = $tbITFile.Text.Trim()
        $hrFold = $tbHRFolder.Text.Trim(); $hrFile = $tbHRFile.Text.Trim()
        $mgrFold = $tbMgrFolder.Text.Trim(); $mgrFile = $tbMgrFile.Text.Trim()
        $pubFold = $tbPubFolder.Text.Trim(); $pubFile = $tbPubFile.Text.Trim()
        $port = [string]$comboPort.SelectedItem
        $prn = $tbPrinterName.Text.Trim()

        $content = [regex]::Replace($content, "(?m)^(\s*VMName\s*=\s*)'.*?'", "`${1}'$vm'")
        $content = [regex]::Replace($content, "(?m)^(\s*RAM_MB\s*=\s*)\d+", "`${1}$ram")
        $content = [regex]::Replace($content, "(?m)^(\s*Disk_GB\s*=\s*)\d+", "`${1}$disk")
        $content = [regex]::Replace($content, "(?m)^(\s*NetMode\s*=\s*)'.*?'", "`${1}'$net'")
        $content = [regex]::Replace($content, "(?m)^(\s*BridgeAdapter\s*=\s*)'.*?'", "`${1}'$bridge'")
        $content = [regex]::Replace($content, "(?m)^(\s*ISOPath\s*=\s*)'.*?'", "`${1}'$iso'")
        $content = [regex]::Replace($content, "(?m)^(\s*ServerName\s*=\s*)'.*?'", "`${1}'$srv'")
        $content = [regex]::Replace($content, "(?m)^(\s*SectionAdminPassword\s*=\s*)'.*?'", "`${1}'$pass'")
        $content = [regex]::Replace($content, "(?m)^(\s*BaseSharePath\s*=\s*)'.*?'", "`${1}'$base'")

        $content = [regex]::Replace($content, "(?m)(IT\s*=\s*@\{[^\r\n]*?FolderName\s*=\s*)'.*?'([^\r\n]*?FileName\s*=\s*)'.*?'", "`${1}'$itFold'${2}'$itFile'")
        $content = [regex]::Replace($content, "(?m)(HR\s*=\s*@\{[^\r\n]*?FolderName\s*=\s*)'.*?'([^\r\n]*?FileName\s*=\s*)'.*?'", "`${1}'$hrFold'${2}'$hrFile'")
        $content = [regex]::Replace($content, "(?m)(Manager\s*=\s*@\{[^\r\n]*?FolderName\s*=\s*)'.*?'([^\r\n]*?FileName\s*=\s*)'.*?'", "`${1}'$mgrFold'${2}'$mgrFile'")
        $content = [regex]::Replace($content, "(?m)(PublicShare\s*=\s*@\{[^\r\n]*?FolderName\s*=\s*)'.*?'([^\r\n]*?FileName\s*=\s*)'.*?'", "`${1}'$pubFold'${2}'$pubFile'")

        $content = [regex]::Replace($content, "(?m)^(\s*PrinterPort\s*=\s*)'.*?'", "`${1}'$port'")
        $content = [regex]::Replace($content, "(?m)^(\s*PrinterName\s*=\s*)'.*?'", "`${1}'$prn'")

        # Test write and validate PSD1 before committing
        $testFile = [System.IO.Path]::GetTempFileName()
        try {
            [System.IO.File]::WriteAllText($testFile, $content, [System.Text.Encoding]::UTF8)
            $null = Import-PowerShellDataFile -Path $testFile
        } catch {
            throw "Generated configuration failed validation: $($_.Exception.Message)"
        } finally {
            if (Test-Path $testFile) { Remove-Item $testFile -Force }
        }

        [System.IO.File]::WriteAllText($script:ConfigPath, $content, [System.Text.Encoding]::UTF8)
        $lblStatusBadge.Text = '● CONFIG SAVED'
        $lblStatusBadge.ForeColor = $script:ColActiveGreen
        Add-LogLine ('[config] Configuration saved to ' + $script:ConfigPath)
        return $true
    } catch {
        $lblStatusBadge.Text = '● CONFIG SAVE FAILED'
        $lblStatusBadge.ForeColor = [System.Drawing.Color]::FromArgb(239, 68, 68)
        Add-LogLine ('[config error] ' + $_.Exception.Message)
        return $false
    }
}

# ---------------------------------------------------------------------------
#  Action Pipelines
# ---------------------------------------------------------------------------
function Invoke-BuildVmTask {
    $exe = 'powershell.exe'
    $target = Join-Path $script:ScriptRoot '1_build_vm.ps1'
    Start-StreamingProcess -FileName $exe -Arguments ('-NoProfile -ExecutionPolicy Bypass -File "' + $target + '" -Start') -Banner 'PIPELINE 1/2 - BUILD VIRTUAL MACHINE'
}

function Invoke-PackIsoTask {
    $exe = 'powershell.exe'
    $target = Join-Path $script:ScriptRoot '3_pack_iso.ps1'
    Start-StreamingProcess -FileName $exe -Arguments ('-NoProfile -ExecutionPolicy Bypass -File "' + $target + '"') -Banner 'PIPELINE 2/2 - PACK SCRIPTS ISO'
}

function Launch-VirtualBoxGui {
    try {
        $candidates = @('VirtualBox', 'D:\VirtualBox\VirtualBox.exe', 'C:\Program Files\Oracle\VirtualBox\VirtualBox.exe')
        foreach ($c in $candidates) {
            $cmd = Get-Command $c -ErrorAction SilentlyContinue
            if ($cmd) {
                [System.Diagnostics.Process]::Start($cmd.Source) | Out-Null
                Add-LogLine '[launcher] VirtualBox GUI launched successfully.'
                return
            }
            if (Test-Path -LiteralPath $c) {
                [System.Diagnostics.Process]::Start($c) | Out-Null
                Add-LogLine '[launcher] VirtualBox GUI launched successfully.'
                return
            }
        }
        Add-LogLine '[launcher] VirtualBox.exe not found in standard paths.'
    } catch {
        Add-LogLine ('[launcher] ' + $_.Exception.Message)
    }
}

# Master Auto-Pilot Button
$btnMasterStart.add_Click({
    if ($script:ActiveProcess) { return }
    [void](Save-ConfigFromForm)
    
    Add-LogLine '======================================================================'
    Add-LogLine '  STARTING FULL AUTO-PILOT PIPELINE FOR IT 311 FINAL LAB'
    Add-LogLine '  1. Pack Scripts ISO (config + guest scripts + verifier)'
    Add-LogLine '  2. Build & Provision Virtual Machine (with ISOs attached & Bridged NIC)'
    Add-LogLine '  3. Power on VM & Launch VirtualBox Manager'
    Add-LogLine '======================================================================'
    
    # Setup Pipeline Queue: Pack ISO -> Build VM -> Launch VirtualBox
    $script:PipelineQueue = @(
        { Invoke-BuildVmTask },
        { 
            Launch-VirtualBoxGui
            $lblStatusBadge.Text = '● AUTO-PILOT READY! SWITCH TO TAB 2'
            $lblStatusBadge.ForeColor = $script:ColActiveGreen
            [System.Windows.Forms.MessageBox]::Show("Auto-Pilot Complete!`n`nYour VM has been provisioned and booted.`n`nSwitch to '2. In-VM Hands-On Guide' to complete the installation!", "IT 311 Auto-Pilot")
            $tabSteps.SelectedTab = $tab2
        }
    )
    Invoke-PackIsoTask
})

$btnStepBuild.add_Click({
    if ($script:ActiveProcess) { return }
    [void](Save-ConfigFromForm)
    Invoke-BuildVmTask
})

$btnStepPack.add_Click({
    if ($script:ActiveProcess) { return }
    [void](Save-ConfigFromForm)
    Invoke-PackIsoTask
})

function Refresh-VmList {
    try {
        $comboVmList.Items.Clear()
        $candidates = @('D:\VirtualBox\VBoxManage.exe', 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe')
        $vboxExe = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $vboxExe) {
            $cmd = Get-Command VBoxManage -ErrorAction SilentlyContinue
            if ($cmd) { $vboxExe = $cmd.Source }
        }
        if (-not $vboxExe) {
            $comboVmList.Items.Add('(VBoxManage not found)')
            $comboVmList.SelectedIndex = 0
            return
        }
        $raw = & $vboxExe list vms
        $vms = @()
        foreach ($line in ($raw -split "[\r\n]+")) {
            if ($line -match '^"([^"]+)"') { $vms += $Matches[1] }
        }
        if ($vms.Count -eq 0) {
            $comboVmList.Items.Add('(No VMs found)')
        } else {
            foreach ($v in $vms) { [void]$comboVmList.Items.Add($v) }
        }
        $comboVmList.SelectedIndex = 0
    } catch {
        Add-LogLine ('[vm scan error] ' + $_.Exception.Message)
    }
}

$btnRefreshVms.add_Click({ Refresh-VmList })

$btnDeleteSelectedVm.add_Click({
    $selected = [string]$comboVmList.SelectedItem
    if (-not $selected -or $selected.StartsWith('(')) { return }
    $confirm = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to completely delete and uninstall VM '$selected'?`n`nThis will unregister the VM and permanently delete its virtual hard disk (.vdi).", "Confirm Delete VM", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    try {
        $candidates = @('D:\VirtualBox\VBoxManage.exe', 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe')
        $vboxExe = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $vboxExe) {
            $cmd = Get-Command VBoxManage -ErrorAction SilentlyContinue
            if ($cmd) { $vboxExe = $cmd.Source }
        }
        if (-not $vboxExe) {
            Add-LogLine '[error] VBoxManage not found.'
            return
        }
        Add-LogLine "[cleanup] Powering off and deleting '$selected'..."
        & $vboxExe controlvm $selected poweroff 2>$null
        Start-Sleep -Milliseconds 600
        $res = & $vboxExe unregistervm $selected --delete 2>&1
        Add-LogLine "[cleanup] $res"
        Add-LogLine "[cleanup] VM '$selected' uninstalled successfully."
        Refresh-VmList
    } catch {
        Add-LogLine ('[delete error] ' + $_.Exception.Message)
    }
})

$comboSection.add_SelectedIndexChanged({
    switch ($comboSection.SelectedIndex) {
        0 { $tbAdminPass.Text = '3106@BatStateU' }
        1 { $tbAdminPass.Text = '3107@BatStateU' }
        2 { $tbAdminPass.Text = '3108@BatStateU' }
    }
})

$btnSaveAllConfig.add_Click({ [void](Save-ConfigFromForm) })

$btnBrowseIso.add_Click({
    $dialog = [System.Windows.Forms.OpenFileDialog]::new()
    try {
        $dialog.Title = 'Select Windows Server 2022 ISO'
        $dialog.Filter = 'ISO Images (*.iso)|*.iso|All files (*.*)|*.*'
        $dialog.InitialDirectory = $script:ScriptRoot
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $tbISO.Text = $dialog.FileName
        }
    } finally {
        $dialog.Dispose()
    }
})

$btnCopyCmdHero.add_Click({
    [System.Windows.Forms.Clipboard]::SetText($script:GuestCommand)
    $lblStatusBadge.Text = '● COPIED GUEST CONFIG CMD'
    $lblStatusBadge.ForeColor = $script:ColActiveGreen
    [System.Windows.Forms.MessageBox]::Show("Copied Guest Command to clipboard:`n`n$($script:GuestCommand)", "IT 311 Assistant")
})

$btnCopyVerifyHero.add_Click({
    [System.Windows.Forms.Clipboard]::SetText($script:VerifyCommand)
    $lblStatusBadge.Text = '● COPIED VERIFIER CMD'
    $lblStatusBadge.ForeColor = $script:ColActiveGreen
    [System.Windows.Forms.MessageBox]::Show("Copied Verifier Command to clipboard:`n`n$($script:VerifyCommand)", "IT 311 Assistant")
})

# ---------------------------------------------------------------------------
#  Background Polling Timer
# ---------------------------------------------------------------------------
$timer = [System.Windows.Forms.Timer]::new()
$timer.Interval = 120
$timer.add_Tick({
    try {
        if ($script:StreamLogPath -and (Test-Path -LiteralPath $script:StreamLogPath)) {
            $content = Read-SharedText -Path $script:StreamLogPath
            if ($content.Length -gt $script:StreamLogRead) {
                $chunk = $content.Substring($script:StreamLogRead)
                $script:StreamLogRead = $content.Length
                if ($script:rtbLog -and -not $script:rtbLog.IsDisposed) {
                    $script:rtbLog.AppendText($chunk)
                    $script:rtbLog.SelectionStart = $script:rtbLog.TextLength
                    $script:rtbLog.ScrollToCaret()
                }
            }
        }
        if ($script:ActiveProcess) {
            if ($script:ActiveProcess.HasExited) {
                if ($null -eq $script:StreamExitSeenAt) {
                    $script:StreamExitSeenAt = [DateTime]::UtcNow
                } elseif (([DateTime]::UtcNow - $script:StreamExitSeenAt).TotalMilliseconds -gt 600) {
                    Complete-ActiveProcess
                }
            }
        }
    } catch {}
})

$form.add_Shown({
    Load-ConfigIntoForm
    Refresh-VmList
    $timer.Start()
})

$form.add_FormClosing({
    $timer.Stop()
})

[void]$form.ShowDialog()
$form.Dispose()
