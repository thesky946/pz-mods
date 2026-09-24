package.path = "../42/media/lua/shared/?.lua;../42/media/lua/client/?.lua;./?.lua;" .. package.path
local Env = require "support/cook_env"
local function eq(a, b, message) assert(a == b, (message or "mismatch") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

for _, dish in ipairs({ "Soup", "Stew", "Stir fry", "Roasted Vegetables" }) do
    for _, strategy in ipairs({ "max", "min", "hunger" }) do
        local e = Env.new(dish)
        CookItForMe.getSettings(e.player).strategy = strategy
        local plan = assert(e.cook.plan(e.player, dish))
        eq(plan.settings.finishCooking, true, "existing saves keep stove cooking enabled by default")
        eq(plan.direction, strategy)
        eq(plan.cookware, e.pot)
        eq(plan.picked.items[1], e.food)
        eq(plan.picked.spices[1], e.spice)
        eq(plan.predictedCalories, 44)
        eq(#e.inv.items, 0, "preview cleanup")
        eq(#e.pot.extra, 0, "preview leaves original pot intact")
        -- A supplied preview must be executed without planning again.
        e.cook.plan = function() error("unexpected replan") end
        e.cook.start(e.player, dish, plan)
        e:drain()
        eq(e.pot.container, e.stoveInv)
        eq(e.spice.container, e.source, "leftover returned")
        local trace = table.concat(e.trace, ",")
        local water = (dish == "Soup" or dish == "Stew") and "water," or ""
        eq(trace, "transfer:" .. plan.cookware.fullType .. ":inventory," .. water
            .. "transfer:Base.Carrot:inventory,add:Base.Carrot,sound,transfer:Base.Salt:inventory,add:Base.Salt,sound,transfer:Base.Salt:cupboard,transfer:"
            .. e.pot.fullType .. ":stove,on", "action order")
        e.pot.cooked = true
        e.tick()
        e:drain()
        eq(e.pot.container, e.inv, "dish retrieved")
        eq(e.on, false)
        eq(e:state().active, false)
        assert(e.messages[#e.messages]:find("UI_CookItForMe_Done", 1, true))
        eq(#e.uiSounds, 1, "successful stove cooking still plays one completion sound")
    end
end

-- Preparation-only plans complete after ingredient actions without querying or using a stove.
local prepOnly = Env.new()
CookItForMe.getSettings(prepOnly.player).finishCooking = false
prepOnly.broken = true
prepOnly.stove.isBroken = function() error("stove must not be checked in preparation-only mode") end
prepOnly.stove.getContainer = function() error("stove must not be checked in preparation-only mode") end
prepOnly.stove.Activated = function() error("stove must not be checked in preparation-only mode") end
prepOnly.stove.Toggle = function() error("stove must not be used in preparation-only mode") end
local prepPlan, prepFailure = prepOnly.cook.plan(prepOnly.player, "Soup")
assert(prepPlan, "preparation-only plan should not require a stove: " .. tostring(prepFailure))
prepOnly.cook.start(prepOnly.player, "Soup", prepPlan)
prepOnly:drain()
eq(prepOnly:state().active, false, "preparation-only session completes after ingredients")
eq(prepOnly:state().reason, "success")
eq(not prepOnly.pot.cooked, true, "prepared dish remains uncooked")
eq(prepOnly.pot.container, prepOnly.inv, "prepared dish remains in player inventory")
eq(prepOnly.on, false, "preparation-only run leaves stove off")
assert(prepOnly.messages[#prepOnly.messages]:find("UI_CookItForMe_PreparationComplete", 1, true), "preparation has a distinct completion message")
eq(prepOnly.uiSounds[1], "StoveTimerExpired", "preparation completion plays the selected completion sound")
eq(#prepOnly.uiSounds, 1, "preparation completion plays the sound only once")

local silentPrep = Env.new()
CookItForMe.getSettings(silentPrep.player).finishCooking = false
CookItForMe.getSettings(silentPrep.player).completionSound = false
local silentPlan = assert(silentPrep.cook.plan(silentPrep.player, "Soup"))
silentPrep.cook.start(silentPrep.player, "Soup", silentPlan)
silentPrep:drain()
eq(#silentPrep.uiSounds, 0, "disabled completion sound remains silent after preparation")

local noStovePrep = Env.new()
CookItForMe.getSettings(noStovePrep.player).finishCooking = false
noStovePrep.scan.stove = nil
assert(noStovePrep.cook.plan(noStovePrep.player, "Soup"), "preparation-only plan should work without a stove in range")

local failures = {
    { "NoStove", function(e) e.scan.stove = nil end },
    { "NoPower", function(e) e.broken = true end },
    { "NoCookware", function(e) e.collected.cookware = {} end },
    { "NoSink", function(e) e.scan.sink = nil end },
    { "NoWater", function(e) e.dry = true end },
    { "NoCookware", function(e) e.noRecipe = true end },
}
for _, case in ipairs(failures) do
    local e = Env.new()
    case[2](e)
    local plan, failure = e.cook.plan(e.player, "Soup")
    eq(plan, nil)
    eq(failure, case[1])
end
local emptyFood = Env.new()
emptyFood.collected.foods = {}
local emptyPlan = assert(emptyFood.cook.plan(emptyFood.player, "Soup"))
assert(#emptyPlan.picked.items == 0 and #emptyPlan.rows >= 6,
    "a plan without available food remains open for filling empty slots")
local started, emptyReason = emptyFood.cook.start(emptyFood.player, "Soup", emptyPlan)
assert(started == false and emptyReason == "NotEnough" and #emptyFood.queue == 0,
    "an unfilled plan cannot begin cooking")

local e = Env.new()
e.forecastError = true
local plan = assert(e.cook.plan(e.player, "Soup"))
eq(plan.predictedCalories, nil)
eq(#e.inv.items, 0, "failed forecast leaves inventory unchanged")
eq(e.food.container, e.source)

e = Env.new()
local keepsake = e.inv:AddItem(Env.item("Base.Keepsake"))
e.food.frozen = true
plan = assert(e.cook.plan(e.player, "Soup"))
eq(plan.picked.frozenCount, 1, "frozen selection")
eq(e.allowFrozen, false, "preview leaves shared recipe unchanged")
eq(#e.inv.items, 1, "preview preserves existing inventory")
eq(e.inv.items[1], keepsake)

for _, failure in ipairs({ "reject", "addError" }) do
    e = Env.new()
    e[failure] = e.food
    e.cook.start(e.player, "Soup", assert(e.cook.plan(e.player, "Soup")))
    e:drain()
    eq(e.food.container, e.inv, "failed ingredient remains available in inventory")
    eq(e:state().active, false, "failure stops without processing spices")
    eq(e.on, false, "failure never starts stove")
end

for _, pos in ipairs({ { 9, 0, true }, { 10, 0, false }, { 1, 1, false } }) do
    e = Env.new()
    e.cook.start(e.player, "Soup", assert(e.cook.plan(e.player, "Soup")))
    e:drain()
    e.zombies = { { getX = function() return pos[1] end, getY = function() return 0 end, getZ = function() return pos[2] end } }
    e.tick()
    eq(e:state().active, not pos[3], "threat boundary")
    eq(e.on, not pos[3], "owned stove on cancellation")
end

-- A preheated stove is left on when the run is cancelled by a threat.
e = Env.new()
e.on = true
e.cook.start(e.player, "Soup", assert(e.cook.plan(e.player, "Soup")))
e:drain()
e.zombies = { { getX = function() return 1 end, getY = function() return 0 end, getZ = function() return 0 end } }
e.tick()
eq(e.on, true, "unowned stove remains on during cancellation")

-- Burnt dishes are still retrieved and reported separately.
e = Env.new()
e.cook.start(e.player, "Soup", assert(e.cook.plan(e.player, "Soup")))
e:drain()
e.pot.burnt = true
e.tick()
e:drain()
eq(e.pot.container, e.inv)
eq(e:state().active, false)
assert(e.messages[#e.messages]:find("UI_CookItForMe_Burnt", 1, true))

-- Preserve the existing missing-dish timeout and message.
e = Env.new()
e.cook.start(e.player, "Soup", assert(e.cook.plan(e.player, "Soup")))
e:drain()
e.stoveInv:Remove(e.pot)
e.now = e.now + 600001
e.tick()
eq(e:state().active, false)
eq(e.messages[#e.messages], "UI_CookItForMe_ItemMissing")
eq(e.on, false, "missing dish shuts off owned stove")

e = Env.new()
eq(CookItForMe.getSettings(e.player).radius, 4, "new players start with a four-tile search radius")

e = Env.new()
local old = { strategy = "min", radius = 7, panelX = 12, custom = true }
e.modData.CookItForMe = old
eq(CookItForMe.getSettings(e.player), old)
eq(old.radius, 7)
eq(old.frozenPenalty, 0.5)
eq(old.custom, true)

e = Env.new()
e.modData.CookItForMe = { strategy = "min" }
eq(CookItForMe.getSettings(e.player).radius, 4, "missing radius gets the new default")

-- Multiplayer must be rejected before planning, mutation, or action enqueueing.
e = Env.new()
isClient = function() return true end
local started, failure = e.cook.start(e.player, "Soup")
eq(started, false, "multiplayer start rejected")
eq(failure, "MultiplayerUnsupported")
eq(#e.queue, 0, "multiplayer start queues nothing")
eq(e.cook.getSession(), nil, "multiplayer start creates no session")
isClient = nil
print("COOK CHARACTERIZATION TESTS PASSED")
