# Надёжная разработка модов Project Zomboid Build 42.x

Дата среза: 2026-09-20. Целевая установленная версия: **42.20.4 (`b0bbce05d5`)**, Steam build `24909800`.

Этот документ описывает проверенные контракты игры и выводы для разработки модов с минимальным числом дефектов. Он намеренно **не оценивает текущую реализацию модов в репозитории**.

## Короткий вывод

Надёжный PZ-мод нельзя тестировать как набор синхронных Lua-функций с успешными callback. В Build 42 игровое действие — это изменяемое во времени состояние: оно может не стартовать, потерять предмет или контейнер, быть отменено, получить отказ MP-транзакции, заменить один объект предмета другим, завершиться повторным или уже устаревшим callback.

Практический стандарт качества:

1. сверять API с **установленной** версией игры и её vanilla Lua;
2. отделять UI/планирование от игрового исполнения и серверной авторитетности;
3. моделировать полный lifecycle timed action, контейнеры и сетевые подтверждения;
4. проверять постусловие в игровом состоянии после каждого шага, а не факт вызова callback;
5. иметь тесты сохранений и миграций;
6. завершать автоматическую проверку сценариями в реально запущенной игре, потому что mocks и hot reload не доказывают совместимость с движком.

## Иерархия источников

В порядке доверия для конкретного установленного билда:

1. установленный `projectzomboid.jar` и vanilla Lua;
2. сгенерированная документация API той же версии;
3. официальные материалы The Indie Stone;
4. исходники открытых модов и шаблонов — только как примеры инженерных приёмов, не как спецификация игры.

Факт версии зафиксирован в `C:\Users\User\Zomboid\console.txt:59`; Steam build — в `D:\steam\steamapps\appmanifest_108600.acf`. Корень актуальной сгенерированной документации также обозначен как [PZ API Documentation 42.20.4](https://pz-wiki-modding.github.io/PZ-API-Docs/). Официальный релиз 42.20: [Project Zomboid Build 42.20 Released](https://projectzomboid.com/blog/news/2026/07/project-zomboid-build-42-20-released/).

## Проверенные факты

### 1. Разделение `client` / `shared` / `server` имеет поведенческий смысл

**Факт.** Vanilla содержит отдельные деревья `media/lua/client`, `media/lua/shared` и `media/lua/server`. Клиентский интерфейс печи посылает команду, а фактическое изменение печи принимает сервер:

- клиент: `D:\steam\steamapps\common\ProjectZomboid\media\lua\client\ISUI\Fireplace\ISOvenUI.lua:157-170`;
- сервер: `D:\steam\steamapps\common\ProjectZomboid\media\lua\server\ClientCommands.lua:1048-1061`.

**Факт.** `sendClientCommand` вызывает `OnClientCommand` на сервере и ничего не делает при вызове на сервере. `sendServerCommand` работает в обратную сторону. Через аргументы гарантированно проходят только простые сериализуемые значения; сложные объекты надо передавать как идентификаторы и заново разрешать на принимающей стороне. Источник: [`LuaManager.GlobalObject.sendClientCommand`](https://albion.codeberg.page/PZ-JavaDocs/zombie/Lua/LuaManager.GlobalObject.html#sendClientCommand(java.lang.String,java.lang.String,se.krka.kahlua.vm.KahluaTable)).

**Вывод.** Разумная граница такова:

- `client`: UI, ввод игрока, локальная очередь действий, отображение прогресса;
- `shared`: чистые определения, DTO/валидация формата, расчёты без владения миром;
- `server`: повторное разрешение ID, проверка текущего состояния и авторитетная мутация мира в MP.

Клиентский запрос не является доказательством права или возможности выполнить действие. Даже vanilla-обработчики различаются по строгости, поэтому их наличие нельзя принимать за готовую модель безопасности.

### 2. Timed action — полноценный lifecycle

**Факт.** Базовый класс различает как минимум `isValidStart`, `isValid`, `waitToStart`, `start`, `update`, `complete`, `stop`, `forceCancel` и `perform`. `forceCancel` отдельно предназначен для действия, удалённого из очереди до старта. `perform` продвигает очередь, а `stop` сбрасывает её. Источники:

- `D:\steam\steamapps\common\ProjectZomboid\media\lua\shared\TimedActions\ISBaseTimedAction.lua:8-89`;
- [`LuaTimedActionNew`](https://albion.codeberg.page/PZ-JavaDocs/zombie/characters/CharacterTimedActions/LuaTimedActionNew.html).

**Факт.** Очередь:

- запускает первое действие немедленно;
- перед запуском следующего повторно вызывает `isValidStart`;
- вызывает `forceCancel` для ещё не стартовавших действий при очистке;
- сбрасывается, если Java-action исчез или очередь стала неконсистентной;
- отдельно обрабатывает stalled action.

Источник: `D:\steam\steamapps\common\ProjectZomboid\media\lua\client\TimedActions\ISTimedActionQueue.lua:9-17,46-57,60-105,107-130`.

**Факт.** Авторитетная мутация может происходить в `complete()`, а `perform()` заниматься только UI и продвижением очереди. При добавлении ингредиента `recipe:addItem(...)` вызывается в `complete()`, и результат заново присваивается `self.baseItem`, потому что блюдо может стать **новым объектом**. Источник: `D:\steam\steamapps\common\ProjectZomboid\media\lua\shared\TimedActions\ISAddItemInRecipe.lua:55-87`.

**Вывод.** Тест, который вызывает только `perform()` либо немедленно вызывает callback, не воспроизводит контракт Build 42. Минимальный автомат должен уметь провести действие по всем переходам:

```text
planned -> rejected-before-start
planned -> queued -> force-cancelled-before-start
planned -> started -> updating -> completed -> performed
planned -> started -> invalidated -> stopped
planned -> started -> transaction-rejected -> stopped
planned -> started -> stalled/vanished -> queue-reset
completed -> duplicate-or-stale-callback
```

### 3. Перемещение предмета не гарантировано

**Факт.** Vanilla `ISInventoryTransferAction:isValid()` проверяет одновременно:

- существование предмета и обоих контейнеров;
- не был ли предмет уже поглощён крафтом;
- находится ли конкретный объект в исходном контейнере;
- согласована ли MP-транзакция;
- серверный лимит числа предметов;
- вместимость пола или `hasRoomFor(character, item)`;
- разрешение вынуть и вставить предмет;
- вложенность контейнеров и доступность источника.

Источник: `D:\steam\steamapps\common\ProjectZomboid\media\lua\client\TimedActions\ISInventoryTransferAction.lua:11-126`. API контейнера действительно разделяет `contains`, рекурсивные варианты, `hasRoomFor`, добавление и удаление: [`ItemContainer`](https://albion.codeberg.page/PZ-JavaDocs/zombie/inventory/ItemContainer.html).

**Факт.** В MP transfer создаёт item transaction и ждёт состояния done/rejected; отказ вызывает остановку. При отмене транзакция удаляется. Completion-callback вызывается лишь после конца обработанной пачки. Источник: тот же файл, строки `161-174,249-318,448-550`.

**Факт.** Подбор предмета с пола — отдельный сценарий. Перед завершением vanilla повторно проверяет, что world object ещё существует и в целевом контейнере есть место; предмет мог забрать другой игрок. В SP объект удаляется из мира до добавления `InventoryItem` в контейнер. Источник: `D:\steam\steamapps\common\ProjectZomboid\media\lua\client\TimedActions\ISGrabItemAction.lua:5-28,50-65,68-145`.

**Факт.** Короткий тип и полный тип — разные понятия; публичный API имеет `InventoryItem:getFullType()`: [`InventoryItem`](https://albion.codeberg.page/PZ-JavaDocs/zombie/inventory/InventoryItem.html#getFullType()).

**Вывод.** Корректное постусловие transfer — не «callback был вызван», а как минимум:

```text
destination:contains(the-resulting-object)
and not source:contains(the-original-object)
and world/conservation invariants hold
```

Для заменяемых предметов проверка должна разрешать новый object identity и проверять ожидаемый `fullType`, свойства и контейнер результата.

### 4. Multiplayer требует явной модели авторитетности

**Факт.** Vanilla использует `sendClientCommand` / `Events.OnClientCommand` и `sendServerCommand` / `Events.OnServerCommand` как явную границу. Центральный server dispatcher находится в `D:\steam\steamapps\common\ProjectZomboid\media\lua\server\ClientCommands.lua:1249-1260`. Foraging имеет парные клиентскую и серверную реализации:

- `D:\steam\steamapps\common\ProjectZomboid\media\lua\client\Foraging\forageClient.lua`;
- `D:\steam\steamapps\common\ProjectZomboid\media\lua\server\Foraging\forageServer.lua`.

**Факт.** Vanilla MP inventory transfer не перемещает предмет локально как в SP: клиент ждёт подтверждение item transaction. Источник: `ISInventoryTransferAction.lua:161-174,306-314,477-550,853-856`.

**Вывод.** В тестах нужны минимум три режима:

1. single-player;
2. клиентская реплика с задержанными/отклонёнными ответами;
3. серверная авторитетная реплика, повторно проверяющая фактическое состояние.

Нужны тесты на повтор пакета, неизвестный ID, подменённый контейнер, устаревшую ревизию сессии, расхождение клиента и сервера и ответ после завершения/отмены сессии.

### 5. Persistent ModData загружается и синхронизируется явно

**Факт.** `GlobalModData` предоставляет `getOrCreate`, `get`, `remove`, `save`, `load`, `request` и `transmit`: [`GlobalModData`](https://albion.codeberg.page/PZ-JavaDocs/zombie/world/moddata/GlobalModData.html).

**Факт.** Vanilla foraging получает таблицу через `ModData.getOrCreate` на сервере и явно вызывает `ModData.transmit`; клиент инициализируется через `Events.OnInitGlobalModData`:

- `D:\steam\steamapps\common\ProjectZomboid\media\lua\server\Foraging\forageServer.lua:26-49`;
- `D:\steam\steamapps\common\ProjectZomboid\media\lua\client\Foraging\forageClient.lua:5-12`.

**Факт.** `OnInitGlobalModData` сообщает `isNewGame`; vanilla использует это различие в `D:\steam\steamapps\common\ProjectZomboid\media\lua\server\Vehicles\ProfessionVehicles.lua:343-347`.

**Вывод.** Универсального автоматического механизма миграции схемы эти источники не показывают. Версионирование и миграция — ответственность мода. Надёжный формат хранит `schemaVersion`, мигрирует пошагово и идемпотентно, не стирает всю таблицу из-за одного плохого поля и не публикует частично мигрированное состояние.

Обязательные fixtures:

- новое сохранение;
- текущая схема;
- каждая поддерживаемая старая схема;
- повторный запуск той же миграции;
- отсутствующие поля;
- неизвестные новые поля;
- неверный тип/обрезанная таблица;
- загрузка без мода и повторное включение, если это поддерживается;
- серверная миграция и последующая синхронизация клиенту.

### 6. Hot reload ускоряет цикл, но не доказывает корректность

**Проверенный в этом репозитории факт.** `RELOAD ACK` подтверждает вызов `reloadLuaFile`, но не отсутствие предупреждений и не игровое постусловие. Уже созданные closures, active actions, UI instances и event registrations могут держать старый код. Изменения существующих Lua-модулей надо проверять в новой игровой сессии действия; структурные изменения требуют рестарта. Источник: `tools/forge-live/docs/KNOWN-LIMITS.md`, разделы «Local CookItForMe watcher changes» и «Event handlers».

**Проверенный в этом репозитории факт.** `.txt` scripts, `mod.info`, models и textures кэшируются при загрузке; для них reload Lua недостаточен. Новые/удалённые/переименованные Lua-модули watcher консервативно требует применять после полного рестарта. Источник: `tools/forge-live/docs/KNOWN-LIMITS.md`, раздел «Hard engine limits».

**Проверенный в этом репозитории факт.** Абсолютный путь reload обновлял используемый require-cache, тогда как относительный мог оставить старое cached return value. Источник: `mods/cook-it-for-me/DEVELOPMENT.md`, раздел «Цикл Lua-разработки».

**Вывод.** Успешный reload — только подтверждение доставки кода. После него нужны:

- свежая строка версии/ревизии в `console.txt`;
- отсутствие новых Lua/Java warnings и errors;
- новый запуск изменённого действия;
- проверка состояния мира после действия;
- рестарт при изменении структуры, регистрации событий, persist-state contract или ресурсов.

### 7. Обновления Build 42 могут менять контракт

**Факт.** The Indie Stone выпускала отдельный migration guide для новой системы identifiers/registries в 42.13: [официальный Modding Migration Guide](https://theindiestone.com/forums/topic/88499-modding-migration-guide-4213/). Официальные планы 42.20 предупреждали о несовместимости сохранений 42.19 с 42.20: [Build 42 Stable Plans](https://projectzomboid.com/blog/news/2026/07/build-42-stable-plans/).

**Вывод.** Зафиксированные сигнатуры и поведение надо привязывать к точной версии. Онлайн-документация другой минорной версии не должна автоматически менять mocks или ожидания тестов без проверки установленной игры.

## Что видно в открытых mod-проектах

Ниже не рейтинг «топовых» модов: надёжно измерить качество или популярность по первичным техническим источникам нельзя. Это только проверяемые примеры практик.

- [`Dihgg/zomboid-mod-template`](https://github.com/Dihgg/zomboid-mod-template) включает Build 42 packaging, типы, deterministic Jest mocks, тесты и отдельные build/playtest/Workshop-команды.
- [`rodmen07/auto-pilot-pz`](https://github.com/rodmen07/auto-pilot-pz) разделяет оркестрацию, state machine, inventory helpers и telemetry; его check запускает Lua/Python-тесты, а документация требует затем проверить поведение в мире. Отдельные truth-tests сверяют README/версию/порядок priority chain с кодом.

Полезный общий знаменатель этих примеров — не конкретный язык или framework, а воспроизводимый pipeline: один source of truth, автоматическая упаковка, API guards, детерминированные тесты и отдельный in-game playtest.

## Рекомендуемая архитектура низкобагового мода

Это инженерные выводы, а не утверждения об обязательном API игры.

```text
UI / intent capture (client)
        |
        v
pure planner ---------> immutable plan + preconditions
        |
        v
session state machine -> one step at a time -> effect adapter
        |                                      |
        |                                      +-> SP vanilla action
        |                                      +-> MP client command
        |                                      +-> deterministic simulator
        v
postcondition verifier -> next step / unified abort+cleanup
        |
        v
server authority + persistence (MP)
```

Ключевые свойства:

- план хранит стабильные ID и ожидаемые характеристики, а не доверяет долгоживущим ссылкам на mutable Java objects;
- каждый шаг имеет `precondition`, `start`, `observe`, `postcondition`, `compensation/cleanup`;
- session ID и monotonically increasing step token делают повторный или устаревший callback безвредным;
- переход состояния и выдача расходуемых эффектов имеют at-most-once guard;
- любой отказ идёт через единый terminal path;
- cleanup управляет только ресурсами, которыми владеет мод: не выключает заранее включённую игроком печь и не очищает чужие действия;
- после неизвестного результата расходующий шаг не повторяется автоматически;
- следующий шаг начинается только после наблюдаемого постусловия предыдущего.

## Спецификация симулятора игровых действий

### Модель состояния

Симулятор должен хранить:

- персонажа и его локальную очередь;
- мир/квадраты/world items;
- контейнеры с parent/source grid/capacity/permissions/nesting;
- предметы с `id`, `type`, `fullType`, object identity, container/world location, consumed/replaced flags;
- плиту/устройство: power, activation ownership, temperature, contents;
- клиентскую и серверную реплики;
- persistent ModData со schema version;
- виртуальное время и очередь событий/callback.

### Планировщик событий

Он должен позволять тесту выбирать порядок и исход:

- reject before start;
- start, затем предмет исчезает;
- destination заполняется после планирования;
- cancel до старта и во время update;
- transaction done/rejected/timeout;
- callback дважды;
- callback старого шага после начала нового;
- callback старой сессии после открытия нового окна;
- reconnect/resync с отличающимся серверным состоянием;
- pause/time acceleration;
- замена предмета новым объектом во время recipe/cooking.

### Contract doubles вместо удобных mocks

Mock должен повторять неприятные свойства vanilla:

- `AddItem`/transfer может не состояться;
- `contains(item)` и recursive search различаются;
- capacity и item-count limit — разные ограничения;
- floor/world transfer не равен container transfer;
- recipe может вернуть новый объект;
- callback completion не заменяет проверку результата;
- client command передаёт POD/ID, а не живой Lua/Java object;
- full type не равен short type;
- `complete()` и `perform()` — разные фазы;
- отмена до старта вызывает `forceCancel`, а не `stop`;
- MP-ответ может опоздать или повториться.

Чтобы mocks не дрейфовали, для каждого двойника нужен комментарий с конкретным vanilla-файлом/диапазоном строк и contract test, который обновляется только после сверки нового билда игры.

### Инварианты

После каждой transition, а не только в конце happy path, проверять:

- один физический предмет не находится одновременно в двух местах;
- количество не создаётся и не исчезает без объявленного consume/replace effect;
- расходующий effect применён не более одного раза;
- завершённая/отменённая сессия не принимает callbacks;
- активная сессия либо ждёт известное действие, либо завершена;
- следующая операция не стартует без постусловия предыдущей;
- мод не оставил включённое им устройство без контроля;
- мод не выключил устройство, которое было включено не им;
- failure path освобождает handlers/timers/ownership;
- серверное состояние побеждает клиентское при расхождении;
- повторная миграция сохранения не меняет уже мигрированный результат.

### Матрица сценариев на каждый изменённый шаг

Минимум:

| Ось | Сценарии |
|---|---|
| Lifecycle | успех; отказ до старта; stop; forceCancel; stalled/vanished |
| Предмет | в инвентаре; на полу; в сумке; исчез; заменён; consumed |
| Место | есть место; стало полно; запрещён item; nested container недоступен |
| Callback | один; повтор; задержан; после cancel; после новой сессии |
| Устройство | выключено; уже включено; без питания; нагревается; не нагревается |
| Время | normal; fast-forward; pause; timeout |
| Сеть | SP; client accepted; client rejected; packet duplicate; reconnect/resync |
| Save | new; current; old schema; malformed; migration repeated |

## Лестница проверки

1. **Static/API gate:** синтаксис, require, запрещённые/несуществующие API, packaging и case-sensitive paths.
2. **Pure unit tests:** planner, validation, state transitions, migrations.
3. **Contract simulation:** полный lifecycle и fault injection по матрице выше.
4. **Integration with installed vanilla contracts:** сигнатуры, item types, recipes, tags, конкретные Lua patterns текущего билда.
5. **In-game single-player:** наблюдаемые постусловия, отмена, пол/сумки, устройство, pause/fast-forward, повторное окно.
6. **In-game multiplayer:** минимум клиент + server authority; задержка/отказ/повтор/переподключение.
7. **Reload audit:** свежая runtime revision и лог, затем новое действие; restart-required изменения — после полного рестарта.
8. **Packaged Workshop smoke test:** именно скачанная сборка, отдельное сохранение, без второй копии того же mod ID.

Автотесты могут доказать, что модель согласована с записанным контрактом. Только игровые проверки подтверждают, что сам контракт не устарел и Java/Kahlua/сеть ведут себя так же.

## Контракт для будущего промпта агенту

Чтобы промпт давал меньше дефектов, он должен требовать не просто «реализуй фичу», а следующее:

```text
Перед изменением:
- зафиксируй точную версию PZ;
- найди vanilla Lua/Java API для затронутого действия;
- напиши failing test, который воспроизводит неверное игровое состояние.

При реализации:
- перечисли precondition/postcondition каждого шага;
- моделируй reject/cancel/disappearance/capacity/replacement/duplicate/stale callback;
- раздели client/shared/server authority;
- не считай callback доказательством успеха;
- не повторяй расходующий шаг после неизвестного результата;
- версионируй persistent state и миграцию.

Перед завершением:
- прогони static + unit + contract + packaging checks;
- укажи, что проверено в реальной игре отдельно от mocks;
- для MP укажи проверенные client/server сценарии;
- не делай вывод об отсутствии багов только по RELOAD ACK.
```

## Ограничения исследования

- «Топовость» модов не имеет технически надёжного первичного критерия; количество подписчиков не доказывает качество архитектуры.
- Сгенерированные JavaDocs и Lua docs полезны для сигнатур, но установленный билд остаётся источником истины при расхождении.
- Репозиторные выводы о Forge Live основаны на измерениях, явно ограниченных описанными режимами; они не доказывают семантику всех вариантов SP/MP.
- Документ задаёт практики и тестовую модель, но не является аудитом конкретного мода или текущего покрытия тестами.
