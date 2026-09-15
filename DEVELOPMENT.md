# Разработка

## Первый запуск

1. В Project Zomboid включить в текущем сохранении `Cook It For Me` и `Forge Live Bridge (dev tool)`.
2. Зайти персонажем в мир.
3. В корне репозитория запустить:

```powershell
.\tools\dev.cmd
```

`dev.cmd` сам установит локальный Forge Live bridge при первом запуске, соберёт мод в `%USERPROFILE%\Zomboid\Workshop\CookItForMe`, запустит offline Lua-тесты и начнёт следить за `42\`.

Успешное подключение к игре:

```text
[CookItForMe] bridge: pong v0.2.0
```

## Цикл Lua-разработки

Менять Lua только в `42\media\lua\`. После сохранения Forge Live проверяет синтаксис Lua 5.1, копирует файл в авторскую папку PZ и вызывает встроенный `reloadLuaFile()`.

Ожидаемый результат:

```text
[CookItForMe] media\lua\...: RECARGADO in ...ms
```

Перезапуск PZ и ручной `reloadLua()` для обычной правки существующего Lua-файла не нужны.

Watcher намеренно следит только за `42\`: просмотр всего репозитория захватывает временные файлы `.git` и может завершиться с `ENOENT`.

## Изменения, требующие перезапуска

После изменения `mod.info`, переводов JSON, `.txt` scripts, изображений, моделей или звуков:

1. Полностью перезапустить PZ.
2. Снова войти в мир.
3. Снова запустить `tools\dev.cmd`.

## Папки

- Исходники: этот репозиторий.
- Авторская сборка: `%USERPROFILE%\Zomboid\Workshop\CookItForMe`.
- Локальный dev bridge: `%USERPROFILE%\Zomboid\mods\ForgeLiveBridge`.
- Forge Live CLI: `tools\forge-live\` — локальная зависимость, намеренно исключена из Git и автоматически устанавливается `tools\setup-forge-live.ps1`.

Не редактировать вручную авторскую сборку или Steam Workshop cache: они являются производными копиями.

## Диагностика и релиз

- Игровые ошибки: `%USERPROFILE%\Zomboid\console.txt`.
- Разовая полная синхронизация и offline-тесты: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev.ps1`.
- Публикация: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\publish_workshop.ps1`.

`Forge Live Bridge` — локальный инструмент разработки; в Workshop-релиз мода он не входит.
