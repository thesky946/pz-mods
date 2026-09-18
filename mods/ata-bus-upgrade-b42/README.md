# AutoTsar Tuning Atelier - Bus Upgrade - 500 HP [B42 SP/MP]

[![Steam Workshop](https://img.shields.io/badge/Steam_Workshop-Subscribe-1b2838?logo=steam)](https://steamcommunity.com/sharedfiles/filedetails/?id=3803915890)
[![Checks](https://github.com/thesky946/pz-mods/actions/workflows/checks.yml/badge.svg)](https://github.com/thesky946/pz-mods/actions/workflows/checks.yml)

An unofficial Project Zomboid Build 42 performance patch for the Army, Prison, and School buses from [Autotsar Tuning Atelier — Bus](https://steamcommunity.com/sharedfiles/filedetails/?id=3402812859).

[![View source on GitHub](../../assets/github-source-banner.png)](https://github.com/thesky946/pz-mods/tree/main/mods/ata-bus-upgrade-b42)

![ATA Bus Upgrade Workshop preview](workshop/preview.png)

## Changes

| Setting | Value |
| --- | ---: |
| Engine power | 500 HP (`engineForce = 5000`) |
| Top-speed setting | `100` |
| Off-road efficiency | `1.1` |
| Steering increment | `0.04` |
| Steering clamp | `0.3` |
| Suspension stiffness | `35` |
| Wheel friction | `1.5` |

The patch also retunes suspension compression, damping, travel, and rest length. These values are applied to `ATAArmyBus`, `ATAPrisonBus`, and `ATASchoolBus`; unrelated vehicles are ignored.

## Existing saves and multiplayer

- Safe to add to an existing save or server; no wipe or vehicle respawn is required.
- Loaded ATA buses are checked periodically and updated in place.
- Repeated scans are idempotent and do not rewrite buses that already have the target values.
- Runtime engine changes execute on the server and are transmitted to clients.

Both the server and every client need this mod and the original ATA Bus mod. `ATA_Bus` is declared as a hard dependency, so this patch loads after it.

## Repository layout

```text
42/media/scripts/vehicles/ata_bus_upgrade_b42.txt  vehicle tuning overrides
42/media/lua/shared/ATABusUpgradeB42_Core.lua      target detection and idempotent updates
42/media/lua/server/ATABusUpgradeB42_Server.lua    server-side periodic scan
tests/run.lua                                      offline contract tests
workshop/                                          Steam metadata and preview
```

## Development

From the repository root:

```powershell
./tools/check.ps1 -Mod ata-bus-upgrade-b42
./tools/watch.cmd ata-bus-upgrade-b42
```

The check validates Lua 5.1 syntax, local dependencies, metadata, all tuning fields, target filtering, repeat callbacks, both Build 42 vehicle collection contracts, and the Forge Live protocol tests.

## Credits and copyright

This is an unofficial add-on and contains no assets from the original ATA Bus mod. All credit for the buses and tuning system belongs to the original Autotsar authors.

Copyright © 2026 thesky. No license is granted; all rights are reserved.
