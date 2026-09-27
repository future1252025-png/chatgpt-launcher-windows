@echo off
setlocal
chcp 65001 >nul 2>&1
title Install ChatGPT Launcher
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" %*
set "launcherExitCode=%ERRORLEVEL%"
if not "%launcherExitCode%"=="0" (
    echo Installation failed with code %launcherExitCode%.
    pause
)
exit /b %launcherExitCode%
