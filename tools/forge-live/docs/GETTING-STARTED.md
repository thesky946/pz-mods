# Getting started

Goal: **you save a `.lua`, and the running game picks it up.** Ten minutes, and most of
that is you finding your own folders.

If something does not work, jump to [When it does not work](#when-it-does-not-work) —
it lists every failure we hit ourselves, and what each one actually means.

---

## Before you start

- **Project Zomboid Build 42** (verified on 42.20.0)
- **Node.js 18+**
- A mod you are working on, with its source somewhere you edit it

You do **not** need `-debug` mode. You do **not** need to be an admin. You do not need
to change any game setting.

---

## Step 1 — Install the bridge mod

Copy the folder `mod/ForgeLiveBridge/` into your Zomboid mods folder:

| OS | Path |
|---|---|
| Windows | `C:\Users\<you>\Zomboid\mods\` |
| Linux | `~/Zomboid/mods/` |
| macOS | `~/Zomboid/mods/` |

You should end up with `…/Zomboid/mods/ForgeLiveBridge/42/mod.info`.

## Step 2 — Enable it, in the right place

Start the game, go to **MODS**, tick **Forge Live Bridge**.

> ### ⚠️ If you are loading an EXISTING save, this is not enough
>
> A save keeps **its own** mod list, separate from the menu. Ticking the mod in the MODS
> screen does not add it to a world that already exists.
>
> Open `Zomboid/Saves/<mode>/<save id>/mods.txt` and add the line yourself:
>
> ```
> mods
> {
>     mod = ForgeLiveBridge,
>     mod = YourOtherMod,
> }
> ```
>
> Mind the four-space indent and the trailing comma — match the lines already there.
>
> This cost us an entire debugging session. We were convinced `Events.OnTick` was broken
> in 42.20 and wrote it up as an engine bug. It was not. Our mod simply was not loaded in
> that save, so every measurement came from the main menu, where there is no world and
> therefore no world tick. **Starting a brand-new world avoids this entirely**, because
> new worlds inherit the enabled list.

You know it worked when `console.txt` says:

```
[ForgeLive] bridge loaded v0.2.0 (development only)
```

## Step 3 — Tell the CLI where your mod lives

```bash
cp forge-live.config.example.json forge-live.config.json
```

Edit it:

```json
{
  "mods": [
    {
      "id": "MyMod",
      "src": "C:/dev/MyMod",
      "targets": [
        "C:/Users/YOU/Zomboid/mods/MyMod",
        "C:/Users/YOU/Zomboid/Workshop/MyMod/Contents/mods/MyMod"
      ],
      "bridgeDir": "C:/Users/YOU/Zomboid/Lua/forgelive"
    }
  ]
}
```

- **`src`** — where you *edit*. Your repo.
- **`targets`** — every place the game might *load* from. **List them all.** If you have
  a Workshop staging copy and only sync `Zomboid/mods`, the game may keep running the
  other one and you will swear the tool is broken. (Yes, this happened to us too.)
- **`bridgeDir`** — always `<Zomboid>/Lua/forgelive`.

Use forward slashes everywhere, including on Windows.

## Step 4 — Turn on the syntax gate (worth 30 seconds)

```bash
npm i luaparse
```

Without it everything still works, but a file with a typo will reach the game and break
your Lua state — exactly what this tool exists to prevent.

## Step 5 — Your first hot reload

Start the game and load your world. Then, in a terminal:

```bash
node cli/forge-live.mjs --mod MyMod
```

Now add a line to any client `.lua` of your mod:

```lua
print("[MyMod] hello from a running game")
```

Save. The terminal should say:

```
[MyMod] media/lua/client/MyMod_Client.lua: RELOADED in 149ms
```

…and that line appears in `console.txt` without you touching the game.

**That is the whole loop.** Everything below is refinement.

---

## Step 6 — Stop your handlers from duplicating (do not skip this)

Here is the thing that bites everyone once they start reloading for real.

`reloadLuaFile()` **re-executes** the file. So this line runs again:

```lua
Events.OnTick.Add(onTick)
```

Now there are **two** `onTick` handlers. Reload ten times, ten handlers. There is **no
error message**. Your mod just quietly does everything ten times and gets slower every
time you save, and you spend an afternoon hunting a performance bug that you created by
saving a file.

Copy [`mod/pattern-DysLive.lua`](../mod/pattern-DysLive.lua) into your mod's
`media/lua/shared/` and register by name instead:

```lua
-- before
Events.OnTick.Add(onTick)

-- after
DysLive.on(Events.OnTick, "mymod_tick", onTick)
```

The name is the identity. On reload the old handler under that name is removed first.

**State rules, which matter just as much:**

```lua
-- survives reloads: or-init, NEVER a plain assignment
-- (plain assignment wipes your player's progress every time you hit save)
MyMod.state = MyMod.state or { trust = {} }

-- should NOT survive: task queues, timers, in-flight actions
DysLive.onReload("mymod", function() MyMod.taskQueue = {} end)
```

It is plain Lua with no dependency on this tool. Ship it with your mod; players never
know it is there.

Credit: the core of this pattern was published first by
[PZModReload](https://github.com/deckard93/PZModReload) — see
[PRIOR-ART.md](PRIOR-ART.md).

---

## Step 7 — Dedicated server (optional)

If you develop against a dedicated server, you can reload **server-side** code without
restarting it. This is the part no other tool does.

Your server `.ini` needs:

```ini
RCONPassword=something-long
RCONPort=27015
```

Then:

```bash
node cli/forge-live-server.mjs \
  --host 1.2.3.4 --port 27015 --password "$PZ_RCON_PASSWORD" \
  --file MyMod/media/lua/server/MyMod_Server.lua \
  --dest user@host:/path/to/mods/MyMod/media/lua/server/MyMod_Server.lua \
  --watch
```

What you should see:

```
> reloadlua "MyMod_Server.lua"
Lua file reloaded
[MyMod] server loaded v0.3.0
```

**Use a dev/lab server.** Reloading server Lua under live players is not something this
tool can make safe for you — and see the honest warning about
[`DoLuaChecksum`](KNOWN-LIMITS.md) before you try it with anyone connected.

---

## When it does not work

Every row here is something that actually happened to us.

| What you see | What it means | Fix |
|---|---|---|
| `timeout: the game did not answer` | Bridge not loaded, or not loaded **in this save** | Check `console.txt` for `[ForgeLive] bridge loaded`. If it is missing, see Step 2 |
| Bridge loaded, still no answer | You are at the main menu with an older bridge | v0.2.0 also listens on `OnRenderTick`, so it answers in menus. Confirm your version in the log |
| `RELOADED`, but the game behaves the same | The game is loading a **different copy** | You missed a path in `targets`. List every install location |
| Mod acts strangely after several reloads | Duplicated handlers | Step 6 |
| Player progress resets when you save a file | You wrote `MyMod.state = {}` instead of `= MyMod.state or {}` | Step 6, state rules |
| `BLOCKED — the game never sees this file` | The gate did its job | Read the reason it printed; fix the file |
| Console spam about `Error 11` / "Reloading lua" | A non-ASCII character or a BOM slipped in | That is what the gate prevents — install `luaparse` |
| You changed an item or a recipe and nothing happened | `.txt` scripts are parsed once at boot | Restart. Or move tunable numbers into a Lua table, which *is* hot |

### Reading the game's own log

`console.txt` lives next to your saves (`Zomboid/console.txt`). It is the ground truth —
if the tool and the log disagree, the log is right.

Useful habit: have your mod print its version at load.

```lua
print("[MyMod] client loaded v" .. MyMod.VERSION)
```

Then you can always tell *which* build is actually running, instead of assuming.

---

## Habits worth stealing

- **Bump the version string on every change.** When something looks wrong, the first
  question is always "is the build I think I am testing the one that is running?" A
  version in the log answers it in one second.
- **Trust the log, not the tool.** Ours once reported "the game never answered" while
  the reload had succeeded — the reply was invalid JSON because of a Windows path. If
  the log shows your change, your change landed.
- **Before blaming the engine, check that your code is even loaded.** We wasted hours
  proving an engine bug that turned out to be a mod missing from a save's mod list.
- **A pcall that swallows an error is worse than a crash.** If a branch can fail
  silently, log it. Most of the time we lost went to failures that printed nothing at
  all.

---

## Where to ask

Open an issue. Please include:

- your PZ build number,
- the `[ForgeLive]` lines from `console.txt`,
- what the CLI printed.

A log excerpt is worth ten paragraphs of description.
