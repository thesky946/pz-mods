# PZ Forge Live

**Save a `.lua`, see it in the running game. No restart.** A hot-reload dev loop for
Project Zomboid Build 42 mods — client *and* dedicated server.

> **Status: alpha.** Verified on **42.20.0**. Everything marked ✅ below was observed in
> a log, not assumed. What is unproven says so — see
> [docs/KNOWN-LIMITS.md](docs/KNOWN-LIMITS.md).

```
$ node cli/forge-live.mjs --mod MyMod
[forge-live] syntax gate: ON
[MyMod] media/lua/client/MyMod_Client.lua: RELOADED in 149ms
```

---

## Why

The normal B42 mod loop is: edit → zip → upload → **restart** → get back in-world →
discover you had a typo. On a dedicated server, add ~8 minutes and every player has to
log back in. Most of the day goes to waiting for a one-line change.

The engine has had the pieces to fix this for a long time: `reloadLuaFile()` on the
client, and the `reloadlua` admin command on the server. What did not exist is the loop
around them — the watcher, the safety gate, the file sync, honest feedback, and the
pattern that stops reloading from quietly duplicating your event handlers.

That is this project.

## What it does

```
you save a .lua in your repo
   -> gate:   UTF-8 BOM / non-ASCII bytes / Lua 5.1 parse
              a broken file NEVER reaches the game
   -> sync:   copy to every installed path (Zomboid/mods + your Workshop staging)
   -> reload: ask the game to run reloadLuaFile() on it
   -> report: print what the game actually answered, and how long it took
```

The client side goes through a small companion mod (`ForgeLiveBridge`) that talks over
files. The server side goes through **RCON**, so no admin has to be logged in to type a
chat command — it is fully scriptable.

## Verified on 42.20

| Capability | |
|---|---|
| `reloadLuaFile(path)` re-executes the file | ✅ |
| ...with a relative path and with an absolute one | ✅ |
| ...on a file that did **not** exist at boot (add new files live) | ✅ |
| `Events.<X>.Remove(fn)` | ✅ |
| Server `reloadlua "<file>"` over RCON, no restart | ✅ |
| `DoLuaChecksum` checks at **login**, not continuously | ✅ — see below |
| Edit → reload → see it, **while connected to a dedicated server** | ✅ |
| N reloads still leaving exactly 1 handler | ❓ unmeasured |

## Multiplayer: the anti-cheat is not the wall you think

`DoLuaChecksum=true` is why most people assume you cannot touch Lua on a live server.
On 42.20 it turns out to check **when a client connects**, and not again after that.

- **Editing while already connected: no kick.** We changed a mod's client `.lua` on disk
  and stayed connected for over three minutes, with nothing in either log.
- **Reconnecting with mismatched files: kicked.** That path is real —
  `user <name> will be kicked in 8000ms because Lua/script checksums do not match`.

So you can iterate during a session; just be in sync before you reconnect.

**And the reload itself works while connected.** We edited a mod's client `.lua` mid-session
on a real server, reloaded it, and the new code ran:

```
[Captive] client loaded v0.3.1 -- HOT-RELOAD IN MULTIPLAYER
```

No errors, connection kept.

> ### ⚠️ The one thing that will waste your evening
>
> Connecting to a server makes PZ **rebuild the Lua state from the SERVER's mod list**.
> Any mod you have that the server does not list is **silently dropped** for that session
> — the connection is still accepted, you just do not get your mod.
>
> So **the bridge must be in the server's `Mods=` line** for the automated loop to work
> there. Fine for a server you control, which is the use case — but nothing warns you,
> and the symptom looks exactly like "the tool is broken".
>
> No server access? PZ's **in-game Lua console works in multiplayer**: type
> `reloadLuaFile("<absolute path>")` and it applies. That is how we proved this.

Full details and caveats in
[KNOWN-LIMITS.md](docs/KNOWN-LIMITS.md#the-doluachecksum-answer-this-matters-most-for-multiplayer).

## Quick start (client)

1. Copy `mod/ForgeLiveBridge/` into `<Zomboid>/mods/`.
2. Enable it — **and if you are loading an existing save, add it to that save's own
   `mods.txt`** (`Saves/<mode>/<id>/mods.txt`). Ticking it in the MODS menu is not
   enough for a save that already exists. This one trips everybody once, including us.
3. `cp forge-live.config.example.json forge-live.config.json`, point `src` at your
   mod's source folder and `targets` at wherever the game loads it from.
4. `npm i luaparse` — optional, but without it you lose the syntax gate.
5. Start the game, then:

```bash
node cli/forge-live.mjs --mod MyMod          # watch, reload on save
node cli/forge-live.mjs --dry                # gate + report only, write nothing
node cli/forge-live.mjs --once path/to.lua   # one file, then exit
node cli/forge-live.mjs --mod MyMod --translations # reload game translations, then exit
```

## Quick start (dedicated server)

Needs `RCONPassword` and `RCONPort` in your server `.ini`. **Use a dev/lab server.**

```bash
node cli/forge-live-server.mjs \
  --host 1.2.3.4 --port 27015 --password "$PZ_RCON_PASSWORD" \
  --file MyMod/media/lua/server/MyMod_Server.lua \
  --dest user@host:/path/to/mods/MyMod/media/lua/server/MyMod_Server.lua \
  --watch
```

Observed on a 42.20 dedicated server:

```
> reloadlua "MyMod_Server.lua"
Lua file reloaded
[MyMod] server loaded v0.3.0 -- edited without a restart
```

## Event handlers: what we measured, and how it changed our mind

The received wisdom — which we repeated in an earlier version of this README — is that
`reloadLuaFile()` re-executes the file, so its `Events.OnTick.Add(fn)` runs again and you
end up with duplicate handlers.

**We measured it on 42.20 and got the opposite result.** A file loaded three times via
`reloadLuaFile` registered a counter each time; after thousands of frames, **all three
counters read zero**. A control handler registered straight from the in-game Lua console
counted 623 in the same window, so the event itself was firing fine.

```
[FHT] RESULT -> reloads=3  handlers ALIVE=0   detail: g1=0 g2=0 g3=0
[TT]  control handler after a few seconds: n=623
```

Two consequences, one good and one you need to know about:

- ✅ **Reloading does not appear to duplicate handlers** — at least not via
  `reloadLuaFile` on this build.
- ⚠️ **Reloading also does not install *new* handlers.** If your edit adds an
  `Events.X.Add`, expect it not to take effect until you restart. Edits to the *body* of
  code that already runs are what reload is good at.

> **Caveat, stated plainly:** this was measured in a multiplayer session and we have not
> cross-checked it in single player, and we do not know the mechanism. Other tools that
> reload via `loadstring` instead of `reloadLuaFile`
> ([PZModReload](https://github.com/deckard93/PZModReload)) do report duplication, so the
> two approaches may genuinely differ. If you can reproduce or contradict this, please
> open an issue — see [PRIOR-ART.md](docs/PRIOR-ART.md).

The pattern below is still worth using: it makes your registration explicit and
idempotent regardless of which reload mechanism you or a future build ends up with. Copy
[`mod/pattern-DysLive.lua`](mod/pattern-DysLive.lua) into your mod and register by name:

```lua
-- instead of Events.OnTick.Add(onTick)
DysLive.on(Events.OnTick, "mymod_tick", onTick)

-- state that should survive a reload: or-init, never plain assignment
MyMod.state = MyMod.state or { trust = {} }

-- state that should be thrown away: clear it here
DysLive.onReload("mymod", function() MyMod.taskQueue = {} end)
```

It is plain Lua with no dependency on this tool. Ship it with your mod; players never
know it is there.

## What cannot be hot-reloaded

The engine reads some things exactly once, at boot. The CLI detects these and tells you
to restart instead of pretending it worked:

| Thing | Why |
|---|---|
| `.txt` scripts (items, `craftRecipe`) | parsed once by ScriptManager at boot |
| `mod.info` | read at boot |
| New models / textures | cached by the engine |

Mitigation for the first: move tunable numbers out of `.txt` and into a Lua table. Lua
is hot; scripts are not.

## Three silent failures this cost us, so it does not cost you

Each of these fails **with no error message**, which is exactly what makes them
expensive. If you are building something similar, these are the landmines:

1. **`getFileWriter` returns `nil` for `.json` files on 42.20.0.** No error, no log line —
   it just does not write. Any file bridge that answers in `.json` dies right there.
   Use `.txt`. This one alone cost us most of a night.
   *(Reportedly fixed in 42.20.1 — thanks SimKDT [PZMC]. We have not re-tested; `.txt` is
   still the safe choice if you support older builds.)*
2. **A command file with no trailing newline can be invisible.** PZ's `readLine()` may
   return nil and your command vanishes. Always end with `\n`, and read the whole file
   instead of trusting a single `readLine()`.
3. **Windows paths inside a JSON reply.** `C:\Users\...` — in JSON a backslash starts an
   escape, so the reply is invalid JSON and your tool reports "the game never answered"
   while the reload actually succeeded. Normalize to `/`.

## Security

The bridge supports `ping`, `reload`, and the fixed `translations` action, which calls
`Translator.loadFiles()`. `reload` refuses anything that is not a `.lua`. There is
**deliberately no `eval`**: a file-driven eval channel is remote code execution on the
machine of whoever installs it.

**Development only.** Do not hand the bridge to players. Do not put it on a production
server.

## Contributing

The most useful contributions right now are the ❓ rows above and the "unproven"
section of [docs/KNOWN-LIMITS.md](docs/KNOWN-LIMITS.md) — especially:

- closing the **full loop with a client connected to a server** (our reload channel went
  quiet in that exact combination and we have not found out why),
- an independent **handler count** after N reloads,
- reproducing, or contradicting, any of our `DoLuaChecksum` observations.

A log excerpt is worth more than an opinion. Contradicting us with evidence is more
welcome than agreeing with us without it.

MIT. Not affiliated with The Indie Stone.
