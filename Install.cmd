@echo off
rem Double-click to install RL ME Blocker.
if not exist "%~dp0src\install.ps1" (
    echo.
    echo   Please extract the zip first: right-click it, choose "Extract All",
    echo   then run Install.cmd from the extracted folder.
    echo.
    pause
    exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\install.ps1"
if errorlevel 1 pause
