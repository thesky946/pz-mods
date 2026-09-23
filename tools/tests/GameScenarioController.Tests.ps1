$controllerPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'run-game-scenario.ps1'
if (-not (Test-Path -LiteralPath $controllerPath -PathType Leaf)) {
    throw 'run-game-scenario.ps1 is missing.'
}

if (-not (Get-Command Assert-Equal -ErrorAction SilentlyContinue)) {
    function Assert-Equal {
        param($Actual, $Expected, [string]$Message = 'Values differ')
        if ($Actual -ne $Expected) { throw "$Message. Expected '$Expected', got '$Actual'." }
    }
}
if (-not (Get-Command Assert-True -ErrorAction SilentlyContinue)) {
    function Assert-True {
        param([bool]$Condition, [string]$Message = 'Expected condition to be true')
        if (-not $Condition) { throw $Message }
    }
}
if (-not (Get-Command Invoke-Test -ErrorAction SilentlyContinue)) {
    function Invoke-Test {
        param([string]$Name, [scriptblock]$Body)
        & $Body
        Write-Host "PASS $Name"
    }
}

function New-GameScenarioFixture {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('pz-scenario-test-' + [guid]::NewGuid())
    $zomboid = Join-Path $root 'Zomboid'
    $forge = Join-Path $zomboid 'Lua\forgelive'
    New-Item -ItemType Directory -Path $forge -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $forge 'cmd.txt'), 'forge command', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $forge 'result.txt'), 'forge result', [Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{
        Root = $root
        Zomboid = $zomboid
        Request = Join-Path $zomboid 'Lua\pzmodtests\request.txt'
        Result = Join-Path $zomboid 'Lua\pzmodtests\result.txt'
        Forge = $forge
    }
}

function Invoke-ScenarioController {
    param([Parameter(Mandatory)]$Fixture, [int]$TimeoutSeconds = 0, [int]$CompletionTimeoutSeconds = 1)
    $json = & $controllerPath -Scenario 'cook.transfer.container.success' -TimeoutSeconds $TimeoutSeconds -CompletionTimeoutSeconds $CompletionTimeoutSeconds -ZomboidRoot $Fixture.Zomboid -Json
    return $json | ConvertFrom-Json
}

function Write-StartedGameScenarioState {
    param([Parameter(Mandatory)]$Fixture, [Parameter(Mandatory)][string]$RunId)
    $state = Join-Path $Fixture.Zomboid 'Lua\pzmodtests\state'
    New-Item -ItemType Directory -Path $state -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $state ($RunId + '.claimed.txt')), "claimed:$RunId`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $state ($RunId + '.granted.txt')), "granted:$RunId`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $state ($RunId + '.started.txt')), "started:$RunId`n", [Text.UTF8Encoding]::new($false))
}

function Read-GameScenarioText {
    param([Parameter(Mandatory)][string]$Path, [ValidateRange(1, 100)][int]$Attempts = 20)
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
            return $text
        } catch {
            $isSharingViolation = $_.Exception -is [IO.IOException] -or $_.Exception.InnerException -is [IO.IOException]
            if (-not $isSharingViolation -or $attempt -eq $Attempts) { throw }
            Start-Sleep -Milliseconds 10
        }
    }
}

Invoke-Test 'atomically writes a request and returns a matching mailbox result' {
    $f = New-GameScenarioFixture
    $responder = Start-Job -ArgumentList $f.Request, $f.Result -ScriptBlock {
        param($RequestPath, $ResultPath)
        for ($attempt = 1; $attempt -le 100; $attempt++) {
            if (Test-Path -LiteralPath $RequestPath) {
                $request = [IO.File]::ReadAllText($RequestPath, [Text.Encoding]::UTF8)
                $runId = ($request -split "`t", 2)[0]
                $state = Join-Path (Split-Path -Parent $RequestPath) 'state'
                New-Item -ItemType Directory -Path $state -Force | Out-Null
                foreach ($entry in @(@('claimed', "claimed:$runId`n"), @('granted', "granted:$runId`n"), @('started', "started:$runId`n"))) {
                    $markerPath = Join-Path $state ($runId + '.' + $entry[0] + '.txt')
                    [IO.File]::WriteAllText($markerPath, $entry[1], [Text.UTF8Encoding]::new($false))
                }
                $response = @{ schema = 1; runId = $runId; scenario = 'cook.transfer.container.success'; status = 'pass'; gameBuild = '42.20.4'; observed = @{}; failures = @(); cleanup = @{ status = 'pass'; failures = @() } } |
                    ConvertTo-Json -Compress -Depth 5
                [IO.File]::WriteAllText($ResultPath, $response, [Text.UTF8Encoding]::new($false))
                return
            }
            Start-Sleep -Milliseconds 10
        }
        throw 'Controller did not write a request.'
    }
    try {
        $result = Invoke-ScenarioController -Fixture $f -TimeoutSeconds 3
        Receive-Job -Job $responder -Wait -AutoRemoveJob | Out-Null
        Assert-Equal $result.status 'pass'
        Assert-Equal $result.scenario 'cook.transfer.container.success'
        $request = [IO.File]::ReadAllText($f.Request, [Text.Encoding]::UTF8)
        Assert-True ($request -match '^[A-Za-z0-9_-]+\tcook\.transfer\.container\.success\n$') 'Request must be complete and newline-terminated.'
        $state = Join-Path (Split-Path -Parent $f.Request) 'state'
        $runId = ($request -split "`t", 2)[0]
        foreach ($marker in @('claimed', 'granted', 'started')) {
            $markerPath = Join-Path $state ($runId + '.' + $marker + '.txt')
            Assert-Equal ([IO.Path]::GetExtension($markerPath)) '.txt' 'Every game state marker must use an installed PZ file extension.'
            Assert-True (Test-Path -LiteralPath $markerPath -PathType Leaf) "Game state marker path must be readable: $markerPath"
        }
        Assert-Equal @((Get-ChildItem -LiteralPath (Split-Path -Parent $f.Request) -Filter '*.tmp' -File)).Count 0 'Atomic write must not leave a temporary request.'
    } finally {
        if ($responder.State -ne 'Removed') { Remove-Job -Job $responder -Force -ErrorAction SilentlyContinue }
        Remove-Item -LiteralPath $f.Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-Test 'rejects a stale result and reports timeout as not-run' {
    $f = New-GameScenarioFixture
    try {
        $stale = '{"schema":1,"runId":"stale-run","scenario":"cook.transfer.container.success","status":"pass","gameBuild":null,"observed":{},"failures":[],"cleanup":{"status":"pass","failures":[]}}'
        $mailbox = Split-Path -Parent $f.Result
        New-Item -ItemType Directory -Path $mailbox -Force | Out-Null
        [IO.File]::WriteAllText($f.Result, $stale, [Text.UTF8Encoding]::new($false))
        $result = Invoke-ScenarioController -Fixture $f
        Assert-Equal $result.status 'not-run'
        Assert-Equal ([IO.File]::ReadAllText($f.Result, [Text.Encoding]::UTF8)) $stale 'Controller must not overwrite stale results.'
    } finally {
        Remove-Item -LiteralPath $f.Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-Test 'revokes only its own timed-out request and records cancellation' {
    $f = New-GameScenarioFixture
    $replacement = "other-run`tCook.transfer.container.success`n"
    $replacer = Start-Job -ArgumentList $f.Request, $replacement -ScriptBlock {
        param($RequestPath, $Replacement)
        for ($attempt = 1; $attempt -le 100; $attempt++) {
            if (Test-Path -LiteralPath $RequestPath) {
                [IO.File]::WriteAllText($RequestPath, $Replacement, [Text.UTF8Encoding]::new($false))
                return
            }
            Start-Sleep -Milliseconds 10
        }
        throw 'Controller did not write a request.'
    }
    try {
        $result = Invoke-ScenarioController -Fixture $f -TimeoutSeconds 1
        Receive-Job -Job $replacer -Wait -AutoRemoveJob | Out-Null
        Assert-Equal $result.status 'not-run'
        Assert-Equal ([IO.File]::ReadAllText($f.Request, [Text.Encoding]::UTF8)) $replacement 'Timeout must not revoke a later request.'
        $cancellation = Join-Path $f.Zomboid ('Lua\pzmodtests\state\' + $result.runId + '.cancelled.txt')
        Assert-Equal ([IO.Path]::GetExtension($cancellation)) '.txt' 'Cancellation marker must use an installed PZ file extension.'
        Assert-True (Test-Path -LiteralPath $cancellation -PathType Leaf) 'Timeout must persist cancellation for a late client.'
    } finally {
        if ($replacer.State -ne 'Removed') { Remove-Job -Job $replacer -Force -ErrorAction SilentlyContinue }
        Remove-Item -LiteralPath $f.Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-Test 'cancels an unclaimed timed-out request without granting execution' {
    $f = New-GameScenarioFixture
    try {
        $result = Invoke-ScenarioController -Fixture $f
        Assert-Equal $result.status 'not-run'
        $grant = Join-Path $f.Zomboid ('Lua\pzmodtests\state\' + $result.runId + '.granted.txt')
        $cancel = Join-Path $f.Zomboid ('Lua\pzmodtests\state\' + $result.runId + '.cancelled.txt')
        Assert-Equal ([IO.Path]::GetExtension($grant)) '.txt' 'Grant marker must use an installed PZ file extension.'
        Assert-Equal ([IO.Path]::GetExtension($cancel)) '.txt' 'Cancellation marker must use an installed PZ file extension.'
        Assert-True (Test-Path -LiteralPath $cancel) 'Timeout must persist cancellation.'
        Assert-True (-not (Test-Path -LiteralPath $grant)) 'Timeout without claim must never grant execution.'
    } finally {
        Remove-Item -LiteralPath $f.Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-Test 'waits for terminal result when the client claim wins the timeout race' {
    $f = New-GameScenarioFixture
    $claimant = Start-Job -ArgumentList $f.Request, $f.Result, $f.Zomboid -ScriptBlock {
        param($RequestPath, $ResultPath, $Zomboid)
        while (-not (Test-Path -LiteralPath $RequestPath)) { Start-Sleep -Milliseconds 10 }
        $runId = ([IO.File]::ReadAllText($RequestPath, [Text.Encoding]::UTF8) -split "`t", 2)[0]
        $state = Join-Path $Zomboid ('Lua\pzmodtests\state')
        New-Item -ItemType Directory -Path $state -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $state ($runId + '.claimed.txt')), ("claimed:$runId`n"), [Text.UTF8Encoding]::new($false))
        $grant = Join-Path $state ($runId + '.granted.txt')
        while (-not (Test-Path -LiteralPath $grant)) { Start-Sleep -Milliseconds 10 }
        [IO.File]::WriteAllText((Join-Path $state ($runId + '.started.txt')), ("started:$runId`n"), [Text.UTF8Encoding]::new($false))
        @{ schema = 1; runId = $runId; scenario = 'cook.transfer.container.success'; status = 'pass'; gameBuild = $null; observed = @{}; failures = @(); cleanup = @{ status = 'pass'; failures = @() } } | ConvertTo-Json -Compress -Depth 5 | Set-Content -LiteralPath $ResultPath -NoNewline -Encoding UTF8
    }
    try {
        $result = Invoke-ScenarioController -Fixture $f -TimeoutSeconds 1 -CompletionTimeoutSeconds 2
        Receive-Job -Job $claimant -Wait -AutoRemoveJob | Out-Null
        Assert-Equal $result.status 'pass' 'Claimed work must not be reported as not-run.'
    } finally { if ($claimant.State -ne 'Removed') { Remove-Job $claimant -Force -ErrorAction SilentlyContinue }; Remove-Item $f.Root -Recurse -Force -ErrorAction SilentlyContinue }
}

Invoke-Test 'grants a claimed request during the main wait phase' {
    $f = New-GameScenarioFixture
    $claimant = Start-Job -ArgumentList $f.Request, $f.Result, $f.Zomboid -ScriptBlock {
        param($RequestPath, $ResultPath, $Zomboid)
        while (-not (Test-Path -LiteralPath $RequestPath)) { Start-Sleep -Milliseconds 10 }
        $runId = ([IO.File]::ReadAllText($RequestPath, [Text.Encoding]::UTF8) -split "`t", 2)[0]
        $state = Join-Path $Zomboid 'Lua\pzmodtests\state'
        New-Item -ItemType Directory -Path $state -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $state ($runId + '.claimed.txt')), "claimed:$runId`n", [Text.UTF8Encoding]::new($false))
        $grant = Join-Path $state ($runId + '.granted.txt')
        $until = [DateTime]::UtcNow.AddSeconds(2)
        while (-not (Test-Path -LiteralPath $grant)) {
            if ([DateTime]::UtcNow -ge $until) { throw 'Controller did not promptly grant the claimed request.' }
            Start-Sleep -Milliseconds 10
        }
        [IO.File]::WriteAllText((Join-Path $state ($runId + '.started.txt')), "started:$runId`n", [Text.UTF8Encoding]::new($false))
        @{ schema = 1; runId = $runId; scenario = 'cook.transfer.container.success'; status = 'pass'; gameBuild = $null; observed = @{}; failures = @(); cleanup = @{ status = 'pass'; failures = @() } } | ConvertTo-Json -Compress -Depth 5 | Set-Content -LiteralPath $ResultPath -NoNewline -Encoding UTF8
    }
    try {
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $result = Invoke-ScenarioController -Fixture $f -TimeoutSeconds 3 -CompletionTimeoutSeconds 1
        $watch.Stop()
        Receive-Job -Job $claimant -Wait -AutoRemoveJob | Out-Null
        Assert-Equal $result.status 'pass'
        Assert-True ($watch.ElapsedMilliseconds -lt 1500) 'Claim must be granted before the ordinary timeout expires.'
    } finally { if ($claimant.State -ne 'Removed') { Remove-Job $claimant -Force -ErrorAction SilentlyContinue }; Remove-Item $f.Root -Recurse -Force -ErrorAction SilentlyContinue }
}

Invoke-Test 'returns indeterminate after grant when the client never produces a terminal result' {
    $f = New-GameScenarioFixture
    $claimant = Start-Job -ArgumentList $f.Request, $f.Zomboid -ScriptBlock {
        param($RequestPath, $Zomboid)
        while (-not (Test-Path -LiteralPath $RequestPath)) { Start-Sleep -Milliseconds 10 }
        $runId = ([IO.File]::ReadAllText($RequestPath, [Text.Encoding]::UTF8) -split "`t", 2)[0]
        $state = Join-Path $Zomboid 'Lua\pzmodtests\state'
        New-Item -ItemType Directory -Path $state -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $state ($runId + '.claimed.txt')), "claimed:$runId`n", [Text.UTF8Encoding]::new($false))
    }
    try {
        $result = Invoke-ScenarioController -Fixture $f -TimeoutSeconds 2 -CompletionTimeoutSeconds 0
        Receive-Job -Job $claimant -Wait -AutoRemoveJob | Out-Null
        Assert-Equal $result.status 'indeterminate' 'Granted work without a terminal result must never be not-run.'
        $cancel = Join-Path $f.Zomboid ('Lua\pzmodtests\state\' + $result.runId + '.cancelled.txt')
        Assert-True (-not (Test-Path -LiteralPath $cancel)) 'Completion timeout after grant must not race a future started marker with cancellation.'
    } finally { if ($claimant.State -ne 'Removed') { Remove-Job $claimant -Force -ErrorAction SilentlyContinue }; Remove-Item $f.Root -Recurse -Force -ErrorAction SilentlyContinue }
}

Invoke-Test 'rejects terminal results without an exact started marker' {
    foreach ($case in @(
        @{ Name = 'missing'; Started = $null },
        @{ Name = 'partial'; Started = 'started:partial' },
        @{ Name = 'case-mismatched'; Started = 'case-mismatched' }
    )) {
        $f = New-GameScenarioFixture
        $responder = Start-Job -ArgumentList $f.Request, $f.Result, $f.Zomboid, $case.Name, $case.Started -ScriptBlock {
            param($RequestPath, $ResultPath, $Zomboid, $Kind, $Started)
            while (-not (Test-Path -LiteralPath $RequestPath)) { Start-Sleep -Milliseconds 10 }
            $runId = ([IO.File]::ReadAllText($RequestPath, [Text.Encoding]::UTF8) -split "`t", 2)[0]
            $state = Join-Path $Zomboid 'Lua\pzmodtests\state'
            New-Item -ItemType Directory -Path $state -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $state ($runId + '.granted.txt')), "granted:$runId`n", [Text.UTF8Encoding]::new($false))
            if ($null -ne $Started) {
                if ($Kind -eq 'case-mismatched') { $Started = "started:$($runId.ToUpperInvariant())`n" }
                [IO.File]::WriteAllText((Join-Path $state ($runId + '.started.txt')), $Started, [Text.UTF8Encoding]::new($false))
            }
            @{ schema = 1; runId = $runId; scenario = 'cook.transfer.container.success'; status = 'pass'; gameBuild = $null; observed = @{}; failures = @(); cleanup = @{ status = 'pass'; failures = @() } } | ConvertTo-Json -Compress -Depth 5 | Set-Content -LiteralPath $ResultPath -NoNewline -Encoding UTF8
            [IO.File]::WriteAllText((Join-Path $state ($runId + '.claimed.txt')), "claimed:$runId`n", [Text.UTF8Encoding]::new($false))
        }
        try {
            $result = Invoke-ScenarioController -Fixture $f -TimeoutSeconds 1 -CompletionTimeoutSeconds 1
            Receive-Job -Job $responder -Wait -AutoRemoveJob | Out-Null
            Assert-Equal $result.status 'indeterminate' "Controller accepted a terminal result with $($case.Name) started marker."
            Assert-Equal $result.observed.reason 'claimed-completion-timeout' 'Controller must enter completion phase and reject the invalid terminal result.'
        } finally {
            if ($responder.State -ne 'Removed') { Remove-Job -Job $responder -Force -ErrorAction SilentlyContinue }
            Remove-Item -LiteralPath $f.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Invoke-Test 'serializes concurrent PowerShell controllers for the singleton request mailbox' {
    $f = New-GameScenarioFixture
    $invoke = {
        param($ControllerPath, $Zomboid)
        & $ControllerPath -Scenario 'cook.transfer.container.success' -TimeoutSeconds 2 -CompletionTimeoutSeconds 1 -ZomboidRoot $Zomboid -Json
    }
    $first = Start-Job -ScriptBlock $invoke -ArgumentList $controllerPath, $f.Zomboid
    $second = $null
    try {
        $until = [DateTime]::UtcNow.AddSeconds(2)
        while (-not (Test-Path -LiteralPath $f.Request)) {
            if ([DateTime]::UtcNow -ge $until) { throw 'First controller did not write its request.' }
            Start-Sleep -Milliseconds 10
        }
        $firstRequest = Read-GameScenarioText -Path $f.Request
        $second = Start-Job -ScriptBlock $invoke -ArgumentList $controllerPath, $f.Zomboid
        Start-Sleep -Milliseconds 250
        Assert-Equal (Read-GameScenarioText -Path $f.Request) $firstRequest 'Second controller must not replace the in-flight request.'
        $firstRunId = ($firstRequest -split "`t", 2)[0]
        Write-StartedGameScenarioState -Fixture $f -RunId $firstRunId
        @{ schema = 1; runId = $firstRunId; scenario = 'cook.transfer.container.success'; status = 'pass'; gameBuild = $null; observed = @{}; failures = @(); cleanup = @{ status = 'pass'; failures = @() } } | ConvertTo-Json -Compress -Depth 5 | Set-Content -LiteralPath $f.Result -NoNewline -Encoding UTF8
        Assert-Equal ((Receive-Job -Job $first -Wait -AutoRemoveJob | ConvertFrom-Json).status) 'pass'
        $first = $null
        $until = [DateTime]::UtcNow.AddSeconds(2)
        do {
            $secondRequest = Read-GameScenarioText -Path $f.Request
            if ($secondRequest -ne $firstRequest) { break }
            if ([DateTime]::UtcNow -ge $until) { throw 'Second controller did not start after the first completed.' }
            Start-Sleep -Milliseconds 10
        } while ($true)
        $secondRunId = ($secondRequest -split "`t", 2)[0]
        Write-StartedGameScenarioState -Fixture $f -RunId $secondRunId
        @{ schema = 1; runId = $secondRunId; scenario = 'cook.transfer.container.success'; status = 'pass'; gameBuild = $null; observed = @{}; failures = @(); cleanup = @{ status = 'pass'; failures = @() } } | ConvertTo-Json -Compress -Depth 5 | Set-Content -LiteralPath $f.Result -NoNewline -Encoding UTF8
        Assert-Equal ((Receive-Job -Job $second -Wait -AutoRemoveJob | ConvertFrom-Json).status) 'pass'
        $second = $null
    } finally {
        if ($first) { Remove-Job -Job $first -Force -ErrorAction SilentlyContinue }
        if ($second) { Remove-Job -Job $second -Force -ErrorAction SilentlyContinue }
        Remove-Item -LiteralPath $f.Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-Test 'requires exact result IDs, scenario casing, and gameBuild presence' {
    foreach ($case in @(
        @{ Name = 'missing gameBuild'; Kind = 'missing-game-build' },
        @{ Name = 'run ID casing'; Kind = 'run-id-casing' },
        @{ Name = 'scenario casing'; Kind = 'scenario-casing' }
    )) {
        $f = New-GameScenarioFixture
        $responder = Start-Job -ArgumentList $f.Request, $f.Result, $case.Kind -ScriptBlock {
            param($RequestPath, $ResultPath, $Kind)
            for ($attempt = 1; $attempt -le 100; $attempt++) {
                if (Test-Path -LiteralPath $RequestPath) {
                    $request = [IO.File]::ReadAllText($RequestPath, [Text.Encoding]::UTF8)
                    $runId = ($request -split "`t", 2)[0]
                    $response = @{ schema = 1; runId = $runId; scenario = 'cook.transfer.container.success'; status = 'pass'; gameBuild = $null; observed = @{}; failures = @(); cleanup = @{ status = 'pass'; failures = @() } }
                    if ($Kind -eq 'missing-game-build') { $response.Remove('gameBuild') }
                    if ($Kind -eq 'run-id-casing') { $response.runId = $runId.ToUpperInvariant() }
                    if ($Kind -eq 'scenario-casing') { $response.scenario = 'Cook.Transfer.Container.Success' }
                    $response = $response | ConvertTo-Json -Compress -Depth 5
                    [IO.File]::WriteAllText($ResultPath, $response, [Text.UTF8Encoding]::new($false))
                    return
                }
                Start-Sleep -Milliseconds 10
            }
            throw 'Controller did not write a request.'
        }
        try {
            $result = Invoke-ScenarioController -Fixture $f -TimeoutSeconds 1
            Receive-Job -Job $responder -Wait -AutoRemoveJob | Out-Null
            Assert-Equal $result.status 'not-run' "Controller accepted $($case.Name)"
        } finally {
            if ($responder.State -ne 'Removed') { Remove-Job -Job $responder -Force -ErrorAction SilentlyContinue }
            Remove-Item -LiteralPath $f.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Invoke-Test 'returns not-run when the game mailbox is unavailable' {
    $missingRoot = Join-Path ([IO.Path]::GetTempPath()) ('pz-scenario-missing-' + [guid]::NewGuid())
    try {
        $json = & $controllerPath -Scenario 'cook.transfer.container.success' -TimeoutSeconds 0 -ZomboidRoot $missingRoot -Json
        $result = $json | ConvertFrom-Json
        Assert-Equal $result.status 'not-run'
        Assert-True (-not (Test-Path -LiteralPath $missingRoot)) 'Unavailable root must not be created.'
    } finally {
        Remove-Item -LiteralPath $missingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-Test 'returns not-run when an existing Zomboid root cannot host the mailbox' {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('pz-scenario-blocked-' + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $root 'Lua'), 'not a directory', [Text.UTF8Encoding]::new($false))
    $stdout = Join-Path $root 'stdout.txt'
    $stderr = Join-Path $root 'stderr.txt'
    try {
        $process = Start-Process -FilePath (Get-Command powershell.exe -ErrorAction Stop).Source `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $controllerPath, '-Scenario', 'cook.transfer.container.success', '-TimeoutSeconds', '0', '-ZomboidRoot', $root, '-Json') `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr -Wait -PassThru
        Assert-Equal $process.ExitCode 0 'Unavailable mailbox must not be a controller error.'
        Assert-Equal ([IO.File]::ReadAllText($stderr, [Text.Encoding]::UTF8)) '' 'Unavailable mailbox must not write stderr.'
        $result = ([IO.File]::ReadAllText($stdout, [Text.Encoding]::UTF8)) | ConvertFrom-Json
        Assert-Equal $result.status 'not-run'
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $root 'Lua'), [Text.Encoding]::UTF8)) 'not a directory'
    } finally {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-Test 'never modifies Forge Live command files' {
    $f = New-GameScenarioFixture
    try {
        $tracked = @('cmd.txt', 'result.txt') | ForEach-Object {
            $path = Join-Path $f.Forge $_
            [pscustomobject]@{ Path = $path; Hash = (Get-FileHash -LiteralPath $path).Hash }
        }
        $result = Invoke-ScenarioController -Fixture $f
        Assert-Equal $result.status 'not-run'
        foreach ($file in $tracked) {
            Assert-Equal (Get-FileHash -LiteralPath $file.Path).Hash $file.Hash 'Controller changed a Forge Live mailbox file'
        }
    } finally {
        Remove-Item -LiteralPath $f.Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}
