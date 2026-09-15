# Known limits, and what is actually proven

This file exists so you can tell our measurements apart from our hopes. Build tested:
**42.20.0 (a2947723ca)**, Windows client + Linux dedicated server.

---

## Proven (observed in a log)

| Claim | Evidence |
|---|---|
| `reloadLuaFile(path)` re-executes a file | a marker file printing its own generation went `gen=1 -> 2 -> 3` without a restart |
| Works with a **relative** path (`media/lua/client/X.lua`) | ✅ |
| Works with an **absolute** path (`C:/.../X.lua`) | ✅ — so the CLI can pass the path it already has |
| Loads a file that **did not exist at boot** | a `.lua` never present in the boot load order was loaded live |
| `Events.<X>.Remove(fn)` raises no error | ✅ — the `DysLive` pattern needs no fallback |
| `Events.OnTick` fires in-world | ✅ |
| `Events.OnRenderTick` fires in menus **and** in-world | ✅ — the only one alive at the main menu |
| `getFileWriter` / `getFileReader` work for `.txt` | ✅ |
| Server `reloadlua "<file>"` works over **RCON**, no restart | `Lua file reloaded` + the mod's new marker in the server log |
| **`DoLuaChecksum` checks at LOGIN, not continuously** | see below — this is the one that decides whether MP development is viable |
| **`reloadLuaFile` works while connected to a dedicated server** | edited a mod's client `.lua` on disk mid-session, reloaded it, the new code ran, no errors, connection kept |
| A server accepts a **connection** from a client carrying extra mods it does not list | no "mods don't match" refusal |
| ...but those extra mods are **NOT loaded** in the session | see the trap below |

## The multiplayer trap: your dev mod is dropped on connect

When you connect to a dedicated server, PZ **rebuilds the Lua state using the SERVER's
mod list**. Anything you have installed that the server does not list is silently
discarded for that session. The connection is still accepted — you just do not get your
mod.

We lost time to this. Our bridge printed its load marker at boot, we connected, and the
command channel went dead. The bridge was not broken; it was gone. The log said so
plainly once we looked at *which* mods loaded after the connect:

```
mods loaded after connecting: Captive, HelmetOfDead, edenmapa, ... (the server's list)
traces of our dev bridge:     0
```

**What this means for you:** to run the automated loop against a server, the bridge has
to be in that server's `Mods=` line too. That is fine for a server you control, which is
the whole use case — but it is not optional, and nothing warns you.

**Manual fallback that needs no server change:** PZ's in-game Lua command console works
in multiplayer. You can type `reloadLuaFile("<absolute path>")` there and it applies
immediately. That is exactly how we proved the reload works in MP.

## The `DoLuaChecksum` answer (this matters most for multiplayer)

`DoLuaChecksum=true` is what makes people assume you cannot touch Lua on a live server.
We tested it on a 42.20 dedicated server and the behaviour is more forgiving than the
name suggests.

**Editing files while you are already connected does not kick you.** We connected a
client, changed a mod's client-side `.lua` on disk, and stayed connected for over three
minutes with no complaint from the server and nothing in either log.

**Reconnecting with mismatched files does kick you.** That path is real, and the server
log shows it plainly:

```
WARN : Multiplayer at ChecksumPacket.parseServer
     > user <name> will be kicked in 8000ms
       because Lua/script checksums do not match
```

So the check happens when the client sends its checksum packet — at connection time —
and is not re-run afterwards.

**What this means in practice:** you can iterate freely during a session. Just make sure
your files are in sync before you reconnect. That is the same discipline any mod already
demands, so it costs you nothing new.

> ⚠️ Two caveats we will not paper over. Our test changed files on disk without also
> reloading them into the runtime, so we have shown "the server does not re-scan your
> disk", not "a reloaded runtime never trips the check". And the test ran with a single
> client on an idle server. If you reproduce either case differently, please open an
> issue.

## Not proven — do not assume

| Question | Why it matters | Status |
|---|---|---|
| Full edit → reload → see it, with a client connected to a server | The complete multiplayer loop | **Not closed.** Our reload channel did not respond in the MP session; the bridge loaded but stopped processing commands and we have not found out why. Single-player and server-side are both proven; this specific combination is not |
| Why do reloaded files not re-register events? | Explains both the good news and the limitation below | **Mechanism unknown.** We have the observation, not the cause |
| Does the same hold in **single player**? | Our handler test ran in an MP session only | **Not cross-checked** |

## Event handlers: reloading does not seem to duplicate — or to add

We built `pattern-DysLive.lua` to solve duplicate handlers, then measured the problem and
found we could not reproduce it.

**The test.** A file that registers a counting handler, loaded three times via
`reloadLuaFile`, each generation counting into its own slot so "one handler counting 60
times" cannot be confused with "three counting 20 each". Plus a control handler
registered directly from the in-game Lua console.

```
[FHT] RESULT -> reloads=3  handlers ALIVE=0   detail: g1=0 g2=0 g3=0
[TT]  control handler after a few seconds: n=623
```

All three file-registered handlers were dead. The control was alive. The event was
firing; the registrations from the reloaded file simply never took effect. Globals
created by that same file *were* visible from the console afterwards, so it is not a
separate Lua environment.

**What follows:**

- Reloading via `reloadLuaFile` **does not duplicate** your handlers on 42.20.
- It also **does not install new ones**. Adding an `Events.X.Add` in an edit will not
  take effect until a restart. Reload is for changing code that already runs.

**What we do not know:** the mechanism. And we tested this in a multiplayer session only.
[PZModReload](https://github.com/deckard93/PZModReload), which reloads via `loadstring`
rather than `reloadLuaFile`, *does* document duplication — so the two mechanisms may
genuinely behave differently, and neither of us is necessarily wrong. Reproductions or
contradictions welcome.
| Multiplayer with 2+ clients: which side needs which file? | Client UI vs `shared/` vs `server/` reload semantics differ | Not started |
| Does reloading `shared/` on the server desync connected clients? | Protocol changes are the risky class | Not started |
| Behaviour on 42.19 and earlier | We only tested 42.20 | Unknown |

## Hard engine limits (not fixable by this tool)

- **`.txt` scripts** (items, `craftRecipe`, sandbox options): parsed once by
  ScriptManager at boot. Requires a restart. Mitigation: move tunable values into a Lua
  table, which *is* hot.
- **`mod.info`**: read at boot.
- **New models / textures**: cached by the engine.

The CLI detects these and prints "requires a restart" rather than reporting a success
that did not happen.

## Traps that cost us real time

**`getFileWriter` returns `nil` for `.json` — on 42.20.0.** Silently. Our bridge wrote
`state.json` and `result.json` and had worked fine on 42.18/42.19; on 42.20.0 it went
completely mute with no LuaError anywhere. Switching to `.txt` fixed it instantly.

> **Reportedly fixed in 42.20.1** — thanks to **SimKDT [PZMC]** for the correction. We
> have not re-tested on 42.20.1 ourselves yet, so treat this row as "true on 42.20.0,
> likely resolved after". `.txt` remains the safe choice if you support older builds.

**`default.txt` is not a save's mod list.** A save keeps its own list in
`Saves/<mode>/<id>/mods.txt`. Enabling a mod in the MODS menu does not add it to an
existing save. We lost time "proving" that `Events.OnTick` was broken in 42.20 — it was
not; our probe simply was not loaded, so every count came from the main menu, where
there is no world and no world tick. The tell was the counter freezing at the exact
moment the world loaded.

> **Before blaming the engine, verify your code is even loaded.**

**A diagnostic must measure, not assert.** One of our probes printed "the file exists on
disk" about a file we had deleted ourselves, and we nearly blamed the wrong API for it.
If your diagnostic states a fact about the world, make it check that fact.

**A command file with no trailing newline can be invisible.** `readLine()` may return
nil, and the command disappears with no trace.

**Windows paths in JSON replies.** `C:\Users\...` produces invalid JSON, so the tool
reports "no answer" while the reload actually worked. Normalize to `/`.
