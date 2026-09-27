# ChatGPT Launcher for Windows

An independent launcher for the Microsoft Store ChatGPT/Codex desktop app. It starts the registered app, waits for a real window, and can prepare the packaged local runtime when a first launch gets stuck.

This community utility is not affiliated with or endorsed by OpenAI.

## Requirements

- Windows with Windows PowerShell 5.1 or later.
- The Microsoft Store `OpenAI.Codex` desktop package installed for the current user.
- No administrator rights are required.

## Install

Double-click `Install.cmd`, or run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

The installer copies the launcher to `%LOCALAPPDATA%\Programs\ChatGPTLauncher` and creates desktop and Start menu shortcuts. It saves an icon locally so a Store app update does not break the shortcut icon. The source project can live on any drive.
It refuses to overwrite a non-empty directory without this launcher's installer marker, and it will not install over the source project.

Options:

```powershell
.\Install.ps1 -NoDesktopShortcut
.\Install.ps1 -NoStartMenuShortcut
.\Install.ps1 -DesktopShortcutName "My ChatGPT Launcher"
.\Install.ps1 -InstallDirectory "D:\Apps\ChatGPTLauncher"
.\Install.ps1 -LaunchAfterInstall
```

If a shortcut name is already in use by another program, choose another name. `-ReplaceExistingShortcut` explicitly replaces it.

## Portable use

Double-click `Launch-ChatGPT.cmd` without installing, or run:

```powershell
.\Launch-ChatGPT.ps1
.\Launch-ChatGPT.ps1 -Diagnostics
.\Launch-ChatGPT.ps1 -WaitSeconds 900
.\Launch-ChatGPT.ps1 -RuntimeRepair Never
```

The default wait is 600 seconds. The launcher makes at most three startup attempts with short increasing delays.

## Runtime preparation

Automatic runtime preparation is considered when the app has no window after 15 seconds, a matching fresh `.staging-*` directory exists, and the installed Store package contains the expected `cua_node` runtime. The launcher:

1. Copies the packaged runtime to a temporary directory on the same volume.
2. Checks every source file's destination and length, plus SHA-256 hashes for core binaries.
3. Stops only `ChatGPT.exe` processes belonging to the selected Store package.
4. Preserves an incomplete runtime directory as a backup, then moves the prepared directory into place.
5. Rechecks the final directory and starts the app again.

It does not download binaries or change account data, proxy settings, or the registry. If a future app version changes its runtime layout, use `-RuntimeRepair Never` and let the official app manage its files.

## Diagnostics and logs

```powershell
.\Launch-ChatGPT.ps1 -Diagnostics
.\tests\Smoke-Test.ps1
```

Logs are stored in `%LOCALAPPDATA%\ChatGPTLauncher\Logs` (at most 20 launcher logs).

Exit codes: `0` means success, `1` means a launch or diagnostic failure, and `3` means another launcher instance is already running.

## Uninstall

Double-click `Uninstall.cmd`, or run `Uninstall.ps1` from the project or installed directory. Add `-RemoveLogs` to remove launcher logs. The uninstaller deletes only its own installed files and shortcuts. It leaves the ChatGPT app and its data untouched.
For a custom install directory, run the uninstaller from that directory, or pass the same `-InstallDirectory` when running it from the source project.

## Limitations

- Only the Microsoft Store `OpenAI.Codex` package is currently recognized. Unknown packages are intentionally skipped.
- Windows may prevent an app from forcing another app's window to the foreground. The window will still open in that case.
