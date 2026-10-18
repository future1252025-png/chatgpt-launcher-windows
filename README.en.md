# ChatGPT Launcher for Windows

An independent launcher for the Microsoft Store ChatGPT/Codex desktop app. It starts the registered app, waits for a real window, and can prepare the packaged local runtime before launch.

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

The default window wait deadline is 1200 seconds. The launcher makes at most three startup attempts with short increasing delays. If the app is already running without a window, it waits without stopping or restarting that process.

## Runtime preparation

Automatic runtime preparation runs before launch when the app is not running and the installed Store package contains the expected `cua_node` runtime. A cached package version, runtime identifier, and file count help avoid repeated preparation. When preparation is needed, the launcher:

1. Computes the runtime directory identifier from SHA-256 hashes of the manifest and core binaries.
2. Confirms that the app is not running and copies the packaged runtime to a temporary directory under the runtime root.
3. Checks that every source file exists in the temporary directory with the same length.
4. Confirms again that the app is not running, renames any existing destination as a backup, and moves the prepared directory into place.
5. Rechecks file lengths, records the package version, runtime identifier, and file count, then removes the old backup.
6. Starts the app and waits for its window. If preparation fails, it logs a warning and lets the official app prepare its own runtime.

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
