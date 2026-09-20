# Reliability Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a low-risk reliability vertical slice that runs stable Cook scenarios through a deterministic timed-action simulator and a dev-only Project Zomboid harness, records evidence, and detects drift in installed vanilla contracts.

**Architecture:** Scenario metadata is the shared source of truth. Offline tests use a Lua 5.1 virtual scheduler; the real game uses a separate allowlisted test mod and mailbox. Both produce normalized scenario results, while PowerShell tooling validates installed-build fingerprints and generates a concise evidence report.

**Tech Stack:** Lua 5.1/Kahlua, PowerShell 7/Windows PowerShell, Node.js built-in test runner where Forge integration is touched, Project Zomboid Build 42.20.4 vanilla Lua/API.

**Spec:** `docs/specs/2026-09-20-reliability-vertical-slice-design.md`

## Global Constraints

- Do not change normal `cook-it-for-me` gameplay behavior or public entrypoints unless a narrowly scoped test seam is proven necessary.
- The harness uses a separate mod ID and never enters a Workshop payload.
- No arbitrary Lua/code execution channel; only allowlisted scenario IDs are accepted.
- `RELOAD ACK` is transport evidence, never a scenario PASS.
- Missing game, save, bridge, or fixture produces `not-run` or failure, never PASS.
- Existing pure tests stay fast and continue running under Lua 5.1.
- Vanilla source is not committed; only relative paths, hashes, expected symbols, and build metadata are stored.
- Final completion remains the repository owner's decision.

## Review Focus

- A duplicate command with the same run ID must not execute a consuming scenario twice; test protocol deduplication in Task 5.
- A callback delivered after session termination must not advance the current run; test stale callbacks in Tasks 2 and 3.
- A hotfix that changes a vanilla file hash but leaves symbols present must still report drift rather than silently accepting it; test in Task 4.
- An interrupted in-game scenario must report cleanup failure separately from the original failure; test result normalization in Task 5.
- A generated Workshop payload must contain no harness mod or test mailbox files; test in Task 7.

---

### Task 1: Scenario registry and evidence truth layer

**Files:**
- Create: `mods/cook-it-for-me/tests/scenarios.lua`
- Create: `mods/cook-it-for-me/tests/test_scenario_registry.lua`
- Create: `mods/cook-it-for-me/tests/REGRESSION.md`
- Create: `tools/lib/ValidationEvidence.ps1`
- Create: `tools/tests/ValidationEvidence.Tests.ps1`
- Modify: `mods/cook-it-for-me/tests/run.lua`
- Modify: `tools/tests/run.ps1`

**Interfaces:**
- Produces: `require("scenarios") -> { schema = 1, scenarios = Scenario[] }`.
- Produces: `New-ValidationEvidence -ScenarioId <string> -Mode <string> -Status <string> ... -> PSCustomObject`.
- Produces: `Write-ValidationReport -Evidence <object[]> -Path <path>`.

- [ ] **Step 1: Write failing Lua registry tests**

Add assertions that scenario IDs are unique, match `^[a-z][a-z0-9_.-]+$`, declare supported modes, and include exactly these initial IDs:

```lua
local expected = {
    ["cook.transfer.container.success"] = true,
    ["cook.recipe.replacement.success"] = true,
    ["cook.stove.ownership.success"] = true,
    ["cook.stove.preexisting.success"] = true,
}
```

Parse headings in `REGRESSION.md` and assert that every registry ID appears exactly once.

- [ ] **Step 2: Run the Lua test and verify RED**

Run: `Push-Location mods/cook-it-for-me/tests; lua test_scenario_registry.lua; Pop-Location`

Expected: failure because `scenarios.lua` and `REGRESSION.md` do not exist.

- [ ] **Step 3: Write failing evidence tests**

Add Pester-style assertions using the repository's existing lightweight PowerShell test pattern:

```powershell
$entry = New-ValidationEvidence -ScenarioId 'cook.transfer.container.success' `
    -Mode offline -Status pass -GameBuild $null -Observed @{ moved = $true }
Assert-Equal $entry.schema 1
Assert-Equal $entry.status 'pass'
Assert-Throws { New-ValidationEvidence -ScenarioId 'x' -Mode offline -Status success }
```

Verify the Markdown report has separate Offline, PZ SP, PZ MP, Packaged, Manual and Remaining sections.

- [ ] **Step 4: Run the PowerShell test and verify RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/tests/ValidationEvidence.Tests.ps1`

Expected: failure because `ValidationEvidence.ps1` is absent.

- [ ] **Step 5: Implement registry, regression documentation and evidence module**

Use data-only scenario entries:

```lua
return {
    schema = 1,
    scenarios = {
        {
            id = "cook.transfer.container.success",
            modes = { offline = true, gameSp = true },
            invariants = { "item-conserved", "destination-owns-item", "session-terminal" },
        },
    },
}
```

Evidence accepts only `pass`, `fail`, `not-run`, `not-applicable` and strips absolute paths from generated Markdown.

- [ ] **Step 6: Add tests to aggregate runners and verify GREEN**

Run:

```powershell
Push-Location mods/cook-it-for-me/tests
lua run.lua
Pop-Location
powershell -NoProfile -ExecutionPolicy Bypass -File tools/tests/run.ps1
```

Expected: all previous suites plus registry/evidence tests pass.

- [ ] **Step 7: Commit**

```powershell
git add mods/cook-it-for-me/tests tools/lib/ValidationEvidence.ps1 tools/tests
git commit -m "Add gameplay scenario evidence registry"
```

---

### Task 2: Deterministic timed-action simulator

**Files:**
- Create: `mods/cook-it-for-me/tests/support/action_simulator.lua`
- Create: `mods/cook-it-for-me/tests/test_action_simulator.lua`
- Modify: `mods/cook-it-for-me/tests/run.lua`

**Interfaces:**
- Produces: `Simulator.new(options) -> simulator`.
- Produces: `sim:queue(action)`, `sim:schedule(delayMs, fn)`, `sim:advance(ms)`, `sim:runUntilIdle(limitMs)`.
- Action contract: optional `isValidStart`, `waitToStart`, `start`, `update`, `complete`, `perform`, `stop`, `forceCancel`.
- Result contract: `sim.trace`, `sim.state`, `sim.failures`.

- [ ] **Step 1: Write lifecycle ordering tests**

Pin exact traces:

```lua
assertTrace(success, { "isValidStart", "waitToStart", "start", "update", "complete", "perform" })
assertTrace(rejected, { "isValidStart", "forceCancel" })
assertTrace(invalidated, { "isValidStart", "start", "update", "isValid", "stop" })
```

Also test that `perform` does not run when `complete` returns false.

- [ ] **Step 2: Run lifecycle tests and verify RED**

Run: `Push-Location mods/cook-it-for-me/tests; lua test_action_simulator.lua; Pop-Location`

Expected: module-not-found failure for `support/action_simulator`.

- [ ] **Step 3: Implement minimal scheduler and action state machine**

Keep the module independent of PZ globals. Use ordered `{ at, sequence, callback }` events and stable sorting by `(at, sequence)`.

- [ ] **Step 4: Write fault tests**

Cover:

- `forceCancelBeforeStart` calls only `forceCancel` after admission;
- `vanishAfterStart` leaves a visible `vanished` result;
- `duplicateCallback` executes a guarded effect once;
- stale callback after terminal state is ignored;
- virtual pause advances wall time without advancing gameplay time;
- timeout yields `stalled` and never PASS.

- [ ] **Step 5: Implement fault injection and invariants**

Expose faults as named options, not test-side mutation of private fields:

```lua
local sim = Simulator.new({ faults = { vanishAfterStart = true }, timeoutMs = 5000 })
```

Add reusable invariants for unique item location, at-most-once effects and terminal-session callback rejection.

- [ ] **Step 6: Run simulator and full Cook tests**

Run:

```powershell
Push-Location mods/cook-it-for-me/tests
lua test_action_simulator.lua
lua run.lua
Pop-Location
```

Expected: simulator tests and all existing Cook suites pass.

- [ ] **Step 7: Commit**

```powershell
git add mods/cook-it-for-me/tests/support/action_simulator.lua mods/cook-it-for-me/tests/test_action_simulator.lua mods/cook-it-for-me/tests/run.lua
git commit -m "Add deterministic timed action simulator"
```

---

### Task 3: Run Cook transfer faults through the simulator

**Files:**
- Modify: `mods/cook-it-for-me/tests/support/cook_env.lua`
- Create: `mods/cook-it-for-me/tests/test_simulated_scenarios.lua`
- Modify: `mods/cook-it-for-me/tests/run.lua`

**Interfaces:**
- Consumes: `Simulator.new`, `sim:queue`, `sim:runUntilIdle` from Task 2.
- Produces: `Env.new(...):runScenario(id, faults) -> normalized observation`.
- Observation fields: `status`, `sessionActive`, `sourceContains`, `destinationContains`, `effectCount`, `stoveActive`, `failureReason`.

- [ ] **Step 1: Write failing scenario tests**

Cover the transfer scenario across:

```lua
local cases = {
    { name = "success", faults = {}, expected = "pass" },
    { name = "reject before start", faults = { rejectBeforeStart = true }, expected = "fail" },
    { name = "force cancel", faults = { forceCancelBeforeStart = true }, expected = "fail" },
    { name = "item disappears", faults = { itemDisappears = true }, expected = "fail" },
    { name = "destination fills", faults = { destinationBecomesFull = true }, expected = "fail" },
    { name = "duplicate callback", faults = { duplicateCallback = true }, expected = "pass" },
    { name = "stale callback", faults = { staleCallbackAfterSession = true }, expected = "pass" },
}
```

For every case assert item conservation and terminal session state.

- [ ] **Step 2: Run scenario tests and verify RED**

Run: `Push-Location mods/cook-it-for-me/tests; lua test_simulated_scenarios.lua; Pop-Location`

Expected: `runScenario` is absent.

- [ ] **Step 3: Adapt boundary doubles to the simulator**

Preserve `Env:drain()` as a compatibility wrapper around the simulator. Model callbacks as scheduled events and implement `complete` separately from `perform`. Do not change production Lua to make the simulator convenient.

- [ ] **Step 4: Add replacement-object scenario**

Assert the old pot is absent, the resulting pot has expected `fullType`, the ingredient effect occurs once, and the resulting pot has exactly one location.

- [ ] **Step 5: Run all Cook tests and verify GREEN**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/check.ps1 -Mod cook-it-for-me`

Expected: complete Cook and shared tooling gate passes with no regression.

- [ ] **Step 6: Commit**

```powershell
git add mods/cook-it-for-me/tests
git commit -m "Exercise Cook scenarios through action simulator"
```

---

### Task 4: Installed-build contract fingerprint and drift gate

**Files:**
- Create: `tools/lib/PzContractSnapshot.ps1`
- Create: `tools/check-pz-contracts.ps1`
- Create: `tools/tests/PzContractSnapshot.Tests.ps1`
- Create: `contracts/pz-42.20.4.json`
- Modify: `tools/tests/run.ps1`

**Interfaces:**
- Produces: `Get-PzContractSnapshot -GamePath <path> -UmbrellaPath <path> -> object`.
- Produces: `Compare-PzContractSnapshot -Expected <object> -Actual <object> -> difference[]`.
- CLI exit codes: `0` match, `2` unknown drift, `1` invalid environment/input.

- [ ] **Step 1: Write fixture-based failing tests**

Create temporary fake vanilla trees and verify normalized `/` paths, SHA-256 hashes, required symbols and Umbrella revision. Include a hotfix case where symbols still exist but a hash differs; expected result is drift.

- [ ] **Step 2: Run fingerprint tests and verify RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/tests/PzContractSnapshot.Tests.ps1`

Expected: missing module failure.

- [ ] **Step 3: Implement snapshot and comparison**

Track these relative files and symbols:

```powershell
@{
  'media/lua/shared/TimedActions/ISBaseTimedAction.lua' = @('isValidStart','complete','perform','forceCancel')
  'media/lua/client/TimedActions/ISTimedActionQueue.lua' = @('add','onTick','resetQueue')
  'media/lua/client/TimedActions/ISInventoryTransferAction.lua' = @('isValid','start','stop','perform','setOnComplete')
  'media/lua/client/TimedActions/ISGrabItemAction.lua' = @('isValid','complete','perform')
  'media/lua/shared/TimedActions/ISAddItemInRecipe.lua' = @('isValidStart','complete','perform')
}
```

Read installed-game location through existing `PzApiTools.ps1`; do not duplicate Steam discovery.

- [ ] **Step 4: Generate and inspect the 42.20.4 snapshot**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-pz-contracts.ps1 -Update`

Expected: writes `contracts/pz-42.20.4.json` containing no absolute game/user paths and reports installed Build 42.20.4.

- [ ] **Step 5: Verify known and drifted snapshots**

Run the CLI normally, then alter a copied fixture hash in the test and verify exit code `2`. Restore nothing in the real snapshot.

- [ ] **Step 6: Add to tooling runner and verify GREEN**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/tests/run.ps1`

Expected: snapshot tests pass on CI fixtures without requiring an installed game.

- [ ] **Step 7: Commit**

```powershell
git add tools/lib/PzContractSnapshot.ps1 tools/check-pz-contracts.ps1 tools/tests contracts/pz-42.20.4.json
git commit -m "Add installed PZ contract drift gate"
```

---

### Task 5: Dev-only harness protocol and controller

**Files:**
- Create: `tools/pz-test-harness/PzModsTestHarness/42/mod.info`
- Create: `tools/pz-test-harness/PzModsTestHarness/42/media/lua/shared/PzTestHarness_Protocol.lua`
- Create: `tools/pz-test-harness/PzModsTestHarness/42/media/lua/client/PzTestHarness_Client.lua`
- Create: `tools/pz-test-harness/PzModsTestHarness/common/.gitkeep`
- Create: `tools/pz-test-harness/tests/test_protocol.lua`
- Create: `tools/run-game-scenario.ps1`
- Create: `tools/tests/GameScenarioController.Tests.ps1`

**Interfaces:**
- Mailbox request: `<runId>\t<scenarioId>\n` under `%USERPROFILE%/Zomboid/Lua/pzmodtests/request.txt`.
- Result: single-line JSON in `result.txt` with `schema`, `runId`, `scenario`, `status`, `gameBuild`, `observed`, `failures`, `cleanup`.
- Controller: `run-game-scenario.ps1 -Scenario <id> [-TimeoutSeconds 180] [-Json]`.

- [ ] **Step 1: Write failing pure protocol tests**

Test accepted allowlisted IDs, rejected unknown IDs, malformed requests, duplicate run IDs, stale result IDs, JSON escaping and cleanup failure normalization.

- [ ] **Step 2: Run protocol tests and verify RED**

Run: `Push-Location tools/pz-test-harness/tests; lua test_protocol.lua; Pop-Location`

Expected: protocol module missing.

- [ ] **Step 3: Implement pure protocol and dev mod metadata**

Use mod ID `PzModsTestHarness`, `require=CookItForMe`, explicit development-only description, and no Workshop manifest.

- [ ] **Step 4: Write failing controller tests**

Use a temporary Zomboid root. Test atomic request write, stale result rejection, timeout as `not-run`, matching result return and no modification of Forge Live command files.

- [ ] **Step 5: Implement controller and in-game polling shell**

Poll every 15 ticks through both `OnTick` and `OnRenderTick`. The in-game shell dispatches only functions pre-registered in `PzTestHarness.scenarios` and remembers the last run ID.

- [ ] **Step 6: Verify protocol, controller and Lua syntax**

Run:

```powershell
Push-Location tools/pz-test-harness/tests
lua test_protocol.lua
Pop-Location
powershell -NoProfile -ExecutionPolicy Bypass -File tools/tests/GameScenarioController.Tests.ps1
lua -e "assert(loadfile('tools/pz-test-harness/PzModsTestHarness/42/media/lua/client/PzTestHarness_Client.lua'))"
```

Expected: all tests pass without opening PZ.

- [ ] **Step 7: Commit**

```powershell
git add tools/pz-test-harness tools/run-game-scenario.ps1 tools/tests
git commit -m "Add allowlisted in-game test harness"
```

---

### Task 6: Three real-game Cook adapters

**Files:**
- Create: `tools/pz-test-harness/PzModsTestHarness/42/media/lua/client/scenarios/CookTransfer.lua`
- Create: `tools/pz-test-harness/PzModsTestHarness/42/media/lua/client/scenarios/CookRecipe.lua`
- Create: `tools/pz-test-harness/PzModsTestHarness/42/media/lua/client/scenarios/CookStove.lua`
- Create: `tools/pz-test-harness/TEST-SAVE.md`
- Modify: `tools/pz-test-harness/PzModsTestHarness/42/media/lua/client/PzTestHarness_Client.lua`
- Modify: `mods/cook-it-for-me/tests/REGRESSION.md`

**Interfaces:**
- Consumes: allowlisted registration from Task 5.
- Scenario function: `run(context, finish)` where `finish(result)` is at-most-once.
- Context owns `runId`, player, created item IDs, start time and cleanup callbacks.

- [ ] **Step 1: Write offline contract tests for scenario adapters**

Load each adapter with narrow PZ doubles and assert it registers only its documented IDs, refuses missing player/fixture, calls finish once, and records every created item for cleanup.

- [ ] **Step 2: Run adapter tests and verify RED**

Run: `Push-Location tools/pz-test-harness/tests; lua test_cook_scenarios.lua; Pop-Location`

Expected: scenario modules missing.

- [ ] **Step 3: Implement real transfer scenario**

Create a real inventory container item in the player inventory, add a test item to its inner container, queue vanilla `ISInventoryTransferAction`, and verify the exact object moved to the player inventory. Cleanup removes only objects recorded by the run.

- [ ] **Step 4: Implement recipe replacement scenario**

Require a clean test player inventory. Create the documented cookware/ingredient types, resolve the actual evolved recipe, invoke the existing Cook public start path where possible, and verify replacement identity/fullType/location and at-most-once consumption. If the installed recipe catalog cannot satisfy the fixture, return failure with discovered candidates rather than choosing silently.

- [ ] **Step 5: Implement stove ownership scenarios**

Locate exactly one valid nearby stove and, for water recipes, a valid sink. Fail on zero or ambiguous fixtures. Run both initially-off and pre-existing-on variants, observing activation ownership, cooking progress, terminal session state and final item location.

- [ ] **Step 6: Document the test save fixture**

Specify required empty player inventory, one reachable powered non-microwave stove, one reachable sink, no zombies within cancellation radius and no unrelated food on the stove. Include exact manual reset steps.

- [ ] **Step 7: Run offline adapter tests**

Run: `Push-Location tools/pz-test-harness/tests; lua test_protocol.lua; lua test_cook_scenarios.lua; Pop-Location`

Expected: adapters pass with doubles.

- [ ] **Step 8: Run inside installed PZ when fixture is available**

Run each command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-game-scenario.ps1 -Scenario cook.transfer.container.success
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-game-scenario.ps1 -Scenario cook.recipe.replacement.success
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-game-scenario.ps1 -Scenario cook.stove.ownership.success
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run-game-scenario.ps1 -Scenario cook.stove.preexisting.success
```

Expected: matching run IDs and PASS from game-observed postconditions. If game/save is unavailable, record `not-run` and do not claim in-game validation.

- [ ] **Step 9: Commit**

```powershell
git add tools/pz-test-harness mods/cook-it-for-me/tests/REGRESSION.md
git commit -m "Add real-game Cook regression scenarios"
```

---

### Task 7: Risk-aware gate, new-mod scaffold and Workshop exclusion

**Files:**
- Modify: `tools/check.ps1`
- Modify: `tools/new-mod.ps1`
- Modify: `tools/build_workshop.ps1`
- Create: `tools/tests/NewModReliability.Tests.ps1`
- Create: `tools/tests/WorkshopHarnessExclusion.Tests.ps1`
- Modify: `tools/tests/run.ps1`
- Modify: `README.md`
- Modify: `AGENTS.md`

**Interfaces:**
- `check.ps1 -Mod <slug>` always runs registry/simulator consistency for mods that declare scenarios.
- `check.ps1 -Mod <slug> -InstalledContracts` additionally runs installed-build drift checking.
- `new-mod.ps1` adds mandatory `-Support SP|MP|both|content-only`.

- [ ] **Step 1: Write failing scaffold tests**

Create a temporary mod with `new-mod.ps1` and assert it contains support declaration, `tests/REGRESSION.md`, a valid smoke scenario manifest and README sections for offline/in-game/manual validation.

- [ ] **Step 2: Write failing Workshop exclusion tests**

Build each mod into a temporary root and assert no path contains `PzModsTestHarness`, `pzmodtests`, `run-game-scenario` or scenario evidence logs.

- [ ] **Step 3: Run tests and verify RED**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/tests/NewModReliability.Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/tests/WorkshopHarnessExclusion.Tests.ps1
```

Expected: scaffold assertions fail before implementation.

- [ ] **Step 4: Implement minimal scaffold and gate changes**

Keep profile generation limited to the spec. Do not add MP framework code. Make scenario checks conditional on presence of `tests/scenarios.lua` so existing simple content mods remain valid.

- [ ] **Step 5: Enforce warning policy narrowly**

Add a checked-in analyzer baseline containing file, diagnostic code and explanation for any confirmed false positive. Fail when analyzer output contains an unlisted warning. Resolve the ATA warning instead of baselining it if a type annotation or direct-call rewrite makes the code clearer without changing behavior.

- [ ] **Step 6: Update agent rules and repository docs**

Add only four rules: risk classification, installed contract fingerprint for gameplay boundaries, stable scenario ID, and `ready for manual validation` wording when PZ did not run.

- [ ] **Step 7: Run full gates**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check.ps1 -Mod cook-it-for-me -InstalledContracts
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check.ps1 -Mod ata-bus-upgrade-b42
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check.ps1 -Mod mma-combat
powershell -NoProfile -ExecutionPolicy Bypass -File tools/tests/run.ps1
```

Expected: all gates pass; no unlisted warning remains.

- [ ] **Step 8: Commit**

```powershell
git add tools README.md AGENTS.md
git commit -m "Enforce reliability gates for new mod work"
```

---

### Task 8: Final evidence, review and closeout

**Files:**
- Create or update: `docs/validation/reliability-vertical-slice.md`
- Update: `docs/audits/reliability-audit-2026-09-20.md`
- Update: `docs/research/pz-mod-quality-practices.md` only if implementation disproves a recorded contract

**Interfaces:**
- Consumes all task test results and in-game JSONL evidence.
- Produces the final human-readable validation record.

- [ ] **Step 1: Run clean full verification**

Run every mod gate, tooling tests, protocol tests, `git diff --check`, and `git status --short`. Capture exact pass/fail counts without copying personal absolute paths into committed evidence.

- [ ] **Step 2: Run packaged payload checks**

Use dry-run or temporary build roots only. Verify all three mod payloads and explicit harness exclusion.

- [ ] **Step 3: Run available in-game scenarios**

Use the four Task 6 commands. Record PASS/FAIL/not-run separately. Do not infer PASS from game process state, watcher state or reload acknowledgements.

- [ ] **Step 4: Perform Zomboid review gate**

Review changed Lua/API calls against installed 42.20.4 vanilla Lua, active B42 folder layout, latest relevant console log, packaging, line endings and save-data impact. Apply focused fixes and rerun affected checks.

- [ ] **Step 5: Generate the validation report**

The report must separate:

```text
Implemented
Verified by automated tests
Verified inside PZ
Verified in packaged payload
Not confirmed / owner playtest
Known limitations
```

- [ ] **Step 6: Final commit**

```powershell
git add docs/validation docs/audits docs/research
git commit -m "Record reliability vertical slice validation"
```
