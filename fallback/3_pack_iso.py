#!/usr/bin/env python3
"""
IT 311 Final Lab - build lab_scripts.iso (Python fallback).

Packages config.psd1 and 2_configure_server.ps1 into lab_scripts.iso.

Preference order:
  1. pycdlib            (pip install pycdlib)
  2. oscdimg / mkisofs / genisoimage
  3. On Windows: delegate to 3_pack_iso.ps1 (uses built-in IMAPI2FS, no packages)

Examples:
    python 3_pack_iso.py
    python 3_pack_iso.py --output lab_scripts.iso
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
FILES = ("config.psd1", "2_configure_server.ps1")
VOLUME_ID = "LAB_SCRIPTS"


def build_with_pycdlib(staging: Path, output: Path) -> bool:
    try:
        import pycdlib  # type: ignore
    except ImportError:
        return False

    iso = pycdlib.PyCdlib()
    try:
        iso.new(interchange_level=3, joliet=3, vol_ident=VOLUME_ID)
        iso.add_file(
            str(staging / "config.psd1"),
            iso_path="/CONFIG.PSD1;1",
            joliet_path="/config.psd1",
        )
        iso.add_file(
            str(staging / "2_configure_server.ps1"),
            iso_path="/2_CONF.PS1;1",
            joliet_path="/2_configure_server.ps1",
        )
        iso.write(str(output))
    finally:
        iso.close()
    return True


def find_external_tool() -> str | None:
    for name in ("oscdimg", "mkisofs", "genisoimage"):
        path = shutil.which(name)
        if path:
            return path
    for candidate in (
        r"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
        r"C:\Program Files\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
    ):
        if Path(candidate).is_file():
            return candidate
    return None


def build_with_external(tool: str, staging: Path, output: Path) -> None:
    if Path(tool).name.lower().startswith("oscdimg"):
        command = [tool, "-m", "-o", "-u2", "-udfver102", f"-l{VOLUME_ID}", str(staging), str(output)]
    else:
        command = [tool, "-J", "-R", "-V", VOLUME_ID, "-o", str(output), str(staging)]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(
            f"{Path(tool).name} failed with exit {result.returncode}:\n"
            f"{result.stdout}\n{result.stderr}"
        )


def build_with_powershell(output: Path) -> int:
    ps1 = SCRIPT_DIR / "3_pack_iso.ps1"
    if not ps1.is_file():
        raise RuntimeError(
            "Cannot build the ISO: pycdlib is not installed, no ISO tool was found, "
            "and 3_pack_iso.ps1 is missing."
        )
    powershell = shutil.which("powershell") or shutil.which("pwsh")
    if not powershell:
        raise RuntimeError(
            "Cannot build the ISO on this host. Install pycdlib (pip install pycdlib), "
            "install mkisofs/genisoimage, or run 3_pack_iso.ps1 on Windows."
        )
    print(f">> Delegating to {ps1.name} via {powershell}")
    return subprocess.call(
        [powershell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(ps1), "-OutputPath", str(output)]
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Package the IT 311 guest files into lab_scripts.iso")
    parser.add_argument("--output", default=str(SCRIPT_DIR / "lab_scripts.iso"), help="Destination ISO path")
    parser.add_argument("--config", default=str(SCRIPT_DIR / "config.psd1"), help="Source config.psd1")
    parser.add_argument(
        "--server-script",
        default=str(SCRIPT_DIR / "2_configure_server.ps1"),
        help="Source 2_configure_server.ps1",
    )
    args = parser.parse_args()

    sources = [Path(args.config), Path(args.server_script)]
    for source in sources:
        if not source.is_file():
            print(f"ERROR: required source file not found: {source}", file=sys.stderr)
            return 1

    output = Path(args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="it311_iso_") as temp_dir:
        staging = Path(temp_dir)
        for source in sources:
            shutil.copy2(source, staging / source.name)

        temp_iso = output.with_suffix(output.suffix + ".tmp")
        if temp_iso.exists():
            temp_iso.unlink()

        try:
            if build_with_pycdlib(staging, temp_iso):
                print(">> ISO created with pycdlib.")
            else:
                tool = find_external_tool()
                if tool:
                    print(f">> ISO created with {Path(tool).name}.")
                    build_with_external(tool, staging, temp_iso)
                else:
                    code = build_with_powershell(output)
                    if code != 0:
                        print("ERROR: 3_pack_iso.ps1 failed.", file=sys.stderr)
                        return code
                    print(f">> Created {output}")
                    return 0

            if not temp_iso.is_file() or temp_iso.stat().st_size < 4096:
                print("ERROR: ISO was not created or is suspiciously small.", file=sys.stderr)
                return 1
            temp_iso.replace(output)
        finally:
            if temp_iso.exists():
                temp_iso.unlink(missing_ok=True)

    print(f">> Created {output} ({output.stat().st_size:,} bytes)")
    print("   Mount it in VirtualBox: Devices > Optical Drives > Choose/Create a disk image...")
    print("   Inside the guest: Set-ExecutionPolicy Bypass -Scope Process -Force; D:\\2_configure_server.ps1")
    return 0


if __name__ == "__main__":
    sys.exit(main())
