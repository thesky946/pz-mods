function New-ValidationEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidatePattern('^[a-z][a-z0-9_.-]+$')][string]$ScenarioId,
        [Parameter(Mandatory)][ValidateSet('offline', 'gameSp', 'gameMp', 'packaged', 'manual')][string]$Mode,
        [Parameter(Mandatory)][ValidateSet('pass', 'fail', 'not-run', 'not-applicable')][string]$Status,
        [AllowNull()][string]$GameBuild,
        [hashtable]$Observed = @{}
    )

    return [pscustomobject]@{
        schema = 1
        scenarioId = $ScenarioId
        mode = $Mode
        status = $Status
        gameBuild = $GameBuild
        observed = $Observed
    }
}

function Protect-ValidationPathText {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) { return $null }
    return [regex]::Replace($Text, '(?i)(?:[a-z]:[\\/]|\\\\[^\\/\s"'']+[\\/]|/)(?:[^\\/\s"'']+[\\/])*[^\\/\s"'']+', '[path]')
}

function ConvertTo-ValidationSafeValue {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value -or $Value -isnot [string] -and $Value -isnot [Collections.IDictionary] -and $Value -isnot [Collections.IEnumerable] -and $Value -isnot [System.Management.Automation.PSCustomObject]) {
        return $Value
    }
    if ($Value -is [string]) { return Protect-ValidationPathText $Value }
    if ($Value -is [Collections.IDictionary]) {
        $safe = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $safeKey = Protect-ValidationPathText ([string]$key)
            $uniqueKey = $safeKey
            $suffix = 2
            while ($safe.Contains($uniqueKey)) {
                $uniqueKey = "$safeKey-$suffix"
                $suffix++
            }
            $safe[$uniqueKey] = ConvertTo-ValidationSafeValue $Value[$key]
        }
        return $safe
    }
    if ($Value -is [Collections.IEnumerable]) {
        return @($Value | ForEach-Object { ConvertTo-ValidationSafeValue $_ })
    }

    $safe = [ordered]@{}
    foreach ($property in $Value.PSObject.Properties) {
        $safeName = Protect-ValidationPathText $property.Name
        $uniqueName = $safeName
        $suffix = 2
        while ($safe.Contains($uniqueName)) {
            $uniqueName = "$safeName-$suffix"
            $suffix++
        }
        $safe[$uniqueName] = ConvertTo-ValidationSafeValue $property.Value
    }
    return [pscustomobject]$safe
}

function ConvertTo-ValidationSafeText {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return '' }
    $safeValue = ConvertTo-ValidationSafeValue $Value
    if ($safeValue -is [string]) { return $safeValue }
    return $safeValue | ConvertTo-Json -Depth 10 -Compress
}

function Write-ValidationReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Evidence,
        [Parameter(Mandatory)][string]$Path
    )

    $sections = @(
        [pscustomobject]@{ Title = 'Offline'; Mode = 'offline' },
        [pscustomobject]@{ Title = 'PZ SP'; Mode = 'gameSp' },
        [pscustomobject]@{ Title = 'PZ MP'; Mode = 'gameMp' },
        [pscustomobject]@{ Title = 'Packaged'; Mode = 'packaged' },
        [pscustomobject]@{ Title = 'Manual'; Mode = 'manual' }
    )
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('# Validation evidence')
    $lines.Add('')

    foreach ($section in $sections) {
        $lines.Add("## $($section.Title)")
        $entries = @($Evidence | Where-Object { $_.mode -eq $section.Mode })
        if ($entries.Count -eq 0) {
            $lines.Add('- No evidence recorded.')
        } else {
            foreach ($entry in $entries) {
                $details = ConvertTo-ValidationSafeText $entry.observed
                $suffix = if ($details) { "; observed: $details" } else { '' }
                $build = if ($entry.gameBuild) { "; game build: $(ConvertTo-ValidationSafeText $entry.gameBuild)" } else { '' }
                $scenarioId = ConvertTo-ValidationSafeText ([string]$entry.scenarioId)
                $status = ConvertTo-ValidationSafeText ([string]$entry.status)
                $lines.Add("- ``$scenarioId`` - $status$build$suffix")
            }
        }
        $lines.Add('')
    }

    $lines.Add('## Remaining')
    $remaining = @($Evidence | Where-Object { $_.status -ne 'pass' })
    if ($remaining.Count -eq 0) {
        $lines.Add('- No remaining validation evidence.')
    } else {
        foreach ($entry in $remaining) {
            $scenarioId = ConvertTo-ValidationSafeText ([string]$entry.scenarioId)
            $status = ConvertTo-ValidationSafeText ([string]$entry.status)
            $mode = ConvertTo-ValidationSafeText ([string]$entry.mode)
            $lines.Add("- ``$scenarioId`` - $status ($mode)")
        }
    }
    $lines.Add('')

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [IO.File]::WriteAllLines($Path, $lines, [Text.UTF8Encoding]::new($false))
}
