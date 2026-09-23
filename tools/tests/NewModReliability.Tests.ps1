$ErrorActionPreference = 'Stop'

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

Invoke-Test 'new mod scaffold canonicalizes every support profile and declares validation surfaces' {
    $cases = @(
        @{ Input = 'SP'; Canonical = 'SP'; GameSp = $true; GameMp = $false },
        @{ Input = 'sp'; Canonical = 'SP'; GameSp = $true; GameMp = $false },
        @{ Input = 'MP'; Canonical = 'MP'; GameSp = $false; GameMp = $true },
        @{ Input = 'mp'; Canonical = 'MP'; GameSp = $false; GameMp = $true },
        @{ Input = 'both'; Canonical = 'both'; GameSp = $true; GameMp = $true },
        @{ Input = 'BoTh'; Canonical = 'both'; GameSp = $true; GameMp = $true },
        @{ Input = 'content-only'; Canonical = 'content-only'; GameSp = $false; GameMp = $false },
        @{ Input = 'CONTENT-ONLY'; Canonical = 'content-only'; GameSp = $false; GameMp = $false }
    )
    foreach ($case in $cases) {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('pz-new-mod-test-' + [guid]::NewGuid())
        try {
            $tools = Join-Path $root 'tools'
            New-Item -ItemType Directory -Path $tools -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'new-mod.ps1') -Destination $tools

            $scriptPath = Join-Path $tools 'new-mod.ps1'
            & $scriptPath -Slug 'fixture-mod' -Id 'FixtureMod' -Name 'Fixture Mod' -Support $case.Input | Out-Null

            $modRoot = Join-Path $root 'mods\fixture-mod'
            $manifestPath = Join-Path $modRoot 'tests\scenarios.lua'
            $regressionPath = Join-Path $modRoot 'tests\REGRESSION.md'
            $readmePath = Join-Path $modRoot 'README.md'

            Assert-True (Test-Path -LiteralPath $manifestPath -PathType Leaf) 'Smoke scenario manifest was not generated.'
            Assert-True (Test-Path -LiteralPath $regressionPath -PathType Leaf) 'REGRESSION.md was not generated.'

            $lua = Get-Command lua -ErrorAction Stop
            $expectedGameSp = if ($case.GameSp) { 'true' } else { 'nil' }
            $expectedGameMp = if ($case.GameMp) { 'true' } else { 'nil' }
            $luaCode = "local r=dofile([[$($manifestPath.Replace('\', '/'))]]); assert(r.schema == 1); assert(r.support == '$($case.Canonical)'); assert(#r.scenarios == 1); local s=r.scenarios[1]; assert(s.id == 'fixture-mod.smoke'); assert(s.modes.offline == true); assert(s.modes.gameSp == $expectedGameSp); assert(s.modes.gameMp == $expectedGameMp); assert(type(s.invariants) == 'table' and #s.invariants > 0)"
            & $lua.Source -e $luaCode
            Assert-Equal $LASTEXITCODE 0 "Generated smoke scenario manifest is invalid for '$($case.Input)'."

            $regression = Get-Content -LiteralPath $regressionPath -Raw -Encoding UTF8
            Assert-True ($regression -match '(?m)^## fixture-mod\.smoke\r?$') 'REGRESSION.md does not document the generated smoke scenario ID.'

            $readme = Get-Content -LiteralPath $readmePath -Raw -Encoding UTF8
            Assert-True ($readme -match ('(?m)^Support: ' + [regex]::Escape($case.Canonical) + '\r?$')) "README did not canonicalize support '$($case.Input)'."
            foreach ($section in @('Offline validation', 'In-game validation', 'Manual validation')) {
                Assert-True ($readme -match ('(?m)^## ' + [regex]::Escape($section) + '\r?$')) "README is missing '$section'."
            }
        } finally {
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Invoke-Test 'new mod scaffold requires an explicit support profile' {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('pz-new-mod-test-' + [guid]::NewGuid())
    try {
        $tools = Join-Path $root 'tools'
        New-Item -ItemType Directory -Path $tools -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'new-mod.ps1') -Destination $tools
        $scriptPath = Join-Path $tools 'new-mod.ps1'

        $failed = $false
        try { & $scriptPath -Slug 'fixture-mod' -Id 'FixtureMod' -Name 'Fixture Mod' | Out-Null } catch { $failed = $true }
        Assert-True $failed 'Scaffold accepted a mod without an explicit support profile.'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $root 'mods\fixture-mod'))) 'Failed scaffold left a partial mod directory.'
    } finally {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}
