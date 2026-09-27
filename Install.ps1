[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$InstallDirectory = (Join-Path $env:LOCALAPPDATA 'Programs\ChatGPTLauncher'),
    [string]$DesktopShortcutName = 'ChatGPT Launcher',
    [switch]$NoDesktopShortcut,
    [switch]$NoStartMenuShortcut,
    [switch]$ReplaceExistingShortcut,
    [switch]$LaunchAfterInstall
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-InstalledChatGptExecutable {
    foreach ($pkg in @(Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue |
            Sort-Object Version -Descending)) {
        if (-not $pkg.InstallLocation -or $pkg.SignatureKind -notin @('Store', 'System')) { continue }
        $exe = Join-Path $pkg.InstallLocation 'app\ChatGPT.exe'
        if (Test-Path -LiteralPath $exe -PathType Leaf) { return $exe }
    }
    return $null
}

function New-LauncherShortcut {
    param(
        [Parameter(Mandatory = $true)][string]$ShortcutPath,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$IconPath
    )

    $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $powershell
    $shortcut.Arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $ScriptPath
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.IconLocation = '{0},0' -f $IconPath
    $shortcut.Description = 'Launch the Microsoft Store ChatGPT desktop app reliably'
    $shortcut.WindowStyle = 1
    $shortcut.Save()
}

function Assert-ShortcutAvailable {
    param(
        [Parameter(Mandatory = $true)][string]$ShortcutPath,
        [Parameter(Mandatory = $true)][string]$InstalledScript
    )
    if (-not (Test-Path -LiteralPath $ShortcutPath -PathType Leaf)) { return }
    if ($ReplaceExistingShortcut) { return }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    if ($shortcut.Arguments.IndexOf($InstalledScript, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw "An unrelated shortcut already exists at $ShortcutPath. Choose another name or pass -ReplaceExistingShortcut."
    }
}

if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is not available for the current user.' }
if ([string]::IsNullOrWhiteSpace($DesktopShortcutName) -or
    $DesktopShortcutName.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) {
    throw 'DesktopShortcutName must be a valid single file name.'
}
$sourceRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$destinationRoot = [System.IO.Path]::GetFullPath($InstallDirectory)
if ($sourceRoot.Equals($destinationRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'InstallDirectory must be different from the project source directory.'
}
if (Test-Path -LiteralPath $destinationRoot) {
    if (-not (Test-Path -LiteralPath $destinationRoot -PathType Container)) {
        throw "InstallDirectory is not a directory: $destinationRoot"
    }
    if (@(Get-ChildItem -LiteralPath $destinationRoot -Force).Count -gt 0) {
        $existingMarkerPath = Join-Path $destinationRoot '.install.json'
        if (-not (Test-Path -LiteralPath $existingMarkerPath -PathType Leaf)) {
            throw "Refusing to overwrite a non-empty directory without a launcher installer marker: $destinationRoot"
        }
        try {
            $existingMarker = Get-Content -LiteralPath $existingMarkerPath -Raw | ConvertFrom-Json
        } catch {
            throw "Refusing to overwrite a directory with an invalid installer marker: $destinationRoot"
        }
        if ($existingMarker.Product -ne 'ChatGPTLauncher') {
            throw "Refusing to overwrite a directory with an unrelated installer marker: $destinationRoot"
        }
    }
}
$requiredFiles = @('Launch-ChatGPT.ps1', 'Launch-ChatGPT.cmd', 'Uninstall.ps1', 'Uninstall.cmd', 'README.md', 'README.en.md', 'LICENSE')
foreach ($file in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot $file) -PathType Leaf)) {
        throw "Required project file is missing: $file"
    }
}

$installedScript = Join-Path $destinationRoot 'Launch-ChatGPT.ps1'
if (-not $NoDesktopShortcut) {
    Assert-ShortcutAvailable -ShortcutPath (Join-Path ([Environment]::GetFolderPath('Desktop')) ($DesktopShortcutName + '.lnk')) -InstalledScript $installedScript
}
if (-not $NoStartMenuShortcut) {
    Assert-ShortcutAvailable -ShortcutPath (Join-Path ([Environment]::GetFolderPath('Programs')) 'ChatGPT Launcher.lnk') -InstalledScript $installedScript
}

if ($PSCmdlet.ShouldProcess($destinationRoot, 'Install ChatGPT Launcher')) {
    New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
    if (-not $sourceRoot.Equals($destinationRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        foreach ($file in $requiredFiles) {
            Copy-Item -LiteralPath (Join-Path $sourceRoot $file) -Destination (Join-Path $destinationRoot $file) -Force
        }
    }

    $marker = [pscustomobject]@{
        Product     = 'ChatGPTLauncher'
        Version     = '2.0.0'
        InstalledAt = (Get-Date).ToString('o')
        Source      = $sourceRoot
        DesktopShortcutName = if ($NoDesktopShortcut) { $null } else { $DesktopShortcutName }
    }
    $marker | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $destinationRoot '.install.json') -Encoding UTF8

    $iconPath = Join-Path $destinationRoot 'ChatGPT.ico'
    $chatGptExe = Get-InstalledChatGptExecutable
    if ($chatGptExe) {
        try {
            Add-Type -AssemblyName System.Drawing
            $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($chatGptExe)
            if ($icon) {
                $stream = [System.IO.File]::Open($iconPath, [System.IO.FileMode]::Create)
                try { $icon.Save($stream) } finally { $stream.Dispose(); $icon.Dispose() }
            }
        } catch {
            Write-Warning "Could not create a stable local icon: $($_.Exception.Message)"
        }
    }
    if (-not (Test-Path -LiteralPath $iconPath -PathType Leaf)) {
        $iconPath = Join-Path $env:WINDIR 'System32\shell32.dll'
    }

    if (-not $NoDesktopShortcut) {
        $desktop = [Environment]::GetFolderPath('Desktop')
        New-LauncherShortcut -ShortcutPath (Join-Path $desktop ($DesktopShortcutName + '.lnk')) -ScriptPath $installedScript -WorkingDirectory $destinationRoot -IconPath $iconPath
    }
    if (-not $NoStartMenuShortcut) {
        $programs = [Environment]::GetFolderPath('Programs')
        New-LauncherShortcut -ShortcutPath (Join-Path $programs 'ChatGPT Launcher.lnk') -ScriptPath $installedScript -WorkingDirectory $destinationRoot -IconPath $iconPath
    }

    Write-Host "ChatGPT Launcher 2.0.0 installed to $destinationRoot"
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installedScript -Diagnostics
    if ($LASTEXITCODE -ne 0) { throw 'Installation completed, but launcher diagnostics failed.' }

    if ($LaunchAfterInstall) {
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $installedScript
    }
}
