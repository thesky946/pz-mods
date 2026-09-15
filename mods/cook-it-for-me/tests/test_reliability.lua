package.path = "../42/media/lua/shared/?.lua;./?.lua;" .. package.path
local Env = require "support/cook_env"
local failures = {}
local function test(name, f)
    local ok, err = pcall(f)
    if not ok then failures[#failures + 1] = name .. ": " .. tostring(err) end
end
local function start(e)
    assert(e.cook.start(e.player, "Soup", assert(e.cook.plan(e.player, "Soup"))) ~= false)
    e:drain()
end
test("cancelled transfer terminates session", function()
    local e = Env.new()
    e.cook.start(e.player, "Soup", assert(e.cook.plan(e.player, "Soup")))
    e.queue = {}
    for i = 1, 5 do e.now = e.now + 500; e.tick() end
    assert(not e:state().active)
end)
test("frozen penalty and burn margin", function()
    local e = Env.new(); e.food.frozen = true; start(e)
    assert(e.pot.minutes == 150)
    assert(e.pot:getMinutesToBurn() > e.pot:getMinutesToCook())
end)

test("mixed ingredients use frozen share and preserve burn margin", function()
    local e = Env.new(); e.food.frozen = true
    local fresh = e.source:AddItem(Env.item("Base.Carrot", 40))
    e.collected.foods[#e.collected.foods + 1] = fresh
    start(e)
    assert(e:state().addedCount == 2 and e:state().frozenCount == 1)
    assert(e.pot.minutes == 125, "one frozen out of two adds 25 percent, spices excluded")
    local cook, burn = e.pot.minutes, e.pot:getMinutesToBurn()
    e.tick(); e.tick()
    assert(e.pot.minutes == cook and e.pot:getMinutesToBurn() == burn, "penalty is not reapplied")
end)
test("own raw dish is never confused with another cooked dish", function()
    local e = Env.new()
    local other = e.stoveInv:AddItem(Env.item("Base.OtherDish")); other.extra = { "Base.Carrot" }; other.cooked = true
    start(e)
    assert(other.container == e.stoveInv and e.pot.container == e.stoveInv and e:state().active)
    e.pot.cooked = true; e.tick(); e:drain()
    assert(other.container == e.stoveInv and e.pot.container == e.inv and not e.on)
end)
test("missing dish cleans up owned stove", function()
    local e = Env.new(); start(e); e.stoveInv:Remove(e.pot)
    e.now = e.now + 1000; e.tick()
    assert(not e:state().active and not e.on)
end)
test("switched off stove cannot wait forever", function()
    local e = Env.new(); start(e); e.on = false; e.tick()
    assert(not e:state().active)
end)
test("preview does not change recipe", function()
    local e = Env.new(); e.food.frozen = true
    assert(e.cook.plan(e.player, "Soup")); assert(not e.allowFrozen)
end)
test("changed plan rejected before consuming ingredients", function()
    local e = Env.new(); local plan = assert(e.cook.plan(e.player, "Soup"))
    e.food.rotten = true; e.cook.start(e.player, "Soup", plan)
    assert(#e.queue == 0 and #e.pot.extra == 0)
end)
test("second start does not discard active cooking", function()
    local e = Env.new(); local plan = assert(e.cook.plan(e.player, "Soup"))
    e.cook.start(e.player, "Soup", plan); local session = e:state()
    e.cook.start(e.player, "Soup", plan)
    assert(e:state() == session and session.active)
end)
test("basic spices leave room for oil", function()
    local e = Env.new(); local spices = {}
    for i = 1, 4 do spices[i] = Env.item("Base.Spice" .. i, 1) end
    spices[5] = Env.item("Base.Oil", 100)
    local result = require("CookItForMe_FoodLogic").pickIngredients({}, spices, "max", 6, 4)
    assert(#result.spices == 3 and result.spices[3] == spices[5])
end)
test("no progress fails, pause does not spend timeout", function()
    local e = Env.new(); start(e); e.speed = 0
    for i = 1, 300 do e.now = e.now + 1000; e.tick() end
    assert(e:state().active and e.on)
    e.speed = 1
    for i = 1, 121 do e.now = e.now + 1000; e.tick() end
    assert(not e:state().active and not e.on)
    assert(e.messages[#e.messages] == "UI_CookItForMe_NoHeat")
end)
test("thawing is legitimate heating progress", function()
    local e = Env.new(); start(e)
    e:state().lastFreezingTime = 100
    for i = 1, 240 do
        e.pot.freezingTime = 100 - i / 10
        e.now = e.now + 1000; e.tick()
    end
    assert(e:state().active and e.on)
end)
test("full inventory refuses pickup and does not consume", function()
    local e = Env.new(); e.inv.full = true; start(e)
    assert(not e:state().active and not e.on and e.food.container == e.source)
end)
test("missing ingredient after preview fails before first action", function()
    local e = Env.new(); local plan = assert(e.cook.plan(e.player, "Soup"))
    e.source:Remove(e.food)
    e.cook.start(e.player, "Soup", plan)
    assert(#e.queue == 0 and #e.pot.extra == 0)
end)
test("partial add exception is not retried", function()
    local e = Env.new(); local original = e.recipe.addItem; local calls = 0
    e.recipe.addItem = function(...)
        calls = calls + 1; original(...); error("failure after consuming ingredient")
    end
    start(e)
    for i = 1, 10 do e.now = e.now + 1000; e.tick() end
    assert(calls == 1 and not e:state().active and not e.on and not e.allowFrozen)
end)
test("floor ingredients and leftover spices use real source kinds", function()
    local e = Env.new()
    for _, item in ipairs({e.food, e.spice}) do
        e.source:Remove(item)
        local world = { square = e.square }
        world.getSquare = function(self) return self.square end
        world.getItem = function() return item end
        item.world = world
    end
    start(e)
    assert(e:state().cooking and e.pot.container == e.stoveInv)
    assert(e.spice.world and e.spice.world:getSquare() == e.square)
end)
test("ordinary user action survives explicit cooking cancel", function()
    local e = Env.new()
    e.cook.start(e.player, "Soup", assert(e.cook.plan(e.player, "Soup")))
    local unrelated = { kind = "unrelated" }
    e.queue[#e.queue + 1] = unrelated
    e.cook.cancel()
    assert(#e.queue == 1 and e.queue[1] == unrelated)
end)
test("failed completion does not enable stove", function()
    local e = Env.new(); local create = ISInventoryTransferAction.new
    ISInventoryTransferAction.new = function(...)
        local a = create(...)
        if a.destContainer == e.stoveInv then a.perform = function() end end
        return a
    end
    start(e)
    assert(not e:state().active and not e.on and e.pot.container == e.inv)
end)
assert(#failures == 0, table.concat(failures, "\n"))
print("RELIABILITY TESTS PASSED")
