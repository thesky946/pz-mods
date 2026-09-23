[CmdletBinding()]
param(
    [string]$Mod = 'cook-it-for-me',
    [switch]$Json,
    [string]$ForgeConfigPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
. (Join-Path $PSScriptRoot 'lib\ForgeStatusTools.ps1')

if (-not $ForgeConfigPath) { $ForgeConfigPath = Join-Path $PSScriptRoot 'forge-live\forge-live.config.json' }

try {
    $modInfo = Resolve-PzMod $Mod
    $status = Get-ForgeGameStatus -ModInfo $modInfo -ForgeConfigPath $ForgeConfigPath
} catch {
    $gameRunning = $null
    try { $gameRunning = @(Get-Process -Name 'ProjectZomboid64' -ErrorAction SilentlyContinue).Count -gt 0 } catch {}
    $status = [pscustomobject]@{
        ok = $false
        game = [pscustomobject]@{ running = $gameRunning; process = 'ProjectZomboid64' }
        watcher = [pscustomobject]@{ state = 'configuration-error'; reason = $_.Exception.Message; pid = $null; running = $false }
        bridge = [pscustomobject]@{ ok = $false; value = $null; at = $null }
        reload = [pscustomobject]@{ at = $null; file = $null; ok = $false; fresh = $false; ageSeconds = $null }
        console = [pscustomobject]@{ path = $null; exists = $false; offset = 0; bytesRead = 0; truncated = $false }
        errors = [pscustomobject]@{ relevant = @(); other = @() }
    }
}

if ($Json) {
    $status | ConvertTo-Json -Depth 7
} else {
    $gameState = if ($null -eq $status.game.running) { 'unknown' } elseif ($status.game.running) { 'running' } else { 'not running' }
    Write-Output "Game:    $gameState"
    $watcherLine = "Watcher: $($status.watcher.state)"
    if ($status.watcher.pid) { $watcherLine += " (PID $($status.watcher.pid))" }
    if ($status.watcher.reason) { $watcherLine += " - $($status.watcher.reason)" }
    Write-Output $watcherLine
    Write-Output ("Bridge:  " + $(if ($status.bridge.ok) { "ok - $($status.bridge.value)" } else { "unavailable - $($status.bridge.value)" }))
    if ($status.reload.at) {
        Write-Output "Reload:  $($status.reload.file), age $($status.reload.ageSeconds)s, fresh=$($status.reload.fresh)"
    } else {
        Write-Output 'Reload:  none recorded'
    }
    if ($status.console.readError) {
        Write-Output "Console: unavailable - $($status.console.readError)"
    } else {
        Write-Output "Console: $($status.console.bytesRead) new bytes, truncated=$($status.console.truncated)"
    }
    Write-Output "Errors:  $(@($status.errors.relevant).Count) relevant, $(@($status.errors.other).Count) other"
    foreach ($line in @($status.errors.relevant | Select-Object -First 20)) { Write-Output "  RELEVANT $line" }
    foreach ($line in @($status.errors.other | Select-Object -First 5)) { Write-Output "  OTHER $line" }
    if (@($status.errors.relevant).Count -gt 20) { Write-Output "  ... relevant errors truncated; use -Json for all" }
    if (@($status.errors.other).Count -gt 5) { Write-Output "  ... other errors truncated; use -Json for all" }
}

if (-not $status.ok) { exit 1 }
