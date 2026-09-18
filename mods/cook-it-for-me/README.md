# Cook It For Me

[![Steam Workshop](https://img.shields.io/badge/Steam_Workshop-Subscribe-1b2838?logo=steam)](https://steamcommunity.com/sharedfiles/filedetails/?id=3801601464)
[![Checks](https://github.com/thesky946/pz-mods/actions/workflows/checks.yml/badge.svg)](https://github.com/thesky946/pz-mods/actions/workflows/checks.yml)

Automatic cooking for Project Zomboid Build 42. Pick a meal and approve the plan; your survivor fetches the cookware, water, ingredients, and spices, cooks with vanilla timed actions, switches off the stove, and brings the result back.

![Cook It For Me plan window](workshop/preview.png)

## Features

- Preview the complete meal plan before anything moves.
- Perform the workflow through real vanilla timed actions instead of instant crafting.
- Cook soup, stew, stir-fry, and roasted vegetables using vanilla evolved recipes.
- Stop safely when danger approaches or the world no longer matches the approved plan.
- Track stove ownership, cooking progress, and the exact dish object through completion.
- English, Russian, Spanish, Brazilian Portuguese, Simplified Chinese, French, and Turkish UI.

Build 42 and single-player only. The mod adds no items or recipes and is safe to add to an existing save.

## How to use

1. Right-click the world and choose **Cook It For Me**.
2. Select a dish, ingredient strategy, and search radius.
3. Review the exact cookware, ingredients, spices, calories, and hunger result.
4. Press **Cook** and let the vanilla timed actions run.

## Supported meals

| Meal | Cookware | Water required |
| --- | --- | --- |
| Soup | Pot or Forged Pot | Yes |
| Stew | Pot or Forged Pot | Yes |
| Stir-fry | Frying Pan, Forged Pan, or Griddle Pan | No |
| Roasted Vegetables | Roasting Pan | No |

## Requirements and limits

- A reachable powered non-microwave stove.
- Compatible cookware and raw ingredients within the configured search radius.
- A reachable water source for soup and stew.
- Build 42 single-player; multiplayer execution is deliberately blocked because no network protocol is implemented.
- Other mods that replace the tracked dish object during cooking are not guessed automatically; the session fails safely instead.

## Reliability model

Cooking is an observed state machine, not a fire-and-forget action queue. Every step verifies the resulting game state before advancing. Sessions reject duplicate and stale callbacks, track the exact dish object, distinguish a stove enabled by the mod from an already-running stove, and converge success, failure, and cancellation through one cleanup path.

See [ARCHITECTURE.md](ARCHITECTURE.md) for module boundaries and runtime contracts.

## Ingredient selection

- Search the player inventory, nested bags, reachable containers, and nearby floor items.
- Skip rotten, cooked, burnt, and already-composed food.
- Use no more than two portions of one item type and respect the vanilla recipe's ingredient limit.
- Choose maximum calories, minimum calories, or maximum hunger relief.
- Allow frozen food with a cooking-time penalty proportional to the frozen share of the meal.

## Development

From the repository root:

```powershell
./tools/check.ps1 -Mod cook-it-for-me
./tools/watch.cmd cook-it-for-me
```

The check runs Lua 5.1 parsing, dependency and translation validation, the complete offline test suite, and Forge Live's protocol tests. [DEVELOPMENT.md](DEVELOPMENT.md) documents staging, hot reload, restart boundaries, and Workshop verification.

Offline mocks cover failure and cancellation paths but cannot prove Project Zomboid engine behavior. Game-dependent scenarios still require in-game verification.

## Bug reports

Open an [issue](https://github.com/thesky946/pz-mods/issues/new/choose) with the game build, reproduction steps, enabled mods, and the relevant `console.txt` excerpt.

## Copyright

Copyright © 2026 thesky. No license is granted; all rights are reserved.
