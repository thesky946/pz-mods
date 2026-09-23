$ErrorActionPreference = 'Stop'

if (-not (Get-Command Assert-Equal -ErrorAction SilentlyContinue)) {
    function Assert-Equal {
        param($Actual, $Expected, [string]$Message = 'Values differ')
        if ($Actual -ne $Expected) { throw "$Message. Expected '$Expected', got '$Actual'." }
    }
}
if (-not (Get-Command Invoke-Test -ErrorAction SilentlyContinue)) {
    function Invoke-Test {
        param([string]$Name, [scriptblock]$Body)
        & $Body
        Write-Host "PASS $Name"
    }
}

Invoke-Test 'aggregate runner exits zero after a passing test asserts an expected native failure' {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('pz-runner-test-' + [guid]::NewGuid())
    try {
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'run.ps1') -Destination (Join-Path $root 'run.ps1')
        foreach ($requiredTest in @(
            'AnalyzerBaseline.Tests.ps1',
            'NewModReliability.Tests.ps1',
            'PzContractSnapshot.Tests.ps1',
            'RunnerExitCode.Tests.ps1',
            'ValidationEvidence.Tests.ps1',
            'WorkshopHarnessExclusion.Tests.ps1'
        )) {
            Set-Content -LiteralPath (Join-Path $root $requiredTest) -Value ''
        }
        Set-Content -LiteralPath (Join-Path $root 'ZzzExpectedNativeFailure.Tests.ps1') -Value @'
Invoke-Test 'fixture accepts an expected native nonzero status' {
    & cmd.exe /d /c exit 7
    Assert-Equal $LASTEXITCODE 7 'Fixture did not produce the expected native status.'
}
'@
        & (Join-Path $root 'run.ps1') | Out-Null
        Assert-Equal $LASTEXITCODE 0 'Aggregate runner leaked a stale native exit code.'
    } finally {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}
