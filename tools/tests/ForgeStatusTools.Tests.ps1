$libraryPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\ForgeStatusTools.ps1'
if (-not (Test-Path -LiteralPath $libraryPath -PathType Leaf)) {
    throw 'ForgeStatusTools.ps1 is missing.'
}
. $libraryPath

function New-ForgeStatusFixture {
    param([string]$State = 'ready', [int]$PidValue = 123)

    $root = Join-Path ([IO.Path]::GetTempPath()) ('forge-status-test-' + [guid]::NewGuid())
    $bridge = Join-Path $root 'Zomboid\Lua\forgelive'
    $source = Join-Path $root 'repo\mods\cook-it-for-me\42'
    $target = Join-Path $root 'Zomboid\Workshop\CookItForMe\Contents\mods\CookItForMe\42'
    New-Item -ItemType Directory -Path $bridge, $source, $target -Force | Out-Null
    $console = Join-Path $root 'Zomboid\console.txt'
    [IO.File]::WriteAllText($console, "old log`n", [Text.UTF8Encoding]::new($false))
    $config = Join-Path $root 'forge-live.config.json'
    @{ mods = @(@{ id = 'CookItForMe'; src = $source; targets = @($target); bridgeDir = $bridge }) } |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $config -Encoding UTF8
    $status = @{
        schema = 1
        state = $State
        updatedAt = '2026-09-19T10:00:03Z'
        watcher = @{ pid = $PidValue; mods = @('CookItForMe'); startedAt = '2026-09-19T10:00:00Z' }
        bridge = @{ ok = $true; value = 'pong v0.2.0'; at = '2026-09-19T10:00:01Z' }
        batch = @{ at = '2026-09-19T10:00:02Z'; files = @('media/lua/client/CookItForMe.lua'); result = 'ok' }
        reload = @{ at = '2026-09-19T10:00:03Z'; file = 'media/lua/client/CookItForMe.lua'; ok = $true; value = 'ack' }
        console = @{ path = $console; offset = [Text.Encoding]::UTF8.GetByteCount("old log`n") }
    }
    $status | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $bridge 'status.json') -Encoding UTF8
    @{ pid = $PidValue; token = 'fixture' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $bridge 'watcher.lock') -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $bridge 'cmd.txt') -Value 'unchanged command'
    Set-Content -LiteralPath (Join-Path $bridge 'result.txt') -Value 'unchanged result'
    return [pscustomobject]@{
        Root = $root; Bridge = $bridge; Source = $source; Target = $target
        Console = $console; Config = $config
        Mod = [pscustomobject]@{ Id = 'CookItForMe'; Root = (Split-Path -Parent $source); Name = 'cook-it-for-me' }
    }
}

Invoke-Test 'parses ISO Forge timestamps under ru-RU and preserves their UTC instant' {
    $f = New-ForgeStatusFixture
    $previousCulture = [Globalization.CultureInfo]::CurrentCulture
    try {
        [Globalization.CultureInfo]::CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('ru-RU')
        $beforeRead = [DateTimeOffset]::UtcNow
        $expectedAge = [Math]::Round(($beforeRead - [DateTimeOffset]::Parse(
            '2026-09-19T10:00:03Z',
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind
        )).TotalSeconds)
        $status = Get-ForgeGameStatus -ModInfo $f.Mod -ForgeConfigPath $f.Config -ConsolePath $f.Console -ProcessLookup {
            param($WatcherPid, $Kind)
            if ($Kind -eq 'game') { return $true }
            return $WatcherPid -eq 123
        }
        Assert-True ([Math]::Abs($status.reload.ageSeconds - $expectedAge) -lt 5) 'Reload age must preserve the UTC instant from ISO JSON under ru-RU.'
    } finally {
        [Globalization.CultureInfo]::CurrentCulture = $previousCulture
        Remove-Item -LiteralPath $f.Root -Recurse -Force
    }
}

Invoke-Test 'reports ready watcher and never mutates bridge files' {
    $f = New-ForgeStatusFixture
    try {
        $tracked = @('cmd.txt', 'result.txt', 'status.json') | ForEach-Object {
            $path = Join-Path $f.Bridge $_
            @{ Path = $path; Hash = (Get-FileHash -LiteralPath $path).Hash }
        }
        $status = Get-ForgeGameStatus -ModInfo $f.Mod -ForgeConfigPath $f.Config -ConsolePath $f.Console -ProcessLookup {
            param($WatcherPid, $Kind)
            if ($Kind -eq 'game') { return $true }
            return $WatcherPid -eq 123
        }
        Assert-Equal $status.watcher.state 'ready'
        Assert-True $status.watcher.running
        Assert-True $status.game.running
        Assert-True $status.reload.fresh
        Assert-True $status.ok
        foreach ($file in $tracked) { Assert-Equal (Get-FileHash -LiteralPath $file.Path).Hash $file.Hash 'Status check changed a bridge file' }
    } finally { Remove-Item -LiteralPath $f.Root -Recurse -Force }
}

Invoke-Test 'keeps game process status when the console log is locked' {
    $f = New-ForgeStatusFixture
    $lock = $null
    try {
        $lock = [IO.File]::Open($f.Console, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $status = Get-ForgeGameStatus -ModInfo $f.Mod -ForgeConfigPath $f.Config -ConsolePath $f.Console -ProcessLookup {
            param($WatcherPid, $Kind)
            if ($Kind -eq 'game') { return $true }
            return $WatcherPid -eq 123
        }
        Assert-True $status.game.running 'A console read failure must not claim the game process is stopped.'
        Assert-True (-not [string]::IsNullOrWhiteSpace($status.console.readError)) 'The unreadable console must be reported.'
        Assert-True (-not $status.ok) 'Status cannot be healthy when the console could not be checked.'
    } finally {
        if ($null -ne $lock) { $lock.Dispose() }
        Remove-Item -LiteralPath $f.Root -Recurse -Force
    }
}

Invoke-Test 'reports blocked, restart-required, stale, missing, and invalid status' {
    foreach ($case in @(
        @{ Stored = 'blocked'; Expected = 'blocked'; Running = $true },
        @{ Stored = 'restart-required'; Expected = 'restart-required'; Running = $true },
        @{ Stored = 'ready'; Expected = 'stale'; Running = $false }
    )) {
        $f = New-ForgeStatusFixture -State $case.Stored
        try {
            $result = Get-ForgeGameStatus -ModInfo $f.Mod -ForgeConfigPath $f.Config -ConsolePath $f.Console -ProcessLookup {
                param($WatcherPid, $Kind)
                if ($Kind -eq 'game') { return $true }
                return $case.Running
            }
            Assert-Equal $result.watcher.state $case.Expected
            Assert-True (-not $result.ok)
        } finally { Remove-Item -LiteralPath $f.Root -Recurse -Force }
    }

    $f = New-ForgeStatusFixture
    try {
        Remove-Item -LiteralPath (Join-Path $f.Bridge 'status.json')
        $missing = Get-ForgeGameStatus -ModInfo $f.Mod -ForgeConfigPath $f.Config -ConsolePath $f.Console -ProcessLookup { $true }
        Assert-Equal $missing.watcher.state 'missing-status'
        $staleLock = Get-ForgeGameStatus -ModInfo $f.Mod -ForgeConfigPath $f.Config -ConsolePath $f.Console -ProcessLookup {
            param($WatcherPid, $Kind)
            return $Kind -eq 'game'
        }
        Assert-Equal $staleLock.watcher.state 'stale'
        Set-Content -LiteralPath (Join-Path $f.Bridge 'status.json') -Value '{"schema":2}'
        $invalid = Get-ForgeGameStatus -ModInfo $f.Mod -ForgeConfigPath $f.Config -ConsolePath $f.Console -ProcessLookup { $true }
        Assert-Equal $invalid.watcher.state 'invalid-status'
    } finally { Remove-Item -LiteralPath $f.Root -Recurse -Force }
}

Invoke-Test 'detects stale ACK, truncated console, and relevant errors' {
    $f = New-ForgeStatusFixture
    try {
        $statusPath = Join-Path $f.Bridge 'status.json'
        $document = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
        $document.batch.at = '2026-09-19T10:00:04Z'
        $document.console.offset = 9999
        $document | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statusPath -Encoding UTF8
        [IO.File]::WriteAllText($f.Console, "ERROR CookItForMe failed`nERROR OtherMod failed`n", [Text.UTF8Encoding]::new($false))

        $result = Get-ForgeGameStatus -ModInfo $f.Mod -ForgeConfigPath $f.Config -ConsolePath $f.Console -ProcessLookup { $true }
        Assert-True (-not $result.reload.fresh)
        Assert-True $result.console.truncated
        Assert-Equal @($result.errors.relevant).Count 1
        Assert-Equal @($result.errors.other).Count 1
        Assert-True (-not $result.ok)
    } finally { Remove-Item -LiteralPath $f.Root -Recurse -Force }
}
