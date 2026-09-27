@echo off
setlocal
chcp 65001 >nul 2>&1
title ChatGPT Launcher

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launch-ChatGPT.ps1" %*
set "launcherExitCode=%ERRORLEVEL%"

if not "%launcherExitCode%"=="0" (
    echo.
    echo ChatGPT Launcher exited with code %launcherExitCode%.
    echo Review the log under %%LOCALAPPDATA%%\ChatGPTLauncher\Logs.
    pause
)

exit /b %launcherExitCode%
