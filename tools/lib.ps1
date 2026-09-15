function Resolve-PzMod {
    param([Parameter(Mandatory)][string]$Name)

    $repo = Split-Path -Parent $PSScriptRoot
    $root = Join-Path $repo (Join-Path 'mods' $Name)
    $info = Join-Path $root '42\mod.info'
    if (-not (Test-Path -LiteralPath $info -PathType Leaf)) {
        throw "Mod '$Name' is missing 42\\mod.info."
    }
    $idLine = Get-Content -LiteralPath $info -Encoding UTF8 | Where-Object { $_ -match '^id=' } | Select-Object -First 1
    if (-not $idLine) { throw "Mod '$Name' has no id in 42\\mod.info." }
    $id = $idLine.Substring(3).Trim()
    if (-not $id) { throw "Mod '$Name' has an empty id in 42\\mod.info." }
    [pscustomobject]@{ Name = $Name; Root = [IO.Path]::GetFullPath($root); Id = $id }
}
