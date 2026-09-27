@echo off
setlocal
chcp 65001 >nul 2>&1
title Uninstall ChatGPT Launcher
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall.ps1" %*
set "launcherExitCode=%ERRORLEVEL%"
if not "%launcherExitCode%"=="0" (
    echo Uninstallation failed with code %launcherExitCode%.
    pause
)
exit /b %launcherExitCode%
