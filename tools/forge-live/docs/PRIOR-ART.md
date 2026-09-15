# Prior art

We are not the first people to hot-reload Lua in Project Zomboid, and this file says so
plainly. If you are choosing a tool, read this and pick the one that fits you — possibly
not ours.

---

## Tools that came before this one

### PZModReload — [deckard93](https://github.com/deckard93/PZModReload)
[Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3764185018) · July 2026

An **in-game** watcher. Each mod opts in with a `media/reload.trigger` file and a
`media/reload.filelist`; the mod polls the trigger about once a second and, when it
changes, re-executes the listed files with `getModFileReader` + `loadstring`.

**They published the duplicate-handler pattern before we did.** Their README documents
the problem and gives essentially the same solution we ship as `pattern-DysLive.lua`:

```lua
if MyMod._onTick then Events.OnTick.Remove(MyMod._onTick) end
MyMod._onTick = onTick
Events.OnTick.Add(MyMod._onTick)
```

Credit where it is due: if you found that pattern useful here, deckard93 wrote it down
first. Our version adds named registration and an `onReload` cleanup hook, but the idea
is theirs.

Their README also claims `reloadLuaFile` **cannot load files that did not exist at
boot** (`FileNotFoundException`), which is why they chose `loadstring`. Our measurements
on 42.20 disagree — see [the note below](#a-technical-disagreement).

### pz_lua_hmr — [escapepz](https://github.com/escapepz/pz_lua_hmr)
April 2026

Architecturally the closest to ours: an **external Node watcher** that bundles with
`luabundle`, writes a state file into `~/Zomboid/Lua/`, and has an in-game runtime poll
it and call `reloadLuaFile()`. Uses a directory junction instead of copying. Handles
stale state with `beforeReload` / `afterReload` lifecycle hooks. Self-described as
experimental; client-only.

### Sync-only tooling (no in-game reload)

- **[Project Zomboid Studio](https://github.com/Konijima/project-zomboid-studio)** and
  the VS Code extension of the same name — "Live Sync" updates your Workshop folder on
  save, but nothing reloads inside the running game.
- **Project Zomboid Mod Creator** (`zjdaniels1985`) — its watch mode is
  *"continuous file sync into the output folder"*. Same category.
- **PipeWrench-Template** — `npm run dev` compiles and copies.

### The engine's own facilities

`reloadLuaFile()` and the `reloadlua` admin command are The Indie Stone's, not ours.
There is a manual **F11 → Experimental Mod Reload** (one file, one click, needs
`-debug`) and a **Reset Lua** button on the title screen.

A good measure of how much this hurts: two Workshop mods exist whose entire purpose is
to expose that manual reload button without `-debug` — and one of them has **1,234
subscribers**. People are reloading by hand, a lot.

---

## So what is actually new here

Being honest about the above, here is what we did not find anywhere else:

1. **A validation gate before the file reaches the game.** Every other tool copies
   blindly. We refuse to sync a file with a UTF-8 BOM, non-ASCII bytes, or a Lua 5.1
   syntax error. In PZ a bad `.lua` can take down the whole Lua state, and BOM/encoding
   is a classic failure — catching it in ~5 seconds instead of after a 3-minute restart
   is the difference we care most about.
2. **The game's real verdict, returned to the terminal you saved from.** Others print
   in-game or show a counter. Nobody answers the person who hit save.
3. **Dedicated-server hot-reload over RCON.** We found nothing. The pieces exist
   separately (RCON libraries, a documented `/reloadlua` command) but nobody wired them
   into a dev loop. The closest thing,
   [RemoteModWatchdog](https://github.com/meigrafd/ProjectZomboid-RemoteModWatchdog),
   *restarts* the server over RCON — the opposite of this.
4. **Any multiplayer story.** Both prior tools are explicitly client/singleplayer.

---

## A technical disagreement

PZModReload's README states that `reloadLuaFile` only works on files present at boot,
because path mapping is fixed at startup, and that new files raise
`FileNotFoundException`.

**On 42.20 we observed otherwise.** Two `.lua` files created *after* the game had booted
were loaded successfully by `reloadLuaFile`:

| File | Created | Game booted |
|---|---|---|
| `DysLive.lua` | 21:00 | ~20:53 |
| `ForgeDysLiveTest.lua` | 21:03 | ~20:53 |

Both loaded, both printed their markers, sixteen consecutive reloads without an error.

**Important nuance:** both files lived inside mod folders that *were* registered at boot
(`Captive`, `DemiurgoBridge`). So the accurate claim is probably "a new file inside an
already-loaded mod works", not a flat contradiction — a brand-new *mod* may well behave
as they describe. We have not tested that case.

This is offered as data, not as a correction of anyone. If you can reproduce either
result, please open an issue with a log excerpt — we would rather be wrong in public
than confidently misinform people.

---

## Search coverage (so you know what we did not check)

Searched: GitHub (repo metadata only — code search needs auth), Steam Workshop, npm,
the VS Code Marketplace, PZwiki (via its API; the site 403s automated fetches), Reddit.

**Not searched: PZ modding Discord servers.** They are not indexable without joining,
and that is the most likely place for an undiscovered homebrew script. The Indie Stone
forums also 403 automated requests, so a relevant thread there may exist unseen.

If you know of prior work we missed, please tell us and we will add it here.
