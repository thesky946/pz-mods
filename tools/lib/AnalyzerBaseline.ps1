function Invoke-AnalyzerProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList
    )

    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $FilePath @ArgumentList 2>&1 | ForEach-Object { "$_" })
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    [pscustomobject]@{ output = $output; exitCode = $exitCode }
}

function ConvertFrom-EmmyLuaDiagnostics {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Output,
        [Parameter(Mandatory)][string]$RepositoryRoot
    )

    $repositoryPrefix = [IO.Path]::GetFullPath($RepositoryRoot).Replace('\', '/').TrimEnd('/') + '/'
    for ($index = 0; $index -lt $Output.Count; $index++) {
        $line = [string]$Output[$index]
        if ($line -notmatch '^(warning|error|hint|info): (.*) \[([^\]]+)\]$') { continue }

        $severity = $Matches[1]
        $message = $Matches[2]
        $code = $Matches[3]
        $file = $null
        for ($pathIndex = $index + 1; $pathIndex -lt [Math]::Min($index + 5, $Output.Count); $pathIndex++) {
            $pathLine = [string]$Output[$pathIndex]
            if ($pathLine -match '^\s*-->\s+(.+):\d+:\d+$') {
                $file = $Matches[1].Replace('\', '/')
                break
            }
        }
        if (-not $file) { throw "Analyzer diagnostic has no source path: $line" }
        if ($file.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            $file = $file.Substring($repositoryPrefix.Length)
        }

        [pscustomobject]@{
            severity = $severity
            file = $file
            code = $code
            message = $message
        }
    }
}

function Compare-AnalyzerDiagnostics {
    param(
        [Parameter(Mandatory)]$Baseline,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Actual
    )

    if (($Baseline.schema -isnot [int] -and $Baseline.schema -isnot [long]) -or $Baseline.schema -ne 1) {
        throw 'Analyzer baseline schema must be integer 1.'
    }

    $allowedCounts = [Collections.Generic.Dictionary[string, int]]::new([StringComparer]::Ordinal)
    foreach ($entry in @($Baseline.diagnostics)) {
        foreach ($property in @('file', 'code', 'message', 'explanation')) {
            if ($entry.$property -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.$property)) {
                throw "Analyzer baseline entry requires non-empty $property."
            }
        }
        if ($entry.count -isnot [int] -and $entry.count -isnot [long]) {
            throw 'Analyzer baseline entry count must be an integer.'
        }
        if ($entry.count -lt 1) { throw 'Analyzer baseline entry count must be positive.' }
        $key = "$($entry.file)`n$($entry.code)`n$($entry.message)"
        if ($allowedCounts.ContainsKey($key)) { throw "Duplicate analyzer baseline identity: $($entry.file) [$($entry.code)]" }
        $allowedCounts[$key] = [int]$entry.count
    }

    $observedCounts = [Collections.Generic.Dictionary[string, int]]::new([StringComparer]::Ordinal)
    foreach ($diagnostic in $Actual) {
        $key = "$($diagnostic.file)`n$($diagnostic.code)`n$($diagnostic.message)"
        if (-not $observedCounts.ContainsKey($key)) { $observedCounts[$key] = 0 }
        $observedCounts[$key]++
        $allowed = if ($allowedCounts.ContainsKey($key)) { $allowedCounts[$key] } else { 0 }
        if ($observedCounts[$key] -gt $allowed) { $diagnostic }
    }
}
