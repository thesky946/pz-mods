local source = "tools/forge-live/mod/ForgeLiveBridge/42/media/lua/client/ForgeLiveBridge_Client.lua"
local commandText
local resultText
local pump
local calls = 0

Events = {
    OnTick = { Add = function(callback) pump = callback end },
    OnRenderTick = { Add = function() end },
}
Translator = {
    loadFiles = function() calls = calls + 1 end,
}

getFileReader = function(path)
    assert(path == "forgelive/cmd.txt")
    if not commandText then return nil end
    local text = commandText
    commandText = nil
    local read = false
    return {
        readLine = function()
            if read then return nil end
            read = true
            return text
        end,
        close = function() end,
    }
end

getFileWriter = function(path)
    assert(path == "forgelive/result.txt")
    local chunks = {}
    return {
        write = function(_, text) chunks[#chunks + 1] = text end,
        close = function() resultText = table.concat(chunks) end,
    }
end

dofile(source)
local function process(command)
    commandText = command
    for _ = 1, 15 do pump() end
end

process("translation-ok\ttranslations\t")
assert(calls == 1, "successful command must call Translator.loadFiles exactly once")
assert(resultText:match('"id":"translation%-ok"'))
assert(resultText:match('"ok":true'))

Translator.loadFiles = function() error("synthetic loader failure") end
process("translation-error\ttranslations\t")
assert(resultText:match('"id":"translation%-error"'))
assert(resultText:match('"ok":false'))
assert(resultText:match("translation reload error:"))

print("BRIDGE TRANSLATION TEST PASSED")
