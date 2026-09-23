[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-z][a-z0-9_.-]+$')][string]$Scenario,
    [ValidateRange(0, 3600)][int]$TimeoutSeconds = 180,
    [ValidateRange(0, 3600)][int]$CompletionTimeoutSeconds = 30,
    [string]$ZomboidRoot = (Join-Path $env:USERPROFILE 'Zomboid'),
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$allowedScenarios = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
@('cook.transfer.container.success', 'cook.recipe.replacement.success', 'cook.stove.ownership.success', 'cook.stove.preexisting.success') |
    ForEach-Object { [void]$allowedScenarios.Add($_) }
$allowedStatuses = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
@('pass', 'fail', 'not-run', 'not-applicable', 'indeterminate') | ForEach-Object { [void]$allowedStatuses.Add($_) }

function New-GameScenarioResult {
    param(
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$ScenarioId,
        [Parameter(Mandatory)][ValidateSet('pass', 'fail', 'not-run', 'not-applicable', 'indeterminate')][string]$Status,
        [hashtable]$Observed = @{},
        [string[]]$Failures = @(),
        [hashtable]$Cleanup = @{ status = 'not-applicable'; failures = @() },
        [AllowNull()][string]$GameBuild = $null
    )

    return [ordered]@{
        schema = 1
        runId = $RunId
        scenario = $ScenarioId
        status = $Status
        gameBuild = $GameBuild
        observed = $Observed
        failures = @($Failures)
        cleanup = $Cleanup
    }
}

function Write-AtomicGameScenarioRequest {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Text)

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $temporary = Join-Path $parent ('.' + [IO.Path]::GetFileName($Path) + '.' + [guid]::NewGuid() + '.tmp')
    $backup = Join-Path $parent ('.' + [IO.Path]::GetFileName($Path) + '.' + [guid]::NewGuid() + '.bak')
    try {
        [IO.File]::WriteAllText($temporary, $Text, [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            [IO.File]::Replace($temporary, $Path, $backup)
        } else {
            [IO.File]::Move($temporary, $Path)
        }
    } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
    }
}

function Test-ExactGameScenarioProperty {
    param([Parameter(Mandatory)]$Object, [Parameter(Mandatory)][string]$Name)
    return @($Object.PSObject.Properties | Where-Object { [string]::Equals($_.Name, $Name, [StringComparison]::Ordinal) }).Count -eq 1
}

function Test-ExactGameScenarioMarker {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Expected)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    try {
        return [string]::Equals([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8), $Expected, [StringComparison]::Ordinal)
    } catch {
        return $false
    }
}

function ConvertTo-MatchingGameScenarioResult {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$ScenarioId,
        [Parameter(Mandatory)][string]$ClaimPath,
        [Parameter(Mandatory)][string]$GrantPath,
        [Parameter(Mandatory)][string]$StartedPath
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        $raw = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
        if ($raw -match "[\r\n]") { return $null }
        $result = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return $null
    }

    if ($result.schema -ne 1 -or -not [string]::Equals([string]$result.runId, $RunId, [StringComparison]::Ordinal) -or -not [string]::Equals([string]$result.scenario, $ScenarioId, [StringComparison]::Ordinal)) { return $null }
    if (-not $allowedStatuses.Contains([string]$result.status)) { return $null }
    if (-not (Test-ExactGameScenarioMarker $ClaimPath "claimed:$RunId`n") -or -not (Test-ExactGameScenarioMarker $GrantPath "granted:$RunId`n") -or -not (Test-ExactGameScenarioMarker $StartedPath "started:$RunId`n")) { return $null }
    if (-not (Test-ExactGameScenarioProperty $result 'gameBuild') -or -not (Test-ExactGameScenarioProperty $result 'observed') -or -not (Test-ExactGameScenarioProperty $result 'failures') -or -not (Test-ExactGameScenarioProperty $result 'cleanup')) { return $null }
    if ($null -eq $result.cleanup -or -not (Test-ExactGameScenarioProperty $result.cleanup 'status') -or -not $allowedStatuses.Contains([string]$result.cleanup.status)) { return $null }
    return $result
}

function Write-GameScenarioOutput {
    param([Parameter(Mandatory)]$Result, [switch]$AsJson)
    if ($AsJson) {
        $Result | ConvertTo-Json -Compress -Depth 10
    } else {
        $Result
    }
}

$controllerMutex = [Threading.Mutex]::new($false, 'Local\PzModsTestHarness.GameScenarioController')
$controllerMutexHeld = $false
try {
    $controllerMutexHeld = $controllerMutex.WaitOne()
    if (-not $controllerMutexHeld) { throw 'Another game scenario controller is active.' }

    if (-not $allowedScenarios.Contains($Scenario)) {
        throw "Scenario '$Scenario' is not allowlisted."
    }

    $runId = [guid]::NewGuid().ToString('N')
    if (-not (Test-Path -LiteralPath $ZomboidRoot -PathType Container)) {
        Write-GameScenarioOutput -Result (New-GameScenarioResult -RunId $runId -ScenarioId $Scenario -Status 'not-run' -Observed @{ reason = 'zomboid-root-unavailable' }) -AsJson:$Json
        exit 0
    }

    $mailbox = Join-Path $ZomboidRoot 'Lua\pzmodtests'
    $requestPath = Join-Path $mailbox 'request.txt'
    $resultPath = Join-Path $mailbox 'result.txt'
    $state = Join-Path $mailbox 'state'
    $claimPath = Join-Path $state ($runId + '.claimed.txt')
    $grantPath = Join-Path $state ($runId + '.granted.txt')
    $cancelPath = Join-Path $state ($runId + '.cancelled.txt')
    $startedPath = Join-Path $state ($runId + '.started.txt')
    try {
        Write-AtomicGameScenarioRequest -Path $requestPath -Text "$runId`t$Scenario`n"
    } catch {
        Write-GameScenarioOutput -Result (New-GameScenarioResult -RunId $runId -ScenarioId $Scenario -Status 'not-run' -Observed @{ reason = 'mailbox-unavailable' }) -AsJson:$Json
        exit 0
    }

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $completionDeadline = $null
    do {
        $claim = if (Test-Path -LiteralPath $claimPath -PathType Leaf) { [IO.File]::ReadAllText($claimPath, [Text.Encoding]::UTF8) } else { $null }
        if ($null -eq $completionDeadline -and [string]::Equals($claim, "claimed:$runId`n", [StringComparison]::Ordinal)) {
            try {
                if (-not (Test-Path -LiteralPath $grantPath -PathType Leaf)) { Write-AtomicGameScenarioRequest -Path $grantPath -Text "granted:$runId`n" }
                $completionDeadline = [DateTime]::UtcNow.AddSeconds($CompletionTimeoutSeconds)
            } catch {
                Write-GameScenarioOutput -Result (New-GameScenarioResult -RunId $runId -ScenarioId $Scenario -Status 'indeterminate' -Observed @{ reason = 'grant-error' } -Failures @($_.Exception.Message)) -AsJson:$Json
                exit 0
            }
        }
        if ($null -ne $completionDeadline) {
            $result = ConvertTo-MatchingGameScenarioResult -Path $resultPath -RunId $runId -ScenarioId $Scenario -ClaimPath $claimPath -GrantPath $grantPath -StartedPath $startedPath
            if ($result) { Write-GameScenarioOutput -Result $result -AsJson:$Json; exit 0 }
        }
        if (($null -eq $completionDeadline -and [DateTime]::UtcNow -ge $deadline) -or ($null -ne $completionDeadline -and [DateTime]::UtcNow -ge $completionDeadline)) { break }
        Start-Sleep -Milliseconds 100
    } while ($true)

    if ($null -ne $completionDeadline) {
        Write-GameScenarioOutput -Result (New-GameScenarioResult -RunId $runId -ScenarioId $Scenario -Status 'indeterminate' -Observed @{ reason = 'claimed-completion-timeout' }) -AsJson:$Json
        exit 0
    }
    try { Write-AtomicGameScenarioRequest -Path $cancelPath -Text "cancelled:$runId`n" } catch {
        Write-GameScenarioOutput -Result (New-GameScenarioResult -RunId $runId -ScenarioId $Scenario -Status 'indeterminate' -Observed @{ reason = 'cancel-error' } -Failures @($_.Exception.Message)) -AsJson:$Json
        exit 0
    }
    Write-GameScenarioOutput -Result (New-GameScenarioResult -RunId $runId -ScenarioId $Scenario -Status 'not-run' -Observed @{ reason = 'timeout-without-claim' }) -AsJson:$Json
} finally {
    if ($controllerMutexHeld) { $controllerMutex.ReleaseMutex() }
    $controllerMutex.Dispose()
}
