-- pattern-DysLive.lua -- the reloadable-module pattern for PZ Forge Live.
--
-- Copy this INTO YOUR OWN MOD (media/lua/shared/). It is plain Lua with no
-- dependency on the bridge or the CLI: your mod keeps working normally for
-- players who never heard of Forge Live.
--
-- ============================ THE PROBLEM ============================
-- reloadLuaFile() RE-EXECUTES the file. That means its Events.OnX.Add(...) calls
-- run again, and now TWO handlers do the same work. Reload ten times and you have
-- ten. Nothing errors. Your mod just silently does everything N times and gets
-- slower with every save. This is the biggest trap in Lua hot-reload, and it is
-- why "just call reloadLuaFile" is not a dev loop on its own.
--
-- ============================ THE USE ============================
-- Replace   Events.OnTick.Add(fn)
-- with      DysLive.on(Events.OnTick, "mymod_tick", fn)
-- The name is the identity: on reload the previous handler registered under that
-- name is removed before the new one goes in. One handler, always.
--
-- ============================ STATE RULES ============================
--   keep across reloads  ->  MyMod.state = MyMod.state or {}
--                            (or-init, never plain assignment, or the player
--                            loses their progress every time you hit save)
--   drop on reload       ->  clear it in DysLive.onReload: task queues, timers,
--                            in-flight actions. Stale queues surviving a reload
--                            are the second-biggest source of confusing bugs.
--
-- ============================ HONEST STATUS ============================
-- We built this to solve duplicate handlers, then measured the problem on 42.20
-- and could not reproduce it: three reloads via reloadLuaFile left ZERO live
-- handlers from the file, while a control handler registered from the in-game
-- console counted normally. See docs/KNOWN-LIMITS.md for the numbers.
--
-- So on this build, reloadLuaFile appears not to re-register events at all --
-- meaning no duplication, but also no NEW handlers from a reload.
--
-- Why keep this pattern anyway? Because it makes registration explicit and
-- idempotent, so your mod behaves the same whichever reload mechanism you use
-- (loadstring-based tools DO report duplication) and whichever way a future
-- build jumps. Events.<X>.Remove(fn) is verified to work on 42.20, so the
-- removal path is sound.

DysLive = DysLive or {}
DysLive.handlers = DysLive.handlers or {}      -- name -> { event = ..., fn = ... }
DysLive.gen = (DysLive.gen or 0) + 1           -- generation: 1 = original load
DysLive.onReloadHooks = DysLive.onReloadHooks or {}

-- Register a named handler, removing any previous one under the same name.
function DysLive.on(event, name, fn)
    if not event or not name or not fn then return false end
    local prev = DysLive.handlers[name]
    if prev and prev.event and prev.fn then
        local ok = pcall(function() prev.event.Remove(prev.fn) end)
        if not ok then
            -- If Remove ever stops working on some build you need the indirection
            -- fallback instead: register ONE stable wrapper that calls
            -- MyMod._impl.whatever, and only swap _impl on reload.
            print("[DysLive] WARNING: Remove failed for '" .. tostring(name) ..
                  "' -- handlers may be duplicating")
        end
    end
    event.Add(fn)
    DysLive.handlers[name] = { event = event, fn = fn }
    return true
end

-- Cleanup hook: runs on reload (gen > 1), not on the original load.
function DysLive.onReload(name, fn)
    DysLive.onReloadHooks[name] = fn
    if DysLive.gen > 1 and type(fn) == "function" then
        local ok, err = pcall(fn)
        if not ok then print("[DysLive] onReload '" .. tostring(name) .. "' failed: " .. tostring(err)) end
    end
end

-- How many named handlers are currently registered.
function DysLive.count()
    local n = 0
    for _ in pairs(DysLive.handlers) do n = n + 1 end
    return n
end

-- Print a marker you (or the CLI) can grep in console.txt to confirm a reload landed.
function DysLive.mark(modName)
    print("[" .. tostring(modName) .. "] DysLive gen " .. DysLive.gen ..
          " (" .. DysLive.count() .. " handlers)")
end

print("[DysLive] ready, gen " .. DysLive.gen)
