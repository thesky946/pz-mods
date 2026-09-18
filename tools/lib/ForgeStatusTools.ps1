function Test-ForgeProcess {
    param([scriptblock]$Lookup, $WatcherPid, [string]$Kind)
    return [bool](& $Lookup $WatcherPid $Kind)
}

function Get-ForgeErrorLines {
    param([string]$Text)
    if (-not $Text) { return @() }
    return @($Text -split "`r?`n" | Where-Object { $_ -match '(?i)(\berror\b|exception|stack traceback)' })
}

function Test-ForgeRelevantLine {
    param([string]$Line, [string[]]$Tokens)
    foreach ($token in $Tokens) {
        if ($token -and $Line.IndexOf($token, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
        if ($token) {
            $alternate = $token.Replace('\', '/')
            if ($Line.Replace('\', '/').IndexOf($alternate, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
        }
    }
    return $false
}

function Get-ForgeGameStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$ModInfo,
        [Parameter(Mandatory)][string]$ForgeConfigPath,
        [string]$ConsolePath,
        [scriptblock]$ProcessLookup = {
            param($WatcherPid, $Kind)
            if ($Kind -eq 'game') { return @(Get-Process -Name 'ProjectZomboid64' -ErrorAction SilentlyContinue).Count -gt 0 }
            if (-not $WatcherPid) { return $false }
            $process = Get-Process -Id $WatcherPid -ErrorAction SilentlyContinue
            return $null -ne $process -and $process.ProcessName -eq 'node'
        }
    )

    $config = Get-Content -LiteralPath $ForgeConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $entries = @($config.mods | Where-Object { $_.id -eq $ModInfo.Id })
    if ($entries.Count -ne 1) { throw "Expected one Forge config entry for '$($ModInfo.Id)', found $($entries.Count)." }
    $entry = $entries[0]
    $bridgeDir = [IO.Path]::GetFullPath([string]$entry.bridgeDir)
    $statusPath = Join-Path $bridgeDir 'status.json'
    $lockPath = Join-Path $bridgeDir 'watcher.lock'

    $gameRunning = Test-ForgeProcess -Lookup $ProcessLookup -WatcherPid $null -Kind 'game'
    $statusDocument = $null
    $statusError = $null
    if (-not (Test-Path -LiteralPath $statusPath -PathType Leaf)) {
        $statusError = 'missing-status'
    } else {
        try {
            $statusDocument = Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($statusDocument.schema -ne 1) { $statusError = 'invalid-status'; $statusDocument = $null }
        } catch {
            $statusError = 'invalid-status'
            $statusDocument = $null
        }
    }

    $lock = $null
    if (Test-Path -LiteralPath $lockPath -PathType Leaf) {
        try { $lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $lock = $null }
    }
    $watcherPid = if ($statusDocument) { $statusDocument.watcher.pid } elseif ($lock) { $lock.pid } else { $null }
    $watcherRunning = Test-ForgeProcess -Lookup $ProcessLookup -WatcherPid $watcherPid -Kind 'watcher'
    $reportedState = if ($statusDocument) { [string]$statusDocument.state } else { $statusError }
    $lockMatches = $null -ne $lock -and $null -ne $watcherPid -and [int64]$lock.pid -eq [int64]$watcherPid
    $activeStates = @('starting', 'ready', 'reloading', 'blocked', 'restart-required')
    $watcherState = $reportedState
    if ($statusDocument -and $activeStates -contains $reportedState -and (-not $watcherRunning -or -not $lockMatches)) {
        $watcherState = 'stale'
    } elseif (-not $statusDocument -and $statusError -eq 'missing-status' -and $lock -and -not $watcherRunning) {
        $watcherState = 'stale'
    }

    $bridge = if ($statusDocument -and $statusDocument.bridge) {
        [pscustomobject]@{ ok = [bool]$statusDocument.bridge.ok; value = $statusDocument.bridge.value; at = $statusDocument.bridge.at }
    } else {
        [pscustomobject]@{ ok = $false; value = $null; at = $null }
    }

    $reloadAt = if ($statusDocument -and $statusDocument.reload) { $statusDocument.reload.at } else { $null }
    $batchAt = if ($statusDocument -and $statusDocument.batch) { $statusDocument.batch.at } else { $null }
    $reloadFresh = $false
    if ($reloadAt) {
        $reloadFresh = -not $batchAt -or ([DateTimeOffset]::Parse([string]$reloadAt) -ge [DateTimeOffset]::Parse([string]$batchAt))
    }
    $reloadAge = if ($reloadAt) {
        [Math]::Max(0, [Math]::Round(([DateTimeOffset]::UtcNow - [DateTimeOffset]::Parse([string]$reloadAt)).TotalSeconds))
    } else { $null }
    $reload = [pscustomobject]@{
        at = $reloadAt
        file = if ($statusDocument -and $statusDocument.reload) { $statusDocument.reload.file } else { $null }
        ok = if ($statusDocument -and $statusDocument.reload) { [bool]$statusDocument.reload.ok } else { $false }
        value = if ($statusDocument -and $statusDocument.reload) { $statusDocument.reload.value } else { $null }
        fresh = $reloadFresh
        ageSeconds = $reloadAge
    }

    if (-not $ConsolePath -and $statusDocument -and $statusDocument.console.path) { $ConsolePath = [string]$statusDocument.console.path }
    if (-not $ConsolePath) { $ConsolePath = Join-Path (Split-Path -Parent (Split-Path -Parent $bridgeDir)) 'console.txt' }
    $ConsolePath = [IO.Path]::GetFullPath($ConsolePath)
    $capturedOffset = if ($statusDocument -and $null -ne $statusDocument.console.offset) { [int64]$statusDocument.console.offset } else { 0 }
    $consoleExists = Test-Path -LiteralPath $ConsolePath -PathType Leaf
    $consoleTruncated = $false
    $bytesRead = 0
    $newText = ''
    if ($consoleExists) {
        $bytes = [IO.File]::ReadAllBytes($ConsolePath)
        $start = $capturedOffset
        if ($bytes.Length -lt $start) { $start = 0; $consoleTruncated = $true }
        $bytesRead = $bytes.Length - $start
        if ($bytesRead -gt 0) { $newText = [Text.Encoding]::UTF8.GetString($bytes, [int]$start, [int]$bytesRead) }
    }

    $tokens = @([string]$ModInfo.Id, [string]$ModInfo.Root, [string]$entry.src) + @($entry.targets | ForEach-Object { [string]$_ })
    $relevant = [Collections.Generic.List[string]]::new()
    $other = [Collections.Generic.List[string]]::new()
    foreach ($line in @(Get-ForgeErrorLines -Text $newText)) {
        if (Test-ForgeRelevantLine -Line $line -Tokens $tokens) { $relevant.Add($line) } else { $other.Add($line) }
    }

    $watcher = [pscustomobject]@{
        state = $watcherState
        reportedState = $reportedState
        pid = $watcherPid
        running = $watcherRunning
        lockPresent = $null -ne $lock
        lockMatches = $lockMatches
        startedAt = if ($statusDocument) { $statusDocument.watcher.startedAt } else { $null }
        updatedAt = if ($statusDocument) { $statusDocument.updatedAt } else { $null }
        reason = if ($statusDocument) { $statusDocument.reason } elseif ($watcherState -eq 'stale') { 'missing status and stale watcher lock' } else { $statusError }
    }
    $healthyWatcher = @('ready', 'reloading') -contains $watcherState
    $ok = $gameRunning -and $healthyWatcher -and $bridge.ok -and $relevant.Count -eq 0
    return [pscustomobject]@{
        ok = $ok
        game = [pscustomobject]@{ running = $gameRunning; process = 'ProjectZomboid64' }
        watcher = $watcher
        bridge = $bridge
        reload = $reload
        console = [pscustomobject]@{
            path = $ConsolePath; exists = $consoleExists; offset = $capturedOffset
            bytesRead = $bytesRead; truncated = $consoleTruncated
        }
        errors = [pscustomobject]@{ relevant = $relevant.ToArray(); other = $other.ToArray() }
    }
}
