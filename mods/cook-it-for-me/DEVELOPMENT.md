# Разработка

Все команды ниже выполняются из корня `pz-mods`; мод обозначается slug `cook-it-for-me`.

## Первый запуск

1. В Project Zomboid включить в текущем сохранении `Cook It For Me` и `Forge Live Bridge (dev tool)`.
2. Зайти персонажем в мир.
3. В корне репозитория запустить:

```powershell
.\tools\watch.cmd
```

`watch.cmd` сам установит локальный Forge Live bridge при первом запуске, соберёт мод в `%USERPROFILE%\Zomboid\Workshop\CookItForMe`, запустит offline Lua-тесты и начнёт следить за `42\`.

Успешное подключение к игре:

```text
[CookItForMe] bridge: pong v0.2.0
```

## Цикл Lua-разработки

Менять Lua только в `42\media\lua\`. После серии сохранений Forge Live собирает пакет изменений, проверяет синтаксис Lua 5.1 всех исходников и наличие локальных require-зависимостей. Затем копирует весь пакет в авторскую папку PZ и последовательно вызывает `reloadLuaFile()`: зависимости перед потребителями, включая потребителей с неизменённым исходником.

Ожидаемый результат:

```text
[CookItForMe] RELOAD ACK: media/lua/shared/CookItForMe_FoodLogic.lua
```

RELOAD ACK означает подтверждение вызова bridge, а не доказательство отсутствия ошибок в игровом коде: движок может записать предупреждение без Lua-исключения. Проверять console.txt и результат в игре. После отрицательного ответа или таймаута пакет останавливается; дальнейший hot reload приостановлен до перезапуска игры и watcher.

Reload отправляется с абсолютным путём установленного файла. Это обязательно для обновления кэша require в текущей сборке PZ: относительный путь создавал отдельную запись, и потребители продолжали получать старую таблицу. Проверено диагностикой в работающей игре: после абсолютного reload require возвращает актуальные REVISION Actions и Executor. При старте готовки строка runtime показывает версии фактически используемых модулей.

Обычные правки существующих Lua-модулей перезагружаются автоматически. Текущая готовка может держать старые замыкания: проверять изменённое исполнение на следующем запуске готовки, а окно плана закрыть и открыть заново. Обновление регистрации событий и миграция уже созданных объектов не гарантируются.

Один watcher на bridge: команды сериализованы внутри процесса. Не запускать несколько watch.cmd одновременно.

Watcher намеренно следит только за `42\`: просмотр всего репозитория захватывает временные файлы `.git` и может завершиться с `ENOENT`.

## Изменения, требующие перезапуска

### Переводы JSON

После первого обновления Forge Live Bridge перезапустите игру один раз, чтобы загрузилась новая команда `translations`. Дальше для перевода или добавления JSON-файла используйте одну команду из корня репозитория:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\reload-translations.ps1 -Mod cook-it-for-me
```

Она запускает проверки проекта, синхронизирует мод целиком и вызывает ванильный `Translator.loadFiles()` через Forge Live. Игра должна быть запущена, мост включён, а персонаж должен находиться в мире или меню. При отсутствии ACK команда завершится ошибкой; проверьте `console.txt` и состояние моста.

### Остальные изменения

После изменения `mod.info`, `.txt` scripts, изображений, моделей или звуков, а также добавления, удаления или переименования Lua-модуля:

1. Остановить watcher. Для новой структуры Lua он выводит RESTART REQUIRED и больше не отправляет reload; последующие корректные Lua-правки только копирует.
2. Закрыть PZ. Выполнить `powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev.ps1 -Mod cook-it-for-me`, чтобы синхронизировать также удаления и не-Lua-файлы.
3. Запустить PZ, снова войти в мир и запустить `tools\watch.cmd cook-it-for-me`.

Перезапуск при новой структуре — консервативное ограничение текущего инструмента: успешная загрузка нового файла через reloadLuaFile не доказывает, что require и уже существующие ссылки обновились. В локальном логе после добавления модулей были require-failed; полноценная загрузка новых зависимостей без перезапуска пока не проверена.

## Папки

- Исходники: этот репозиторий.
- Авторская сборка: `%USERPROFILE%\Zomboid\Workshop\CookItForMe`.
- Локальный dev bridge: `%USERPROFILE%\Zomboid\mods\ForgeLiveBridge`.
- Forge Live CLI: `tools\forge-live\` — исходники локальной версии находятся в Git; node_modules и локальный config — окружение разработки.

Не редактировать вручную авторскую сборку или Steam Workshop cache: они являются производными копиями.

## Диагностика и релиз

Поиск символа одновременно в установленном vanilla Lua, Umbrella и именах Java-классов:

```powershell
.\tools\find-pz-api.ps1 -Query RecipeManager
.\tools\find-pz-api.ps1 -Query IsoStove -Json
```

Результат `java-class` подтверждает наличие класса в `projectzomboid.jar`, но не сигнатуру метода. Для сигнатур сначала сверять Umbrella, затем установленный API игры.

Статус игры, watcher, bridge, последнего ACK и новых ошибок после запуска watcher:

```powershell
.\tools\game-status.ps1 -Mod cook-it-for-me
.\tools\game-status.ps1 -Mod cook-it-for-me -Json
```

После обновления инструментов один раз перезапустить только watcher, чтобы он начал писать `status.json` схемы 1. Игру ради этого перезапускать не нужно. Статус `ready` и `RELOAD ACK` подтверждают применение файла, но не корректное поведение мода в игре.

- Полная проверка без синхронизации: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/check.ps1 -Mod cook-it-for-me`. Отсутствие Lua-раннера считается ошибкой.
- `dev.ps1` проверяет проект до синхронизации. `publish_workshop.ps1` проверяет проект и собирает изолированную копию в `%TEMP%/CookItForMe-release-*/CookItForMe`; авторская папка работающей игры не пересоздаётся при публикации.
- Forge Live создаёт `watcher.lock` в каталоге bridge. Второй процесс отказывается работать; запись завершившегося процесса восстанавливается автоматически.
- Обновление надёжности меняет контракт сессии, обработчики и переводы: после синхронизации нужен один полный перезапуск PZ. Затем снова запустить `tools/watch.cmd`.

- Только офлайн-проверки, без синхронизации: из каталога `tests` выполнить `lua run.lua`.
- Проверки watcher и протокола с имитацией bridge: из `tools/forge-live` выполнить `npm test`. Пакет на реальном проекте без записи/команд игре: `node tools/forge-live/cli/forge-live.mjs --mod CookItForMe --dry --once 42/media/lua/shared/CookItForMe_FoodLogic.lua`.
- Архитектура: [ARCHITECTURE.md](ARCHITECTURE.md).
- После установки архитектурного рефакторинга с новыми Lua-модулями полностью перезапустить игру; hot reload старой монолитной версии недостаточен.

- Игровые ошибки: `%USERPROFILE%\Zomboid\console.txt`.
- Разовая полная синхронизация и offline-тесты: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev.ps1 -Mod cook-it-for-me`.
- Публикация: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\publish_workshop.ps1 -Mod cook-it-for-me`.

`Forge Live Bridge` — локальный инструмент разработки; в Workshop-релиз мода он не входит.

## Проверка скачанной Workshop-версии

Не включать авторскую staging-копию и Steam-копию с одним `id=CookItForMe` одновременно.
После подписки и завершения загрузки выполнить:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_workshop_distribution.ps1 -Mod cook-it-for-me -Start -Launch
```

Скрипт требует закрытую игру и остановленный `tools\watch.cmd`, переносит авторскую
копию из `Zomboid\Workshop` в обратимый backup и убеждается, что Steam скачал item
`3801601464`. Тестировать в отдельном тестовом сохранении. Вернуть разработку:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_workshop_distribution.ps1 -Mod cook-it-for-me -Stop
```

Пока режим активен, `dev.ps1` откажется синхронизировать staging. Статус:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\test_workshop_distribution.ps1 -Mod cook-it-for-me
```
