$ErrorActionPreference = 'Stop'

if (-not (Get-Command Test-PzGamePath -ErrorAction SilentlyContinue)) {
    $apiToolsPath = Join-Path $PSScriptRoot 'PzApiTools.ps1'
    if (-not (Test-Path -LiteralPath $apiToolsPath -PathType Leaf)) { throw 'PzApiTools.ps1 is missing.' }
    . $apiToolsPath
}

$script:PzContractDefinition = @(
    [pscustomobject]@{
        path = 'media/lua/shared/TimedActions/ISBaseTimedAction.lua'
        symbols = @('isValidStart', 'complete', 'perform', 'forceCancel')
    },
    [pscustomobject]@{
        path = 'media/lua/client/TimedActions/ISTimedActionQueue.lua'
        symbols = @('add', 'onTick', 'resetQueue')
    },
    [pscustomobject]@{
        path = 'media/lua/client/TimedActions/ISInventoryTransferAction.lua'
        symbols = @('isValid', 'start', 'stop', 'perform', 'setOnComplete')
    },
    [pscustomobject]@{
        path = 'media/lua/client/TimedActions/ISGrabItemAction.lua'
        symbols = @('isValid', 'complete', 'perform')
    },
    [pscustomobject]@{
        path = 'media/lua/shared/TimedActions/ISAddItemInRecipe.lua'
        symbols = @('isValidStart', 'complete', 'perform')
    }
)

function Get-PzContractDefinition {
    return $script:PzContractDefinition
}

function Get-PzObjectValue {
    param([Parameter(Mandatory)]$Object, [Parameter(Mandatory)][string]$Name)

    if ($Object -is [Collections.IDictionary]) { return $Object[$Name] }
    foreach ($property in $Object.PSObject.Properties) {
        if ($property.Name -ceq $Name) { return $property.Value }
    }
    return $null
}

function Get-PzSteamBuild {
    param([Parameter(Mandatory)][string]$GamePath)

    $steamApps = Split-Path -Parent (Split-Path -Parent $GamePath)
    $manifest = Join-Path $steamApps 'appmanifest_108600.acf'
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw 'Steam appmanifest_108600.acf is missing.' }
    $match = [regex]::Match((Get-Content -LiteralPath $manifest -Raw), '"buildid"\s*"(?<build>[^"]+)"')
    if (-not $match.Success -or $match.Groups['build'].Value -notmatch '^\d+$') {
        throw 'Steam appmanifest_108600.acf does not contain a numeric buildid.'
    }
    return $match.Groups['build'].Value
}

function Get-PzGameVersionFromSteamBuild {
    param([Parameter(Mandatory)][string]$SteamBuild)

    $knownVersions = @{ '24909800' = '42.20.4' }
    if ($knownVersions.ContainsKey($SteamBuild)) { return $knownVersions[$SteamBuild] }
    return 'unknown'
}

function Get-PzUmbrellaRevision {
    param([Parameter(Mandatory)][string]$UmbrellaPath)

    $revision = (& git -C $UmbrellaPath rev-parse HEAD 2>$null | Select-Object -First 1)
    if (-not $revision -or $revision -notmatch '^[0-9a-f]{40}$') {
        throw 'Unable to determine the Umbrella revision.'
    }
    return $revision
}

function Test-PzContractSymbol {
    param([Parameter(Mandatory)][string]$Content, [Parameter(Mandatory)][string]$Symbol)

    $escapedSymbol = [regex]::Escape($Symbol)
    $methodPattern = 'function\s+[A-Za-z_][A-Za-z0-9_.]*\s*[:.]\s*' + $escapedSymbol + '\s*\('
    $assignedPattern = '\b[A-Za-z_][A-Za-z0-9_.]*\s*\.\s*' + $escapedSymbol + '\s*=\s*function\s*\('
    return [regex]::IsMatch($Content, $methodPattern) -or [regex]::IsMatch($Content, $assignedPattern)
}

function Get-PzContractSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$GamePath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$UmbrellaPath
    )

    $game = [IO.Path]::GetFullPath($GamePath)
    $umbrella = [IO.Path]::GetFullPath($UmbrellaPath)
    if (-not (Test-PzGamePath -Path $game)) { throw 'Invalid Project Zomboid installation.' }
    if (-not (Test-Path -LiteralPath $umbrella -PathType Container)) { throw 'Umbrella library was not found.' }

    $files = foreach ($definition in Get-PzContractDefinition) {
        $relativePath = $definition.path.Replace('\', '/')
        $filePath = Join-Path $game $relativePath.Replace('/', '\')
        if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
            throw "Required vanilla contract file is missing: $relativePath"
        }
        $content = Get-Content -LiteralPath $filePath -Raw
        $symbols = [ordered]@{}
        foreach ($symbol in $definition.symbols) {
            $symbols[$symbol] = Test-PzContractSymbol -Content $content -Symbol $symbol
        }
        [pscustomobject]@{
            path = $relativePath
            sha256 = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash
            symbols = [pscustomobject]$symbols
        }
    }

    $steamBuild = Get-PzSteamBuild -GamePath $game
    return [pscustomobject]@{
        schema = 1
        game = [pscustomobject]@{
            version = Get-PzGameVersionFromSteamBuild -SteamBuild $steamBuild
            steamBuild = $steamBuild
        }
        umbrella = [pscustomobject]@{
            revision = Get-PzUmbrellaRevision -UmbrellaPath $umbrella
        }
        files = @($files)
    }
}

function Add-PzContractDifference {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[object]]$Differences,
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$Path,
        $Expected,
        $Actual
    )

    $Differences.Add([pscustomobject]@{
        kind = $Kind
        path = $Path.Replace('\', '/')
        expected = $Expected
        actual = $Actual
    })
}

function Assert-PzContractProperties {
    param([Parameter(Mandatory)]$Object, [Parameter(Mandatory)][string[]]$Names, [Parameter(Mandatory)][string]$Context)

    if ($Object -isnot [pscustomobject]) { throw "Invalid contract snapshot: $Context must be an object." }
    $actualNames = @($Object.PSObject.Properties.Name | Sort-Object)
    $expectedNames = @($Names | Sort-Object)
    if ($actualNames.Count -ne $expectedNames.Count -or @($actualNames | Where-Object { $_ -cnotin $expectedNames }).Count -ne 0) {
        throw "Invalid contract snapshot: $Context has an invalid structure."
    }
}

function Assert-PzContractSnapshot {
    param([Parameter(Mandatory)]$Snapshot)

    Assert-PzContractProperties -Object $Snapshot -Names @('schema', 'game', 'umbrella', 'files') -Context 'root'
    $schema = Get-PzObjectValue -Object $Snapshot -Name 'schema'
    if (($schema -isnot [int] -and $schema -isnot [long]) -or $schema -ne 1) {
        throw 'Invalid contract snapshot: schema must be integer 1.'
    }
    $game = Get-PzObjectValue -Object $Snapshot -Name 'game'
    Assert-PzContractProperties -Object $game -Names @('version', 'steamBuild') -Context 'game'
    $version = Get-PzObjectValue -Object $game -Name 'version'
    if ($version -isnot [string] -or ($version -ne 'unknown' -and $version -notmatch '^\d+\.\d+\.\d+$')) {
        throw 'Invalid contract snapshot: game.version must be a version string or unknown.'
    }
    $steamBuild = Get-PzObjectValue -Object $game -Name 'steamBuild'
    if ($steamBuild -isnot [string] -or $steamBuild -notmatch '^\d+$') {
        throw 'Invalid contract snapshot: game.steamBuild must be a numeric string.'
    }
    $umbrella = Get-PzObjectValue -Object $Snapshot -Name 'umbrella'
    Assert-PzContractProperties -Object $umbrella -Names @('revision') -Context 'umbrella'
    $revision = Get-PzObjectValue -Object $umbrella -Name 'revision'
    if ($revision -isnot [string] -or $revision -notmatch '^[0-9a-f]{40}$') {
        throw 'Invalid contract snapshot: umbrella.revision must be a git SHA.'
    }
    $files = Get-PzObjectValue -Object $Snapshot -Name 'files'
    if ($files -isnot [object[]]) { throw 'Invalid contract snapshot: files must be an array.' }
    $definitions = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($definition in Get-PzContractDefinition) { $definitions[$definition.path] = $definition.symbols }
    if ($files.Count -ne $definitions.Count) { throw 'Invalid contract snapshot: files has an invalid count.' }
    $seenPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($file in $files) {
        Assert-PzContractProperties -Object $file -Names @('path', 'sha256', 'symbols') -Context 'file'
        $path = Get-PzObjectValue -Object $file -Name 'path'
        if ($path -isnot [string] -or -not $seenPaths.Add($path)) {
            throw 'Invalid contract snapshot: file.path is invalid.'
        }
        $definitionSymbols = $definitions[$path]
        if ($null -eq $definitionSymbols) {
            foreach ($definitionPath in $definitions.Keys) {
                if ($definitionPath -ieq $path) { $definitionSymbols = $definitions[$definitionPath]; break }
            }
        }
        if ($null -eq $definitionSymbols) { throw 'Invalid contract snapshot: file.path is invalid.' }
        $sha256 = Get-PzObjectValue -Object $file -Name 'sha256'
        if ($sha256 -isnot [string] -or $sha256 -notmatch '^[0-9A-F]{64}$') {
            throw 'Invalid contract snapshot: file.sha256 must be an uppercase SHA-256.'
        }
        $symbols = Get-PzObjectValue -Object $file -Name 'symbols'
        Assert-PzContractProperties -Object $symbols -Names $definitionSymbols -Context 'symbols'
        foreach ($symbol in $symbols.PSObject.Properties) {
            if ($symbol.Value -isnot [bool]) { throw 'Invalid contract snapshot: symbols must contain booleans.' }
        }
    }
}

function Compare-PzContractSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Expected,
        [Parameter(Mandatory)]$Actual
    )

    Assert-PzContractSnapshot -Snapshot $Expected
    Assert-PzContractSnapshot -Snapshot $Actual
    $differences = [Collections.Generic.List[object]]::new()
    foreach ($name in @('schema')) {
        $expectedValue = Get-PzObjectValue -Object $Expected -Name $name
        $actualValue = Get-PzObjectValue -Object $Actual -Name $name
        if ($expectedValue -ne $actualValue) {
            Add-PzContractDifference -Differences $differences -Kind $name -Path $name -Expected $expectedValue -Actual $actualValue
        }
    }
    foreach ($name in @('version', 'steamBuild')) {
        $expectedValue = Get-PzObjectValue -Object (Get-PzObjectValue -Object $Expected -Name 'game') -Name $name
        $actualValue = Get-PzObjectValue -Object (Get-PzObjectValue -Object $Actual -Name 'game') -Name $name
        if ($expectedValue -ne $actualValue) {
            Add-PzContractDifference -Differences $differences -Kind "game.$name" -Path 'game' -Expected $expectedValue -Actual $actualValue
        }
    }
    $expectedUmbrella = Get-PzObjectValue -Object (Get-PzObjectValue -Object $Expected -Name 'umbrella') -Name 'revision'
    $actualUmbrella = Get-PzObjectValue -Object (Get-PzObjectValue -Object $Actual -Name 'umbrella') -Name 'revision'
    if ($expectedUmbrella -ne $actualUmbrella) {
        Add-PzContractDifference -Differences $differences -Kind 'umbrella.revision' -Path 'umbrella' -Expected $expectedUmbrella -Actual $actualUmbrella
    }

    $expectedFiles = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($file in @(Get-PzObjectValue -Object $Expected -Name 'files')) { $expectedFiles[$file.path] = $file }
    $actualFiles = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($file in @(Get-PzObjectValue -Object $Actual -Name 'files')) { $actualFiles[$file.path] = $file }
    $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($path in $expectedFiles.Keys) { $paths.Add($path) | Out-Null }
    foreach ($path in $actualFiles.Keys) { $paths.Add($path) | Out-Null }
    foreach ($path in @($paths | Sort-Object)) {
        $expectedFile = $expectedFiles[$path]
        $actualFile = $actualFiles[$path]
        if ($null -eq $expectedFile -or $null -eq $actualFile) {
            Add-PzContractDifference -Differences $differences -Kind 'file' -Path $path -Expected ($null -ne $expectedFile) -Actual ($null -ne $actualFile)
            continue
        }
        if ($expectedFile.sha256 -ne $actualFile.sha256) {
            Add-PzContractDifference -Differences $differences -Kind 'sha256' -Path $path -Expected $expectedFile.sha256 -Actual $actualFile.sha256
        }
        $expectedSymbols = $expectedFile.symbols.PSObject.Properties
        $actualSymbols = $actualFile.symbols.PSObject.Properties
        foreach ($symbol in @($expectedSymbols.Name + $actualSymbols.Name | Sort-Object -Unique)) {
            $expectedValue = Get-PzObjectValue -Object $expectedFile.symbols -Name $symbol
            $actualValue = Get-PzObjectValue -Object $actualFile.symbols -Name $symbol
            if ($expectedValue -ne $actualValue) {
                Add-PzContractDifference -Differences $differences -Kind 'symbol' -Path "$path#$symbol" -Expected $expectedValue -Actual $actualValue
            }
        }
    }
    return $differences.ToArray()
}
