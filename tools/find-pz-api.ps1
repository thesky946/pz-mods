[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Query,
    [string]$GamePath,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'lib\PzApiTools.ps1')

if (-not $GamePath) {
    $steamRoot = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if (-not $steamRoot) { throw 'Steam installation was not found in HKCU:\Software\Valve\Steam.' }
    $GamePath = Resolve-PzGamePath -SteamRoot $steamRoot
} else {
    $GamePath = Resolve-PzGamePath -GamePath $GamePath
}

$umbrella = Join-Path $repo '.types\umbrella\library'
$results = @(Find-PzApi -Query $Query -GamePath $GamePath -UmbrellaPath $umbrella)
if ($Json) {
    ConvertTo-Json -InputObject $results -Depth 4
} elseif ($results.Count -eq 0) {
    Write-Host "No API matches for '$Query'."
} else {
    $results | Format-Table source, path, line, text -AutoSize -Wrap
}
