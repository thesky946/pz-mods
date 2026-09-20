# Reliability Vertical Slice

Дата: 2026-09-20
Статус: design review

## Цель

Снизить число дефектов в будущих агентских изменениях без массового рефакторинга production-кода. Первый этап должен доказать один сквозной путь: одинаковый сценарий проверяется детерминированно offline и внутри установленного Project Zomboid, а результат сохраняется как проверяемое evidence.

## Критерии успеха

1. Существующие production Lua-файлы сохраняют поведение и публичные точки входа.
2. Все текущие проверки продолжают проходить.
3. Offline runner воспроизводит полный минимальный lifecycle timed action: отказ до старта, запуск, completion, perform, stop и force-cancel до старта.
4. Три критических Cook-сценария могут исполняться внутри реального PZ и возвращают машинно читаемый результат.
5. Для каждого сценария явно разделены offline, in-game и manual статусы.
6. Gameplay gate обнаруживает неизвестный drift критических vanilla-контрактов установленного build.

## Не входит в этап

- поддержка Cook в multiplayer;
- автоматизация мыши и клавиатуры;
- полноценный dedicated-server lab;
- рефакторинг всех production-модулей;
- универсальная система миграций сохранений;
- полное покрытие ATA и MMA внутриигровыми сценариями;
- публикация Workshop.

## Архитектура

```text
Cook scenario definitions
       |                |
       v                v
offline lifecycle   in-game Cook test adapter
simulator            inside PzModsTestHarness
       |                |
       +-------+--------+
               v
       normalized evidence
               v
      validation Markdown/JSON
```

Scenario definition описывает идентификатор, setup, действие и наблюдаемые постусловия. Offline и in-game adapters не обязаны использовать одинаковый setup-код: они обязаны выдавать одинаковый набор нормализованных наблюдений и проверять одинаковые инварианты.

## Компонент 1: минимальный lifecycle simulator

### Граница

Simulator расширяет test support `cook-it-for-me`; он не становится новым runtime framework и не подключается в Workshop payload.

### Модель action

Поддерживаемые фазы:

```text
queued
  -> rejected-before-start
  -> force-cancelled-before-start
  -> started -> updating -> completed -> performed
  -> started -> invalidated -> stopped
  -> started -> vanished/stalled
```

Scheduler использует виртуальное время и явную очередь событий. Тест выбирает исход через fault configuration, а не вызывает callback вручную в произвольном месте.

### Минимальные faults

- `rejectBeforeStart`;
- `invalidateDuringUpdate`;
- `forceCancelBeforeStart`;
- `vanishAfterStart`;
- `duplicateCallback`;
- `staleCallbackAfterSession`;
- `destinationBecomesFull`;
- `itemDisappears`;
- `replacementObject`.

### Инварианты

- предмет не находится одновременно в двух местах;
- consume/replace учитывается явно;
- effect не выполняется повторно;
- terminal session не принимает callback;
- следующий шаг не начинается без постусловия предыдущего;
- мод не оставляет включённую им плиту без контроля;
- заранее включённая плита не выключается при чужом failure path.

### Совместимость

Существующие pure tests остаются быстрыми. Текущий `Env.new()` сохраняется как facade либо получает совместимый adapter, чтобы перенос тестов был постепенным.

## Компонент 2: dev-only in-game Cook harness

### Упаковка

Harness живёт под `tools/` как отдельный мод с отдельным ID. Общие Workshop build scripts не включают его в payload пользовательских модов.

### Управление

Harness принимает только allowlisted scenario ID через существующий file bridge Forge Live или отдельный узкий mailbox. Arbitrary Lua/code execution не добавляется.

### Первый набор сценариев

1. `cook.transfer.container.success`
   - предмет реально находится в исходном контейнере;
   - запускается vanilla transfer action;
   - проверяется исходный и целевой контейнер.

2. `cook.recipe.replacement.success`
   - создаётся совместимая посуда и ингредиент;
   - используется текущий Cook execution boundary;
   - проверяется возможная смена object identity, `fullType`, контейнер и consume effect.

3. `cook.stove.ownership.success`
   - блюдо ставится в реальную плиту;
   - проверяется включение модом, прогресс/готовность, выключение и возврат блюда;
   - отдельная вариация проверяет заранее включённую плиту.

### Результат

Каждый запуск пишет JSONL-запись:

```json
{
  "schema": 1,
  "scenario": "cook.transfer.container.success",
  "status": "pass",
  "gameBuild": "42.20.4",
  "modRevision": "...",
  "observed": {},
  "failures": []
}
```

PASS вычисляется внутри игры из фактического состояния. `RELOAD ACK` не является результатом сценария.

### Безопасность fixture

- Harness работает только при явной test/debug настройке.
- Все создаваемые сущности маркируются run ID.
- Cleanup удаляет только сущности текущего run ID.
- По умолчанию используется отдельное тестовое сохранение.
- Timeout завершает сценарий как failure и сохраняет наблюдаемое состояние.

## Компонент 3: scenario registry и evidence

### Источник истины

Создаётся `mods/cook-it-for-me/tests/REGRESSION.md`, на который уже ссылается `CODEX.md`. Он содержит стабильные scenario IDs, setup, action и expected state.

Машинная часть хранится рядом в компактном manifest. Markdown может проверяться truth-test-ом против manifest, чтобы список сценариев не расходился.

### Статусы

Для каждого scenario ID фиксируются отдельно:

- `offline`: pass/fail/not-run;
- `inGameSp`: pass/fail/not-run;
- `inGameMp`: pass/fail/not-applicable/not-run;
- `packaged`: pass/fail/not-run;
- `manual`: required/not-required/confirmed.

Generated evidence не подменяет историю: коммитится небольшой последний подтверждённый report без временных абсолютных путей и персональных данных. Полные runtime logs остаются локальными.

### Агентский итог

Инструмент формирует разделы:

- изменено;
- static/unit/simulator;
- PZ SP;
- PZ MP;
- packaged build;
- осталось проверить владельцу;
- известные ограничения.

Окончательную завершённость определяет владелец репозитория.

## Компонент 4: build/API drift gate

### Fingerprint

Локальный инструмент определяет:

- версию игры и Steam build;
- hashes выбранных vanilla Lua-файлов;
- наличие ожидаемых функций/phases;
- Umbrella commit/version.

Первый contract set:

- `ISBaseTimedAction.lua`;
- `ISTimedActionQueue.lua`;
- `ISInventoryTransferAction.lua`;
- `ISGrabItemAction.lua`;
- `ISAddItemInRecipe.lua`;
- API `ItemContainer` и `InventoryItem`, используемый Cook.

### Policy

- Известный fingerprint разрешает gameplay tests.
- Неизвестный drift не утверждает несовместимость, но блокирует подтверждение gameplay contract до review.
- CI без установленной игры проверяет формат snapshot и consistency; оно не притворяется проверкой vanilla build.
- Vanilla source не коммитится. Коммитятся hashes, относительные пути, ожидаемые символы и обоснование контракта.

## Изменения gate и документации

`tools/check.ps1` получает opt-in проверку simulator и consistency, не требующую запущенной игры. In-game запуск остаётся отдельной командой, потому что обычный CI не имеет PZ.

Новые статические warnings блокируют проверку. Подтверждённый false positive разрешается точечным baseline с файлом, правилом и объяснением; глобальное разрешение warnings запрещено.

`new-mod.ps1` в этом этапе меняется минимально:

- создаёт `tests/REGRESSION.md`;
- объявляет `support = SP|MP|both|content-only`;
- создаёт manifest одного smoke scenario;
- README разделяет offline и in-game validation.

Полные profile-specific scaffolds остаются будущим этапом.

## Обратная совместимость и rollout

1. Добавить новые инструменты без подключения к production Lua.
2. Подключить offline Cook scenario и доказать red/green lifecycle faults.
3. Подключить in-game transfer scenario.
4. Только после совпадения наблюдений добавить recipe и stove scenarios.
5. Сделать simulator/consistency обязательной частью `check.ps1`.
6. Расширить `new-mod.ps1`.

Production changes допускаются только как узкие test seams, если текущие публичные точки не позволяют запустить сценарий. Такой seam не должен менять обычный runtime path.

## Обработка ошибок

- Любой неизвестный scenario ID отклоняется.
- Повторная команда с тем же run ID не запускает расходующий сценарий повторно.
- Stale result не принимается за результат нового запуска.
- Timeout записывает failure, observed state и cleanup status.
- Ошибка cleanup не скрывается и не превращает запуск в PASS.
- Отсутствующая игра/bridge даёт `not-run`, а не PASS.

## Проверка этапа

- Все существующие `tools/check.ps1 -Mod ...`.
- Red/green tests каждой simulator phase и fault.
- Truth-test registry/Markdown/evidence schema.
- Snapshot parser tests без установленной игры через fixtures.
- Локальная contract проверка установленной PZ 42.20.4.
- Три in-game Cook scenario на отдельном test save.
- Проверка, что Workshop build не содержит harness.
- Финальный scoped Zomboid review с явным списком того, что подтверждено в игре.

## Риски

- Vanilla lifecycle может отличаться от simulator. Снижение риска: одинаковые observable assertions и in-game comparison.
- Harness может повредить save. Снижение риска: отдельный save, run ownership и узкий cleanup.
- Forge transport может дать ACK без результата. Снижение риска: независимый scenario result с correlation/run ID.
- Snapshot hashes могут давать шум после hotfix. Снижение риска: drift требует review, а не автоматически объявляет поломку.
- Расширение `check.ps1` может замедлить inner loop. Снижение риска: offline simulator остаётся детерминированным и быстрым; PZ не запускается обычным check.
