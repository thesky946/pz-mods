package.path = "../42/media/lua/shared/?.lua;../42/media/lua/client/?.lua;./?.lua;" .. package.path
local Env = require "support/cook_env"
local function eq(a, b, message) assert(a == b, message .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

-- A transfer from an invalidated run must not append more actions.
local e = Env.new()
local plan = assert(e.cook.plan(e.player, "Soup"))
e.cook.start(e.player, "Soup", plan)
local staleCallback = e.queue[1].callback
e.cook.cancel()
e.cook.start(e.player, "Soup", plan)
local queued = #e.queue
staleCallback()
eq(#e.queue, queued, "stale transfer continuation")
eq(queued, 1, "restart clears previous queued actions")
e:drain()
eq(e:state().addedCount, 1, "only current run added ingredients")

-- The monitor follows the owner passed to start, not a global player.
getPlayer = function() error("global player must not be consulted") end
e.tick()
e.pot.cooked = true
e.tick()
e:drain()
eq(e:state().active, false, "completed")
eq(e:state().delayNext, nil, "completion clears continuation")

-- Successful previous cooking cannot make a new empty dish appear valid.
e.pot = e.source:AddItem(Env.item("Base.Pot"))
e.collected.cookware = { e.pot }
e.food = e.source:AddItem(Env.item("Base.Carrot", 40))
e.collected.foods = { e.food }
e.recipe.isItemUsableInRecipe = function() return false end
e.cook.start(e.player, "Soup", assert(e.cook.plan(e.player, "Soup")))
e:drain()
eq(e:state().active, false, "empty new run fails")
eq(e:state().addedCount, 0, "counter belongs to one run")
eq(e.on, false, "empty dish does not start heating")
eq(e.messages[#e.messages], "UI_CookItForMe_PlanChanged", "empty dish error")

-- Cancelling while a delay is pending clears both timer and continuation.
e = Env.new()
e.cook.start(e.player, "Soup", assert(e.cook.plan(e.player, "Soup")))
while not e:state().delayNext do
    local action = assert(table.remove(e.queue, 1))
    if action.perform then action.perform() end
    if action.callback then action.callback() end
end
local delayed = e:state().delayNext
e.zombies = { { getX = function() return 1 end, getY = function() return 0 end, getZ = function() return 0 end } }
e.tick()
eq(e:state().active, false, "cancelled")
eq(e:state().delayNext, nil, "cancel clears callback")
eq(e:state().delayUntil, nil, "cancel clears time")
delayed()
eq(#e.queue, 0, "saved delay is invalid after cancellation")

-- A failed request must report to its caller and never leak failKey globally.
e = Env.new()
e.scan.stove = nil
failKey = nil
e.cook.start(e.player, "Soup")
eq(failKey, nil, "no global failKey")
eq(e.messages[1], "UI_CookItForMe_NoStove", "failed start message")

-- Reloading the facade preserves the running session and one event handler.
e = Env.new()
e.cook.start(e.player, "Soup", assert(e.cook.plan(e.player, "Soup")))
local state, tick = e:state(), e.tick
dofile("../42/media/lua/shared/CookItForMe_Cook.lua")
eq(e:state(), state, "reload preserves session")
eq(e.tick, tick, "reload keeps event handler")
e:drain()
eq(e:state().cooking, true, "reloaded run continues")
print("LIFECYCLE TESTS PASSED")
