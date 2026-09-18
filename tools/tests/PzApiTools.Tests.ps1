$libraryPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\PzApiTools.ps1'
if (-not (Test-Path -LiteralPath $libraryPath -PathType Leaf)) {
    throw 'PzApiTools.ps1 is missing.'
}
. $libraryPath

function New-PzFixtureGame {
    param([Parameter(Mandatory)][string]$Root, [string]$LuaText = 'RecipeManager.getEvolvedRecipe()')
    $game = Join-Path $Root 'steamapps\common\ProjectZomboid'
    $luaRoot = Join-Path $game 'media\lua\shared'
    New-Item -ItemType Directory -Path $luaRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $luaRoot 'Recipes.lua') -Value $LuaText

    $jarPayload = Join-Path $Root 'jar-payload\zombie\inventory'
    New-Item -ItemType Directory -Path $jarPayload -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $jarPayload 'RecipeManager.class') -Value 'fixture' -NoNewline
    $zip = Join-Path $Root 'projectzomboid.zip'
    Compress-Archive -Path (Join-Path $Root 'jar-payload\*') -DestinationPath $zip
    Move-Item -LiteralPath $zip -Destination (Join-Path $game 'projectzomboid.jar')
    return $game
}

Invoke-Test 'parses Steam root and libraryfolders paths once' {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('pz-api-test-' + [guid]::NewGuid())
    New-Item -ItemType Directory -Path (Join-Path $root 'steamapps') -Force | Out-Null
    try {
        $second = Join-Path $root 'second-library'
        $vdf = @"
"libraryfolders"
{
    "0" { "path" "$($root.Replace('\', '\\'))" }
    "1" { "path" "$($second.Replace('\', '\\'))" }
}
"@
        Set-Content -LiteralPath (Join-Path $root 'steamapps\libraryfolders.vdf') -Value $vdf
        $paths = @(Get-SteamLibraryPaths -SteamRoot $root)
        Assert-Equal $paths.Count 2
        Assert-Equal $paths[0] ([IO.Path]::GetFullPath($root))
        Assert-Equal $paths[1] ([IO.Path]::GetFullPath($second))
    } finally {
        if ($root.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $root -Recurse -Force }
    }
}

Invoke-Test 'rejects ambiguous Project Zomboid installations' {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('pz-api-test-' + [guid]::NewGuid())
    New-Item -ItemType Directory -Path (Join-Path $root 'steamapps') -Force | Out-Null
    try {
        $second = Join-Path $root 'second-library'
        New-PzFixtureGame -Root $root | Out-Null
        New-PzFixtureGame -Root $second | Out-Null
        $vdf = @"
"libraryfolders"
{
    "1" { "path" "$($second.Replace('\', '\\'))" }
}
"@
        Set-Content -LiteralPath (Join-Path $root 'steamapps\libraryfolders.vdf') -Value $vdf
        Assert-Throws { Resolve-PzGamePath -SteamRoot $root } '*Multiple*'
    } finally {
        if ($root.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $root -Recurse -Force }
    }
}

Invoke-Test 'finds vanilla Lua, Umbrella, and Java class matches' {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('pz-api-test-' + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $root | Out-Null
    try {
        $game = New-PzFixtureGame -Root $root
        $umbrella = Join-Path $root 'umbrella'
        New-Item -ItemType Directory -Path $umbrella | Out-Null
        Set-Content -LiteralPath (Join-Path $umbrella 'RecipeManager.lua') -Value '---@class RecipeManager'
        $results = @(Find-PzApi -Query 'RecipeManager' -GamePath $game -UmbrellaPath $umbrella)
        Assert-Equal @($results | Where-Object source -eq 'vanilla-lua').Count 1
        Assert-Equal @($results | Where-Object source -eq 'umbrella').Count 1
        Assert-Equal @($results | Where-Object source -eq 'java-class').Count 1
        Assert-True (@($results | Where-Object { [IO.Path]::IsPathRooted($_.path) }).Count -eq 0) 'Search results must use relative paths.'
    } finally {
        if ($root.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $root -Recurse -Force }
    }
}
