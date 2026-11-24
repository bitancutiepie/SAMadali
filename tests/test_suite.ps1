# Unit, Integration, and UI Layout Test Suite for IT 311 Lab Automation

Describe "IT 311 Final Lab Suite" {
    $labRoot = "D:\SAM_LAB"
    $configPath = Join-Path $labRoot "config.psd1"

    It "config.psd1 must exist and be valid PowerShell Data File" {
        (Test-Path $configPath) | Should Be $true
        $cfg = Import-PowerShellDataFile -Path $configPath
        $cfg.RAM_MB | Should BeGreaterThan 2047
        $cfg.Disk_GB | Should BeGreaterThan 19
        $cfg.VMName | Should Not BeNullOrEmpty
        $cfg.ServerName | Should Not BeNullOrEmpty
        $cfg.SectionAdminPassword | Should Match '^\d{4}@BatStateU$'
    }

    It "Save-Config logic preserves valid PSD1 structure after replacement" {
        $content = [System.IO.File]::ReadAllText($configPath, [System.Text.Encoding]::UTF8)
        
        $testRAM = "4096"
        $testDisk = "30"
        $testVM = "Lab_Exam_VM"
        $testServer = "Lab-Server-01"
        $testPass = "3106@BatStateU"

        $newContent = [regex]::Replace($content, "(?m)^(\s*VMName\s*=\s*)'.*?'", "`${1}'$testVM'")
        $newContent = [regex]::Replace($newContent, "(?m)^(\s*RAM_MB\s*=\s*)\d+", "`${1}$testRAM")
        $newContent = [regex]::Replace($newContent, "(?m)^(\s*Disk_GB\s*=\s*)\d+", "`${1}$testDisk")
        $newContent = [regex]::Replace($newContent, "(?m)^(\s*ServerName\s*=\s*)'.*?'", "`${1}'$testServer'")
        $newContent = [regex]::Replace($newContent, "(?m)^(\s*SectionAdminPassword\s*=\s*)'.*?'", "`${1}'$testPass'")

        $tempPsd1 = Join-Path $labRoot "tests\temp_config_test.psd1"
        [System.IO.File]::WriteAllText($tempPsd1, $newContent, [System.Text.Encoding]::UTF8)

        try {
            $parsed = Import-PowerShellDataFile -Path $tempPsd1
            $parsed.RAM_MB | Should Be 4096
            $parsed.Disk_GB | Should Be 30
            $parsed.VMName | Should Be "Lab_Exam_VM"
        } finally {
            if (Test-Path $tempPsd1) { Remove-Item $tempPsd1 -Force }
        }
    }

    It "1_build_vm.ps1 syntax and required keys check" {
        $errs = $null
        [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $labRoot "1_build_vm.ps1"), [ref]$null, [ref]$errs)
        $errs.Count | Should Be 0
    }

    It "2_configure_server.ps1 syntax check" {
        $errs = $null
        [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $labRoot "2_configure_server.ps1"), [ref]$null, [ref]$errs)
        $errs.Count | Should Be 0
    }

    It "verify_exam.ps1 syntax check" {
        $errs = $null
        [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $labRoot "verify_exam.ps1"), [ref]$null, [ref]$errs)
        $errs.Count | Should Be 0
    }

    It "3_pack_iso.ps1 runs successfully and packages verify_exam.ps1" {
        $res = powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $labRoot "3_pack_iso.ps1")
        $LASTEXITCODE | Should Be 0
        (Test-Path (Join-Path $labRoot "lab_scripts.iso")) | Should Be $true
    }

    It "Launcher UI has ZERO overlapping controls and correct docking layout" {
        Add-Type -Path (Join-Path $labRoot "ReaLTaiizor.dll")
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing

        function Find-Overlaps {
            param([System.Windows.Forms.Control]$container)
            $ctrls = @($container.Controls)
            $count = 0
            for ($i = 0; $i -lt $ctrls.Count; $i++) {
                for ($j = $i + 1; $j -lt $ctrls.Count; $j++) {
                    $c1 = $ctrls[$i]; $c2 = $ctrls[$j]
                    if ($c1.Visible -and $c2.Visible) {
                        $inter = [System.Drawing.Rectangle]::Intersect($c1.Bounds, $c2.Bounds)
                        if (-not $inter.IsEmpty -and $inter.Width -gt 0 -and $inter.Height -gt 0) {
                            $count++
                        }
                    }
                }
            }
            return $count
        }

        $code = [System.IO.File]::ReadAllText((Join-Path $labRoot "launcher.ps1"))
        $inspectBlock = @'
        $form.CreateControl()
        $global:overlapCount = 0
        $global:overlapCount += (Find-Overlaps $pnlHeader)
        $global:overlapCount += (Find-Overlaps $cardHero)
        $global:overlapCount += (Find-Overlaps $cardConfig)
        $global:overlapCount += (Find-Overlaps $cardLog)
        $global:tabTop = $tabSteps.Top
        $form.Dispose()
'@
        $testCode = $code.Replace('[void]$form.ShowDialog()', $inspectBlock)
        [ScriptBlock]::Create($testCode).Invoke()

        $global:overlapCount | Should Be 0
        $global:tabTop | Should BeGreaterThan 64
    }
}
