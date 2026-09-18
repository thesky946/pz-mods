# Project Zomboid Mods

[![Checks](https://github.com/thesky946/pz-mods/actions/workflows/checks.yml/badge.svg)](https://github.com/thesky946/pz-mods/actions/workflows/checks.yml)

Project Zomboid Build 42 mods built with explicit runtime contracts, offline game-API mocks, automated checks, and reproducible Workshop releases.

## Published mods

<table>
  <tr>
    <td width="50%" valign="top">
      <a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3801601464"><img src="mods/cook-it-for-me/workshop/preview.png" alt="Cook It For Me" width="100%"></a>
      <h3 align="center">Cook It For Me</h3>
      <p>Plan a meal, approve the ingredients, and let your survivor perform the real vanilla cooking workflow.</p>
      <p align="center"><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3801601464"><strong>Steam Workshop</strong></a> · <a href="mods/cook-it-for-me"><strong>Source and docs</strong></a></p>
    </td>
    <td width="50%" valign="top">
      <a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3803915890"><img src="mods/ata-bus-upgrade-b42/workshop/preview.png" alt="ATA Bus Upgrade" width="100%"></a>
      <h3 align="center">ATA Bus Upgrade</h3>
      <p>A 500 HP Build 42 handling patch for AutoTsar's Army, Prison, and School buses, with server-authoritative multiplayer updates.</p>
      <p align="center"><a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3803915890"><strong>Steam Workshop</strong></a> · <a href="mods/ata-bus-upgrade-b42"><strong>Source and docs</strong></a></p>
    </td>
  </tr>
</table>

## Engineering highlights

- Modular Lua 5.1 code with narrow responsibilities and documented state contracts.
- Offline game-API mocks for success, failure, cancellation, duplicate callbacks, stale callbacks, replacement objects, and multiplayer authority.
- Static validation for syntax, local dependencies, translations, metadata, and Workshop layout.
- [Forge Live](tools/forge-live), a dependency-aware hot-reload bridge with restart detection and serialized game commands.
- Isolated staging, validation, and publishing for existing Steam Workshop items.

The repository also contains [MMA Combat](mods/mma-combat), an experimental unarmed-combat and animation project with Blender authoring sources.

## Repository layout

```text
mods/<slug>/
  42/            Build 42 mod files
  common/        files shared by supported builds
  tests/         offline Lua tests and game API mocks
  workshop/      Steam Workshop metadata and preview
tools/           checks, staging, publishing, and Forge Live
```

## Run the checks

Requirements: PowerShell, Node.js, npm, and Lua 5.1.

```powershell
./tools/check.ps1 -Mod cook-it-for-me
./tools/check.ps1 -Mod ata-bus-upgrade-b42
./tools/check.ps1 -Mod mma-combat
```

The offline suite validates code and mocked game contracts. It does not replace verification inside Project Zomboid; game-only limitations are documented per mod.

## Development workflow

Every mod under `mods/<slug>/` uses the same check, staging, and hot-reload tooling. Start one watcher for the mod being developed:

```powershell
./tools/watch.cmd cook-it-for-me
# or
./tools/watch.cmd ata-bus-upgrade-b42
```

The watcher validates the project, installs the local Forge Live bridge when needed, stages the mod, and monitors its `42/` directory. Saving an existing Lua module reloads that module together with affected dependants in the running game.

A `RELOAD ACK` confirms that the game accepted the reload request; it does not prove correct behavior. Check the game state and `%USERPROFILE%/Zomboid/console.txt`. Use only one watcher for the bridge.

A game restart is required after adding, removing, or renaming Lua modules, or changing `mod.info`, translations, scripts, models, textures, sounds, or other boot-time resources. Test and documentation changes do not require a restart.

See [Forge Live](tools/forge-live) for the shared tooling and limitations. [Cook It For Me development](mods/cook-it-for-me/DEVELOPMENT.md) is a concrete mod-specific workflow; its [architecture notes](mods/cook-it-for-me/ARCHITECTURE.md) document only that mod's runtime boundaries and failure model.

## Issues

Use [GitHub Issues](https://github.com/thesky946/pz-mods/issues) for reproducible bugs. Include the mod name, game build, steps, enabled mods, and the relevant part of `%USERPROFILE%/Zomboid/console.txt`.

## Copyright

Copyright © 2026 thesky. Except for identified third-party material, no license is granted for this repository; all rights are reserved. The repository is public for inspection and issue reporting, not as permission to redistribute or republish its contents.
