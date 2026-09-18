# Build and update the existing Steam Workshop item in one command.
[CmdletBinding()]
param(
    [string]$Mod = 'cook-it-for-me',
    [string]$PatchNote,
    [switch]$DryRun,
    [string]$UploaderPath = $env:STEAM_UPLOADER_PATH
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib.ps1')
$modInfo = Resolve-PzMod $Mod
$sourceManifestPath = Join-Path $modInfo.Root 'mod-manifest.json'
$manifest = Get-Content -LiteralPath $sourceManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.appid -ne 108600) {
    throw 'Manifest must target Project Zomboid (appid 108600).'
}

if (-not $UploaderPath) {
    $command = Get-Command SteamUploader.exe -ErrorAction SilentlyContinue
    if ($command) { $UploaderPath = $command.Source }
    else { $UploaderPath = Join-Path $env:USERPROFILE '.codex\tools\SteamUploader\SteamUploader.exe' }
}
if (-not (Test-Path -LiteralPath $UploaderPath -PathType Leaf)) {
    throw 'SteamUploader.exe not found. Set STEAM_UPLOADER_PATH or pass -UploaderPath.'
}
$UploaderPath = (Resolve-Path -LiteralPath $UploaderPath).Path
if (-not $DryRun -and -not (Get-Process steam -ErrorAction SilentlyContinue)) {
    throw 'Start Steam and sign into the account that owns the Workshop item.'
}

$workshopRoot = if ($env:ZOMBOID_WORKSHOP_DIR) { $env:ZOMBOID_WORKSHOP_DIR }
                else { Join-Path $env:USERPROFILE 'Zomboid\Workshop' }
$itemRoot = [IO.Path]::GetFullPath((Join-Path $workshopRoot $modInfo.Id))
foreach ($entry in @(
    @{ Key = 'content'; Relative = 'Contents' },
    @{ Key = 'preview'; Relative = 'preview.png' },
    @{ Key = 'description'; Relative = 'description.bbcode' }
)) {
    $expected = Join-Path $itemRoot $entry.Relative
    if (-not $manifest.($entry.Key) -or [IO.Path]::GetFullPath($manifest.($entry.Key)) -ne $expected) {
        throw "Manifest $($entry.Key) must point to $expected"
    }
}

$releaseRoot = Join-Path ([IO.Path]::GetTempPath()) ($modInfo.Id + '-release-' + [guid]::NewGuid().ToString('N'))
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'build_workshop.ps1') -Mod $Mod -DestinationRoot $releaseRoot
if ($LASTEXITCODE -ne 0) { throw "Workshop build failed ($LASTEXITCODE)." }

# Upload an isolated snapshot, never the directory currently used by the dev game.
$releaseItem = Join-Path $releaseRoot $modInfo.Id
$manifest.content = Join-Path $releaseItem 'Contents'
$manifest.preview = Join-Path $releaseItem 'preview.png'
$manifest.description = Join-Path $releaseItem 'description.bbcode'
$manifestPath = Join-Path $releaseItem 'mod-manifest.json'
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))

$uploadArgs = @('upload', '--manifest-path', $manifestPath)
if ($PatchNote) { $uploadArgs += @('--patchnote', $PatchNote) }
if ($DryRun) { $uploadArgs += '--dry-run' }
Push-Location (Split-Path -Parent $UploaderPath)
try {
    & $UploaderPath @uploadArgs
    $uploadExitCode = $LASTEXITCODE
} finally {
    Pop-Location
}

# On first publication SteamUploader creates the item and writes its new ID into the
# isolated release manifest. Persist that ID even if the subsequent content update fails,
# otherwise retrying would create an orphaned duplicate Workshop item.
if (-not $DryRun -and (Test-Path -LiteralPath $manifestPath)) {
    $uploadedManifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($uploadedManifest.workshopid -and $uploadedManifest.workshopid -ne $manifest.workshopid) {
        $sourceManifest = Get-Content -LiteralPath $sourceManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($sourceManifest.PSObject.Properties.Name -contains 'workshopid') {
            $sourceManifest.workshopid = $uploadedManifest.workshopid
        } else {
            $sourceManifest | Add-Member -NotePropertyName workshopid -NotePropertyValue $uploadedManifest.workshopid
        }
        [IO.File]::WriteAllText($sourceManifestPath, ($sourceManifest | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))

        $sourceWorkshop = Join-Path $modInfo.Root 'workshop\workshop.txt'
        $workshopText = [IO.File]::ReadAllText($sourceWorkshop)
        if ($workshopText -notmatch '(?m)^id=') {
            [IO.File]::AppendAllText($sourceWorkshop, "id=$($uploadedManifest.workshopid)`r`n", [Text.UTF8Encoding]::new($false))
        }
        Write-Host "Saved new Workshop ID: $($uploadedManifest.workshopid)"
    }
}

if ($uploadExitCode -ne 0) { throw "Steam upload failed ($uploadExitCode)." }
if ($DryRun) { Write-Host 'Dry run completed; nothing uploaded.' }
else {
    $publishedManifest = Get-Content -LiteralPath $sourceManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-Host "Published: https://steamcommunity.com/sharedfiles/filedetails/?id=$($publishedManifest.workshopid)"
}
