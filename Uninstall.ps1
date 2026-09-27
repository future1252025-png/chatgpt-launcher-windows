[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$InstallDirectory,
    [switch]$RemoveLogs
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Remove-OwnedShortcut {
    param(
        [Parameter(Mandatory = $true)][string]$ShortcutPath,
        [Parameter(Mandatory = $true)][string]$InstalledScript
    )
    if (-not (Test-Path -LiteralPath $ShortcutPath -PathType Leaf)) { return }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    if ($shortcut.Arguments.IndexOf($InstalledScript, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
        Remove-Item -LiteralPath $ShortcutPath -Force
    }
}

if ([string]::IsNullOrWhiteSpace($InstallDirectory)) {
    $localMarker = Join-Path $PSScriptRoot '.install.json'
    if (Test-Path -LiteralPath $localMarker -PathType Leaf) {
        $InstallDirectory = $PSScriptRoot
    } else {
        $InstallDirectory = Join-Path $env:LOCALAPPDATA 'Programs\ChatGPTLauncher'
    }
}
$destinationRoot = [System.IO.Path]::GetFullPath($InstallDirectory)
$markerPath = Join-Path $destinationRoot '.install.json'
if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) {
    throw "Refusing to remove an unrecognized directory. Installer marker not found: $markerPath"
}
$marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
if ($marker.Product -ne 'ChatGPTLauncher') {
    throw 'Refusing to remove a directory with an invalid installer marker.'
}

if ($PSCmdlet.ShouldProcess($destinationRoot, 'Uninstall ChatGPT Launcher')) {
    $installedScript = Join-Path $destinationRoot 'Launch-ChatGPT.ps1'
    if ($marker.DesktopShortcutName) {
        Remove-OwnedShortcut -ShortcutPath (Join-Path ([Environment]::GetFolderPath('Desktop')) ($marker.DesktopShortcutName + '.lnk')) -InstalledScript $installedScript
    }
    Remove-OwnedShortcut -ShortcutPath (Join-Path ([Environment]::GetFolderPath('Programs')) 'ChatGPT Launcher.lnk') -InstalledScript $installedScript

    $ownedFiles = @(
        'Launch-ChatGPT.ps1', 'Launch-ChatGPT.cmd',
        'Uninstall.ps1', 'Uninstall.cmd', 'README.md', 'README.en.md', 'LICENSE',
        'ChatGPT.ico', '.install.json'
    )
    foreach ($file in $ownedFiles) {
        $path = Join-Path $destinationRoot $file
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Remove-Item -LiteralPath $path -Force
        }
    }
    if (@(Get-ChildItem -LiteralPath $destinationRoot -Force).Count -eq 0) {
        Remove-Item -LiteralPath $destinationRoot
    } else {
        Write-Warning "Other files remain in $destinationRoot; the directory was preserved."
    }

    if ($RemoveLogs) {
        $logRoot = Join-Path $env:LOCALAPPDATA 'ChatGPTLauncher'
        if (Test-Path -LiteralPath $logRoot -PathType Container) {
            $logDirectory = Join-Path $logRoot 'Logs'
            if (Test-Path -LiteralPath $logDirectory -PathType Container) {
                Get-ChildItem -LiteralPath $logDirectory -Filter 'launcher-*.log' -File |
                    Remove-Item -Force
                if (@(Get-ChildItem -LiteralPath $logDirectory -Force).Count -eq 0) {
                    Remove-Item -LiteralPath $logDirectory
                }
            }
            if (@(Get-ChildItem -LiteralPath $logRoot -Force).Count -eq 0) {
                Remove-Item -LiteralPath $logRoot
            }
        }
    }
    Write-Host 'ChatGPT Launcher was removed. The ChatGPT app and its data were not changed.'
}
