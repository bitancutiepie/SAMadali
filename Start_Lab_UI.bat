@echo off
setlocal
cd /d "%~dp0"

if not exist "%~dp0launcher.ps1" (
    echo launcher.ps1 was not found next to this file.
    pause
    exit /b 1
)

where powershell.exe >nul 2>nul
if errorlevel 1 (
    echo Windows PowerShell was not found.
    pause
    exit /b 1
)

start "IT311 Launcher" powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0launcher.ps1"
exit /b 0
