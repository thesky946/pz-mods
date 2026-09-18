# Agent Development Tooling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add deterministic EmmyLua checking, installed Project Zomboid API search, and read-only Forge Live/game status reporting.

**Architecture:** Each capability has a thin public PowerShell command backed by sourceable functions, while Forge Live owns its status lifecycle through a small JavaScript status store. All machine-local artifacts stay under ignored `.tools/` or the existing Forge bridge directory; CI uses the same entry point as local development.

**Tech Stack:** PowerShell 7/Windows PowerShell, Node.js 24 test runner, Lua 5.1, EmmyLua Analyzer 0.25.1, GitHub Actions, Forge Live ES modules.

**Spec:** `docs/superpowers/specs/2026-09-19-agent-dev-tooling-design.md`

## Global Constraints

- Support Windows x64 for the pinned analyzer installer and fail explicitly elsewhere.
- Pin `emmylua_check` to `0.25.1` and verify SHA-256 `577982e68d925972d8ae35f54b5f384ad77a84a2e31e340bd663d1efd2ef5983`.
- Never modify the Steam installation, Umbrella submodule, game mailbox, or `console.txt`.
- Never treat a reload acknowledgement as proof of correct gameplay.
- Preserve the existing Lua, localization, offline-test, and Forge Live gates.
- Keep downloaded executables and machine-local state out of Git.

---

### Task 1: Pinned EmmyLua checker and CI gate

**Files:**
- Create: `tools/lib/EmmyLuaTools.ps1`
- Create: `tools/setup-emmylua.ps1`
- Create: `tools/tests/EmmyLuaTools.Tests.ps1`
- Create: `tools/tests/run.ps1`
- Modify: `tools/check.ps1`
- Modify: `.github/workflows/checks.yml`
- Modify: `.gitignore`
- Track: `.emmyrc.json`
- Track: `.gitmodules`
- Track: `.types/umbrella`

**Interfaces:**
- Produces: `Install-EmmyLuaCheck -DestinationRoot <path> [-ArchivePath <path>] [-ExpectedSha256 <hex>] -> FileInfo`; the wrapper supplies the pinned production hash, while tests supply the fixture hash.
- Produces: `tools/setup-emmylua.ps1 [-DestinationRoot <path>]`, printing the executable path as its final output line.
- Consumes: repository `.emmyrc.json` and `.types/umbrella/library`.

- [ ] **Step 1: Write failing installer tests**

Create a minimal assertion runner in `tools/tests/run.ps1` that executes every `*.Tests.ps1`, counts failures, and exits nonzero. In `EmmyLuaTools.Tests.ps1`, create temporary zip fixtures and assert:

```powershell
$good = Install-EmmyLuaCheck -DestinationRoot $destination -ArchivePath $validZip
Assert-Equal $good.Name 'emmylua_check.exe'
Assert-Throws { Install-EmmyLuaCheck -DestinationRoot $destination -ArchivePath $tamperedZip } '*checksum*'
Assert-Throws { Install-EmmyLuaCheck -DestinationRoot $destination -ArchivePath $missingExeZip } '*emmylua_check.exe*'
```

- [ ] **Step 2: Run the tests and verify red**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/tests/run.ps1
```

Expected: failure because `Install-EmmyLuaCheck` does not exist.

- [ ] **Step 3: Implement verified installation**

In `EmmyLuaTools.ps1`, define constants for version, URL, and hash. Implement cached-version detection, download to a unique temp directory, `Get-FileHash -Algorithm SHA256`, extraction, executable validation, and atomic replacement of `.tools/emmylua/0.25.1`. `-ArchivePath` bypasses the network only for fixture tests but still requires and enforces `-ExpectedSha256`; normal calls always use the pinned production hash.

The wrapper calls:

```powershell
$exe = Install-EmmyLuaCheck -DestinationRoot $DestinationRoot
Write-Output $exe.FullName
```

- [ ] **Step 4: Run installer tests and the real bootstrap**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/tests/run.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/setup-emmylua.ps1
```

Expected: tests pass; bootstrap prints an existing `emmylua_check.exe` under `.tools/emmylua/0.25.1`.

- [ ] **Step 5: Add the static-analysis gate**

Update `tools/check.ps1` to reject a missing Umbrella library, invoke the setup wrapper, and run from repository root:

```powershell
& $emmyLuaPath (Join-Path $modInfo.Root '42\media\lua') --config (Join-Path $repo '.emmyrc.json')
if ($LASTEXITCODE -ne 0) { throw 'EmmyLua analysis failed.' }
```

Add `.tools/` to `.gitignore`. Configure checkout with:

```yaml
with:
  submodules: recursive
```

- [ ] **Step 6: Verify and commit the checker deliverable**

Run the test runner and `tools/check.ps1 -Mod cook-it-for-me`. Fix configuration diagnostics only when they represent the intended PZ runtime contract; do not disable diagnostics wholesale.

Commit only Task 1 files:

```powershell
git add .emmyrc.json .gitmodules .types/umbrella .gitignore .github/workflows/checks.yml tools/check.ps1 tools/setup-emmylua.ps1 tools/lib/EmmyLuaTools.ps1 tools/tests
git commit -m "Add pinned EmmyLua validation"
```

---

### Task 2: Installed Project Zomboid API search

**Files:**
- Create: `tools/lib/PzApiTools.ps1`
- Create: `tools/find-pz-api.ps1`
- Create: `tools/tests/PzApiTools.Tests.ps1`
- Modify: `mods/cook-it-for-me/DEVELOPMENT.md`

**Interfaces:**
- Produces: `Get-SteamLibraryPath -SteamRoot <path> -> string[]`.
- Produces: `Resolve-PzGamePath [-GamePath <path>] [-SteamRoot <path>] -> string`.
- Produces: `Find-PzApi -Query <string> -GamePath <path> -UmbrellaPath <path> -> object[]` with `source`, `path`, `line`, and `text`.
- Produces: `tools/find-pz-api.ps1 -Query <string> [-GamePath <path>] [-Json]`.

- [ ] **Step 1: Write failing discovery and search tests**

Create fixture Steam libraries, vanilla Lua files, an Umbrella stub, and a zip renamed to `projectzomboid.jar`. Assert exact source classification and ambiguity behavior:

```powershell
Assert-SequenceEqual (Get-SteamLibraryPath -SteamRoot $steam) @($steam, $secondLibrary)
Assert-Throws { Resolve-PzGamePath -SteamRoot $ambiguousSteam } '*multiple*'
$results = Find-PzApi -Query 'RecipeManager' -GamePath $game -UmbrellaPath $umbrella
Assert-Equal ($results | Where-Object source -eq 'vanilla-lua').Count 1
Assert-Equal ($results | Where-Object source -eq 'umbrella').Count 1
Assert-Equal ($results | Where-Object source -eq 'java-class').Count 1
```

- [ ] **Step 2: Run the test runner and verify red**

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tools/tests/run.ps1`.

Expected: failures because the API functions are undefined.

- [ ] **Step 3: Implement deterministic discovery**

Parse quoted `path` entries from `libraryfolders.vdf`, unescape doubled backslashes, normalize full paths, and include the Steam root exactly once. Resolve only candidates containing both `projectzomboid.jar` and `media/lua`. Validate explicit `-GamePath` by the same contract.

- [ ] **Step 4: Implement bounded source search**

Search only `*.lua` under the three vanilla Lua roots and Umbrella library with `Select-String -SimpleMatch`. Open the jar read-only with `[IO.Compression.ZipFile]::OpenRead()` and match normalized `.class` entry names. Sort results by `source`, `path`, and `line`; emit objects rather than formatted strings from the library function.

- [ ] **Step 5: Add CLI output and documentation**

The wrapper prints a concise table or `ConvertTo-Json -Depth 4` with `-Json`. Document these examples in `DEVELOPMENT.md`:

```powershell
.\tools\find-pz-api.ps1 -Query RecipeManager
.\tools\find-pz-api.ps1 -Query IsoStove -Json
```

- [ ] **Step 6: Verify and commit API search**

Run the PowerShell tests and both commands against the installed B42.20 game. Confirm all reported files are inside the game path or Umbrella submodule.

```powershell
git add tools/find-pz-api.ps1 tools/lib/PzApiTools.ps1 tools/tests/PzApiTools.Tests.ps1 mods/cook-it-for-me/DEVELOPMENT.md
git commit -m "Add installed PZ API search"
```

---

### Task 3: Forge Live status persistence

**Files:**
- Create: `tools/forge-live/cli/status-store.mjs`
- Create: `tools/forge-live/cli/status-store.test.mjs`
- Modify: `tools/forge-live/cli/forge-live.mjs`
- Modify: `tools/forge-live/package.json`

**Interfaces:**
- Produces: `createStatusStore({ bridgeDir, mods, consolePath, pid, now })`.
- Produces store methods: `update(patch)`, `transition(state, patch)`, and `stop(reason)`.
- Persists schema version `1` to `<bridgeDir>/status.json` atomically.

- [ ] **Step 1: Write failing lifecycle tests**

Use `node:test` with a temporary directory and injected clock. Assert that initialization records `starting`, transitions preserve previous fields, `blocked` is not reset by later scheduling, `stop()` records `stopped`, and no `.tmp` file remains after a write.

```javascript
const store = createStatusStore({ bridgeDir, mods: ["CookItForMe"], consolePath, pid: 123, now });
store.transition("ready", { bridge: { ok: true, value: "pong v0.2.0" } });
assert.equal(readStatus().state, "ready");
assert.equal(readStatus().watcher.pid, 123);
```

- [ ] **Step 2: Run the Node test and verify red**

Run `node --test tools/forge-live/cli/status-store.test.mjs`.

Expected: module-not-found failure.

- [ ] **Step 3: Implement the atomic status store**

Capture console size at startup, serialize timestamps as ISO-8601 UTC, write `status.json.<pid>.tmp`, then rename over `status.json`. Keep terminal states `blocked` and `restart-required` until explicit stop. Expose immutable snapshots to tests.

- [ ] **Step 4: Wire every watcher lifecycle edge**

Create one store per unique bridge directory before acquiring locks. Record:

- startup and ping success/failure;
- batch file list before copies;
- each ACK and final ready state;
- reload rejection or I/O failure as blocked;
- added/removed modules as restart-required;
- SIGINT, SIGTERM, and normal exit as stopped.

Do not change mailbox serialization or reload ordering.

- [ ] **Step 5: Run all Forge Live tests and commit**

Update the npm test command to include `status-store.test.mjs`, then run `npm.cmd test` inside `tools/forge-live`.

```powershell
git add tools/forge-live/cli/status-store.mjs tools/forge-live/cli/status-store.test.mjs tools/forge-live/cli/forge-live.mjs tools/forge-live/package.json
git commit -m "Persist Forge Live watcher status"
```

---

### Task 4: Read-only game status command

**Files:**
- Create: `tools/lib/ForgeStatusTools.ps1`
- Create: `tools/game-status.ps1`
- Create: `tools/tests/ForgeStatusTools.Tests.ps1`
- Modify: `mods/cook-it-for-me/DEVELOPMENT.md`

**Interfaces:**
- Produces: `Get-ForgeGameStatus -ModInfo <object> -ForgeConfigPath <path> [-ConsolePath <path>] [-ProcessLookup <scriptblock>] -> object`.
- Produces: `tools/game-status.ps1 [-Mod cook-it-for-me] [-Json]`.
- Consumes: status schema version `1` from Task 3.

- [ ] **Step 1: Write failing status tests**

Build fixtures for ready, blocked, restart-required, stale PID, missing status, stale ACK, and truncated console. Inject process lookup so tests do not depend on real PIDs. Assert that reading status never creates or changes `cmd.txt`, `result.txt`, or `status.json`.

```powershell
$before = Get-FileHash $cmd
$status = Get-ForgeGameStatus -ModInfo $mod -ForgeConfigPath $config -ConsolePath $console -ProcessLookup { param($pid) $pid -eq 123 }
Assert-Equal $status.watcher.state 'ready'
Assert-Equal (Get-FileHash $cmd).Hash $before.Hash
```

- [ ] **Step 2: Run the PowerShell tests and verify red**

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tools/tests/run.ps1`.

Expected: failures because `Get-ForgeGameStatus` does not exist.

- [ ] **Step 3: Implement read-only status aggregation**

Resolve the selected mod through existing `Resolve-PzMod`, find its unique Forge configuration entry, validate schema `1`, verify watcher PID and `ProjectZomboid64` process independently, and read console bytes starting at the captured offset. If the file shrank, mark `console.truncated = true` and read from byte zero.

Classify new log lines into `errors.relevant` when they contain the mod ID, source path, or target path; retain remaining error blocks in `errors.other`. Report ACK age and set `reload.fresh = false` when its timestamp predates the latest batch.

- [ ] **Step 4: Implement human and JSON output**

Return stable JSON with `game`, `watcher`, `bridge`, `reload`, `console`, and `errors`. Human output uses one line per section and exits nonzero for missing/stale watcher, blocked, restart-required, invalid status, or relevant new Lua errors. Other-mod errors remain visible warnings but do not fail the command.

- [ ] **Step 5: Verify against fixtures and current local state**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/tests/run.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/game-status.ps1 -Mod cook-it-for-me
powershell -NoProfile -ExecutionPolicy Bypass -File tools/game-status.ps1 -Mod cook-it-for-me -Json
```

The current stale watcher lock must be reported as stale rather than ready.

- [ ] **Step 6: Document and commit status reporting**

Document that the watcher must be restarted once to emit schema `1`, and that status/ACK does not replace in-game validation.

```powershell
git add tools/game-status.ps1 tools/lib/ForgeStatusTools.ps1 tools/tests/ForgeStatusTools.Tests.ps1 mods/cook-it-for-me/DEVELOPMENT.md
git commit -m "Add read-only game status reporting"
```

---

### Task 5: Full integration verification

**Files:**
- Modify only files required to fix integration defects revealed by the commands below.

**Interfaces:**
- Consumes every public command and schema defined in Tasks 1-4.
- Produces a repository state where the standard check is the single release gate.

- [ ] **Step 1: Run whitespace and repository checks**

```powershell
git diff --check
git submodule status
powershell -NoProfile -ExecutionPolicy Bypass -File tools/tests/run.ps1
```

- [ ] **Step 2: Run the complete mod gate**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check.ps1 -Mod cook-it-for-me
```

Expected: EmmyLua, syntax/localization, offline Lua tests, PowerShell tooling tests, and Forge Live Node tests all exit zero.

- [ ] **Step 3: Exercise the agent-facing commands**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/find-pz-api.ps1 -Query RecipeManager -Json
powershell -NoProfile -ExecutionPolicy Bypass -File tools/game-status.ps1 -Mod cook-it-for-me -Json
```

Expected: API search returns valid JSON with installed and stub sources; game status returns valid JSON and truthfully reports the current stopped/stale runtime if the game and watcher are not running.

- [ ] **Step 4: Review final diff and commit integration fixes**

Confirm no downloaded binaries, Steam files, bridge files, or console logs are tracked. Commit only necessary integration changes with `git commit -m "Verify agent development tooling"`; skip the commit when no integration changes were needed.
