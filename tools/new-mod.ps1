[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9]+(?:-[a-z0-9]+)*$')][string]$Slug,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z][A-Za-z0-9_]*$')][string]$Id,
    [Parameter(Mandatory)][ValidatePattern('^[^\r\n]+$')][string]$Name
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$root = Join-Path $repo (Join-Path 'mods' $Slug)
if (Test-Path -LiteralPath $root) { throw "Mod already exists: $root" }
$nameJson = $Name | ConvertTo-Json -Compress

function Write-Utf8([string]$Path, [string]$Content) {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

function Write-Image([string]$Path, [string]$Title) {
    Add-Type -AssemblyName System.Drawing
    $image = [Drawing.Bitmap]::new(256, 256)
    $graphics = [Drawing.Graphics]::FromImage($image)
    try {
        $graphics.Clear([Drawing.Color]::FromArgb(27, 36, 48))
        $font = [Drawing.Font]::new('Arial', 20, [Drawing.FontStyle]::Bold)
        try {
            $format = [Drawing.StringFormat]::new()
            $format.Alignment = [Drawing.StringAlignment]::Center
            $format.LineAlignment = [Drawing.StringAlignment]::Center
            $graphics.DrawString($Title, $font, [Drawing.Brushes]::White, [Drawing.RectangleF]::new(12, 12, 232, 232), $format)
            $format.Dispose()
        } finally { $font.Dispose() }
        $image.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $image.Dispose()
    }
}

if (-not $PSCmdlet.ShouldProcess($root, 'Create Project Zomboid mod scaffold')) { return }

try {
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    Write-Utf8 (Join-Path $root '42\mod.info') "name=$Name`nid=$Id`ndescription=TODO: describe $Name.`nposter=poster.png`n"
    Write-Utf8 (Join-Path $root "42\media\lua\shared\${Id}_Shared.lua") "$Id = $Id or {}`n$Id.ID = '$Id'`n`nreturn $Id`n"
    Write-Utf8 (Join-Path $root 'common\media\lua\shared\Translate\EN\UI.json') "{`n  `"UI_${Id}_Name`": $nameJson`n}`n"
    Write-Utf8 (Join-Path $root 'common\media\lua\shared\Translate\EN\Sandbox.json') "{}`n"
    Write-Utf8 (Join-Path $root 'tests\run.lua') "package.path = package.path .. ';../42/media/lua/shared/?.lua'`nlocal mod = require '${Id}_Shared'`nassert(mod.ID == '$Id')`nprint('ALL TESTS PASSED')`n"
    Write-Utf8 (Join-Path $root 'workshop\workshop.txt') "version=1`ntitle=$Name`ndescription=TODO: describe $Name.`ntags=Build 42;Misc`nvisibility=private`n"
    Write-Utf8 (Join-Path $root 'mod-manifest.json') "{`n  `"`$schema`": `"https://raw.githubusercontent.com/SimKDT/Steam-Uploader-rs/refs/heads/main/manifest_schema/mod-manifest-schema.json`",`n  `"appid`": 108600,`n  `"workshopid`": null,`n  `"content`": `"`",`n  `"preview`": `"`",`n  `"title`": $nameJson,`n  `"description`": `"`",`n  `"visibility`": 0,`n  `"tags`": [`"Build 42`", `"Misc`"]`n}`n"
    $readme = "# $Name`n`n" + '```powershell' + "`n.\tools\check.ps1 -Mod $Slug`n.\tools\dev.cmd $Slug`n" + '```' + "`n`nBefore first publication, set workshopid in mod-manifest.json.`n"
    Write-Utf8 (Join-Path $root 'README.md') $readme
    Write-Image (Join-Path $root '42\poster.png') $Name
    Copy-Item -LiteralPath (Join-Path $root '42\poster.png') -Destination (Join-Path $root 'workshop\preview.png')
} catch {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    throw
}

Write-Host "Created: $root" -ForegroundColor Green
Write-Host "Next: .\tools\check.ps1 -Mod $Slug"
