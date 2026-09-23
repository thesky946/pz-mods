$ErrorActionPreference = 'Stop'

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

Invoke-Test 'Workshop builds exclude harness mailbox controller and evidence artifacts for every mod' {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $root = Join-Path ([IO.Path]::GetTempPath()) ('pz-workshop-test-' + [guid]::NewGuid())
    try {
        $fixtureTools = Join-Path $root 'tools'
        $fixtureMods = Join-Path $root 'mods'
        New-Item -ItemType Directory -Path $fixtureTools, $fixtureMods -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $repositoryRoot 'tools\build_workshop.ps1') -Destination $fixtureTools
        Copy-Item -LiteralPath (Join-Path $repositoryRoot 'tools\lib.ps1') -Destination $fixtureTools

        foreach ($sourceMod in Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'mods') -Directory) {
            $fixtureMod = Join-Path $fixtureMods $sourceMod.Name
            Copy-Item -LiteralPath $sourceMod.FullName -Destination $fixtureMod -Recurse

            $forbiddenFiles = @(
                (Join-Path $fixtureMod '42\media\lua\client\PzModsTestHarness.lua'),
                (Join-Path $fixtureMod 'common\pzmodtests\request.txt'),
                (Join-Path $fixtureMod '42\run-game-scenario.ps1'),
                (Join-Path $fixtureMod 'common\validation\scenario-evidence.jsonl')
            )
            foreach ($path in $forbiddenFiles) {
                New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
                Set-Content -LiteralPath $path -Value 'must not ship' -NoNewline
            }

            $destination = Join-Path $root ('build-' + $sourceMod.Name)
            & (Join-Path $fixtureTools 'build_workshop.ps1') -Mod $sourceMod.Name -DestinationRoot $destination -SkipChecks | Out-Null
            $payloadRoot = Join-Path $destination ((Get-Content -LiteralPath (Join-Path $fixtureMod '42\mod.info') | Where-Object { $_ -match '^id=' } | Select-Object -First 1).Substring(3).Trim())
            $relativePaths = @(Get-ChildItem -LiteralPath $payloadRoot -Recurse -Force | ForEach-Object {
                $_.FullName.Substring($payloadRoot.Length).TrimStart('\', '/') -replace '\\', '/'
            })
            $forbidden = @($relativePaths | Where-Object {
                $_ -match '(?i)PzModsTestHarness|pzmodtests|run-game-scenario|scenario[-_.]?evidence'
            })
            Assert-True ($forbidden.Count -eq 0) "Workshop payload for $($sourceMod.Name) contains dev-only artifacts: $($forbidden -join ', ')"
        }
    } finally {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}
