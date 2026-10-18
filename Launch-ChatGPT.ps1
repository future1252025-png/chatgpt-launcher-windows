[CmdletBinding()]
param(
    [ValidateRange(15, 1800)]
    [int]$WaitSeconds = 1200,

    [ValidateRange(1, 10)]
    [int]$MaxStartAttempts = 3,

    [ValidateSet('Auto', 'Never')]
    [string]$RuntimeRepair = 'Auto',

    [switch]$NoForeground,
    [switch]$Diagnostics
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:LauncherVersion = '2.1.0'
$script:LogPath = $null
$script:StateRoot = $null
$script:Mutex = $null
$script:MutexOwned = $false

function Initialize-Logging {
    if (-not $env:LOCALAPPDATA) {
        throw 'LOCALAPPDATA is not available for the current user.'
    }

    $script:StateRoot = Join-Path $env:LOCALAPPDATA 'ChatGPTLauncher'
    $logRoot = Join-Path $script:StateRoot 'Logs'
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    $script:LogPath = Join-Path $logRoot ('launcher-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))

    # Keep the log directory bounded without touching ChatGPT data.
    Get-ChildItem -LiteralPath $logRoot -Filter 'launcher-*.log' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip 20 |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )

    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    if ($script:LogPath) {
        try { Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8 } catch { }
    }
}

function Get-ChatGptApplication {
    foreach ($pkg in @(Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue |
            Sort-Object Version -Descending)) {
        if (-not $pkg.InstallLocation) { continue }
        if ($pkg.SignatureKind -notin @('Store', 'System')) { continue }

        $exe = Join-Path $pkg.InstallLocation 'app\ChatGPT.exe'
        if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { continue }

        $appId = 'App'
        $manifestPath = Join-Path $pkg.InstallLocation 'AppxManifest.xml'
        if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
            try {
                [xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw
            $manifestApp = @($manifest.Package.Applications.Application |
                        Where-Object { (($_.Executable -replace '/', '\') -match '(^|\\)ChatGPT\.exe$') } |
                        Select-Object -First 1)
                if ($manifestApp.Count -eq 0) { continue }
                $appId = [string]$manifestApp[0].Id
            } catch {
                Write-Log "Could not parse AppxManifest.xml; using AppId 'App'. $($_.Exception.Message)" 'WARN'
            }
        }

        return [pscustomobject]@{
            Package          = $pkg
            PackageName      = [string]$pkg.Name
            PackageFullName  = [string]$pkg.PackageFullName
            PackageFamily    = [string]$pkg.PackageFamilyName
            Version          = [string]$pkg.Version
            InstallLocation  = [string]$pkg.InstallLocation
            Executable       = $exe
            AppId            = $appId
            Aumid            = ('{0}!{1}' -f $pkg.PackageFamilyName, $appId)
            RuntimeSource    = Join-Path $pkg.InstallLocation 'app\resources\cua_node'
        }
    }

    return $null
}

function Get-ChatGptProcesses {
    param([Parameter(Mandatory = $true)]$Application)

    $installRoot = [System.IO.Path]::GetFullPath($Application.InstallLocation).TrimEnd('\') + '\'
    $result = @()
    foreach ($process in @(Get-Process -Name 'ChatGPT' -ErrorAction SilentlyContinue)) {
        try {
            $path = $process.Path
            if ($path -and $path.StartsWith($installRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                $result += $process
            }
        } catch { }
    }
    return @($result)
}

function Get-ChatGptWindow {
    param([Parameter(Mandatory = $true)]$Application)
    return @(Get-ChatGptProcesses -Application $Application |
            Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } |
            Sort-Object StartTime |
            Select-Object -First 1)
}

function Initialize-NativeWindowApi {
    if ('ChatGPTLauncher.NativeMethods' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace ChatGPTLauncher {
    public static class NativeMethods {
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
        [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    }
}
'@
}

function Show-ChatGptWindow {
    param([Parameter(Mandatory = $true)]$Process)
    if ($NoForeground -or $Process.MainWindowHandle -eq [IntPtr]::Zero) { return }

    try {
        Initialize-NativeWindowApi
        $handle = $Process.MainWindowHandle
        $showCommand = if ([ChatGPTLauncher.NativeMethods]::IsIconic($handle)) { 9 } else { 5 }
        [void][ChatGPTLauncher.NativeMethods]::ShowWindowAsync($handle, $showCommand)
        if (-not [ChatGPTLauncher.NativeMethods]::SetForegroundWindow($handle)) {
            $shell = New-Object -ComObject WScript.Shell
            [void]$shell.AppActivate($Process.Id)
        }
    } catch {
        Write-Log "The ChatGPT window is open, but Windows did not allow foreground activation. $($_.Exception.Message)" 'WARN'
    }
}

function Start-ChatGptApplication {
    param([Parameter(Mandatory = $true)]$Application)

    $explorer = Join-Path $env:WINDIR 'explorer.exe'
    if (-not (Test-Path -LiteralPath $explorer -PathType Leaf)) {
        throw "explorer.exe was not found at $explorer"
    }

    Write-Log "Starting $($Application.PackageName) $($Application.Version)."
    Start-Process -FilePath $explorer -ArgumentList ('shell:AppsFolder\{0}' -f $Application.Aumid) | Out-Null
}

function Get-RuntimeRoot {
    if (-not $env:LOCALAPPDATA) { return $null }
    return Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\runtimes\cua_node'
}

function Get-StagingCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$RuntimeRoot,
        [datetime]$NotBefore = [datetime]::MinValue
    )

    if (-not (Test-Path -LiteralPath $RuntimeRoot -PathType Container)) { return $null }
    foreach ($directory in @(Get-ChildItem -LiteralPath $RuntimeRoot -Force -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like '.staging-*' -and $_.LastWriteTime -ge $NotBefore } |
            Sort-Object LastWriteTime -Descending)) {
        if ($directory.Name -match '^\.staging-([0-9a-fA-F]+)-') {
            return [pscustomobject]@{
                Directory     = $directory.FullName
                Name          = $directory.Name
                Hash          = $Matches[1].ToLowerInvariant()
                LastWriteTime = $directory.LastWriteTime
            }
        }
    }
    return $null
}

function Test-RuntimeTree {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [switch]$VerifyCoreHashes
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { return $false }
    if (-not (Test-Path -LiteralPath $Destination -PathType Container)) { return $false }

    $sourceRoot = [System.IO.Path]::GetFullPath($Source).TrimEnd('\')
    $destinationRoot = [System.IO.Path]::GetFullPath($Destination).TrimEnd('\')
    $sourceFiles = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -ErrorAction Stop)
    if ($sourceFiles.Count -eq 0) { return $false }

    foreach ($sourceFile in $sourceFiles) {
        $relative = $sourceFile.FullName.Substring($sourceRoot.Length).TrimStart('\')
        $destinationFile = Join-Path $destinationRoot $relative
        if (-not (Test-Path -LiteralPath $destinationFile -PathType Leaf)) { return $false }
        if ((Get-Item -LiteralPath $destinationFile).Length -ne $sourceFile.Length) { return $false }
    }

    foreach ($relative in @('bin\node.exe', 'bin\node_repl.exe')) {
        $sourceFile = Join-Path $sourceRoot $relative
        $destinationFile = Join-Path $destinationRoot $relative
        if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) { return $false }
        if (-not (Test-Path -LiteralPath $destinationFile -PathType Leaf)) { return $false }
        if ($VerifyCoreHashes) {
            if ((Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash -ne
                (Get-FileHash -LiteralPath $destinationFile -Algorithm SHA256).Hash) {
                return $false
            }
        }
    }

    return $true
}

function Assert-ChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Parent,
        [Parameter(Mandatory = $true)][string]$Child
    )
    $parentPath = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\') + '\'
    $childPath = [System.IO.Path]::GetFullPath($Child)
    if (-not $childPath.StartsWith($parentPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to operate outside the runtime root: $childPath"
    }
}

function Get-BundledRuntimeIdentity {
    param([Parameter(Mandatory = $true)][string]$RuntimeRoot)

    # Same 16-hex identity the desktop app uses for cua_node\<hash>.
    $sentinels = @('manifest.json', 'bin/node.exe', 'bin/node_repl.exe')
    $aggregate = [Security.Cryptography.IncrementalHash]::CreateHash(
        [Security.Cryptography.HashAlgorithmName]::SHA256
    )
    try {
        foreach ($relativePath in $sentinels) {
            $sourcePath = Join-Path $RuntimeRoot ($relativePath.Replace('/', '\'))
            if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                throw "Runtime sentinel is missing: $sourcePath"
            }
            $digest = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
            $aggregate.AppendData([Text.Encoding]::UTF8.GetBytes($relativePath))
            $aggregate.AppendData([byte[]](0))
            $aggregate.AppendData([Text.Encoding]::UTF8.GetBytes($digest))
            $aggregate.AppendData([byte[]](0))
        }
        $hex = -join ($aggregate.GetHashAndReset() | ForEach-Object { $_.ToString('x2') })
        return $hex.Substring(0, 16)
    } finally {
        $aggregate.Dispose()
    }
}

function Get-RuntimeRecordPath {
    return Join-Path $script:StateRoot 'package-runtime.txt'
}

function Read-RuntimeRecord {
    $path = Get-RuntimeRecordPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $lines = @(Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)
    if ($lines.Count -lt 3) { return $null }
    $count = 0
    if (-not [int]::TryParse($lines[2].Trim(), [ref]$count)) { return $null }
    if ($lines[1].Trim() -notmatch '^[0-9a-f]{16}$') { return $null }
    return [pscustomobject]@{
        PackageFullName = $lines[0].Trim()
        Hash            = $lines[1].Trim()
        Files           = $count
    }
}

function Write-RuntimeRecord {
    param(
        [Parameter(Mandatory = $true)][string]$PackageFullName,
        [Parameter(Mandatory = $true)][string]$Hash,
        [Parameter(Mandatory = $true)][int]$Files
    )
    @(
        $PackageFullName
        $Hash
        $Files
    ) | Set-Content -LiteralPath (Get-RuntimeRecordPath) -Encoding ASCII
}

function Test-CachedRuntime {
    param(
        [Parameter(Mandatory = $true)]$Application,
        [Parameter(Mandatory = $true)][string]$RuntimeRoot
    )

    $record = Read-RuntimeRecord
    if ($null -eq $record -or $record.PackageFullName -ne $Application.PackageFullName) { return $false }
    $destination = Join-Path $RuntimeRoot $record.Hash
    foreach ($relative in @('manifest.json', 'bin\node.exe', 'bin\node_repl.exe')) {
        $sourceFile = Join-Path $Application.RuntimeSource $relative
        $destinationFile = Join-Path $destination $relative
        if (-not (Test-Path -LiteralPath $destinationFile -PathType Leaf)) { return $false }
        if ((Get-Item -LiteralPath $sourceFile).Length -ne (Get-Item -LiteralPath $destinationFile).Length) { return $false }
    }
    $destinationCount = @(Get-ChildItem -LiteralPath $destination -Recurse -File -Force -ErrorAction SilentlyContinue).Count
    return ($destinationCount -eq $record.Files)
}

function Install-PackagedRuntime {
    param(
        [Parameter(Mandatory = $true)]$Application,
        [Parameter(Mandatory = $true)][string]$RuntimeRoot,
        [Parameter(Mandatory = $true)][string]$Hash
    )

    $source = $Application.RuntimeSource
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "This app version does not include a packaged runtime at $source"
    }
    if (@(Get-ChatGptProcesses -Application $Application).Count -gt 0) {
        throw 'ChatGPT is running. Refusing to copy the runtime over an active startup.'
    }

    New-Item -ItemType Directory -Path $RuntimeRoot -Force | Out-Null
    $destination = Join-Path $RuntimeRoot $Hash
    $temporary = Join-Path $RuntimeRoot ('.launcher-install-{0}-{1}' -f $Hash, $PID)
    Assert-ChildPath -Parent $RuntimeRoot -Child $temporary
    Assert-ChildPath -Parent $RuntimeRoot -Child $destination
    if (Test-Path -LiteralPath $temporary) {
        Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Log "Preparing runtime $Hash before launch. ChatGPT is not running."
    New-Item -ItemType Directory -Path $temporary -ErrorAction Stop | Out-Null
    $promoted = $false
    $backup = $null
    try {
        $robocopy = Join-Path $env:WINDIR 'System32\robocopy.exe'
        if (-not (Test-Path -LiteralPath $robocopy -PathType Leaf)) { throw 'robocopy.exe was not found.' }

        # /COPY:DT skips the Encrypted attribute. Copying that attribute makes
        # robocopy fail immediately on Store files. Do not pipe this command:
        # Windows PowerShell would discard its exit code.
        $null = & $robocopy $source $temporary '/E' '/COPY:DT' '/DCOPY:T' '/MT:8' '/XJ' '/NFL' '/NDL' '/NJH' '/NJS' '/NC' '/NS' '/NP' '/R:1' '/W:1'
        $copyExitCode = $LASTEXITCODE
        if ($copyExitCode -ge 8) { throw "robocopy failed with exit code $copyExitCode" }

        Write-Log "Copied runtime $Hash (robocopy exit $copyExitCode). Checking file lengths."
        if (-not (Test-RuntimeTree -Source $source -Destination $temporary)) {
            throw 'The prepared runtime failed validation.'
        }

        if (@(Get-ChatGptProcesses -Application $Application).Count -gt 0) {
            throw 'ChatGPT started during the runtime copy. Leaving its files untouched.'
        }

        if (Test-Path -LiteralPath $destination -PathType Container) {
            $backup = Join-Path $RuntimeRoot ('.launcher-backup-{0}-{1}' -f $Hash, (Get-Date -Format 'yyyyMMdd-HHmmss'))
            Assert-ChildPath -Parent $RuntimeRoot -Child $backup
            Move-Item -LiteralPath $destination -Destination $backup -ErrorAction Stop
        }

        Move-Item -LiteralPath $temporary -Destination $destination -ErrorAction Stop
        $promoted = $true
        if (-not (Test-RuntimeTree -Source $source -Destination $destination)) {
            throw 'Runtime validation failed after the atomic switch.'
        }

        $count = @(Get-ChildItem -LiteralPath $destination -Recurse -File -Force).Count
        Write-RuntimeRecord -PackageFullName $Application.PackageFullName -Hash $Hash -Files $count
        if ($backup -and (Test-Path -LiteralPath $backup)) {
            Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-Log "Runtime $Hash is ready ($count files)."
        return $true
    } catch {
        if ($backup -and (Test-Path -LiteralPath $backup) -and -not (Test-Path -LiteralPath $destination)) {
            Move-Item -LiteralPath $backup -Destination $destination -ErrorAction SilentlyContinue
        }
        throw
    } finally {
        if (-not $promoted -and (Test-Path -LiteralPath $temporary)) {
            Assert-ChildPath -Parent $RuntimeRoot -Child $temporary
            Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-Diagnostics {
    $application = Get-ChatGptApplication
    $runtimeRoot = Get-RuntimeRoot
    $staging = if ($runtimeRoot) { Get-StagingCandidate -RuntimeRoot $runtimeRoot } else { $null }
    $window = if ($application) { @(Get-ChatGptWindow -Application $application).Count -gt 0 } else { $false }

    return [pscustomobject]@{
        LauncherVersion       = $script:LauncherVersion
        PowerShellVersion     = $PSVersionTable.PSVersion.ToString()
        Windows               = [Environment]::OSVersion.VersionString
        PackageFound          = [bool]$application
        PackageName           = if ($application) { $application.PackageName } else { $null }
        PackageVersion        = if ($application) { $application.Version } else { $null }
        PackageStatus         = if ($application) { [string]$application.Package.Status } else { $null }
        ApplicationId         = if ($application) { $application.Aumid } else { $null }
        ExecutableExists      = [bool]($application -and (Test-Path -LiteralPath $application.Executable -PathType Leaf))
        RuntimeSourceExists   = [bool]($application -and (Test-Path -LiteralPath $application.RuntimeSource -PathType Container))
        RuntimeRoot           = $runtimeRoot
        StagingRuntime        = if ($staging) { $staging.Name } else { $null }
        ChatGptProcessCount   = if ($application) { @(Get-ChatGptProcesses -Application $application).Count } else { 0 }
        ChatGptWindowDetected = $window
        LogPath               = $script:LogPath
    }
}

function Acquire-LauncherMutex {
    $created = $false
    $script:Mutex = New-Object System.Threading.Mutex($false, 'Local\ChatGPTLauncher.SingleInstance', [ref]$created)
    try {
        $script:MutexOwned = $script:Mutex.WaitOne(0, $false)
    } catch [System.Threading.AbandonedMutexException] {
        $script:MutexOwned = $true
    }
    return $script:MutexOwned
}

function Invoke-Launcher {
    $env:CODEX_SPARKLE_ENABLED = 'false'
    $application = Get-ChatGptApplication
    if (-not $application) {
        throw 'A supported Microsoft Store ChatGPT/Codex desktop package was not found for the current user.'
    }

    $existingWindow = @(Get-ChatGptWindow -Application $application | Select-Object -First 1)
    if ($existingWindow.Count -gt 0) {
        Show-ChatGptWindow -Process $existingWindow[0]
        Write-Log 'ChatGPT is already open.'
        return 0
    }

    if (-not (Acquire-LauncherMutex)) {
        Write-Log 'Another launcher instance is already preparing ChatGPT. See the newest log for progress.' 'WARN'
        return 3
    }

    $attempts = 0
    $startedAt = Get-Date
    $deadline = $startedAt.AddSeconds($WaitSeconds)
    $nextStatus = $startedAt
    $runtimeRoot = Get-RuntimeRoot

    $runtimeReady = $false
    if ($RuntimeRepair -eq 'Auto' -and $runtimeRoot -and
        (Test-Path -LiteralPath $application.RuntimeSource -PathType Container)) {
        try {
            $runtimeReady = Test-CachedRuntime -Application $application -RuntimeRoot $runtimeRoot
        } catch {
            Write-Log "Could not read the runtime cache record. $($_.Exception.Message)" 'WARN'
        }
    }

    if ($runtimeReady) {
        Write-Log "Runtime cache matches $($application.Version)."
    } elseif (@(Get-ChatGptProcesses -Application $application).Count -gt 0) {
        Write-Log 'ChatGPT is already running without a window. Waiting, without interrupting its runtime copy.'
    } elseif ($RuntimeRepair -eq 'Auto' -and $runtimeRoot -and
        (Test-Path -LiteralPath $application.RuntimeSource -PathType Container)) {
        try {
            $hash = Get-BundledRuntimeIdentity -RuntimeRoot $application.RuntimeSource
            $destination = Join-Path $runtimeRoot $hash
            $sourceCount = @(Get-ChildItem -LiteralPath $application.RuntimeSource -Recurse -File -Force -ErrorAction SilentlyContinue).Count
            $destinationCount = 0
            if (Test-Path -LiteralPath $destination -PathType Container) {
                $destinationCount = @(Get-ChildItem -LiteralPath $destination -Recurse -File -Force -ErrorAction SilentlyContinue).Count
            }
            if ($sourceCount -gt 0 -and $destinationCount -eq $sourceCount) {
                Write-RuntimeRecord -PackageFullName $application.PackageFullName -Hash $hash -Files $sourceCount
                Write-Log "Runtime $hash is already complete ($sourceCount files)."
            } else {
                Install-PackagedRuntime -Application $application -RuntimeRoot $runtimeRoot -Hash $hash | Out-Null
            }
        } catch {
            Write-Log "Runtime preparation failed; the official app will copy it itself. $($_.Exception.Message)" 'WARN'
        }
    }

    if (@(Get-ChatGptProcesses -Application $application).Count -eq 0) {
        $attempts++
        Start-ChatGptApplication -Application $application
    }

    while ((Get-Date) -lt $deadline) {
        $window = @(Get-ChatGptWindow -Application $application | Select-Object -First 1)
        if ($window.Count -gt 0) {
            Show-ChatGptWindow -Process $window[0]
            Write-Log 'ChatGPT window is ready.'
            return 0
        }

        $processes = @(Get-ChatGptProcesses -Application $application)
        if ($processes.Count -eq 0) {
            if ($attempts -ge $MaxStartAttempts) {
                throw "ChatGPT exited before showing a window after $attempts start attempts."
            }
            $delay = [math]::Min([math]::Pow(2, $attempts), 15)
            Write-Log "ChatGPT exited before showing a window. Retrying in $delay second(s)." 'WARN'
            Start-Sleep -Seconds $delay
            $attempts++
            Start-ChatGptApplication -Application $application
            Start-Sleep -Seconds 2
            continue
        }

        if ((Get-Date) -ge $nextStatus) {
            $elapsed = [int]((Get-Date) - $startedAt).TotalSeconds
            $message = "Waiting for the ChatGPT window ($elapsed/$WaitSeconds seconds)."
            if ($runtimeRoot) {
                $staging = Get-StagingCandidate -RuntimeRoot $runtimeRoot
                if ($staging) { $message += ' The app is still copying its runtime.' }
            }
            Write-Log $message
            $nextStatus = (Get-Date).AddSeconds(20)
        }

        Start-Sleep -Seconds 2
    }

    throw "Timed out after $WaitSeconds seconds while waiting for the ChatGPT window."
}

$exitCode = 1
try {
    Initialize-Logging
    Write-Log "ChatGPT Launcher $script:LauncherVersion started."

    if ($Diagnostics) {
        $diagnosticReport = Get-Diagnostics
        $diagnosticReport | Format-List | Out-String | Write-Host
        if ($diagnosticReport.PackageFound -and $diagnosticReport.ExecutableExists) { $exitCode = 0 } else { $exitCode = 1 }
    } else {
        $exitCode = Invoke-Launcher
    }
} catch {
    Write-Log $_.Exception.Message 'ERROR'
    Write-Host "Log: $script:LogPath"
    $exitCode = 1
} finally {
    if ($script:MutexOwned -and $script:Mutex) {
        try { $script:Mutex.ReleaseMutex() } catch { }
    }
    if ($script:Mutex) { $script:Mutex.Dispose() }
}

exit $exitCode
