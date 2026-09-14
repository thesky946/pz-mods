# build_workshop.ps1 — собирает папку мода для загрузки в Steam Workshop.
#
# Запуск из корня репозитория:
#     powershell -ExecutionPolicy Bypass -File tools\build_workshop.ps1
#
# Результат: %USERPROFILE%\Zomboid\Workshop\CookItForMe\
#
# ВАЖНО: скрипт НЕ загружает ничего в Steam. Он только раскладывает файлы так, как ждёт
# игровой загрузчик. Сама загрузка — вручную: запустить PZ -> Workshop -> Create/Update
# Item -> выбрать эту папку -> Upload. Без запущенной игры обновить Workshop нельзя:
# загрузка идёт через Steam UGC, который дёргает движок изнутри игры.
#
# Раскладка, которую ждёт загрузчик:
#     %USERPROFILE%\Zomboid\Workshop\CookItForMe\
#         preview.png            <- 256x256 PNG, строго в КОРНЕ элемента, не в Contents
#         workshop.txt           <- title/description/tags/visibility
#         Contents\
#             mods\CookItForMe\
#                 42\            <- mod.info, poster.png, icon.png, media\
#                 common\        <- переводы

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

if (-not (Test-Path $SrcWorkshopTxt)) { Fail "нет $SrcWorkshopTxt" }

# Steam-овский id элемента. Игра дописывает его в workshop.txt после первой загрузки.
# Сборка пересоздаёт папку с нуля, поэтому id надо перенести — иначе следующая загрузка
# предложит создать НОВЫЙ элемент вместо обновления, и в Workshop появится дубль,
# который потом придётся удалять через поддержку Steam.
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

# Версионные папки мода копируются как есть — ничего лишнее в Contents попасть не должно
foreach ($d in @("42", "common")) {
    $from = Join-Path $Src $d
    if (-not (Test-Path $from)) { Fail "нет папки $from" }
    Copy-Item $from -Destination (Join-Path $ModOut $d) -Recurse -Force
}

# Метаданные Workshop лежат в корне элемента
Copy-Item $SrcWorkshopTxt (Join-Path $Out "workshop.txt") -Force
if (Test-Path $SrcPreview) {
    Copy-Item $SrcPreview (Join-Path $Out "preview.png") -Force
} else {
    Copy-Item $SrcPoster (Join-Path $Out "preview.png") -Force
}

# Возвращаем id в собранный файл и, если его там не было, в исходник — чтобы он пережил
# любые следующие сборки и не потерялся, если папку Workshop удалят.
# Пишем через .NET, а не Add-Content: та в PowerShell 5.1 добавляет BOM и портит UTF-8.
if ($PrevId) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $outTxt = Join-Path $Out "workshop.txt"
    if (-not (Select-String -Path $outTxt -Pattern '^id=' -List)) {
        [System.IO.File]::AppendAllText($outTxt, "$PrevId`r`n", $utf8NoBom)
    }
    if (-not (Select-String -Path $SrcWorkshopTxt -Pattern '^id=' -List)) {
        [System.IO.File]::AppendAllText($SrcWorkshopTxt, "$PrevId`r`n", $utf8NoBom)
        Write-Host "id $PrevId из прошлой загрузки дописан в workshop\workshop.txt"
    }
}

# Мусор, который ломает загрузку: на macOS это .DS_Store, на Windows — Thumbs.db и desktop.ini
Get-ChildItem -Path $Out -Recurse -Force -File |
    Where-Object { $_.Name -in @(".DS_Store", "Thumbs.db", "desktop.ini") } |
    Remove-Item -Force

foreach ($f in @("workshop.txt", "preview.png", "Contents\mods\$ModName\42\mod.info")) {
    $p = Join-Path $Out $f
    if (-not (Test-Path $p)) { Fail "не собралось: $p" }
}

# Загрузчик ожидает превью 256x256 (валидирует сам через validatePreviewImage — предупреждаем)
try {
    Add-Type -AssemblyName System.Drawing
    $img = [System.Drawing.Image]::FromFile((Join-Path $Out "preview.png"))
    $w = $img.Width; $h = $img.Height
    $img.Dispose()
    if ($w -ne 256 -or $h -ne 256) {
        Warn "внимание: preview.png ${w}x${h}, а загрузчик ожидает 256x256"
    }
} catch {
    Warn "внимание: не удалось проверить размер preview.png ($_)"
}

if (-not (Select-String -Path (Join-Path $Out "workshop.txt") -Pattern '^visibility=' -List)) {
    Warn "внимание: в workshop.txt нет visibility"
}
if (Select-String -Path (Join-Path $Out "workshop.txt") -Pattern '^id=' -List) {
    Write-Host "запись уже опубликована (в workshop.txt есть id — загрузчик обновит существующий элемент)"
}

Write-Host ""
Write-Host "готово: $Out" -ForegroundColor Green
Write-Host "дальше: запустить PZ -> Workshop -> Create/Update Item -> выбрать эту папку -> Upload"
Write-Host "напоминание: не держи мод включённым одновременно из Zomboid\mods и из Zomboid\Workshop —"
Write-Host "             после публикации Steam скачает свою копию, и в менеджере модов будет два одинаковых мода"
