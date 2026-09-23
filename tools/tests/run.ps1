[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$script:TestFailures = 0
$script:TestPasses = 0

function Assert-Equal {
    param($Actual, $Expected, [string]$Message = 'Values differ')
    if ($Actual -ne $Expected) {
        throw "$Message. Expected '$Expected', got '$Actual'."
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Message = 'Expected condition to be true')
    if (-not $Condition) { throw $Message }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Like)
    try {
        & $Action
    } catch {
        if ($_.Exception.Message -like $Like) { return }
        throw "Expected error like '$Like', got '$($_.Exception.Message)'."
    }
    throw "Expected error like '$Like', but no error was thrown."
}

function Invoke-Test {
    param([string]$Name, [scriptblock]$Body)
    try {
        & $Body
        $script:TestPasses++
        Write-Host "PASS $Name"
    } catch {
        $script:TestFailures++
        Write-Host "FAIL $Name`: $($_.Exception.Message)" -ForegroundColor Red
    }
}

$testFiles = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.Tests.ps1' -File | Sort-Object Name)
foreach ($requiredTest in @(
    'AnalyzerBaseline.Tests.ps1',
    'NewModReliability.Tests.ps1',
    'PzContractSnapshot.Tests.ps1',
    'RunnerExitCode.Tests.ps1',
    'ValidationEvidence.Tests.ps1',
    'WorkshopHarnessExclusion.Tests.ps1'
)) {
    if (@($testFiles | Where-Object Name -eq $requiredTest).Count -ne 1) {
        throw "$requiredTest must be included in the aggregate tool test suite."
    }
}

$testFiles |
    ForEach-Object {
        try { . $_.FullName }
        catch {
            $script:TestFailures++
            Write-Host "FAIL $($_.Name) setup: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

Write-Host "$script:TestPasses passed, $script:TestFailures failed."
if ($script:TestFailures -gt 0) { exit 1 }
exit 0

