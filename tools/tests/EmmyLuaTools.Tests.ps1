$libraryPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\EmmyLuaTools.ps1'
if (-not (Test-Path -LiteralPath $libraryPath -PathType Leaf)) {
    throw 'EmmyLuaTools.ps1 is missing.'
}
. $libraryPath

Invoke-Test 'resolves the default cache after script initialization' {
    $repositoryRoot = 'C:\repo'
    $resolved = Resolve-EmmyLuaDestinationRoot -RequestedPath '' -RepositoryRoot $repositoryRoot
    Assert-Equal $resolved ([IO.Path]::GetFullPath('C:\repo\.tools\emmylua'))
}

function New-EmmyLuaFixtureArchive {
    param([string]$Root, [switch]$WithoutExecutable)
    $payload = Join-Path $Root 'payload'
    New-Item -ItemType Directory -Path $payload -Force | Out-Null
    $fileName = if ($WithoutExecutable) { 'readme.txt' } else { 'emmylua_check.exe' }
    Set-Content -LiteralPath (Join-Path $payload $fileName) -Value 'fixture' -NoNewline
    $archive = Join-Path $Root 'tool.zip'
    Compress-Archive -Path (Join-Path $payload '*') -DestinationPath $archive
    return $archive
}

Invoke-Test 'installs a checksum-verified fixture archive' {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('emmy-test-' + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $root | Out-Null
    try {
        $archive = New-EmmyLuaFixtureArchive -Root $root
        $hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
        $exe = Install-EmmyLuaCheck -DestinationRoot (Join-Path $root 'installed') -ArchivePath $archive -ExpectedSha256 $hash
        Assert-Equal $exe.Name 'emmylua_check.exe'
        Assert-True (Test-Path -LiteralPath $exe.FullName -PathType Leaf) 'Installed executable is missing.'
    } finally {
        if ($root.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }
}

Invoke-Test 'rejects an archive with the wrong checksum' {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('emmy-test-' + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $root | Out-Null
    try {
        $archive = New-EmmyLuaFixtureArchive -Root $root
        Assert-Throws {
            Install-EmmyLuaCheck -DestinationRoot (Join-Path $root 'installed') -ArchivePath $archive -ExpectedSha256 ('0' * 64)
        } '*checksum*'
    } finally {
        if ($root.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }
}

Invoke-Test 'rejects an archive without emmylua_check.exe' {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('emmy-test-' + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $root | Out-Null
    try {
        $archive = New-EmmyLuaFixtureArchive -Root $root -WithoutExecutable
        $hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
        Assert-Throws {
            Install-EmmyLuaCheck -DestinationRoot (Join-Path $root 'installed') -ArchivePath $archive -ExpectedSha256 $hash
        } '*emmylua_check.exe*'
    } finally {
        if ($root.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }
}
