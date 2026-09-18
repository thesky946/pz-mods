$script:EmmyLuaVersion = '0.25.1'
$script:EmmyLuaAssetUri = 'https://github.com/EmmyLuaLs/emmylua-analyzer-rust/releases/download/0.25.1/emmylua_check-win32-x64.zip'
$script:EmmyLuaAssetSha256 = '577982e68d925972d8ae35f54b5f384ad77a84a2e31e340bd663d1efd2ef5983'

function Resolve-EmmyLuaDestinationRoot {
    param([string]$RequestedPath, [Parameter(Mandatory)][string]$RepositoryRoot)

    $path = if ([string]::IsNullOrWhiteSpace($RequestedPath)) {
        Join-Path $RepositoryRoot '.tools\emmylua'
    } else {
        $RequestedPath
    }
    return [IO.Path]::GetFullPath($path)
}

function Install-EmmyLuaCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DestinationRoot,
        [string]$ArchivePath,
        [string]$ExpectedSha256 = $script:EmmyLuaAssetSha256
    )

    if (-not [Environment]::Is64BitOperatingSystem -or $env:OS -ne 'Windows_NT') {
        throw 'The pinned EmmyLua installer currently supports Windows x64 only.'
    }
    if ($ExpectedSha256 -notmatch '^[0-9a-fA-F]{64}$') {
        throw 'ExpectedSha256 must contain exactly 64 hexadecimal characters.'
    }

    $root = [IO.Path]::GetFullPath($DestinationRoot)
    $versionDirectory = Join-Path $root $script:EmmyLuaVersion
    $installed = Join-Path $versionDirectory 'emmylua_check.exe'
    if (-not $ArchivePath -and (Test-Path -LiteralPath $installed -PathType Leaf)) {
        return Get-Item -LiteralPath $installed
    }

    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $temporary = Join-Path $root ('.install-' + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $temporary | Out-Null
    try {
        $archive = if ($ArchivePath) {
            [IO.Path]::GetFullPath($ArchivePath)
        } else {
            $download = Join-Path $temporary 'emmylua_check.zip'
            Invoke-WebRequest -Uri $script:EmmyLuaAssetUri -OutFile $download
            $download
        }
        if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
            throw "EmmyLua archive not found: $archive"
        }

        $actualHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
        if ($actualHash -ine $ExpectedSha256) {
            throw "EmmyLua archive checksum mismatch. Expected $ExpectedSha256, got $actualHash."
        }

        $expanded = Join-Path $temporary 'expanded'
        Expand-Archive -LiteralPath $archive -DestinationPath $expanded
        $sourceExecutable = Get-ChildItem -LiteralPath $expanded -Recurse -Filter 'emmylua_check.exe' -File |
            Select-Object -First 1
        if (-not $sourceExecutable) {
            throw 'Verified EmmyLua archive does not contain emmylua_check.exe.'
        }

        $stage = Join-Path $root ('.stage-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $stage | Out-Null
        Copy-Item -LiteralPath $sourceExecutable.FullName -Destination (Join-Path $stage 'emmylua_check.exe')

        if (Test-Path -LiteralPath $versionDirectory) {
            Remove-Item -LiteralPath $versionDirectory -Recurse -Force
        }
        Move-Item -LiteralPath $stage -Destination $versionDirectory
        return Get-Item -LiteralPath $installed
    } finally {
        if ((Test-Path -LiteralPath $temporary) -and $temporary.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $temporary -Recurse -Force
        }
    }
}
