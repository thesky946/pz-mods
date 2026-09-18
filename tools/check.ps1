[CmdletBinding()]
param([string]$Mod = 'cook-it-for-me')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
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
& $emmyLuaPath --config (Join-Path $repo '.emmyrc.json') (Join-Path $modInfo.Root '42\media\lua')
if ($LASTEXITCODE -ne 0) { throw 'EmmyLua analysis failed.' }
$luaCommand = Get-Command lua -ErrorAction SilentlyContinue
$luaPath = if ($luaCommand) { $luaCommand.Source } else { Join-Path $env:LOCALAPPDATA 'Programs\Lua\bin\lua.exe' }
if (-not (Test-Path -LiteralPath $luaPath)) { throw 'Lua runner is required. Checks were not completed.' }
& node (Join-Path $PSScriptRoot 'forge-live\cli\check-project.mjs') $modInfo.Root
if ($LASTEXITCODE -ne 0) { throw 'Syntax or localization checks failed.' }
Push-Location (Join-Path $modInfo.Root 'tests')
try {
    & $luaPath run.lua
    if ($LASTEXITCODE -ne 0) { throw 'Lua tests failed.' }
} finally { Pop-Location }
Push-Location (Join-Path $PSScriptRoot 'forge-live')
try {
    & npm.cmd test
    if ($LASTEXITCODE -ne 0) { throw 'Forge Live tests failed.' }
} finally { Pop-Location }
& (Join-Path $PSScriptRoot 'tests\run.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Developer tooling tests failed.' }
Write-Host 'All checks passed.'
