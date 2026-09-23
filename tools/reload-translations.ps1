[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Mod
)

$ErrorActionPreference = 'Stop'
$tools = $PSScriptRoot
. (Join-Path $tools 'lib.ps1')
$modInfo = Resolve-PzMod $Mod

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tools 'dev.ps1') -Mod $modInfo.Name
if ($LASTEXITCODE -ne 0) { throw 'Checks or translation sync failed.' }

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tools 'setup-forge-live.ps1') -Mod $modInfo.Name
if ($LASTEXITCODE -ne 0) { throw 'Forge Live configuration failed.' }

$previousControl = $env:PZ_ALLOW_CONTROL
$env:PZ_ALLOW_CONTROL = '1'
try {
    & node (Join-Path $tools 'forge-live\cli\forge-live.mjs') --mod $modInfo.Id --translations
    if ($LASTEXITCODE -ne 0) { throw 'The game did not confirm the translation reload.' }
} finally {
    if ($null -eq $previousControl) { Remove-Item Env:PZ_ALLOW_CONTROL -ErrorAction SilentlyContinue }
    else { $env:PZ_ALLOW_CONTROL = $previousControl }
}
