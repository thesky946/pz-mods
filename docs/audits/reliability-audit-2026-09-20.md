# Аудит надёжности `pz-mods`

Дата: 2026-09-20
Цель: определить, чего не хватает репозиторию, чтобы агентские изменения давали минимум дефектов и максимально близко воспроизводили реальные игровые действия Project Zomboid.

Связанное исследование игровых контрактов: [`../research/pz-mod-quality-practices.md`](../research/pz-mod-quality-practices.md).

## Вердикт

Репозиторий уже заметно сильнее типичного PZ mod-проекта: есть единый build/check pipeline, Lua 5.1, статический анализ, типы Umbrella, CI, воспроизводимая упаковка, Forge Live и хорошо проработанные failure-path тесты `cook-it-for-me`.

Но текущая формулировка в корневом README — «offline game-API mocks» — точнее реальности, чем желаемое слово «симуляция». Главный mock-файл сам честно говорит: `This is not a simulation of the game engine` (`mods/cook-it-for-me/tests/support/cook_env.lua:1`). Его очередь вызывает в основном `isValid -> perform -> callback` (`:236-245`) и не воспроизводит полный lifecycle Build 42: `isValidStart`, `waitToStart`, `start`, `update`, `complete`, `perform`, `stop`, `forceCancel`, stalled action и MP transaction.

Главный недостающий элемент — не ещё один prompt и не больше удобных моков. Нужна проверяемая цепочка:

```text
точный installed-build contract
    -> pure tests
    -> детерминированный lifecycle simulator
    -> dev-only in-game scenario runner
    -> SP test save
    -> MP dedicated-server lab
    -> packaged Workshop smoke test
    -> отчёт агенту и ручная оценка владельца
```

Без слоёв simulator + in-game runner агент может улучшать только собственную модель игры. Он не может доказать, что модель совпала с Java/Kahlua и текущим билдом PZ.

## Что было проверено

- Установленная версия: PZ **42.20.4**, Steam build `24909800`; источник версии и пути приведены в связанном исследовании.
- Выполнены `tools/check.ps1` для всех трёх модов.
- Выполнены тесты общих инструментов и Forge Live.
- Все проверки завершились успешно; `ata-bus-upgrade-b42` оставляет одно предупреждение статического анализатора.
- Изучены production Lua, mock environment, CI, `new-mod.ps1`, Forge Live, документация и установленный vanilla Lua/API.
- Игра во время аудита не была запущена. `tools/game-status.ps1 -Mod cook-it-for-me` сообщил `configuration-error`: в локальной Forge-конфигурации нет записи `CookItForMe`. Поэтому этот аудит не подтверждает игровое поведение модов.

## Сравнение с современной практикой

Steam показывает более 25 тысяч элементов с тегом Build 42, но рейтинг и подписчики не доказывают качество архитектуры. Большинство популярных Workshop-модов нельзя честно оценить изнутри без открытых исходников и воспроизводимого тестового процесса. Поэтому сравнение разделено:

- [Steam Workshop: Top Rated Build 42](https://steamcommunity.com/workshop/browse/?appid=108600&browsesort=toprated&requiredtags%5B%5D=Build+42) показывает востребованные функции и совместимость, но не инженерное качество.
- [Dihgg/zomboid-mod-template](https://github.com/Dihgg/zomboid-mod-template) даёт packaging, типы, deterministic Jest mocks, coverage и отдельные build/playtest/Workshop-команды.
- [rodmen07/auto-pilot-pz](https://github.com/rodmen07/auto-pilot-pz) использует state-machine разделение, telemetry, API guards, Lua/Python-тесты и truth-tests, связывающие документацию с кодом.
- [rk-gamemods/proximity-inventory](https://github.com/rk-gamemods/proximity-inventory) использует крупный offline-набор тестов и параметрические прогоны, но также прямо отделяет их от проверки внутри игры.
- Vanilla Build 42 остаётся главным образцом фактического lifecycle и authority, а не любой community repository.

`pz-mods` уже имеет большую часть базовых практик этих проектов. Его следующий качественный скачок — не смена Lua на TypeScript и не копирование чужого framework, а engine-aware проверка собственных контрактов.

## Оценка по слоям

| Область | Сейчас | Целевое состояние | Основной пробел |
| --- | --- | --- | --- |
| Статика и packaging | Сильно | Сильно | Новые warnings не блокируют gate |
| Pure/unit tests | Сильно у Cook, слабо у двух других | По риску мода | Нет общего стандарта покрытия поведения |
| Boundary mocks | Средне/сильно у Cook | Contract doubles | Mock-контракты не привязаны автоматически к vanilla build |
| Lifecycle simulation | Отсутствует | Детерминированный scheduler + fault injection | Текущий `drain()` слишком оптимистичен |
| In-game automation | Отсутствует | Dev-only scenario runner | Нет машинно проверяемых постусловий внутри PZ |
| SP regression | Ручные указания | Каталог сценариев + test save + evidence | Нет сохранённого результата проверки |
| MP regression | Только guards/Forge transport | Client/server lab | Нет проверки authority, reject, delay, reconnect |
| Save migrations | Ad-hoc defaults | Versioned fixtures/migrations | Нет общего schema contract |
| Agent workflow | Сильные инструкции | Инструкции, исполняемые gate-ами | Правила требуют больше, чем инструменты умеют проверить |
| Шаблон нового мода | Минимальный | Quality-ready scaffold | Создаёт только smoke assert по `ID` |

## Что сделано хорошо

### Корень репозитория

- `tools/check.ps1` централизует статический анализ, Lua-тесты, Forge Live tests и tooling tests.
- CI запускает gate для каждого мода на Windows с Lua 5.1 и pinned actions.
- `find-pz-api.ps1` ищет одновременно Umbrella, vanilla Lua и Java API.
- Build/Workshop staging отделён от исходников.
- Корневой `AGENTS.md:7-15` уже требует failing regression, реальных постусловий, исчезновения предмета, capacity, duplicate/stale callback и честного разделения offline/in-game доказательств.
- Forge Live правильно позиционируется как доставка кода, а не доказательство корректности.

### `cook-it-for-me`

- 13 production Lua-файлов, 14 test/support-файлов, около 1.9k production и 1.1k test lines.
- Слои planner/scanner/session/actions/executor разделены осмысленно.
- Есть единый terminal path, session guards, защита от duplicate/stale callback, ownership плиты, проверка фактического перемещения и защита от повторения расходующего `recipe:addItem()`.
- Тестируются отмена, исчезновение предмета, пол/сумки, capacity, заморозка, pause/speed, другая еда на плите, повторный callback и partial-consume exception.
- Мод честно отключён в multiplayer вместо фиктивной поддержки.

### `ata-bus-upgrade-b42`

- Runtime-модификация расположена на сервере.
- Повторный scan идемпотентен.
- Проверяются целевые vehicle scripts, сохранение engine quality/loudness и оба наблюдавшихся контракта коллекции (`iterator` и `size/get`).

### `mma-combat`

- Эксперимент явно помечен как `not production-ready` в `ANIMATION_STATUS.md`.
- Неудачные animation experiments и ограничения инструментов сохранены как доказательства, а не скрыты.

## Критические пробелы

### P0. Нет настоящего lifecycle simulator

`cook_env.lua` полезен как boundary mock, но его очередь синхронна и оптимистична. Она не моделирует:

- отказ `isValidStart` до запуска;
- различие `complete()` и `perform()`;
- `forceCancel` для ещё не стартовавшего действия;
- Java-action, исчезнувший из очереди;
- stalled action;
- MP transaction `done/rejected/timeout`;
- изменение мира между plan, start, complete и callback;
- повторный или устаревший callback при управляемом порядке событий.

Это особенно важно, потому что vanilla `ISAddItemInRecipe` выполняет мутацию в `complete()` и может вернуть новый объект блюда. Текущий production code сознательно вызывает `recipe:addItem()` напрямую (`CookItForMe_Actions.lua:178-216`), поэтому его безопасность зависит от точного наблюдения transfer/consume/replace границы.

Рекомендация: общий simulator в `tools/pz-sim/` или `tests/support/pz_sim/` с виртуальным временем, event queue, client/server replicas, item identity/location и fault injection. Сценарий должен задавать порядок событий, а не вручную вызывать `perform()` и callback.

### P0. Нет dev-only in-game scenario runner

В репозитории нет отдельного мода, который внутри PZ:

1. подготавливает test fixture в мире;
2. запускает тот же публичный путь мода;
3. ждёт реальный timed action;
4. проверяет фактические контейнеры, world objects, устройство и session state;
5. пишет машинно читаемый PASS/FAIL с build fingerprint;
6. восстанавливает test fixture.

Рекомендация: `tools/in-game-harness/mod/PzModsTestHarness`, исключённый из Workshop payload. Команды могут идти через безопасный Forge bridge, но результат должен вычисляться в игре, а не watcher-ом.

### P0. Нет каталога и журнала игровых доказательств

`mods/cook-it-for-me/CODEX.md:9` ссылается на отсутствующий `tests/REGRESSION.md`. Нет единого места с:

- ID сценария;
- точной версией PZ;
- fixture/save;
- setup/action/expected state;
- режимом SP/hosted/dedicated;
- датой последнего PASS;
- runtime revision и log excerpt;
- статусом packaged Workshop smoke test.

Из-за этого будущий агент не может отличить реально подтверждённый контракт от хорошо написанного предположения.

Рекомендация: versioned scenario manifests плюс generated evidence JSON/Markdown. Логи не должны считаться PASS без проверки состояния мира.

### P0. Нет автоматической привязки doubles к установленному build

Umbrella submodule закреплён на `42.20.0`, а установленная игра — `42.20.4`. `find-pz-api.ps1` помогает искать вручную, но `check.ps1` не проверяет, что используемые сигнатуры и mock contracts соответствуют установленному vanilla Lua.

Рекомендация:

- генерировать локальный build fingerprint;
- извлекать только контрактные метаданные: сигнатуры, методы, hashes и выбранные behavioral probes;
- хранить рядом с double ссылку на vanilla file/line и fingerprint;
- падать при drift затронутого контракта;
- не коммитить защищённый vanilla source.

## Высокоприоритетные пробелы

### P1. Gate не учитывает риск изменения

Сейчас один `check.ps1` одинаково относится к переводу, pure calculation и серверной мутации мира. Он не требует scenario update при изменении gameplay-файла и завершает проверку успешно при warning статического анализатора.

Нужны классы риска:

- `docs/assets`: syntax/package only;
- `pure logic`: unit + property/parameter tests;
- `game boundary`: contract simulation + installed API check;
- `persistent state`: migration fixtures;
- `MP/server`: client/server simulator + dedicated lab;
- `release`: packaged smoke.

Новый warning должен блокировать gate либо иметь точечное объяснённое suppress-правило. Текущий ATA warning нельзя просто игнорировать навсегда.

### P1. `new-mod.ps1` создаёт ложное ощущение готовности

Шаблон создаёт один shared module и один assert `mod.ID == ...` (`tools/new-mod.ps1:48`). Он не создаёт:

- архитектурный контракт;
- test matrix;
- fixtures;
- contract doubles;
- in-game scenarios;
- SP/MP declaration;
- persistence schema;
- evidence report;
- mod-specific agent instructions.

Рекомендация: scaffold должен требовать выбор профиля (`client-ui`, `sp-gameplay`, `server-authoritative`, `content-only`) и генерировать соответствующие gates. Пустой smoke-test не должен называться полноценным quality gate.

### P1. Нет multiplayer test lab

Forge Live умеет доставлять client/server Lua, но это не проверка gameplay authority. Нужен воспроизводимый dedicated-server профиль с тестовыми save/config, серверным scenario runner и клиентским probe.

Минимальные сценарии:

- accepted/rejected command;
- duplicate packet;
- stale session/step token;
- неизвестный item/container ID;
- disconnect/reconnect и resync;
- server state wins;
- два клиента конкурируют за один объект.

### P1. Persistence не имеет общего migration contract

`cook-it-for-me` безопасно нормализует простые настройки, но таблица `player:getModData().CookItForMe` не имеет `schemaVersion` (`CookItForMe_Shared.lua:26-41`). Для текущих UI-настроек риск невысок, но шаблон закрепляет ad-hoc подход для будущего сложного состояния.

Нужны fixture tests: new/current/old/malformed/repeated migration и явное правило ownership persistent data.

### P1. Package smoke test не унифицирован

Есть хороший `test_workshop_distribution.ps1`, но workflow ориентирован на `cook-it-for-me` и остаётся ручным. Для каждого публикуемого мода нужен generic smoke manifest, проверяющий именно собранную/скачанную копию без duplicate mod ID.

## Пробелы по модам

### `cook-it-for-me`

Статус: сильная offline-модель, но ещё не engine-level regression system.

Не хватает:

- полного timed-action lifecycle simulator;
- реального in-game runner для пола, сумок, воды, replacement pot, stove ownership, pause/speed и cancellation;
- versioned scenario/evidence каталога;
- build-pinned contract tests для `ISInventoryTransferAction`, `ISGrabItemAction`, `ISTakeWaterAction`, `RecipeManager` и `ItemContainer`;
- save fixture для настроек;
- автоматической проверки, что direct `recipe:addItem()` workaround по-прежнему нужен и корректен на текущем build.

### `ata-bus-upgrade-b42`

Статус: хорошие pure/idempotency tests, слабое доказательство server runtime.

Не хватает:

- теста загрузки `ATABusUpgradeB42_Server.lua`, регистрации `Events.OnTick` и интервала 300 ticks;
- installed-build probe реальных `setEngineFeature`, `setMaxSpeed`, `transmitEngine`;
- dedicated-server проверки, что клиент действительно получает обновление;
- сценария existing vehicle/newly loaded vehicle/two clients/reconnect;
- устранения или точечного suppress текущего analyzer warning.

### `mma-combat`

Статус: исследовательский asset prototype, не gameplay implementation.

Текущие тесты проверяют несколько констант и строки в `.X`; они не проверяют hit resolution, range, stamina, knockdown, animation selection или authority. README утверждает, что vanilla server path «resolves damage in both SP and MP», тогда как `ANIMATION_STATUS.md:15-17` честно говорит, что это не проверено ни в SP, ни в MP.

До продолжения разработки нужны:

- truth-test или единая status metadata, исключающая противоречивые заявления;
- in-game animation probe;
- SP hit/damage/range scenarios;
- dedicated MP authority scenarios;
- проверка конфликта глобального override `Base.BareHands` с другими модами.

### Forge Live

Статус: сильный dev-loop и один из лучших компонентов репозитория.

Ограничение: Forge Live доказывает доставку/reload, а не корректность gameplay. Его следует использовать как transport для in-game harness, не превращать ACK в test result.

## Целевая тестовая архитектура

### 1. Scenario DSL

Один сценарий описывается один раз:

```lua
scenario {
    id = "cook.transfer.floor.cancel_before_start",
    modes = { "sim", "game-sp" },
    setup = function(world) ... end,
    act = function(world) ... end,
    faults = { "force_cancel_before_start" },
    expect = function(world)
        invariant.itemConserved(...)
        invariant.sessionTerminal(...)
        invariant.stoveOwnershipPreserved(...)
    end,
}
```

Adapters выполняют его в simulator и in-game harness. Не все unit tests должны работать в игре, но критические scenario IDs должны иметь оба режима.

### 2. Детерминированный simulator

Обязательное состояние:

- virtual clock и event scheduler;
- player/action queue;
- item identity, fullType, container/world location;
- nested containers, permissions, capacity и item-count limit;
- consume/replace effects;
- stove power/heat/ownership;
- client/server replicas и transaction states;
- persistent data/schema version.

Обязательные faults перечислены в связанном исследовании: reject, stop, forceCancel, vanish, full destination, duplicate/stale callback, transaction reject/timeout, pause/speed, replacement identity, reconnect/resync.

### 3. In-game harness

Dev-мод должен:

- запускаться только при явной debug/test настройке;
- иметь allowlist сценариев, без arbitrary code protocol;
- писать JSONL или другой простой машинно читаемый результат;
- включать build, mod revision, scenario ID, observed state и failure reason;
- очищать только созданные им fixtures;
- никогда не попадать в Workshop content.

### 4. Evidence report

После задачи агент выдаёт:

```text
Изменено
Проверено static/unit/simulator
Проверено внутри PZ SP
Проверено внутри PZ MP
Проверено packaged build
Осталось проверить владельцу
Известные ограничения
```

Окончательное решение о завершённости остаётся за владельцем репозитория. Агент обязан выполнить все доступные ему автоматические и игровые проверки, но не подменять ручную оценку заявлением «багов нет».

## Приоритетный план

### Этап 0 — исправить truth layer

1. Создать реальный `tests/REGRESSION.md` или убрать битую ссылку.
2. Устранить противоречие README/ANIMATION_STATUS у MMA Combat.
3. Ввести единый build fingerprint и `last verified in game` metadata.
4. Сделать новые analyzer warnings blocking с точечным baseline для известного false positive.

Результат: агент знает, чему можно доверять уже сейчас.

### Этап 1 — scenario manifests и evidence

1. Зафиксировать критические сценарии каждого мода.
2. Ввести stable scenario IDs.
3. Генерировать validation report из результатов gate-ов.
4. Добавить truth-tests для документации, списка модулей, версий и заявленной поддержки SP/MP.

Результат: требования становятся исполняемыми и не теряются между prompt-ами.

### Этап 2 — общий lifecycle simulator

1. Реализовать state store и virtual scheduler.
2. Смоделировать vanilla action phases и queue reset.
3. Добавить inventory/world/container/replace invariants.
4. Добавить deterministic fault matrix.
5. Перенести критические тесты Cook на scenario DSL, сохранив быстрые pure tests.

Результат: агент воспроизводит race/failure paths, а не только happy callback.

### Этап 3 — dev-only in-game harness

1. Создать отдельный test mod.
2. Подключить Forge Live как transport.
3. Реализовать SP fixtures и postcondition probes.
4. Добавить test save и команды запуска выбранного scenario ID.
5. Сопоставлять simulator и game outcomes.

Результат: расхождения mock/game обнаруживаются до ручного playtest.

### Этап 4 — multiplayer lab

1. Версионированный dedicated config и test save.
2. Server/client probes и correlation IDs.
3. Fault scenarios для delay/reject/duplicate/reconnect.
4. Первый полный набор для ATA; Cook остаётся явно SP, пока не появится server-authoritative design.

Результат: надпись MP опирается на проверку, а не на расположение файла в `server/`.

### Этап 5 — новый universal scaffold

1. Расширить `new-mod.ps1` профилями риска.
2. Генерировать test/scenario/evidence skeleton.
3. Включить simulator и harness adapters.
4. Добавить generic packaged smoke workflow.
5. Подключить policy checks в CI.

Результат: новый мод не начинает жизнь с одного `assert(ID)`.

## Что изменить в будущих prompt-инструкциях

Текущий `AGENTS.md` уже хорош и не нуждается в полном переписывании. После появления инструментов ему не хватает четырёх обязательных правил:

1. Классифицировать риск затронутых файлов и запускать соответствующий gate.
2. Для gameplay boundary указывать конкретный installed vanilla contract и build fingerprint.
3. Добавлять/обновлять stable scenario ID, а не только произвольный test function.
4. При наличии in-game harness запускать его; если игра недоступна — готовить точный сценарий владельцу и помечать результат `готово к ручной проверке`, а не `подтверждено в игре`.

Просто сделать prompt длиннее без simulator/harness почти бесполезно: агент будет подробнее описывать те же непроверенные предположения.

## Рекомендуемый первый практический шаг

Не начинать с MP и не строить огромный framework сразу. Первый вертикальный срез:

1. сценарий Cook «перенос кастрюли из контейнера»;
2. success, reject-before-start, cancel, disappear, full destination, duplicate callback;
3. один и тот же scenario ID в simulator и dev-only in-game harness;
4. проверка conservation, container identity и terminal session state;
5. generated evidence report.

Если этот срез работает, архитектуру можно расширять на воду, `recipe:addItem`, плиту, ATA server scan и затем MP. Если он не работает, масштабирование framework только размножит неверную модель.

## Итог

Репозиторию не не хватает «профессиональности» в целом. Базовая дисциплина уже сильная. Ему не хватает последнего и самого дорогого слоя: исполняемого соответствия между mock-моделью, установленным vanilla contract и фактическим состоянием мира в SP/MP.

Приоритет: **scenario truth layer -> lifecycle simulator -> in-game harness -> MP lab -> новый scaffold**.
