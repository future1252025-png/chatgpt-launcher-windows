[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$scripts = @(
    (Join-Path $projectRoot 'Launch-ChatGPT.ps1'),
    (Join-Path $projectRoot 'Install.ps1'),
    (Join-Path $projectRoot 'Uninstall.ps1')
)

$failures = New-Object System.Collections.Generic.List[string]
foreach ($script in $scripts) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$errors)
    foreach ($error in @($errors)) {
        $failures.Add("${script}:$($error.Extent.StartLineNumber): $($error.Message)")
    }
}

$projectText = ($scripts | ForEach-Object { Get-Content -LiteralPath $_ -Raw }) -join "`n"
foreach ($forbidden in @('xwl20', 'OpenAI.Codex_26.')) {
    if ($projectText -match [regex]::Escape($forbidden)) {
        $failures.Add("Machine-specific text found: $forbidden")
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'Launch-ChatGPT.ps1') -Diagnostics
if ($LASTEXITCODE -ne 0) { throw 'Launcher diagnostics failed.' }

Write-Host 'Smoke test passed.'
exit 0
