@echo off
rem Double-click to remove RL ME Blocker and its firewall rules.
if not exist "%~dp0src\uninstall.ps1" (
    echo.
    echo   Please extract the zip first, or uninstall from Settings ^> Apps.
    echo.
    pause
    exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\uninstall.ps1"
