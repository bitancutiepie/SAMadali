# IT 311 Final Lab — Exam-Day Toolkit

A parameterized toolkit for the **IT 311 System Administration Final Lab** (50 points): VirtualBox + Windows Server 2022, six task areas, one config file.

> [!NOTE]
> This toolkit was built and validated on **Windows 11 Home Single Language (64-bit)** with **VirtualBox 7.2.16** and the **Windows Server 2022 Evaluation ISO**. The host builder auto-detects your environment, so it works on other Windows hosts without editing scripts.

## Table of contents

- [Detected environment](#detected-environment)
- [Files](#files)
- [Quick start](#quick-start)
- [Configuration reference](#configuration-reference)
- [Exam-day workflow](#exam-day-workflow)
- [Manual steps you must do yourself](#manual-steps-you-must-do-yourself)
- [Common mistakes to avoid](#common-mistakes-to-avoid)
- [Troubleshooting](#troubleshooting)
- [GUI launcher](#gui-launcher)

## Detected environment

| Item | Value |
|---|---|
| Host OS | Windows 11 Home Single Language, 64-bit |
| VirtualBox | 7.2.16 at `D:\VirtualBox\VBoxManage.exe` |
| Guest OS type | `Windows2022_64` (supported by this VirtualBox build) |
| ISO | `D:\SAM_LAB\SERVER_EVAL_x64FRE_en-us.iso` |
| Active host NIC | `Intel(R) Wi-Fi 6 AX201 160MHz` (auto-detected for bridged mode) |
| Working folder | `D:\SAM_LAB` |

## Files

| File | Purpose |
|---|---|
| `config.psd1` | **Edit this only.** VM name/specs, ISO, server name, password, shares, printer. |
| `1_build_vm.ps1` | Host builder for Windows (primary on this PC). Task Area 01. |
| `1_build_vm.sh` | Host builder for Linux / macOS / WSL. Task Area 01. |
| `2_configure_server.ps1` | Inside the guest: rename → password policy → users → file/storage → print → verify. Task Areas 03–06. |
| `3_pack_iso.ps1` | Packages the guest script + config into `lab_scripts.iso` using Windows' built-in IMAPI2FS. |
| `3_pack_iso.py` | Python fallback for the ISO (pycdlib, external ISO tool, or delegates to the `.ps1`). |
| `launcher.ps1` / `Start_Lab_UI.bat` | Zero-dependency monochrome GUI control panel. |
| `BEGINNER_GUIDE.md` | Plain-English, step-by-step guide for beginners. |
| `README.md` | This file. |

Generated at exam time: `lab_scripts.iso`.

## Quick start

```powershell
cd D:\SAM_LAB
powershell -ExecutionPolicy Bypass -File .\3_pack_iso.ps1
powershell -ExecutionPolicy Bypass -File .\1_build_vm.ps1 -Start
```

Or double-click `Start_Lab_UI.bat` to use the GUI.

## Configuration reference

`config.psd1` is the only file you edit on exam day. Every other script reads it.

| Field | Example | Notes |
|---|---|---|
| `VMName` | `Lab_Exam_VM` | Exact spelling from the sheet. |
| `RAM_MB` | `4096` | Minimum 2048 MB. 4096 recommended. |
| `Disk_GB` | `30` | Dynamic VDI. Minimum 20 GB. |
| `NetMode` | `bridged` | `bridged` / `nat` / `hostonly` / `intnet`. |
| `BridgeAdapter` | *(blank)* | Leave blank to auto-detect your active NIC. |
| `ISOPath` | `D:\SAM_LAB\SERVER_EVAL_x64FRE_en-us.iso` | Full path to the Server 2022 ISO. |
| `ServerName` | `Lab-Server-01` | Max 15 characters. Letters, numbers, hyphens only. |
| `SectionAdminPassword` | `3106@BatStateU` | Format: `<section>@BatStateU`. |
| `BaseSharePath` | `C:\Shares` | Where department folders are created. |
| `Departments` | IT / HR / Manager | Passwords, folder names, file names per department. |
| `PublicShare` | `Public_Share` / `public.txt` | Public folder + file. |
| `PrinterPort` | `LPT1:` | `LPT1:` or `FILE:`. |
| `PrinterName` | `Office-Printer` | Must match the sheet exactly. |

## Exam-day workflow

### Step 0 — Edit `config.psd1`
Confirm these match the instruction sheet **exactly**: VM name, RAM, disk, server name, password, share names, printer name.

### Step 1 — Build the VM (Task Area 01)
```powershell
powershell -ExecutionPolicy Bypass -File .\1_build_vm.ps1 -Start
```
The builder creates the VM, sets RAM/disk/network, attaches the ISO, and prints a PASS/FAIL verification summary. It does **not** run an unattended install.

### Step 2 — Install Windows Server 2022 (manual)
1. Start the VM. Press any key to boot from CD.
2. Choose language → **Install now**.
3. Select **Windows Server 2022 Standard Evaluation (Desktop Experience)**. (Not Server Core.)
4. Accept license → **Custom: Install Windows only** → select the disk → Next.
5. Set the Administrator password. Log in as Administrator.

### Step 3 — Mount the ISO and run the guest script (Task Areas 03–06)
1. In the VM: **Devices → Optical Drives → Choose disk image** → `lab_scripts.iso`.
2. Open PowerShell as Administrator:
   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process -Force
   D:\2_configure_server.ps1
   ```
   The script renames the server, prompts for a reboot, and exits. **This is expected.**
3. After reboot, log in, re-mount the ISO, and run the script again. This pass completes password policy, users, shares, ACLs, printer, and verification.

### Step 4 — Manual verification
See [Manual steps you must do yourself](#manual-steps-you-must-do-yourself).

### Step 5 — Leave the VM running
Do not shut down. Raise your hand for grading.

## Manual steps you must do yourself

These cannot be automated and are checked by the grader:

1. **Select "Desktop Experience"** during Windows setup.
2. **Log in once as IT, HR, and Manager** so Windows creates their profiles. Then re-run `D:\2_configure_server.ps1` so shortcuts land in the real profile folders.
3. **Verify desktop shortcuts** — each user sees only their own share shortcut plus `Public_Share`. No other departments.
4. **Verify "Access is denied"** — log in as IT and open `\\Lab-Server-01\HR_Share` and `\\Lab-Server-01\Manager_Share`. Both must deny access.
5. **Verify the printer** — `Office-Printer` appears at `\\Lab-Server-01`.
6. **Verify credential files** — `it.txt`, `hr.txt`, `manager.txt`, `public.txt` contain the correct passwords.
7. **Leave the VM running** and raise your hand.

## Common mistakes to avoid

| # | Mistake | How this toolkit prevents it |
|---|---|---|
| 1 | Wrong VM name or OS type | Builder uses `Windows2022_64` and reads `VMName` from config; prints PASS/FAIL verification. |
| 2 | RAM under 2048 MB or disk under 20 GB | Config defaults to 4096 / 30; builder verifies read-back. |
| 3 | Network mode not `bridged` | Config default `bridged`; builder auto-detects the real host NIC. |
| 4 | Unattended install used | Builder attaches ISO but does **not** enable unattended install. |
| 5 | Selected "Server Core" | Manual step — you must choose Desktop Experience. |
| 6 | Server name > 15 chars or contains spaces/underscores | GUI live counter warns; script validates. |
| 7 | Shares created before the rename | Script renames first, reboots, then creates shares. |
| 8 | Lost Administrators/SYSTEM access on folders | Script grants Full Control to Administrators and SYSTEM first. |
| 9 | Public desktop leaks department shortcuts | Shortcuts go into each user's private profile desktop. |
| 10 | `.txt.txt` double extensions | `Get-TextFileName` normalizes. |
| 11 | "Must change password at next logon" left ON | Script sets `PasswordExpired = 0` via ADSI. |
| 12 | Password policy not applied | Script uses `secedit` + `gpupdate /force` and verifies. |
| 13 | Printer not shared | Script creates `Office-Printer` on `LPT1:` and shares it. |
| 14 | Shutting down the VM before grading | Leave it running and raise your hand. |

## Troubleshooting

| Problem | Fix |
|---|---|
| `VBoxManage.exe was not found` | Install VirtualBox or add its folder to `PATH`. |
| `Windows2022_64` not listed | Update VirtualBox. |
| `VM already exists` | Use `-Recreate` (only if disposable) or delete the VM. |
| ISO build fails | Run `3_pack_iso.ps1` again; uses Windows' built-in IMAPI2FS. |
| `config.psd1` parse error | Check for missing quotes or commas. |
| Guest script "Access is denied" | Run PowerShell **as Administrator**. |
| Shortcuts missing after first run | Log in as each user, then re-run the guest script. |
| Printer driver fails | Script retries with `Windows x64` environment automatically. |
| GUI won't open | Run `powershell -NoProfile -STA -ExecutionPolicy Bypass -File launcher.ps1` from a console. |

## GUI launcher

Double-click `Start_Lab_UI.bat` to open the monochrome control panel (`launcher.ps1`). No external dependencies — only Windows PowerShell and WinForms.

- On launch it reads `config.psd1` and fills every field.
- `[ SAVE CONFIG ]` writes the form values back to `config.psd1` (department passwords are preserved).
- `[ 1. BUILD VM ]` saves the config, runs `1_build_vm.ps1`, and streams output into the console box.
- `[ 2. PACK ISO ]` saves the config, runs `3_pack_iso.ps1`, and streams output into the console box.
- `[ 3. COPY GUEST COMMAND ]` copies the guest command to the clipboard.
- `[ GUIDE ]` opens a step-by-step wizard inside the launcher.
- Hotkeys: `Ctrl+S` save, `F5` build, `F6` pack. `CLEAR` empties the console.