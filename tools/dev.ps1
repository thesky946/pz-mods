# Fast local development loop for Cook It For Me.
#
# One-off sync and checks:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev.ps1
# Keep syncing after every saved source file:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev.ps1 -Watch
# Also launch Steam's Project Zomboid after the first successful sync:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev.ps1 -Launch

[CmdletBinding()]
param(
    [switch]$Watch,
    [switch]$Launch,
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ModName = 'CookItForMe'
$WorkshopRoot = if ($env:ZOMBOID_WORKSHOP_DIR) { $env:ZOMBOID_WORKSHOP_DIR } else { Join-Path $env:USERPROFILE 'Zomboid\Workshop' }
$Target = Join-Path $WorkshopRoot "$ModName\Contents\mods\$ModName"
$DistributionTestState = Join-Path $env:USERPROFILE "Zomboid\DistributionTests\$ModName\state.json"

function Fail([string]$Message) { throw $Message }

if (Test-Path -LiteralPath $DistributionTestState) {
    Fail "Workshop distribution-test mode is active. Restore author staging with tools\\test_workshop_distribution.ps1 -Stop before running dev.ps1."
}

function Assert-Source {
    foreach ($path in @('42\mod.info', '42\media', 'common\media', 'workshop\workshop.txt')) {
        if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot $path))) { Fail "Missing source: $path" }
    }

    Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'common') -Recurse -Filter '*.json' -File | ForEach-Object {
        try { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null }
        catch { Fail "Invalid JSON: $($_.FullName): $($_.Exception.Message)" }
    }
}

function Sync-Directory([string]$Source, [string]$Destination) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    # /MIR makes deleted source files disappear locally too. It only targets this mod's author folder.
    & robocopy $Source $Destination /MIR /FFT /Z /R:1 /W:1 /XD '.git' '.idea' /XF 'Thumbs.db' 'desktop.ini' | Out-Null
    if ($LASTEXITCODE -gt 7) { Fail "robocopy failed for $Source (exit code $LASTEXITCODE)" }
}

function Sync-Mod {
    Assert-Source
    Sync-Directory (Join-Path $ProjectRoot '42') (Join-Path $Target '42')
    Sync-Directory (Join-Path $ProjectRoot 'common') (Join-Path $Target 'common')
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'workshop\workshop.txt') -Destination (Join-Path $WorkshopRoot "$ModName\workshop.txt") -Force
    Write-Host "Synced: $Target" -ForegroundColor Green
}

function Run-Tests {
    if ($SkipTests) { return }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'check.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Checks failed; sync stopped.' }
}

function Start-Game {
    Start-Process 'steam://rungameid/108600'
    Write-Host 'Project Zomboid launch requested through Steam.' -ForegroundColor Green
}

function Show-ReloadReminder {
    Write-Host 'Ready: files synced.' -ForegroundColor Cyan
}

Run-Tests
Sync-Mod
Show-ReloadReminder
if ($Launch) { Start-Game }
if (-not $Watch) { exit 0 }

$watchPaths = @('42', 'common', 'workshop') | ForEach-Object { Join-Path $ProjectRoot $_ }
$watchers = foreach ($path in $watchPaths) {
    $watcher = [System.IO.FileSystemWatcher]::new($path, '*')
    $watcher.IncludeSubdirectories = $true
    $watcher.NotifyFilter = [System.IO.NotifyFilters]'FileName, DirectoryName, LastWrite, Size'
    $watcher.InternalBufferSize = 32768
    $watcher.EnableRaisingEvents = $true
    $watcher
}
$subscriptions = foreach ($watcher in $watchers) {
    foreach ($eventName in @('Changed', 'Created', 'Deleted', 'Renamed')) {
        Register-ObjectEvent -InputObject $watcher -EventName $eventName | Out-Null
    }
}

Write-Host 'Watching source files. Stop with Ctrl+C. Restart the game/world after Lua changes.' -ForegroundColor Cyan
try {
    while ($true) {
        $event = Wait-Event -Timeout 1
        if ($event) {
            Remove-Event -EventIdentifier $event.EventIdentifier
            Start-Sleep -Milliseconds 150 # coalesce an editor's save/rename sequence
            while ($queuedEvent = Wait-Event -Timeout 0) {
                Remove-Event -EventIdentifier $queuedEvent.EventIdentifier
            }
            Run-Tests
            Sync-Mod
            Show-ReloadReminder
        }
    }
} finally {
    Get-EventSubscriber | Where-Object { $_.SourceObject -in $watchers } | Unregister-Event
    $watchers | ForEach-Object { $_.Dispose() }
}
