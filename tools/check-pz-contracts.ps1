[CmdletBinding()]
param(
    [string]$GamePath,
    [string]$SnapshotPath,
    [switch]$Update
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'lib\PzApiTools.ps1')
. (Join-Path $PSScriptRoot 'lib\PzContractSnapshot.ps1')

try {
    if ($GamePath) {
        $game = Resolve-PzGamePath -GamePath $GamePath
    } else {
        $steamRoot = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
        if (-not $steamRoot) { throw 'Steam installation was not found in HKCU.' }
        $game = Resolve-PzGamePath -SteamRoot $steamRoot
    }
    $umbrella = Join-Path $repo '.types\umbrella'
    $actual = Get-PzContractSnapshot -GamePath $game -UmbrellaPath $umbrella
    if ($actual.game.version -ne '42.20.4') {
        throw "Selected Project Zomboid install has Steam build $($actual.game.steamBuild), not the known 42.20.4 build 24909800."
    }
    if (-not $SnapshotPath) { $SnapshotPath = Join-Path $repo 'contracts\pz-42.20.4.json' }
    if ($Update) {
        $directory = Split-Path -Parent $SnapshotPath
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
        $actual | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $SnapshotPath -Encoding utf8
        Write-Host "Updated contract snapshot for Build $($actual.game.version) (Steam build $($actual.game.steamBuild))."
        exit 0
    }
    if (-not (Test-Path -LiteralPath $SnapshotPath -PathType Leaf)) { throw 'Expected contract snapshot was not found.' }
    $expected = Get-Content -LiteralPath $SnapshotPath -Raw | ConvertFrom-Json
    $differences = @(Compare-PzContractSnapshot -Expected $expected -Actual $actual)
    if ($differences.Count -eq 0) {
        Write-Host "PZ contract matches Build $($actual.game.version)."
        exit 0
    }
    Write-Host 'PZ contract drift detected:' -ForegroundColor Yellow
    $differences | Format-Table kind, path, expected, actual -AutoSize
    exit 2
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
