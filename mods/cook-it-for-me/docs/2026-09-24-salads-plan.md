# Salad Support Implementation Plan

> **For agentic workers:** Implement task by task with `superpowers:executing-plans`. Each behavior change starts with a failing test. The user requested this plan before the specification; the specification is the next artifact.

**Goal:** Add ordinary and fruit salads, using either vanilla bowl, to the existing single-player cooking planner and executor.

**Architecture:** Keep the current scanner, planner, session, and executor. Dish metadata decides whether a recipe needs heat, whether cooked ingredients may enter the candidate pool, and whether frozen ingredients are allowed. Both salad types finish after ingredient assembly; no user-facing frozen setting is added now. Keep the frozen-policy decision behind one catalog function so a future setting has one entry point.

**Tech Stack:** Project Zomboid 42.20.4 Lua 5.1, vanilla `EvolvedRecipe`/`RecipeManager`, existing offline Lua doubles and Forge Live.

**Spec:** `mods/cook-it-for-me/docs/2026-09-24-salads-spec.md` (created after this plan, as requested).

**Evidence:** `mods/cook-it-for-me/docs/vanilla-salads-b42.20.4.md` records installed-game scripts and API contracts.

## Global constraints

- Keep single-player-only execution and existing mod ID. Add no custom items or recipes.
- Right-click entry still requires a nearby stove; the configured key can open plans elsewhere.
- Support `Salad`, `SaladClay`, `FruitSalad`, `FruitSaladClay` vanilla recipes with `Base.Bowl` and `Base.ClayBowl`.
- A bowl containing any liquid must not be consumed. No salad step checks or changes a stove or sink.
- Cooked ingredients are eligible only where the selected vanilla recipe accepts their cooked state. Frozen ingredients are permitted for salads now and can thaw instantly through vanilla result creation; add no player setting yet.
- Hide the finish-cooking control on salad tabs, retaining its saved value for hot meals. Reuse general Cook and completion strings.
- Before any game sync or publication, run `tools/check.ps1 -Mod cook-it-for-me`. After translation edits, run `tools/reload-translations.ps1 -Mod cook-it-for-me` and verify ACK or report why it was unavailable.
- Tests must check resulting item/container and terminal session state, including refusal before consumption, cancellation, duplicate and stale callbacks. Mock success alone is insufficient for an in-game claim.

## File map

| File | Responsibility |
| --- | --- |
| `42/media/lua/shared/CookItForMe_Dishes.lua` | Add two dish definitions and central frozen policy; expose heat/cooked-ingredient flags. |
| `42/media/lua/shared/CookItForMe_Scanner.lua` | Admit cooked candidate food only for salad scans. |
| `42/media/lua/shared/CookItForMe_Planner.lua` | Choose exact salad recipe; validate empty bowl, ingredient state, resources and stale plan without heat checks. |
| `42/media/lua/shared/CookItForMe_Forecast.lua` | Preserve nutrition preview for cooked ingredients accepted by the salad recipe. |
| `42/media/lua/shared/CookItForMe_Actions.lua` | Recheck base and ingredient state before consuming; respect central frozen policy. |
| `42/media/lua/shared/CookItForMe_Executor.lua` | Complete no-heat salads after verifying the actual result in inventory. |
| `42/media/lua/client/CookItForMe_PlanUI.lua` | Hide finish toggle on salads, fit six dish tabs at minimum size. |
| `common/media/lua/shared/Translate/*/UI.json` | Names for two salads in all current languages. |
| `tests/test_catalog.lua`, `test_scanner.lua`, `test_cook.lua`, `test_plan_edit.lua`, `test_ui.lua`, `test_reliability.lua` and `tests/support/cook_env.lua` | Focused red-green coverage with a mock that replaces the bowl on first `addItem`. |
| `README.md`, `ARCHITECTURE.md`, `CODEX.md`, `tests/REGRESSION.md` | User-facing capabilities, contract, and in-game scenario. |

## Review focus

1. Fluid-filled bowl: planner and action must refuse it before `addItem`, preserving bowl and liquid.
2. Raw `|Cooked` ingredient: candidate and edited plan must reject it; the cooked version must work.
3. First addition replaces bowl: all later additions and final result must follow the returned object.
4. Frozen salad ingredient: accepted without a heat step; policy is centralized and recipe override restored on error.
5. Six tabs at the smallest supported window: all tabs visible and above the footer.

## Task 1: Catalog and candidate collection

**Interfaces:** `Catalog.DISHES[key].needsHeat`, `.allowCookedIngredients`; `Catalog.allowsFrozen(dish, settings) -> boolean`; `Scanner.collectFood(player, scan, includeCooked) -> collected`.

- [ ] Add failing catalog tests for both labels, both bowl types, recipe matching against `Make Salad` / `Make Fruit Salad`, ordering and no duplicate tabs. Run `lua test_catalog.lua` from `tests/`; expect missing dishes.
- [ ] Add failing scanner test: cooked food is excluded by default and included when `includeCooked == true`. Run `lua test_scanner.lua`; expect cooked item absent.
- [ ] Add definitions and one frozen-policy function in `Dishes.lua`, with `needsHeat=false` and `allowCookedIngredients=true` for salads. Default hot dishes to heat when the field is absent. Do not add ModData or UI settings.
- [ ] Add optional `includeCooked` argument to `Scanner.collectFood`; continue excluding rotten, burnt, composite food and non-food in both modes. Run both focused tests; expect pass.

## Task 2: Planning and validation

**Interfaces:** `Planner.plan(player, dishKey) -> plan | nil, failKey`; `Planner.validate(player, plan) -> boolean, failKey`; `plan.needsHeat` is a snapshotted boolean, independent of later global setting changes.

- [ ] Add failing tests for a dry bowl plan without stove or sink even when `finishCooking=true`, and for rejection of a wet bowl without consuming it. Run `lua test_cook.lua`; expect no plan / wrong failure.
- [ ] Add failing tests for cooked `|Cooked` items, raw rejection, incompatible ingredients, stale bowl fluid change, and available alternative rows. Run `lua test_plan_edit.lua` and `lua test_cook.lua`; expect incorrect candidates or validation.
- [ ] Select dish before collection, pass `dish.allowCookedIngredients` to scanner, and compute `plan.needsHeat = settings.finishCooking and dish.needsHeat ~= false`. Use it for all stove scan/validation branches. Keep hot-meal behavior unchanged.
- [ ] Match salad recipes by exact selected name and result/base pair from installed B42 scripts. For salad bowls, require `getFluidContainer():isEmpty()` at planning and pre-start validation; provide a specific `NoEmptyBowl` failure.
- [ ] For salads, combine recipe metadata, `recipe:needToBeCooked(item)`, ordinary item state and central frozen policy in initial pick, alternatives and validation. Preserve existing hot-meal filtering. Run focused suites to green.

## Task 3: Execution and lifecycle

**Interfaces:** `Actions.add(...)` keeps the returned result object in `session.pot`; `Executor` uses `plan.needsHeat` and verifies the final salad item before terminal success.

- [ ] Add failing salad execution tests for ordinary and fruit bowls, replacement on first addition, frozen and cooked ingredients, no stove/sink calls, result in inventory, one completion sound and terminal success. Run `lua test_cook.lua`; expect heating or state mismatch.
- [ ] Add failing tests for wet bowl immediately before first ingredient, a raw `|Cooked` item after transfer, full inventory/failed transfer, vanished item, cancellation, repeated callback and callback after finish. Assert no consumed ingredient after pre-start refusals and no abandoned session. Run `lua test_reliability.lua`; expect wrong outcome.
- [ ] In `Actions.add`, recheck bowl and salad ingredient state before `addItem`; pass the frozen decision through one helper and restore recipe state after error. Never retry `addItem` after an unknown result.
- [ ] In `Executor`, branch on `plan.needsHeat`: hot dishes retain stove path; salads verify `addedCount > 0`, exact tracked result, expected recipe result type, and player inventory ownership, then finish successfully. Preserve the existing preparation-only path for hot dishes.
- [ ] Run `lua test_cook.lua`, `lua test_reliability.lua`, `lua test_session.lua`; expect pass.

## Task 4: UI and translations

- [ ] Add failing UI tests: six tab cards stay above the footer at 560×460, salad hides finish toggle without modifying persisted value, returning to soup shows it again. Run `lua test_ui.lua`; expect overflow or visible toggle.
- [ ] Update salad-tab layout and visibility in `PlanUI.lua`; keep general button/completion wording.
- [ ] Add translated dish labels for EN, RU, ES, PTBR, CN, FR, TR and DE. Run project translation validation through `tools/check.ps1 -Mod cook-it-for-me`.

## Task 5: Verification and game handoff

- [ ] Update README support table, architecture policy description, CODEX capability summary and `tests/REGRESSION.md` with explicit in-game cases: both salads/bowls; cooked/raw and frozen ingredients; wet bowl; no stove; other food on running stove; cancellation; missing/changed item; reopen window; pause and time acceleration.
- [ ] Run `powershell -NoProfile -ExecutionPolicy Bypass -File tools/check.ps1 -Mod cook-it-for-me`; fix concrete failures, then rerun once.
- [ ] Review the diff against `zomboid-review`, inspect installed API calls, line endings and console errors. Run `tools/reload-translations.ps1 -Mod cook-it-for-me` after JSON edits; report ACK and any restart requirement precisely.
- [ ] If a playable game session is available, execute the regression scenario and inspect actual dish ownership/food state and `console.txt`. State explicitly which game cases remain unverified.
- [ ] Do not publish to Steam without a new explicit release request.
