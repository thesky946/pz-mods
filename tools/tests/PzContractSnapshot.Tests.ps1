$libraryPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\PzContractSnapshot.ps1'
$apiLibraryPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\PzApiTools.ps1'
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $libraryPath -PathType Leaf)) {
    throw 'PzContractSnapshot.ps1 is missing.'
}
. $apiLibraryPath
. $libraryPath

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
if (-not (Get-Command Assert-Throws -ErrorAction SilentlyContinue)) {
    function Assert-Throws {
        param([scriptblock]$Action, [string]$Like = '*')
        try { & $Action } catch {
            if ($_.Exception.Message -like $Like) { return }
            throw "Expected error like '$Like', got '$($_.Exception.Message)'."
        }
        throw "Expected error like '$Like', but no error was thrown."
    }
}
if (-not (Get-Command Invoke-Test -ErrorAction SilentlyContinue)) {
    function Invoke-Test {
        param([string]$Name, [scriptblock]$Body)
        & $Body
        Write-Host "PASS $Name"
    }
}

Invoke-Test 'loads the Project Zomboid path helper with the snapshot module' {
    & powershell -NoProfile -Command "& { . '$libraryPath'; if (-not (Get-Command Test-PzGamePath -ErrorAction SilentlyContinue)) { exit 1 } }"
    Assert-Equal $LASTEXITCODE 0 'Snapshot module did not load PzApiTools.'
}

function New-PzContractFixture {
    param([Parameter(Mandatory)][string]$Root)

    $game = Join-Path $Root 'steamapps\common\ProjectZomboid'
    New-Item -ItemType Directory -Path $game -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $game 'projectzomboid.jar') -Value 'fixture' -NoNewline
    $fixtureDefinitions = [ordered]@{
        'media/lua/shared/TimedActions/ISBaseTimedAction.lua' = @('isValidStart', 'complete', 'perform', 'forceCancel')
        'media/lua/client/TimedActions/ISTimedActionQueue.lua' = @('add', 'onTick', 'resetQueue')
        'media/lua/client/TimedActions/ISInventoryTransferAction.lua' = @('isValid', 'start', 'stop', 'perform', 'setOnComplete')
        'media/lua/client/TimedActions/ISGrabItemAction.lua' = @('isValid', 'complete', 'perform')
        'media/lua/shared/TimedActions/ISAddItemInRecipe.lua' = @('isValidStart', 'complete', 'perform')
    }
    foreach ($definition in $fixtureDefinitions.GetEnumerator()) {
        $path = Join-Path $game $definition.Key.Replace('/', '\')
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
        $class = [IO.Path]::GetFileNameWithoutExtension($path)
        $content = $definition.Value | ForEach-Object { "function $class`:$_() end" }
        Set-Content -LiteralPath $path -Value $content -NoNewline
    }
    Set-Content -LiteralPath (Join-Path $Root 'steamapps\appmanifest_108600.acf') -Value '"buildid" "24909800"' -NoNewline

    $umbrella = Join-Path $Root 'umbrella'
    New-Item -ItemType Directory -Path $umbrella | Out-Null
    & git -C $umbrella init --quiet
    & git -C $umbrella config user.email 'fixture@example.invalid'
    & git -C $umbrella config user.name 'PZ fixture'
    Set-Content -LiteralPath (Join-Path $umbrella 'README.md') -Value 'fixture' -NoNewline
    & git -C $umbrella add README.md
    & git -C $umbrella commit --quiet -m fixture

    return [pscustomobject]@{ Game = $game; Umbrella = $umbrella }
}

function Get-ProjectUmbrellaPath {
    return (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) '.types\umbrella')
}

function Invoke-PzContractCli {
    param([Parameter(Mandatory)][string]$GamePath, [Parameter(Mandatory)][string]$SnapshotPath, [switch]$Update)

    $scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'check-pz-contracts.ps1'
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath, '-GamePath', $GamePath, '-SnapshotPath', $SnapshotPath)
    if ($Update) { $arguments += '-Update' }
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & powershell @arguments 2>$null | Out-Null
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
}

Invoke-Test 'snapshots normalized vanilla paths hashes symbols and Umbrella revision' {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('pz-contract-test-' + [guid]::NewGuid())
    try {
        $fixture = New-PzContractFixture -Root $root
        $snapshot = Get-PzContractSnapshot -GamePath $fixture.Game -UmbrellaPath $fixture.Umbrella
        Assert-Equal $snapshot.schema 1
        Assert-Equal $snapshot.game.steamBuild '24909800'
        Assert-Equal $snapshot.game.version '42.20.4'
        Assert-True ($snapshot.umbrella.revision -match '^[0-9a-f]{40}$') 'Umbrella revision must be a git SHA.'
        Assert-Equal $snapshot.files.Count 5
        foreach ($expectedPath in @(
            'media/lua/shared/TimedActions/ISBaseTimedAction.lua',
            'media/lua/client/TimedActions/ISTimedActionQueue.lua',
            'media/lua/client/TimedActions/ISInventoryTransferAction.lua',
            'media/lua/client/TimedActions/ISGrabItemAction.lua',
            'media/lua/shared/TimedActions/ISAddItemInRecipe.lua'
        )) {
            Assert-True (@($snapshot.files.path) -contains $expectedPath) "Required contract path is missing: $expectedPath"
        }
        foreach ($file in $snapshot.files) {
            Assert-True ($file.path -notmatch '\\') "Snapshot path was not normalized: $($file.path)"
            Assert-True ($file.path -match '^media/lua/') "Snapshot path is not game-relative: $($file.path)"
            Assert-True ($file.sha256 -match '^[0-9A-F]{64}$') "Missing SHA-256 for $($file.path)"
            foreach ($symbol in $file.symbols.psobject.Properties) {
                Assert-True $symbol.Value "Expected symbol $($symbol.Name) was not found in $($file.path)"
            }
        }
    } finally {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-Test 'rejects missing or malformed Steam appmanifest data' {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('pz-contract-test-' + [guid]::NewGuid())
    try {
        $fixture = New-PzContractFixture -Root $root
        $manifest = Join-Path $root 'steamapps\appmanifest_108600.acf'
        Remove-Item -LiteralPath $manifest -Force
        Assert-Throws { Get-PzContractSnapshot -GamePath $fixture.Game -UmbrellaPath $fixture.Umbrella } '*appmanifest*'
        Set-Content -LiteralPath $manifest -Value '"buildid" "not-a-number"' -NoNewline
        Assert-Throws { Get-PzContractSnapshot -GamePath $fixture.Game -UmbrellaPath $fixture.Umbrella } '*appmanifest*'
    } finally {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-Test 'rejects schema and symbol types instead of coercing them' {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('pz-contract-test-' + [guid]::NewGuid())
    try {
        $fixture = New-PzContractFixture -Root $root
        $snapshot = Get-PzContractSnapshot -GamePath $fixture.Game -UmbrellaPath $fixture.Umbrella
        $wrongSchema = $snapshot | ConvertTo-Json -Depth 8 | ConvertFrom-Json
        $wrongSchema.schema = '1'
        Assert-Throws { Compare-PzContractSnapshot -Expected $wrongSchema -Actual $snapshot } '*schema*'
        $wrongSymbol = $snapshot | ConvertTo-Json -Depth 8 | ConvertFrom-Json
        $wrongSymbol.files[0].symbols.isValidStart = 'false'
        Assert-Throws { Compare-PzContractSnapshot -Expected $snapshot -Actual $wrongSymbol } '*symbols*'
    } finally {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-Test 'reports false-to-true and true-to-false symbol drift' {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('pz-contract-test-' + [guid]::NewGuid())
    try {
        $fixture = New-PzContractFixture -Root $root
        $snapshot = Get-PzContractSnapshot -GamePath $fixture.Game -UmbrellaPath $fixture.Umbrella
        $expectedFalse = $snapshot | ConvertTo-Json -Depth 8 | ConvertFrom-Json
        $expectedFalse.files[0].symbols.isValidStart = $false
        Assert-True (@(Compare-PzContractSnapshot -Expected $expectedFalse -Actual $snapshot | Where-Object kind -eq 'symbol').Count -eq 1) 'false-to-true must be drift.'
        $actualFalse = $snapshot | ConvertTo-Json -Depth 8 | ConvertFrom-Json
        $actualFalse.files[0].symbols.isValidStart = $false
        Assert-True (@(Compare-PzContractSnapshot -Expected $snapshot -Actual $actualFalse | Where-Object kind -eq 'symbol').Count -eq 1) 'true-to-false must be drift.'
    } finally {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-Test 'CLI returns match drift and invalid-environment exit codes using fixtures' {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('pz-contract-test-' + [guid]::NewGuid())
    try {
        $fixture = New-PzContractFixture -Root $root
        $snapshotPath = Join-Path $root 'expected.json'
        $snapshot = Get-PzContractSnapshot -GamePath $fixture.Game -UmbrellaPath (Get-ProjectUmbrellaPath)
        $snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $snapshotPath -Encoding utf8
        Assert-Equal (Invoke-PzContractCli -GamePath $fixture.Game -SnapshotPath $snapshotPath) 0 'Known fixture must match.'
        $propertyCaseSnapshotPath = Join-Path $root 'property-case.json'
        ((Get-Content -LiteralPath $snapshotPath -Raw) -replace '"schema"', '"Schema"') | Set-Content -LiteralPath $propertyCaseSnapshotPath -Encoding utf8
        Assert-Equal (Invoke-PzContractCli -GamePath $fixture.Game -SnapshotPath $propertyCaseSnapshotPath) 1 'Schema property casing must be invalid.'
        $gameCaseSnapshotPath = Join-Path $root 'game-case.json'
        ((Get-Content -LiteralPath $snapshotPath -Raw) -replace '"game"', '"Game"') | Set-Content -LiteralPath $gameCaseSnapshotPath -Encoding utf8
        Assert-Equal (Invoke-PzContractCli -GamePath $fixture.Game -SnapshotPath $gameCaseSnapshotPath) 1 'Nested property casing must be invalid.'
        $pathCaseSnapshotPath = Join-Path $root 'path-case.json'
        ((Get-Content -LiteralPath $snapshotPath -Raw) -replace 'media/lua/shared/TimedActions/ISBaseTimedAction.lua', 'Media/lua/shared/TimedActions/ISBaseTimedAction.lua') | Set-Content -LiteralPath $pathCaseSnapshotPath -Encoding utf8
        Assert-Equal (Invoke-PzContractCli -GamePath $fixture.Game -SnapshotPath $pathCaseSnapshotPath) 2 'Contract path casing must be drift.'
        Add-Content -LiteralPath (Join-Path $fixture.Game 'media\lua\shared\TimedActions\ISBaseTimedAction.lua') -Value '-- hotfix'
        Assert-Equal (Invoke-PzContractCli -GamePath $fixture.Game -SnapshotPath $snapshotPath) 2 'Hash-only fixture hotfix must drift.'
        $invalidSnapshotPath = Join-Path $root 'invalid.json'
        $invalidSnapshot = Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json
        $invalidSnapshot.schema = '1'
        $invalidSnapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $invalidSnapshotPath -Encoding utf8
        Assert-Equal (Invoke-PzContractCli -GamePath $fixture.Game -SnapshotPath $invalidSnapshotPath) 1 'Invalid snapshot input must fail.'
        Set-Content -LiteralPath (Join-Path $root 'steamapps\appmanifest_108600.acf') -Value '"buildid" "24909801"' -NoNewline
        $unknownUpdatePath = Join-Path $root 'unknown-build.json'
        Assert-Equal (Invoke-PzContractCli -GamePath $fixture.Game -SnapshotPath $unknownUpdatePath -Update) 1 'Unknown selected Steam build must not update.'
        Assert-True (-not (Test-Path -LiteralPath $unknownUpdatePath)) 'Unknown selected Steam build must not write an update snapshot.'
        Remove-Item -LiteralPath (Join-Path $root 'steamapps\appmanifest_108600.acf') -Force
        $updatePath = Join-Path $root 'must-not-exist.json'
        Assert-Equal (Invoke-PzContractCli -GamePath $fixture.Game -SnapshotPath $updatePath -Update) 1 'Missing appmanifest must be invalid.'
        Assert-True (-not (Test-Path -LiteralPath $updatePath)) 'Invalid environment must not write an update snapshot.'
    } finally {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-Test 'reports drift when a hotfix changes a hash but leaves every symbol present' {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('pz-contract-test-' + [guid]::NewGuid())
    try {
        $fixture = New-PzContractFixture -Root $root
        $expected = Get-PzContractSnapshot -GamePath $fixture.Game -UmbrellaPath $fixture.Umbrella
        Add-Content -LiteralPath (Join-Path $fixture.Game 'media\lua\shared\TimedActions\ISBaseTimedAction.lua') -Value '-- hotfix'
        $actual = Get-PzContractSnapshot -GamePath $fixture.Game -UmbrellaPath $fixture.Umbrella
        $differences = @(Compare-PzContractSnapshot -Expected $expected -Actual $actual)
        Assert-True ($differences.Count -gt 0) 'A changed vanilla hash must be reported as drift.'
        Assert-True (@($differences | Where-Object kind -eq 'sha256').Count -eq 1) 'Expected one hash-drift difference.'
        Assert-True (@($actual.files | Where-Object path -eq 'media/lua/shared/TimedActions/ISBaseTimedAction.lua').symbols.psobject.Properties.Value -notcontains $false) 'Fixture hotfix must preserve symbols.'
    } finally {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-Test 'compares known snapshots without differences' {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('pz-contract-test-' + [guid]::NewGuid())
    try {
        $fixture = New-PzContractFixture -Root $root
        $snapshot = Get-PzContractSnapshot -GamePath $fixture.Game -UmbrellaPath $fixture.Umbrella
        Assert-Equal @(Compare-PzContractSnapshot -Expected $snapshot -Actual $snapshot).Count 0
    } finally {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-Test 'recognizes table fields assigned anonymous functions' {
    $content = @'
ISTimedActionQueue.add = function(action)
    return ISTimedActionQueue:getTimedActionQueue(action.character)
end
'@
    Assert-True (Test-PzContractSymbol -Content $content -Symbol 'add') 'Assigned static functions must count as contract symbols.'
}
