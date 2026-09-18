# Agent development tooling design

## Goal

Give local and CI agents three deterministic capabilities:

1. run EmmyLua static analysis against the pinned Umbrella B42.20 stubs;
2. find symbols in the installed Project Zomboid API without guessing paths;
3. inspect the current Forge Live and game-log state without sending bridge commands.

The tools must work from the repository root on Windows, fail explicitly when required state is unavailable, and keep downloaded binaries and machine-local data out of Git.

## EmmyLua checker

`tools/setup-emmylua.ps1` installs a pinned `emmylua_check` release into `.tools/emmylua/`. Version, asset URL, and SHA-256 are constants in the script. Installation downloads to a temporary directory, verifies the checksum before extraction, and replaces the cached tool only after validation succeeds.

The initial supported platform is Windows x64 because both the local workflow and GitHub Actions job run on Windows. Unsupported platforms fail with an actionable message instead of selecting an unverified asset.

`tools/check.ps1` calls the setup script, then runs `emmylua_check` for the selected mod using the repository `.emmyrc.json`. A failed download, invalid checksum, missing Umbrella submodule, analyzer crash, or reported diagnostic fails the check.

GitHub Actions initializes submodules so `.types/umbrella/library` exists before the checker runs. The existing syntax, Lua test, and Forge Live test gates remain intact.

## Installed API discovery

`tools/find-pz-api.ps1 -Query <text>` discovers Steam through the current-user registry and parses every library path from `steamapps/libraryfolders.vdf`. It selects installations containing `steamapps/common/ProjectZomboid/projectzomboid.jar`.

The command searches:

- installed vanilla Lua under `media/lua/client`, `media/lua/shared`, and `media/lua/server`;
- pinned Umbrella stubs under `.types/umbrella/library`;
- Java class entry names inside the installed `projectzomboid.jar`.

Results identify their source, relative path, line number when applicable, and matching text. Java archive results prove that a class exists but do not claim method signatures; method details still come from Umbrella or direct bytecode inspection. Multiple valid game installations cause an explicit ambiguity error unless `-GamePath` selects one. `-Json` emits stable machine-readable output for agents.

The search is read-only. It never modifies Steam files, the game installation, or the Umbrella submodule.

## Forge Live status contract

The current `watcher.lock` proves only ownership and `result.txt` may contain an old response. Therefore the watcher will persist an explicit status document at `<bridgeDir>/status.json`.

The status schema contains:

- schema version, watcher PID and watched mod IDs;
- watcher start time and current lifecycle state;
- bridge ping result;
- latest batch time, files, and result;
- latest acknowledged reload time and file;
- blocked or restart-required reason;
- console path and byte offset captured when the watcher started.

Writes are atomic through a temporary file followed by replacement. Lifecycle states are `starting`, `ready`, `reloading`, `ready`, `blocked`, `restart-required`, and `stopped`. Fatal bridge failures and rejected reloads remain visible as terminal states instead of being overwritten by later filesystem events.

`tools/game-status.ps1 -Mod <slug>` reads the Forge configuration, lock, status document, process table, Project Zomboid process, and only the section of `console.txt` written after the watcher baseline. It does not write `cmd.txt` or otherwise occupy the single bridge mailbox.

Human output summarizes watcher, game, bridge, last reload, and new errors. `-Json` returns the same information as structured data. A stale PID, missing status, invalid schema, old acknowledgement, truncated console, blocked watcher, or restart requirement is reported explicitly.

Errors from other mods remain visible but are distinguished from lines mentioning the selected mod ID or its source/target paths. The tool does not interpret an ACK as proof of correct gameplay.

## Testing

PowerShell logic is organized into sourceable functions. A repository test script uses temporary Steam layouts, VDF files, jars, bridge files, process-state fixtures, and console logs to cover success, missing dependencies, ambiguous installations, stale locks, old results, truncated logs, blocked state, and JSON output.

Forge Live status persistence is covered by Node tests for atomic writes and lifecycle transitions. Production watcher code uses the tested state writer rather than duplicating serialization logic.

Final verification runs:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check.ps1 -Mod cook-it-for-me
```

No Project Zomboid restart is required because the change affects repository tooling and the external watcher, not game Lua modules. A running watcher must be restarted to begin emitting the new status schema.

## Non-goals

- No GUI automation or claim of in-game behavioral correctness.
- No automatic Java decompiler installation.
- No bridge probe commands or additional mailbox clients.
- No automatic update to the latest EmmyLua release.
- No support for silently choosing between multiple PZ installations.
