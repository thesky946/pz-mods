[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$luaCommand = Get-Command lua -ErrorAction SilentlyContinue
$luaPath = if ($luaCommand) { $luaCommand.Source } else { Join-Path $env:LOCALAPPDATA 'Programs\Lua\bin\lua.exe' }
if (-not (Test-Path -LiteralPath $luaPath)) { throw 'Lua runner is required. Checks were not completed.' }
& node (Join-Path $PSScriptRoot 'forge-live\cli\check-project.mjs') $repo
if ($LASTEXITCODE -ne 0) { throw 'Syntax or localization checks failed.' }
Push-Location (Join-Path $repo 'tests')
try {
    & $luaPath run.lua
    if ($LASTEXITCODE -ne 0) { throw 'Lua tests failed.' }
} finally { Pop-Location }
Push-Location (Join-Path $PSScriptRoot 'forge-live')
try {
    & npm.cmd test
    if ($LASTEXITCODE -ne 0) { throw 'Forge Live tests failed.' }
} finally { Pop-Location }
Write-Host 'All checks passed.'
