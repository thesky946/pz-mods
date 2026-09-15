-- ForgeLiveBridge_Client.lua
-- PZ Forge Live: the in-game half of the hot-reload loop, for B42 mod development.
--
-- WHAT IT DOES: watches a command file and, when asked to "reload <path.lua>",
-- calls the engine's own reloadLuaFile() on it. That is all.
--
-- WHAT IT DELIBERATELY DOES NOT DO: run arbitrary code. A file-driven eval
-- channel is remote code execution on the machine of whoever installs it, so it
-- does not ship here. Add it to your own copy if you want it for local dev.
--
-- DEVELOPMENT ONLY. Do not hand this to players and do not put it on a
-- production server.
--
-- PROTOCOL (files under <Zomboid>/Lua/forgelive/):
--   cmd.txt     written by the CLI:  "<id>\treload\t<absolute path to .lua>\n"
--   result.txt  written by us:       {"id":"..","ok":true,"value":".."}

ForgeLive = ForgeLive or { lastId = nil, ticks = 0, warned = false }
ForgeLive.VERSION = "0.2.0"

local CMD = "forgelive/cmd.txt"

-- THIS ONE COSTS YOU HALF A DAY IF YOU DO NOT KNOW IT:
-- in B42 (verified on 42.20) getFileWriter RETURNS NIL for .json files. No error,
-- no log line -- it simply does not write. Any bridge that answers in .json dies
-- right there, silently. That is why the reply goes to a .txt.
local RES = "forgelive/result.txt"

local CHECK_EVERY_TICKS = 15   -- ~4 polls/second; one file-open attempt each

local function log(s) print("[ForgeLive] " .. s) end

local function reply(id, ok, value)
    local w = getFileWriter(RES, true, false)
    if not w then log("could not open " .. RES .. " for writing") return end
    -- Windows paths contain backslashes, and in JSON a backslash starts an escape.
    -- Without this the CLI gets invalid JSON and concludes the game never answered
    -- -- even though the reload actually happened.
    local safe = tostring(value):gsub("\\", "/"):gsub('"', "'")
    w:write('{"id":"' .. tostring(id) .. '","ok":' .. tostring(ok == true) ..
            ',"value":"' .. safe .. '","bridge":"' .. ForgeLive.VERSION .. '"}')
    w:close()
end

-- Read the WHOLE file and join it, instead of trusting a single readLine():
-- if the external writer does not end the file with a newline, one readLine()
-- can return nil and the command vanishes without a trace.
local function readCmd()
    if not getFileReader then return nil end
    local r = getFileReader(CMD, false)
    if not r then return nil end          -- normal: no command pending
    local parts = {}
    local line = r:readLine()
    while line do
        table.insert(parts, line)
        line = r:readLine()
    end
    r:close()
    if #parts == 0 then return nil end
    return table.concat(parts, "\n")
end

local function doReload(id, path)
    if not path or path == "" then
        reply(id, false, "empty path") return
    end
    if not string.find(string.lower(path), "%.lua$") then
        reply(id, false, "refused: only .lua files") return
    end
    if not reloadLuaFile then
        reply(id, false, "reloadLuaFile not available in this build") return
    end
    local ok, err = pcall(function() reloadLuaFile(path) end)
    if ok then
        log("reloaded: " .. path)
        reply(id, true, "reloaded: " .. path)
    else
        reply(id, false, "reload error: " .. tostring(err))
    end
end

local function pump()
    ForgeLive.ticks = ForgeLive.ticks + 1
    if ForgeLive.ticks % CHECK_EVERY_TICKS ~= 0 then return end

    local text = readCmd()
    if not text then return end

    local id, kind, payload = text:match("^([^\t]*)\t([^\t]*)\t(.*)$")
    if not id then
        if not ForgeLive.warned then
            ForgeLive.warned = true
            log("read the file but it does not match the format: [" .. text .. "]")
        end
        return
    end
    if id == ForgeLive.lastId then return end     -- already handled
    ForgeLive.lastId = id

    if kind == "reload" then
        doReload(id, payload)
    elseif kind == "ping" then
        reply(id, true, "pong v" .. ForgeLive.VERSION)
    else
        reply(id, false, "unknown command (this bridge supports: ping, reload)")
    end
end

-- OnTick only fires INSIDE the world; OnRenderTick also fires in menus and while
-- paused. Registering both means the channel answers in more situations -- which
-- matters, because you often want to reload right after loading a save.
Events.OnTick.Add(pump)
Events.OnRenderTick.Add(pump)

log("bridge loaded v" .. ForgeLive.VERSION .. " (development only)")
