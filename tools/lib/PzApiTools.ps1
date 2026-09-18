function Get-SteamLibraryPaths {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SteamRoot)

    $root = [IO.Path]::GetFullPath($SteamRoot)
    $paths = [Collections.Generic.List[string]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($seen.Add($root)) { $paths.Add($root) }

    $vdfPath = Join-Path $root 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdfPath -PathType Leaf) {
        $content = Get-Content -LiteralPath $vdfPath -Raw
        foreach ($match in [regex]::Matches($content, '"path"\s*"([^"]+)"')) {
            $path = [IO.Path]::GetFullPath($match.Groups[1].Value.Replace('\\', '\'))
            if ($seen.Add($path)) { $paths.Add($path) }
        }
    }
    return $paths.ToArray()
}

function Test-PzGamePath {
    param([Parameter(Mandatory)][string]$Path)
    return (Test-Path -LiteralPath (Join-Path $Path 'projectzomboid.jar') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $Path 'media\lua') -PathType Container)
}

function Get-PzRelativePath {
    param([Parameter(Mandatory)][string]$BasePath, [Parameter(Mandatory)][string]$Path)

    $base = [IO.Path]::GetFullPath($BasePath).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $baseUri = [Uri]::new($base)
    $pathUri = [Uri]::new([IO.Path]::GetFullPath($Path))
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString()).Replace('\', '/')
}

function Resolve-PzGamePath {
    [CmdletBinding()]
    param([string]$GamePath, [string]$SteamRoot)

    if ($GamePath) {
        $explicit = [IO.Path]::GetFullPath($GamePath)
        if (-not (Test-PzGamePath $explicit)) { throw "Invalid Project Zomboid installation: $explicit" }
        return $explicit
    }
    if (-not $SteamRoot) { throw 'SteamRoot is required when GamePath is not supplied.' }

    $candidates = @(
        Get-SteamLibraryPaths -SteamRoot $SteamRoot |
            ForEach-Object { Join-Path $_ 'steamapps\common\ProjectZomboid' } |
            Where-Object { Test-PzGamePath $_ } |
            ForEach-Object { [IO.Path]::GetFullPath($_) }
    )
    if ($candidates.Count -eq 0) { throw 'Project Zomboid installation was not found in Steam libraries.' }
    if ($candidates.Count -gt 1) { throw "Multiple Project Zomboid installations found: $($candidates -join '; '). Use -GamePath." }
    return $candidates[0]
}

function Find-PzApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Query,
        [Parameter(Mandatory)][string]$GamePath,
        [Parameter(Mandatory)][string]$UmbrellaPath
    )

    $game = [IO.Path]::GetFullPath($GamePath)
    $umbrella = [IO.Path]::GetFullPath($UmbrellaPath)
    if (-not (Test-PzGamePath $game)) { throw "Invalid Project Zomboid installation: $game" }
    if (-not (Test-Path -LiteralPath $umbrella -PathType Container)) { throw "Umbrella library not found: $umbrella" }

    $results = [Collections.Generic.List[object]]::new()
    $luaRoot = Join-Path $game 'media\lua'
    Get-ChildItem -LiteralPath $luaRoot -Recurse -Filter '*.lua' -File | ForEach-Object {
        $file = $_
        Select-String -LiteralPath $file.FullName -SimpleMatch $Query | ForEach-Object {
            $results.Add([pscustomobject]@{
                source = 'vanilla-lua'
                path = Get-PzRelativePath -BasePath $luaRoot -Path $file.FullName
                line = $_.LineNumber
                text = $_.Line.Trim()
            })
        }
    }
    Get-ChildItem -LiteralPath $umbrella -Recurse -Filter '*.lua' -File | ForEach-Object {
        $file = $_
        Select-String -LiteralPath $file.FullName -SimpleMatch $Query | ForEach-Object {
            $results.Add([pscustomobject]@{
                source = 'umbrella'
                path = Get-PzRelativePath -BasePath $umbrella -Path $file.FullName
                line = $_.LineNumber
                text = $_.Line.Trim()
            })
        }
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $jarPath = Join-Path $game 'projectzomboid.jar'
    $archive = [IO.Compression.ZipFile]::OpenRead($jarPath)
    try {
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName.EndsWith('.class', [StringComparison]::OrdinalIgnoreCase) -and
                $entry.FullName.IndexOf($Query, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $results.Add([pscustomobject]@{
                    source = 'java-class'
                    path = $entry.FullName
                    line = $null
                    text = $entry.FullName.Substring(0, $entry.FullName.Length - 6).Replace('/', '.')
                })
            }
        }
    } finally {
        $archive.Dispose()
    }

    return $results | Sort-Object source, path, line
}
