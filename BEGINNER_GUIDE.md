# IT 311 Final Lab — Beginner Step-by-Step Guide

> **Who this is for:** Students doing the IT 311 System Administration Final Lab (50 points).
> **What this covers:** All 6 task areas, the manual steps you must do by hand, and the common mistakes that cost points.
> **Tools needed:** This toolkit folder (`D:\SAM_LAB`), VirtualBox, the Windows Server 2022 ISO, and ~30 minutes.

---

## 0. Before you start (checklist)

Make sure all of these are true before exam day:

- [ ] VirtualBox is installed (this PC: `D:\VirtualBox\VBoxManage.exe`, version 7.2.16).
- [ ] The Windows Server 2022 ISO is in `D:\SAM_LAB` (file: `SERVER_EVAL_x64FRE_en-us.iso`).
- [ ] The toolkit files are in `D:\SAM_LAB`:
  - `config.psd1`
  - `1_build_vm.ps1` (and `1_build_vm.sh`)
  - `2_configure_server.ps1`
  - `3_pack_iso.ps1` (and `3_pack_iso.py`)
  - `launcher.ps1` + `Start_Lab_UI.bat`
  - `README.md`
- [ ] You know your **section number** (e.g. 3106, 3107, 3108) — it becomes part of your admin password.
- [ ] You know your **department names** and the passwords/folders/files the instruction sheet lists.

> **Tip:** Read the instruction sheet once before touching the PC. Write down the exact VM name, server name, printer name, and share names. Spelling counts for grading.

---

## 1. Edit `config.psd1` (the only file you edit on exam day)

You can edit it two ways:

### Option A — GUI launcher (recommended for beginners)
1. Double-click `Start_Lab_UI.bat`.
2. The window opens and reads `config.psd1` automatically.
3. Fill in every field (see table below).
4. Click **[ SAVE CONFIG ]**.
5. Click **[ 2. PACK ISO ]** to rebuild `lab_scripts.iso`.

### Option B — Edit the file directly
Open `D:\SAM_LAB\config.psd1` in Notepad and change the values between the single quotes.

### What each field means

| Field | Example | Notes |
|---|---|---|
| `VMName` | `Lab_Exam_VM` | Exact spelling from the sheet. |
| `RAM_MB` | `4096` | Minimum 2048 MB. 4096 recommended. |
| `Disk_GB` | `30` | Dynamic VDI. Minimum 20 GB. |
| `NetMode` | `bridged` | `bridged` / `nat` / `hostonly` / `intnet`. |
| `BridgeAdapter` | *(blank)* | Leave blank to auto-detect your Wi-Fi NIC. |
| `ISOPath` | *(blank)* | Leave blank to auto-detect the newest `*.iso` in this folder (recommended). |
| `ServerName` | `Lab-Server-01` | **Max 15 characters.** Letters, numbers, hyphens only. No spaces or underscores. |
| `SectionAdminPassword` | `3106@BatStateU` | Format: `<section>@BatStateU` (capital B, S, U). |
| `BaseSharePath` | `C:\Shares` | Where department folders will be created. |
| `Departments` → IT/HR/Manager | passwords, folder names, file names | Keep the passwords the sheet gives you. |
| `PublicShare` | `Public_Share` / `public.txt` | Public folder + file. |
| `PrinterPort` | `LPT1:` | `LPT1:` or `FILE:`. |
| `PrinterName` | `Office-Printer` | Must match the sheet exactly. |

> **Beginner tip:** The GUI shows a live counter next to Server Name. If it turns black with white text, the name is invalid — fix it before saving.

---

## 2. Build the virtual machine (Task Area 01)

### Using the GUI
1. Click **[ 1. BUILD VM ]**.
2. Watch the console box at the bottom — it streams live output.
3. When it says `FINISHED WITH EXIT CODE 0`, the VM is ready.

### Using PowerShell (manual)
```powershell
cd D:\SAM_LAB
powershell -ExecutionPolicy Bypass -File .\1_build_vm.ps1 -Start
```

### What the builder does for you
- Creates a VM named `Lab_Exam_VM` with OS type `Windows2022_64`.
- Sets RAM to 4096 MB.
- Creates a **dynamic** 30 GB VDI (grows as needed).
- Sets network mode (auto-detects your active Wi-Fi NIC for bridged mode).
- Attaches the Server 2022 ISO to the optical drive.
- **Does NOT run an unattended install** — you install Windows yourself.
- Prints a verification summary (RAM, VDI, network, ISO) with PASS/FAIL checks.

> **Common mistake:** Do not let VirtualBox auto-install Windows. The builder deliberately leaves the ISO attached but unattended install OFF. You must choose "Windows Server 2022 (Desktop Experience)" yourself.

---

## 3. Install Windows Server 2022 (MANUAL — you must do this)

1. Open VirtualBox Manager and start `Lab_Exam_VM`.
2. The VM boots from the ISO. Press any key when prompted ("Press any key to boot from CD or DVD").
3. Choose your language, time format, and keyboard. Click **Next** → **Install now**.
4. When asked for the operating system, choose:
   > **Windows Server 2022 Standard Evaluation (Desktop Experience)**
   >
   > ⚠️ Pick the one that says **Desktop Experience**. The "Server Core" version has no GUI and you will lose points.
5. Accept the license terms. Click **Next**.
6. Choose **Custom: Install Windows only (advanced)**.
7. Select the unallocated disk space (the 30 GB VDI). Click **Next**.
8. Wait for installation to finish. The VM will reboot.
9. When prompted, set the Administrator password to `3106@BatStateU` (or your section's password).
10. Log in as **Administrator**.

> **Manual step reminder:** Selecting "Desktop Experience" is 100% manual. The script cannot do this for you.

---

## 4. Mount the ISO and run the guest script (Task Areas 03–06)

### Step 4.1 — Mount `lab_scripts.iso` in the guest
1. In the running VM window: **Devices → Optical Drives → Choose/Create a disk image...**
2. Select `D:\SAM_LAB\lab_scripts.iso` on the host.
3. Inside Windows Server, open **File Explorer**. The ISO appears as a CD drive (usually `D:`).

### Step 4.2 — Run the script (first pass)
1. Open **PowerShell as Administrator** in the guest.
2. Run:
   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process -Force
   D:\2_configure_server.ps1
   ```
3. The script reads `config.psd1` from the ISO and:
   - Renames the server to `Lab-Server-01`.
   - **Prompts you to reboot.** Press `Y` (or let it reboot).
   - **Exits after the rename** — this is correct and expected.

> ⚠️ **Do not panic when it exits.** The rename must happen first, then a reboot, then the rest. This is by design.

### Step 4.3 — Reboot and run again (second pass)
1. After reboot, log in as **Administrator**.
2. Re-mount `lab_scripts.iso` (Devices → Optical Drives → Choose).
3. Open PowerShell as Administrator again:
   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process -Force
   D:\2_configure_server.ps1
   ```
4. This pass completes everything:
   - Password policy (complexity ON, min length 8) + `gpupdate /force`.
   - Creates users **IT**, **HR**, **Manager** with passwords from config.
   - Disables "must change password at next logon".
   - Installs `FS-FileServer` and `FS-iSCSI-Target-Server`.
   - Creates folders, SMB shares, and NTFS permissions under `C:\Shares`.
   - Writes the credential `.txt` files (e.g. `it.txt`, `hr.txt`, `manager.txt`, `public.txt`).
   - Creates per-user private desktop shortcuts + a public desktop shortcut.
   - Installs and shares the printer `Office-Printer` on `LPT1:`.
   - Runs verification: confirms IT is **denied** access to HR's folder.

### GUI shortcut for the guest command
On your host, click **[ 3. COPY GUEST COMMAND ]** in the launcher. It copies
`Set-ExecutionPolicy Bypass -Scope Process -Force; D:\2_configure_server.ps1`
to your clipboard — paste it into the guest PowerShell.

---

## 5. Manual steps you MUST do yourself (do not skip)

These cannot be automated and are checked by the grader:

### 5.1 Log in once per department user
After the script finishes, log out of Administrator and log in as:
- `IT` (password `Tech#Dept2026`)
- `HR` (password `People#Dept2026`)
- `Manager` (password `Lead#Dept2026`)

**Why:** Windows only creates a user's profile folder on first login. The script creates shortcuts in the profile folders; if the profile doesn't exist yet, re-run `D:\2_configure_server.ps1` after these logins so shortcuts land in the real profile paths.

### 5.2 Verify desktop shortcuts
For each department user, check their **Desktop**:
- They should see **only their own** department share shortcut (e.g. `IT_Share.lnk`).
- They should **NOT** see other departments' shortcuts.
- They **should** see the `Public_Share` shortcut.

> **Common mistake:** "Public desktop" department-shortcut leaks. The script avoids this by placing shortcuts in each user's private profile desktop, not `C:\Users\Public\Desktop`.

### 5.3 Verify "Access is denied"
Log in as **IT**, open File Explorer, and try to open:
- `\\Lab-Server-01\HR_Share` → must show **"Access is denied."**
- `\\Lab-Server-01\Manager_Share` → must show **"Access is denied."**

Repeat as HR and Manager. This proves NTFS/SMB permissions are correct.

> **Common mistake:** Running as Administrator bypasses access checks. The script verifies ACLs directly (Allow ACEs) so Administrator access does not fake a pass.

### 5.4 Verify the printer
- Open `\\Lab-Server-01` from a client — `Office-Printer` should appear.
- Or: Control Panel → Devices and Printers → `Office-Printer` should be listed and shared.

### 5.5 Verify credential files
Open each share folder and confirm the `.txt` file contains the department password:
- `C:\Shares\IT_Share\it.txt` → `Tech#Dept2026`
- `C:\Shares\HR_Share\hr.txt` → `People#Dept2026`
- `C:\Shares\Manager_Share\manager.txt` → `Lead#Dept2026`
- `C:\Shares\Public_Share\public.txt` → public info

> **Common mistake:** Double extensions like `it.txt.txt`. The script uses `Get-TextFileName` to avoid this. If you see `.txt.txt`, rename the file.

### 5.6 Leave the VM running
- Do **not** shut down the VM.
- Leave it running with the console visible.
- Raise your hand to signal the grader.

---

## 6. Common mistakes that cost points (avoid all of these)

| # | Mistake | How this toolkit prevents it |
|---|---|---|
| 1 | Wrong VM name or wrong OS type | Builder uses `Windows2022_64` and reads `VMName` from config; prints PASS/FAIL verification. |
| 2 | RAM under 2048 MB or disk under 20 GB | Config defaults to 4096 / 30; builder verifies read-back. |
| 3 | Network mode not `bridged` | Config default `bridged`; builder auto-detects the real host NIC. |
| 4 | Unattended install used | Builder attaches ISO but does **not** enable unattended install. |
| 5 | Selected "Server Core" instead of "Desktop Experience" | Manual step — you must choose Desktop Experience. |
| 6 | Server name > 15 chars or contains spaces/underscores | GUI live counter warns; script validates. |
| 7 | Shares created before the rename | Script renames first, reboots, then creates shares. |
| 8 | Lost Administrators/SYSTEM access on folders | Script grants Full Control to Administrators and SYSTEM before removing broad groups. |
| 9 | Public desktop leaks department shortcuts | Shortcuts go into each user's private profile desktop. |
| 10 | `.txt.txt` double extensions | `Get-TextFileName` normalizes. |
| 11 | "Must change password at next logon" left ON | Script sets `PasswordExpired = 0` via ADSI. |
| 12 | Password policy not applied | Script uses `secedit` + `gpupdate /force` and verifies. |
| 13 | Printer not shared | Script creates `Office-Printer` on `LPT1:` and shares it. |
| 14 | Shutting down the VM before grading | Leave it running and raise your hand. |

---

## 7. Troubleshooting

| Problem | Fix |
|---|---|
| `VBoxManage.exe was not found` | Install VirtualBox or add its folder to `PATH`. Builder checks `D:\VirtualBox\` and the registry. |
| `Windows2022_64` not listed | Update VirtualBox. Older builds only offer `Windows2019_64`. |
| `VM already exists` | Use `-Recreate` (only if disposable) or delete the VM in VirtualBox Manager. `-Recreate` also clears a leftover VDI. |
| ISO build fails | Run `3_pack_iso.ps1` again; it uses Windows' built-in IMAPI2FS (no network, no tools). |
| `config.psd1` parse error | Check for missing quotes or commas. The packer validates before building. |
| Guest script says "Access is denied" on its own shares | Run PowerShell **as Administrator**. |
| Shortcuts missing after first run | Log in as each department user once, then re-run `D:\2_configure_server.ps1`. |
| Printer driver fails to install | The script retries with `Windows x64` environment automatically. |
| GUI won't open | Run `powershell -NoProfile -STA -ExecutionPolicy Bypass -File launcher.ps1` from a console to see the error. |

---

## 8. Quick reference card (print this)

```
VM NAME:        Lab_Exam_VM
RAM:            4096 MB
DISK:           30 GB (dynamic VDI)
NETWORK:        Bridged
SERVER NAME:    Lab-Server-01
ADMIN PASSWORD: 3106@BatStateU
BASE SHARE:     C:\Shares
PRINTER:        Office-Printer on LPT1:

DEPARTMENTS
  IT       password Tech#Dept2026   folder IT_Share      file it.txt
  HR       password People#Dept2026 folder HR_Share      file hr.txt
  Manager  password Lead#Dept2026   folder Manager_Share file manager.txt
  Public                            folder Public_Share  file public.txt

GUEST COMMAND (run in guest PowerShell as Admin):
  Set-ExecutionPolicy Bypass -Scope Process -Force
  D:\2_configure_server.ps1
  (run twice: once before reboot, once after)

MANUAL FINAL STEPS:
  1. Choose "Windows Server 2022 (Desktop Experience)".
  2. Log in as IT, HR, Manager once (creates profiles).
  3. Re-run guest script after those logins.
  4. As IT, open \\Lab-Server-01\HR_Share -> "Access is denied."
  5. Check printer at \\Lab-Server-01.
  6. Leave VM running, raise hand.
```

---

*Generated for the IT 311 Final Lab toolkit. Keep this file next to your scripts for exam day.*