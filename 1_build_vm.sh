#!/usr/bin/env bash
# =============================================================================
#  IT 311 Final Lab - Task Area 01: VirtualBox VM builder (Linux / macOS / WSL)
#  Companion to 1_build_vm.ps1. Reads config.psd1 and uses VBoxManage.
#
#  Usage:
#      chmod +x 1_build_vm.sh
#      ./1_build_vm.sh
#      ./1_build_vm.sh --recreate --start
#
#  NOTE: The host detected on this machine is Windows 11, so the PowerShell
#  builder is the primary script. This shell version is provided for Linux,
#  macOS, and WSL hosts.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${SCRIPT_DIR}/config.psd1"

RECREATE=0
START_VM=0
for arg in "$@"; do
    case "$arg" in
        --recreate|-r) RECREATE=1 ;;
        --start|-s)    START_VM=1 ;;
        -h|--help)
            echo "Usage: $0 [--recreate] [--start]"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            echo "Usage: $0 [--recreate] [--start]" >&2
            exit 2
            ;;
    esac
done

if [[ ! -f "$CONFIG" ]]; then
    echo "ERROR: config.psd1 not found at $CONFIG" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Read scalar values out of config.psd1 (comments, quotes and spaces handled)
# ---------------------------------------------------------------------------
read_cfg() {
    local key="$1"
    sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//p" "$CONFIG" \
        | head -n 1 \
        | sed -e "s/[[:space:]]*#.*$//" \
              -e "s/^[[:space:]'\"]*//" \
              -e "s/[[:space:]'\"]*$//"
}

VM_NAME="$(read_cfg VMName)"
RAM_MB="$(read_cfg RAM_MB)"
DISK_GB="$(read_cfg Disk_GB)"
NET_MODE="$(read_cfg NetMode | tr '[:upper:]' '[:lower:]')"
BRIDGE_CFG="$(read_cfg BridgeAdapter)"
ISO_CFG="$(read_cfg ISOPath)"

[[ -n "$VM_NAME" ]] || { echo "ERROR: VMName is blank in config.psd1" >&2; exit 1; }
[[ "$RAM_MB" =~ ^[0-9]+$ ]] || { echo "ERROR: RAM_MB must be a number" >&2; exit 1; }
[[ "$DISK_GB" =~ ^[0-9]+$ ]] || { echo "ERROR: Disk_GB must be a number" >&2; exit 1; }
(( RAM_MB >= 2048 )) || { echo "ERROR: RAM_MB is below rubric minimum 2048 MB" >&2; exit 1; }
(( DISK_GB >= 20 )) || { echo "ERROR: Disk_GB is below rubric minimum 20 GB" >&2; exit 1; }

case "$NET_MODE" in
    nat|bridged|hostonly|intnet) ;;
    *) echo "ERROR: NetMode must be nat, bridged, hostonly, or intnet" >&2; exit 1 ;;
esac

# ---------------------------------------------------------------------------
# Locate VBoxManage
# ---------------------------------------------------------------------------
VBOX=""
if command -v VBoxManage >/dev/null 2>&1; then
    VBOX="$(command -v VBoxManage)"
elif [[ -x "/Applications/VirtualBox.app/Contents/MacOS/VBoxManage" ]]; then
    VBOX="/Applications/VirtualBox.app/Contents/MacOS/VBoxManage"
elif [[ -x "/usr/lib/virtualbox/VBoxManage" ]]; then
    VBOX="/usr/lib/virtualbox/VBoxManage"
elif [[ -x "/mnt/c/Program Files/Oracle/VirtualBox/VBoxManage.exe" ]]; then
    VBOX="/mnt/c/Program Files/Oracle/VirtualBox/VBoxManage.exe"
elif [[ -x "/d/VirtualBox/VBoxManage.exe" ]]; then
    VBOX="/d/VirtualBox/VBoxManage.exe"
fi
if [[ -z "$VBOX" ]]; then
    echo "ERROR: VBoxManage not found. Install Oracle VirtualBox or add it to PATH." >&2
    exit 1
fi
echo ">> VBoxManage: $VBOX"
echo "   Version: $("$VBOX" --version)"

if ! "$VBOX" list ostypes | grep -q 'Windows2022_64'; then
    echo "ERROR: This VirtualBox build does not list Windows2022_64. Update VirtualBox." >&2
    exit 1
fi

vbox() {
    if ! "$VBOX" "$@"; then
        echo "ERROR: VBoxManage $* failed" >&2
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Resolve ISO
# ---------------------------------------------------------------------------
ISO_PATH="$ISO_CFG"
if [[ -z "$ISO_PATH" ]]; then
    ISO_LIST="$(find "$SCRIPT_DIR" -maxdepth 1 -type f -iname '*.iso' 2>/dev/null | sort || true)"
    ISO_COUNT="$(printf '%s\n' "$ISO_LIST" | grep -c . || true)"
    if [[ "$ISO_COUNT" -eq 0 ]]; then
        echo "ERROR: ISOPath is blank and no .iso was found in $SCRIPT_DIR" >&2
        exit 1
    elif [[ "$ISO_COUNT" -eq 1 ]]; then
        ISO_PATH="$ISO_LIST"
    else
        ISO_MATCH="$(printf '%s\n' "$ISO_LIST" | grep -Ei 'server|2022|windows' || true)"
        if [[ "$(printf '%s\n' "$ISO_MATCH" | grep -c . || true)" -eq 1 ]]; then
            ISO_PATH="$ISO_MATCH"
        else
            echo "ERROR: Multiple ISOs found. Set ISOPath in config.psd1:" >&2
            printf '%s\n' "$ISO_LIST" >&2
            exit 1
        fi
    fi
elif [[ "$ISO_PATH" != /* && "$ISO_PATH" != [A-Za-z]:* && "$ISO_PATH" != */* ]]; then
    ISO_PATH="$SCRIPT_DIR/$ISO_PATH"
fi
[[ -f "$ISO_PATH" ]] || { echo "ERROR: ISO not found: $ISO_PATH" >&2; exit 1; }
echo ">> ISO: $ISO_PATH"

# ---------------------------------------------------------------------------
# Network resolution
# ---------------------------------------------------------------------------
list_bridged() {
    "$VBOX" list bridgedifs | awk '
        function val(s) { sub(/^[^:]*:[[:space:]]*/, "", s); return s }
        /^Name:/   { name = val($0) }
        /^Status:/ { status = val($0) }
        /^$/ {
            if (name != "" && status == "Up" && name !~ /VirtualBox/) { print name; exited = 1; exit }
            name = ""; status = ""
        }
        END {
            if (!exited && name != "" && status == "Up" && name !~ /VirtualBox/) { print name }
        }'
}

BRIDGE_NAME=""
if [[ "$NET_MODE" == "bridged" ]]; then
    if [[ -n "$BRIDGE_CFG" ]]; then
        BRIDGE_NAME="$BRIDGE_CFG"
    else
        BRIDGE_NAME="$(list_bridged | head -n 1)"
        if [[ -z "$BRIDGE_NAME" ]]; then
            echo "ERROR: No active bridged host interface found. Set NetMode = 'nat' or run on a connected host." >&2
            exit 1
        fi
        echo "   Auto-detected bridge: $BRIDGE_NAME"
    fi
fi

HOSTONLY_NAME=""
if [[ "$NET_MODE" == "hostonly" ]]; then
    HOSTONLY_NAME="$("$VBOX" list hostonlyifs | awk '
        function val(s) { sub(/^[^:]*:[[:space:]]*/, "", s); return s }
        /^Name:/   { name = val($0) }
        /^Status:/ { status = val($0) }
        /^$/ { if (name != "" && status == "Up") { print name; exit } }
        END { if (name != "" && status == "Up") print name }' | head -n 1)"
    if [[ -z "$HOSTONLY_NAME" ]]; then
        echo "ERROR: No VirtualBox host-only adapter found. Create one in VirtualBox Network Manager." >&2
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Existing VM
# ---------------------------------------------------------------------------
MACHINE_FOLDER="$("$VBOX" list systemproperties | sed -n 's/^Default machine folder:[[:space:]]*//p' | head -n 1)"
[[ -n "$MACHINE_FOLDER" ]] || MACHINE_FOLDER="$HOME/VirtualBox VMs"
mkdir -p "$MACHINE_FOLDER"
VM_FOLDER="$MACHINE_FOLDER/$VM_NAME"
VDI_PATH="$VM_FOLDER/$VM_NAME.vdi"

if "$VBOX" list vms | grep -Fq "\"$VM_NAME\""; then
    if [[ "$RECREATE" -ne 1 ]]; then
        echo "ERROR: VM '$VM_NAME' already exists. Use --recreate to delete and rebuild it." >&2
        exit 1
    fi
    STATE="$("$VBOX" showvminfo "$VM_NAME" --machinereadable | sed -n 's/^VMState="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' | head -n 1)"
    if [[ -n "$STATE" && "$STATE" != "poweroff" && "$STATE" != "aborted" ]]; then
        echo "ERROR: VM '$VM_NAME' is '$STATE'. Shut it down completely before --recreate." >&2
        exit 1
    fi
    echo ">> Removing existing VM '$VM_NAME' (--recreate)"
    vbox unregistervm "$VM_NAME" --delete
fi

if [[ -f "$VDI_PATH" ]]; then
    echo "ERROR: Disk already exists: $VDI_PATH. Move or delete it, then re-run." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Build VM
# ---------------------------------------------------------------------------
echo ''
echo "========================================================================"
echo "  IT 311 FINAL LAB - TASK AREA 01: VIRTUAL MACHINE BUILDER"
echo "========================================================================"

echo ">> Creating VM '$VM_NAME' (Windows2022_64, ${RAM_MB} MB)"
vbox createvm --name "$VM_NAME" --ostype Windows2022_64 --register --basefolder "$MACHINE_FOLDER"
vbox modifyvm "$VM_NAME" \
    --memory "$RAM_MB" --cpus 2 --vram 128 --ioapic on \
    --boot1 dvd --boot2 disk --boot3 none --boot4 none

echo ">> Configuring Adapter 1 ($NET_MODE)"
case "$NET_MODE" in
    nat)
        vbox modifyvm "$VM_NAME" --nic1 nat --nictype1 82540EM
        ;;
    bridged)
        vbox modifyvm "$VM_NAME" --nic1 bridged --bridgeadapter1 "$BRIDGE_NAME" --nictype1 82540EM
        ;;
    hostonly)
        vbox modifyvm "$VM_NAME" --nic1 hostonly --hostonlyadapter1 "$HOSTONLY_NAME" --nictype1 82540EM
        ;;
    intnet)
        vbox modifyvm "$VM_NAME" --nic1 intnet --intnet1 intnet --nictype1 82540EM
        ;;
esac

SIZE_MB=$(( DISK_GB * 1024 ))
echo ">> Creating dynamic VDI ($DISK_GB GB = $SIZE_MB MB)"
vbox createmedium disk --filename "$VDI_PATH" --size "$SIZE_MB" --format VDI --variant Standard

echo ">> Attaching storage controllers"
vbox storagectl "$VM_NAME" --name SATA --add sata --controller IntelAhci --portcount 4 --bootable on
vbox storageattach "$VM_NAME" --storagectl SATA --port 0 --device 0 --type hdd --medium "$VDI_PATH"
vbox storagectl "$VM_NAME" --name IDE --add ide --controller PIIX4 --bootable on
vbox storageattach "$VM_NAME" --storagectl IDE --port 1 --device 0 --type dvddrive --medium "$ISO_PATH"

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
INFO="$("$VBOX" showvminfo "$VM_NAME" --machinereadable)"
info_get() { printf '%s\n' "$INFO" | sed -n "s/^\"*$1\"*=//p" | head -n 1 | tr -d '"'; }

MEM_ACTUAL="$(info_get memory)"
OSTYPE_ACTUAL="$(info_get ostype)"
NIC_ACTUAL="$(info_get nic1)"
ISO_ACTUAL="$(info_get IDE-1-0)"
VDI_ACTUAL="$(info_get SATA-0-0)"
DISK_ACTUAL="$("$VBOX" showmediuminfo disk "$VDI_PATH" | sed -n 's/^Capacity:[[:space:]]*\([0-9][0-9]*\)[[:space:]]*MBytes.*/\1/p' | head -n 1)"

echo ''
echo "  ---------------------------------------------------------------"
echo "  VM SUMMARY (from VBoxManage showvminfo)"
echo "  ---------------------------------------------------------------"
printf '  VM name ............ %s\n' "$VM_NAME"
printf '  Guest OS type ...... %s\n' "$OSTYPE_ACTUAL"
printf '  RAM ................ %s MB\n' "$MEM_ACTUAL"
printf '  VDI disk ........... %s (%s MB capacity, dynamic)\n' "$VDI_PATH" "$DISK_ACTUAL"
printf '  ISO attached ....... %s\n' "$ISO_ACTUAL"
printf '  Network Adapter 1 .. %s\n' "$NIC_ACTUAL"
if [[ "$NIC_ACTUAL" == "bridged" ]]; then printf '  Bridged to ......... %s\n' "$BRIDGE_NAME"; fi
if [[ "$NIC_ACTUAL" == "hostonly" ]]; then printf '  Host-only to ....... %s\n' "$HOSTONLY_NAME"; fi
printf '  Boot order ......... %s, %s\n' "$(info_get boot1)" "$(info_get boot2)"
echo "  ---------------------------------------------------------------"

FAILED=0
check() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "   [ OK ] $label"
    else
        echo "   [FAIL] $label (expected '$expected', found '$actual')" >&2
        FAILED=1
    fi
}
check "RAM is exactly $RAM_MB MB" "$RAM_MB" "$MEM_ACTUAL"
if [[ "$OSTYPE_ACTUAL" == "Windows2022_64" || "$OSTYPE_ACTUAL" == *"Windows Server 2022"* ]]; then
    echo "   [ OK ] Guest OS is Windows Server 2022 (Windows2022_64): $OSTYPE_ACTUAL"
else
    echo "   [FAIL] Guest OS is '$OSTYPE_ACTUAL', expected Windows Server 2022 (Windows2022_64)" >&2
    FAILED=1
fi
check "Network Adapter 1 is $NET_MODE" "$NET_MODE" "$NIC_ACTUAL"
check "VDI path is attached" "$VDI_PATH" "$VDI_ACTUAL"
check "ISO is attached" "$ISO_PATH" "$ISO_ACTUAL"

if [[ -n "$DISK_ACTUAL" ]] && (( DISK_ACTUAL >= SIZE_MB )); then
    echo "   [ OK ] VDI capacity is $DISK_ACTUAL MB (>= $SIZE_MB MB)"
else
    echo "   [FAIL] VDI capacity is '$DISK_ACTUAL' MB, expected >= $SIZE_MB MB" >&2
    FAILED=1
fi

if [[ "$FAILED" -ne 0 ]]; then
    echo ''
    echo "VM validation failed." >&2
    exit 1
fi

echo ''
echo "ALL TASK AREA 01 CHECKS PASSED"
echo ''
echo "NEXT (manual OS install - Task Area 02):"
echo "  1. Start the VM and press a key to boot from the ISO."
echo "  2. Choose language > Install now."
echo "  3. Select an edition with (Desktop Experience) - NOT Server Core."
echo "  4. Accept license > Custom install > select the disk > Next."
echo "  5. Set the Administrator password from config.psd1."
echo "  6. Log in with Host key + Del (Right Ctrl + Del by default)."
echo ''

if [[ "$START_VM" -eq 1 ]]; then
    echo ">> Starting '$VM_NAME'"
    vbox startvm "$VM_NAME" --type gui
fi
