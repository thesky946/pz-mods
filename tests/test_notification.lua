package.path = "../42/media/lua/shared/?.lua;./?.lua;" .. package.path
local Env = require "support/cook_env"

-- Default on, persisted off/on, no early/repeated success, cancellation,
-- burnt food, failed transfer, active stove, and unavailable audio API.
for _, mode in ipairs({ "on", "off", "cancel", "burnt", "transferFailed", "stoveOn", "audioError" }) do
    local e = Env.new()
    local sounds = 0
    getSoundManager = function() return { playUISound = function(_, name)
        assert(name == "StoveTimerExpired")
        assert(e.pot:getContainer() == e.inv and not e.on)
        sounds = sounds + 1
        if mode == "audioError" then error("audio unavailable") end
    end } end
    assert(CookItForMe.getSettings(e.player).completionSound == true)
    CookItForMe.saveSettings(e.player, { completionSound = false })
    assert(CookItForMe.getSettings(e.player).completionSound == false)
    CookItForMe.saveSettings(e.player, { completionSound = mode ~= "off" })
    e.cook.start(e.player, "Soup", assert(e.cook.plan(e.player, "Soup")))
    e:drain()
    assert(sounds == 0 and #e.messages == 0)
    e.pot.cooked = true
    e.pot.burnt = mode == "burnt"
    e.tick()
    assert(sounds == 0 and #e.messages == 0, "must wait for retrieval")
    local retrieve = assert(table.remove(e.queue, 1))
    if mode == "cancel" then
        e.cook.execution.cancel()
    elseif mode ~= "transferFailed" then
        retrieve.perform()
    end
    if mode == "stoveOn" then e.on = true end
    retrieve.callback()
    retrieve.callback()
    e.tick()
    assert(not e:state().active)
    local success = mode == "on" or mode == "off" or mode == "audioError"
    assert(sounds == ((success and mode ~= "off") and 1 or 0), mode .. " sound count")
    assert(#e.messages == 1, mode .. " exactly one outcome message")
    if not success and mode ~= "burnt" then
        assert(not e.messages[1]:find("UI_CookItForMe_Done", 1, true), "failure must not report success")
    end
end
getSoundManager = nil
print("NOTIFICATION TESTS PASSED")
