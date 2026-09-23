$libraryPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\AnalyzerBaseline.ps1'
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $libraryPath -PathType Leaf)) {
    throw 'AnalyzerBaseline.ps1 is missing.'
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
if (-not (Get-Command Invoke-Test -ErrorAction SilentlyContinue)) {
    function Invoke-Test {
        param([string]$Name, [scriptblock]$Body)
        & $Body
        Write-Host "PASS $Name"
    }
}

Invoke-Test 'parses stable analyzer identity without line and column numbers' {
    $repositoryRoot = 'C:\repo'
    $output = @(
        'warning: Undefined field `foo` [undefined-field]',
        '  --> C:/repo/mods/example/42/media/lua/client/example.lua:12:8',
        '',
        'warning: Undefined field `foo` [undefined-field]',
        '  --> C:/repo/mods/example/42/media/lua/client/example.lua:88:2'
    )
    $diagnostics = @(ConvertFrom-EmmyLuaDiagnostics -Output $output -RepositoryRoot $repositoryRoot)
    Assert-Equal $diagnostics.Count 2
    Assert-Equal $diagnostics[0].file 'mods/example/42/media/lua/client/example.lua'
    Assert-Equal $diagnostics[0].code 'undefined-field'
    Assert-Equal $diagnostics[0].message 'Undefined field `foo`'
    Assert-Equal $diagnostics[0].severity 'warning'
}

Invoke-Test 'allows removed diagnostics but reports unlisted identities and excess duplicates' {
    $baseline = [pscustomobject]@{
        schema = 1
        diagnostics = @(
            [pscustomobject]@{
                file = 'mods/example/42/media/lua/client/example.lua'
                code = 'undefined-field'
                message = 'Undefined field `foo`'
                count = 1
                explanation = 'Known game-provided field missing from offline analyzer types.'
            }
        )
    }
    Assert-Equal @(Compare-AnalyzerDiagnostics -Baseline $baseline -Actual @()).Count 0 'Removed warnings must not fail the gate.'

    $known = [pscustomobject]@{ file = 'mods/example/42/media/lua/client/example.lua'; code = 'undefined-field'; message = 'Undefined field `foo`'; severity = 'warning' }
    $new = [pscustomobject]@{ file = 'mods/example/42/media/lua/client/example.lua'; code = 'need-check-nil'; message = 'Value may be nil'; severity = 'warning' }
    Assert-Equal @(Compare-AnalyzerDiagnostics -Baseline $baseline -Actual @($known)).Count 0
    Assert-Equal @(Compare-AnalyzerDiagnostics -Baseline $baseline -Actual @($known, $known)).Count 1 'An additional duplicate must be treated as new.'
    Assert-Equal @(Compare-AnalyzerDiagnostics -Baseline $baseline -Actual @($known, $new)).Count 1 'A new identity must fail the gate.'
}

Invoke-Test 'compares analyzer identity with ordinal case sensitivity' {
    $baseline = [pscustomobject]@{
        schema = 1
        diagnostics = @(
            [pscustomobject]@{
                file = 'mods/example/foo.lua'
                code = 'undefined-field'
                message = 'Undefined field `foo`'
                count = 1
                explanation = 'Known fixture diagnostic.'
            }
        )
    }
    $differentFileCase = [pscustomobject]@{ file = 'mods/example/Foo.lua'; code = 'undefined-field'; message = 'Undefined field `foo`'; severity = 'warning' }
    $differentCodeCase = [pscustomobject]@{ file = 'mods/example/foo.lua'; code = 'Undefined-Field'; message = 'Undefined field `foo`'; severity = 'warning' }
    $differentMessageCase = [pscustomobject]@{ file = 'mods/example/foo.lua'; code = 'undefined-field'; message = 'Undefined field `Foo`'; severity = 'warning' }

    Assert-Equal @(Compare-AnalyzerDiagnostics -Baseline $baseline -Actual @($differentFileCase)).Count 1 'File identity must be ordinal case-sensitive.'
    Assert-Equal @(Compare-AnalyzerDiagnostics -Baseline $baseline -Actual @($differentCodeCase)).Count 1 'Diagnostic code identity must be ordinal case-sensitive.'
    Assert-Equal @(Compare-AnalyzerDiagnostics -Baseline $baseline -Actual @($differentMessageCase)).Count 1 'Diagnostic message identity must be ordinal case-sensitive.'
}

Invoke-Test 'rejects baseline entries without a concrete explanation' {
    $baseline = [pscustomobject]@{
        schema = 1
        diagnostics = @(
            [pscustomobject]@{
                file = 'mods/example/file.lua'
                code = 'unused'
                message = 'Unused local'
                count = 1
                explanation = ''
            }
        )
    }
    $failed = $false
    try { Compare-AnalyzerDiagnostics -Baseline $baseline -Actual @() | Out-Null } catch { $failed = $true }
    Assert-True $failed 'Baseline accepted an entry without an explanation.'
}

Invoke-Test 'accepts integer schema and counts after JSON roundtrip' {
    $baseline = @{
        schema = 1
        diagnostics = @(
            @{
                file = 'mods/example/file.lua'
                code = 'unused'
                message = 'Unused local'
                count = 1
                explanation = 'Known fixture diagnostic.'
            }
        )
    } | ConvertTo-Json -Depth 4 | ConvertFrom-Json
    Assert-Equal @(Compare-AnalyzerDiagnostics -Baseline $baseline -Actual @()).Count 0
}

Invoke-Test 'captures successful native stderr without leaking PowerShell error policy' {
    $originalPreference = $ErrorActionPreference
    $result = Invoke-AnalyzerProcess -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile',
        '-Command',
        "[Console]::Error.WriteLine('Check finished'); exit 0"
    )
    Assert-Equal $result.exitCode 0
    Assert-True (@($result.output | Where-Object { "$_" -eq 'Check finished' }).Count -eq 1) 'Analyzer stderr was not captured.'
    Assert-Equal $ErrorActionPreference $originalPreference 'Analyzer process changed the caller error policy.'
}
