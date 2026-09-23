$libraryPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\ValidationEvidence.ps1'
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $libraryPath -PathType Leaf)) {
    throw 'ValidationEvidence.ps1 is missing.'
}
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

Invoke-Test 'creates stable pass evidence and rejects invalid status' {
    $entry = New-ValidationEvidence -ScenarioId 'cook.transfer.container.success' `
        -Mode offline -Status pass -GameBuild $null -Observed @{ moved = $true }
    Assert-Equal $entry.schema 1
    Assert-Equal $entry.status 'pass'
    Assert-Throws { New-ValidationEvidence -ScenarioId 'x.y' -Mode offline -Status success } '*Status*'
    Assert-Throws { New-ValidationEvidence -ScenarioId 'C:\Users\User\secret' -Mode offline -Status pass } '*ScenarioId*'
}

Invoke-Test 'writes all validation report sections without rooted paths' {
    $entries = @(
        (New-ValidationEvidence -ScenarioId 'cook.transfer.container.success' -Mode offline -Status pass -GameBuild 'C:\Users\User\build-42' -Observed @{
            windows = 'C:\Users\User\Zomboid\console.txt'
            unc = '\\fileserver\share\evidence.log'
            unix = '/home/validation-user/Zomboid/console.txt'
            'C:\Users\User\secret' = 'dictionary key must be redacted'
            'C:\Users\User\second-secret' = 'second dictionary key must be retained'
            nested = [pscustomobject]@{ 'C:\Users\User\custom-property' = 'custom property key must be redacted' }
        })
        (New-ValidationEvidence -ScenarioId 'cook.recipe.replacement.success' -Mode gameSp -Status not-run -GameBuild '\\fileserver\share\build-42')
        (New-ValidationEvidence -ScenarioId 'cook.stove.ownership.success' -Mode gameMp -Status fail)
        (New-ValidationEvidence -ScenarioId 'cook.stove.preexisting.success' -Mode packaged -Status not-applicable)
        ([pscustomobject]@{
            schema = 1
            scenarioId = 'C:\Users\User\untrusted-scenario'
            mode = 'manual'
            status = 'not-run'
            gameBuild = $null
            observed = @{}
        })
    )
    $path = Join-Path ([IO.Path]::GetTempPath()) ('validation-evidence-' + [guid]::NewGuid() + '.md')
    try {
        Write-ValidationReport -Evidence $entries -Path $path
        $report = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        foreach ($section in @('Offline', 'PZ SP', 'PZ MP', 'Packaged', 'Manual', 'Remaining')) {
            Assert-True ($report -match ('(?m)^## ' + [regex]::Escape($section) + '\r?$')) "Missing report section: $section"
        }
        foreach ($rootedPath in @(
            'C:\Users\User',
            'C:\\Users\\User',
            '\\fileserver\share',
            '\\\\fileserver\\share',
            '/home/validation-user'
        )) {
            Assert-True (-not $report.Contains($rootedPath)) "Report exposes rooted path: $rootedPath"
        }
        Assert-True ($report.Contains('dictionary key must be redacted')) 'Sanitized dictionary key lost its value'
        Assert-True ($report.Contains('second dictionary key must be retained')) 'Colliding sanitized dictionary key lost its value'
        Assert-True ($report.Contains('custom property key must be redacted')) 'Sanitized custom property key lost its value'
    } finally {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}
