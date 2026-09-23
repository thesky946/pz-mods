[CmdletBinding()]
param(
    [string]$Mod = 'cook-it-for-me',
    [switch]$InstalledContracts
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
. (Join-Path $PSScriptRoot 'lib\AnalyzerBaseline.ps1')
$modInfo = Resolve-PzMod $Mod
$repo = Split-Path -Parent $PSScriptRoot
$umbrellaLibrary = Join-Path $repo '.types\umbrella\library'
if (-not (Test-Path -LiteralPath $umbrellaLibrary -PathType Container)) {
    throw 'Umbrella submodule is required. Run: git submodule update --init --recursive'
}
$emmyLuaPath = & (Join-Path $PSScriptRoot 'setup-emmylua.ps1')
if (-not (Test-Path -LiteralPath $emmyLuaPath -PathType Leaf)) {
    throw 'EmmyLua checker setup failed.'
}
$analyzerResult = Invoke-AnalyzerProcess -FilePath $emmyLuaPath -ArgumentList @(
    '--config',
    (Join-Path $repo '.emmyrc.json'),
    (Join-Path $modInfo.Root '42\media\lua')
)
$analyzerOutput = @($analyzerResult.output)
$analyzerExitCode = $analyzerResult.exitCode
$analyzerOutput | ForEach-Object { Write-Host $_ }
if ($analyzerExitCode -ne 0) { throw 'EmmyLua analysis failed.' }
$baselinePath = Join-Path $PSScriptRoot 'analyzer-baseline.json'
if (-not (Test-Path -LiteralPath $baselinePath -PathType Leaf)) { throw 'Analyzer baseline is missing.' }
$baseline = Get-Content -LiteralPath $baselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
$diagnostics = @(ConvertFrom-EmmyLuaDiagnostics -Output $analyzerOutput -RepositoryRoot $repo)
$newDiagnostics = @(Compare-AnalyzerDiagnostics -Baseline $baseline -Actual $diagnostics)
if ($newDiagnostics.Count -gt 0) {
    $newDiagnostics | Format-Table file, code, message -AutoSize | Out-Host
    throw "EmmyLua reported $($newDiagnostics.Count) unlisted diagnostic(s)."
}
if ($InstalledContracts) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'check-pz-contracts.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Installed Project Zomboid contracts did not match the checked-in fingerprint.' }
}
$luaCommand = Get-Command lua -ErrorAction SilentlyContinue
$luaPath = if ($luaCommand) { $luaCommand.Source } else { Join-Path $env:LOCALAPPDATA 'Programs\Lua\bin\lua.exe' }
if (-not (Test-Path -LiteralPath $luaPath)) { throw 'Lua runner is required. Checks were not completed.' }
& node (Join-Path $PSScriptRoot 'forge-live\cli\check-project.mjs') $modInfo.Root
if ($LASTEXITCODE -ne 0) { throw 'Syntax or localization checks failed.' }
Push-Location (Join-Path $modInfo.Root 'tests')
try {
    if (Test-Path -LiteralPath 'scenarios.lua' -PathType Leaf) {
        if (-not (Test-Path -LiteralPath 'test_scenario_registry.lua' -PathType Leaf)) {
            throw 'Scenario registry requires tests/test_scenario_registry.lua.'
        }
        foreach ($scenarioTest in @('test_scenario_registry.lua', 'test_action_simulator.lua', 'test_simulated_scenarios.lua')) {
            if (-not (Test-Path -LiteralPath $scenarioTest -PathType Leaf)) { continue }
            & $luaPath $scenarioTest
            if ($LASTEXITCODE -ne 0) { throw "Scenario consistency test failed: $scenarioTest" }
        }
    }
    & $luaPath run.lua
    if ($LASTEXITCODE -ne 0) { throw 'Lua tests failed.' }
} finally { Pop-Location }
Push-Location $repo
try {
    & $luaPath (Join-Path $PSScriptRoot 'forge-live\tests\bridge-translations.lua')
    if ($LASTEXITCODE -ne 0) { throw 'Forge Live translation bridge test failed.' }
} finally { Pop-Location }
Push-Location (Join-Path $PSScriptRoot 'forge-live')
try {
    & npm.cmd test
    if ($LASTEXITCODE -ne 0) { throw 'Forge Live tests failed.' }
} finally { Pop-Location }
& (Join-Path $PSScriptRoot 'tests\run.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Developer tooling tests failed.' }
Write-Host 'All checks passed.'
