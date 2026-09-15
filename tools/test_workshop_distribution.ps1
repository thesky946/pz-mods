# Switch between the local author staging copy and the downloaded Workshop release.
[CmdletBinding(DefaultParameterSetName = 'Status')]
param(
    [string]$Mod = 'cook-it-for-me',
    [Parameter(Mandatory, ParameterSetName = 'Start')][switch]$Start,
    [Parameter(Mandatory, ParameterSetName = 'Stop')][switch]$Stop,
    [Parameter(ParameterSetName = 'Start')][switch]$Launch,
    [string]$ZomboidRoot = (Join-Path $env:USERPROFILE 'Zomboid'),
    [string]$SteamRoot
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
$modInfo = Resolve-PzMod $Mod
$modId = $modInfo.Id
$manifest = Get-Content -LiteralPath (Join-Path $modInfo.Root 'mod-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$workshopId = [string]$manifest.workshopid
if (-not $workshopId) { throw "Mod '$Mod' has no workshopid in mod-manifest.json." }
$ZomboidRoot = [IO.Path]::GetFullPath($ZomboidRoot)
$staging = Join-Path $ZomboidRoot "Workshop\$modId"
$stateRoot = Join-Path $ZomboidRoot "DistributionTests\$modId"
$backup = Join-Path $stateRoot 'author-staging'
$stateFile = Join-Path $stateRoot 'state.json'

function Find-SteamRoots {
    if ($SteamRoot) { return @([IO.Path]::GetFullPath($SteamRoot)) }
    $roots = @()
    $steamPath = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction SilentlyContinue).SteamPath
    if ($steamPath) { $roots += $steamPath.Replace('/', '\') }
    foreach ($root in @('C:\Program Files (x86)\Steam', 'C:\Program Files\Steam')) {
        if (Test-Path -LiteralPath $root) { $roots += $root }
    }
    $libraries = @($roots)
    foreach ($root in $roots | Select-Object -Unique) {
        $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (-not (Test-Path -LiteralPath $vdf)) { continue }
        foreach ($match in [regex]::Matches([IO.File]::ReadAllText($vdf), '"path"\s+"([^"]+)"')) {
            $libraries += $match.Groups[1].Value.Replace('\\', '\')
        }
    }
    return @($libraries | Where-Object { $_ } | Select-Object -Unique)
}

function Find-DownloadedMod {
    foreach ($root in Find-SteamRoots) {
        $candidate = Join-Path $root "steamapps\workshop\content\108600\$workshopId"
        if (Test-Path -LiteralPath (Join-Path $candidate "mods\$modId\42\mod.info")) { return $candidate }
    }
    return $null
}

function Assert-GameClosed {
    $running = @(Get-Process -Name 'ProjectZomboid64', 'ProjectZomboid32' -ErrorAction SilentlyContinue)
    if ($running.Count) { throw 'Close Project Zomboid before switching copies.' }
}

function Assert-WatcherStopped {
    $lock = Join-Path $ZomboidRoot 'Lua\forgelive\watcher.lock'
    if (-not (Test-Path -LiteralPath $lock)) { return }
    try { $owner = Get-Content -LiteralPath $lock -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return }
    if ($owner.pid -and (Get-Process -Id $owner.pid -ErrorAction SilentlyContinue)) {
        throw "Stop tools\\dev.cmd first (Forge Live watcher PID $($owner.pid))."
    }
}

function Show-Status {
    $download = Find-DownloadedMod
    $mode = if (Test-Path -LiteralPath $stateFile) { 'distribution test' } elseif (Test-Path -LiteralPath $staging) { 'development' } else { 'no local staging' }
    Write-Host "Mode: $mode"
    Write-Host "Author staging: $(if (Test-Path -LiteralPath $staging) { 'available' } else { 'hidden' })"
    Write-Host "Workshop download: $(if ($download) { $download } else { 'not downloaded' })"
}

if (-not $Start -and -not $Stop) { Show-Status; exit 0 }
Assert-GameClosed
Assert-WatcherStopped

if ($Start) {
    $download = Find-DownloadedMod
    if (-not $download) {
        throw "Workshop item $workshopId is not downloaded. Subscribe in Steam, wait for the download, then run this command again."
    }
    if (Test-Path -LiteralPath $stateFile) { throw 'Distribution-test mode is already active. Run -Stop to restore author staging.' }
    if (-not (Test-Path -LiteralPath $staging)) { throw "Author staging not found: $staging" }
    if (Test-Path -LiteralPath $backup) { throw "Refusing to overwrite existing backup: $backup" }
    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    Move-Item -LiteralPath $staging -Destination $backup
    @{ workshopId = $workshopId; downloadedMod = $download; startedAt = (Get-Date).ToUniversalTime().ToString('o') } |
        ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding UTF8
    Write-Host 'Distribution-test mode is active. Enable Cook It For Me from the subscribed Workshop item and use a test save.' -ForegroundColor Green
    if ($Launch) { Start-Process 'steam://rungameid/108600' }
    exit 0
}

if (-not (Test-Path -LiteralPath $backup)) { throw "Author staging backup not found: $backup" }
if (Test-Path -LiteralPath $staging) { throw "Refusing to overwrite author staging: $staging" }
Move-Item -LiteralPath $backup -Destination $staging
Remove-Item -LiteralPath $stateRoot -Recurse -Force
Write-Host 'Development mode restored. Run tools\\dev.cmd before testing new source changes.' -ForegroundColor Green
