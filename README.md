# Project Zomboid Mods

[![Checks](https://github.com/thesky946/pz-mods/actions/workflows/checks.yml/badge.svg)](https://github.com/thesky946/pz-mods/actions/workflows/checks.yml)

Source, tests, tooling, and release metadata for my Project Zomboid Build 42 mods.

## Mods

| Mod | Status | Description |
| --- | --- | --- |
| [Cook It For Me](mods/cook-it-for-me) | [Published on Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3801601464) | Plans and performs real vanilla cooking from nearby cookware and ingredients. |
| [ATA Bus Upgrade](mods/ata-bus-upgrade-b42) | Development | A server-authoritative Build 42 performance patch for AutoTsar's bus. |
| [MMA Combat](mods/mma-combat) | Experimental | Unarmed-combat and animation research, including the Blender authoring sources. |

<p align="center">
  <a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3801601464">
    <img src="mods/cook-it-for-me/workshop/preview.png" alt="Cook It For Me — automatic cooking for Project Zomboid Build 42" width="640">
  </a>
</p>

## What is worth looking at

- A modular Lua 5.1 cooking pipeline with explicit planning, execution, cancellation, and stale-callback guards.
- Offline game-contract mocks covering inventory transfers, replacement items, full containers, missing items, interrupted actions, and stove ownership.
- Static checks for Lua syntax, local dependencies, translations, and Workshop layout.
- [Forge Live](tools/forge-live), a local hot-reload bridge with dependency-aware reload ordering and restart detection.
- Reproducible Workshop staging and publishing scripts.

Cook It For Me's module boundaries and runtime contracts are documented in its [architecture notes](mods/cook-it-for-me/ARCHITECTURE.md). The local development and hot-reload workflow is in [DEVELOPMENT.md](mods/cook-it-for-me/DEVELOPMENT.md).

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

## Issues

Use [GitHub Issues](https://github.com/thesky946/pz-mods/issues) for reproducible bugs. Include the mod name, game build, steps, enabled mods, and the relevant part of `%USERPROFILE%/Zomboid/console.txt`.

## Copyright

Copyright © 2026 thesky. Except for identified third-party material, no license is granted for this repository; all rights are reserved. The repository is public for inspection and issue reporting, not as permission to redistribute or republish its contents.
