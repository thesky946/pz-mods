# build_workshop.ps1 - assembles the mod folder for the Steam Workshop upload.
#
# Run from anywhere:
#     powershell -ExecutionPolicy Bypass -File tools\build_workshop.ps1
#
# Result: %USERPROFILE%\Zomboid\Workshop\CookItForMe\
#
# NOTE: this script does NOT upload anything to Steam. It only lays the files out the
# way the in-game uploader expects. The upload itself is manual: launch PZ -> Workshop ->
# Create/Update Item -> pick this folder -> Upload. There is no headless way: uploads go
# through Steam UGC, which the game engine drives from inside the game.
#
# Layout the uploader expects:
#     %USERPROFILE%\Zomboid\Workshop\CookItForMe\
#         preview.png            <- 256x256 PNG, at the ITEM ROOT, not inside Contents
#         workshop.txt           <- title/description/tags/visibility
#         Contents\
#             mods\CookItForMe\
#                 42\            <- mod.info, poster.png, icon.png, media\
#                 common\        <- translations
#
# Keep this file ASCII-only: Windows PowerShell 5.1 reads .ps1 as ANSI unless it has a
# UTF-8 BOM, so non-ASCII text here breaks the parser on a non-English locale.

$ErrorActionPreference = "Stop"

function Fail($msg) { Write-Host $msg -ForegroundColor Red; exit 1 }
function Warn($msg) { Write-Host $msg -ForegroundColor Yellow }

$Src      = Split-Path -Parent $PSScriptRoot
$ModName  = "CookItForMe"
$DestRoot = if ($env:ZOMBOID_WORKSHOP_DIR) { $env:ZOMBOID_WORKSHOP_DIR }
            else { Join-Path $env:USERPROFILE "Zomboid\Workshop" }
$Out      = Join-Path $DestRoot $ModName

$SrcWorkshopTxt = Join-Path $Src "workshop\workshop.txt"
$SrcPreview     = Join-Path $Src "workshop\preview.png"
$SrcPoster      = Join-Path $Src "42\poster.png"

if (-not (Test-Path $SrcWorkshopTxt)) { Fail "missing $SrcWorkshopTxt" }

# Steam item id. The game appends it to workshop.txt after the first upload. The build
# recreates the folder from scratch, so the id has to be carried over - otherwise the next
# upload would create a NEW item instead of updating the existing one, leaving a duplicate
# that only Steam support can remove.
$PrevId = ""
foreach ($candidate in @((Join-Path $Out "workshop.txt"), $SrcWorkshopTxt)) {
    if (-not $PrevId -and (Test-Path $candidate)) {
        $match = Select-String -Path $candidate -Pattern '^id=' -List
        if ($match) { $PrevId = $match.Line.Trim() }
    }
}

if (Test-Path $Out) { Remove-Item $Out -Recurse -Force }
$ModOut = Join-Path $Out "Contents\mods\$ModName"
New-Item -ItemType Directory -Path $ModOut -Force | Out-Null

# Version folders are copied as-is; nothing else may land inside Contents
foreach ($d in @("42", "common")) {
    $from = Join-Path $Src $d
    if (-not (Test-Path $from)) { Fail "missing folder $from" }
    Copy-Item $from -Destination (Join-Path $ModOut $d) -Recurse -Force
}

# Workshop metadata lives at the item root
Copy-Item $SrcWorkshopTxt (Join-Path $Out "workshop.txt") -Force
if (Test-Path $SrcPreview) {
    Copy-Item $SrcPreview (Join-Path $Out "preview.png") -Force
} else {
    Copy-Item $SrcPoster (Join-Path $Out "preview.png") -Force
}

# Put the id back into the built file and, if it was missing, into the source file, so it
# survives future builds and is not lost when the Workshop folder is deleted.
# Written via .NET: Add-Content on PowerShell 5.1 prepends a BOM and corrupts UTF-8.
if ($PrevId) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $outTxt = Join-Path $Out "workshop.txt"
    if (-not (Select-String -Path $outTxt -Pattern '^id=' -List)) {
        [System.IO.File]::AppendAllText($outTxt, "$PrevId`r`n", $utf8NoBom)
    }
    if (-not (Select-String -Path $SrcWorkshopTxt -Pattern '^id=' -List)) {
        [System.IO.File]::AppendAllText($SrcWorkshopTxt, "$PrevId`r`n", $utf8NoBom)
        Write-Host "carried over item id from previous upload: $PrevId"
    }
}

# Junk that breaks the upload: .DS_Store on macOS, Thumbs.db / desktop.ini on Windows
Get-ChildItem -Path $Out -Recurse -Force -File |
    Where-Object { $_.Name -in @(".DS_Store", "Thumbs.db", "desktop.ini") } |
    Remove-Item -Force

foreach ($f in @("workshop.txt", "preview.png", "Contents\mods\$ModName\42\mod.info")) {
    $p = Join-Path $Out $f
    if (-not (Test-Path $p)) { Fail "not built: $p" }
}

# The uploader wants a 256x256 preview (it validates it itself via validatePreviewImage)
try {
    Add-Type -AssemblyName System.Drawing
    $img = [System.Drawing.Image]::FromFile((Join-Path $Out "preview.png"))
    $w = $img.Width; $h = $img.Height
    $img.Dispose()
    if ($w -ne 256 -or $h -ne 256) {
        Warn "warning: preview.png is ${w}x${h}, the uploader expects 256x256"
    }
} catch {
    Warn "warning: could not check preview.png size ($_)"
}

if (-not (Select-String -Path (Join-Path $Out "workshop.txt") -Pattern '^visibility=' -List)) {
    Warn "warning: workshop.txt has no visibility"
}
if (Select-String -Path (Join-Path $Out "workshop.txt") -Pattern '^id=' -List) {
    Write-Host "already published (workshop.txt has an id - the uploader will update the existing item)"
}

Write-Host ""
Write-Host "done: $Out" -ForegroundColor Green
Write-Host "next: launch PZ -> Workshop -> Create/Update Item -> pick this folder -> Upload"
Write-Host "reminder: do not keep the mod enabled from both Zomboid\mods and Zomboid\Workshop -"
Write-Host "          after publishing, Steam downloads its own copy and the mod list shows two entries"
