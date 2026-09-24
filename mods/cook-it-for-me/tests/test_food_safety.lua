package.path = "../42/media/lua/shared/?.lua;./?.lua;" .. package.path
local Env = require "support/cook_env"
isItemFood = function() return true end

local e = Env.new("Fruit Salad")
local poisonedBerry = e.food
poisonedBerry.poisonPower = 8
local Scanner = dofile("../42/media/lua/shared/CookItForMe_Scanner.lua")
local scanned = Scanner.collectFood(e.player, e.scan, true)
for _, item in ipairs(scanned.foods) do
    assert(item ~= poisonedBerry, "poisoned berry must not enter the scanned food pool")
end

local mushroom = e.source:AddItem(Env.item("Base.MushroomGeneric1", 30))
mushroom.poisonPower = 20
local scannedMushrooms = Scanner.collectFood(e.player, e.scan, false)
for _, item in ipairs(scannedMushrooms.foods) do
    assert(item ~= mushroom, "poisoned mushroom must not enter the scanned food pool")
end
e.spice.poisonPower = 3
assert(#Scanner.collectFood(e.player, e.scan, true).spices == 0,
    "poisoned seasoning must not enter the scanned spice pool")

poisonedBerry.poisonPower = 0
poisonedBerry.stale = true
local staleFound = false
for _, item in ipairs(Scanner.collectFood(e.player, e.scan, true).foods) do
    if item == poisonedBerry then staleFound = true end
end
assert(staleFound, "stale but not rotten food stays available")
poisonedBerry.rotten = true
for _, item in ipairs(Scanner.collectFood(e.player, e.scan, true).foods) do
    assert(item ~= poisonedBerry, "rotten food remains excluded")
end

local carried = e.inv:AddItem(Env.item("Base.BerryGeneric2", 10))
carried.poisonPower = 3
local bag = e.inv:AddItem(Env.item("Base.Bag"))
bag.IsInventoryContainer = function() return true end
local bagInventory = Env.container("bag")
bag.getInventory = function() return bagInventory end
local bagBerry = bagInventory:AddItem(Env.item("Base.BerryGeneric3", 10))
bagBerry.poisonPower = 4
local floorBerry = Env.item("Base.BerryGeneric4", 10)
floorBerry.poisonPower = 5
local locations = Scanner.collectFood(e.player, { containers = { e.source }, floorItems = { floorBerry } }, true)
for _, item in ipairs(locations.foods) do
    assert(item ~= carried and item ~= bagBerry and item ~= floorBerry,
        "poisoned food in inventory, nested bag, or on floor must be excluded")
end

local preview = Env.new("Fruit Salad")
preview.food.poisonPower = 5
local poisonPlan = assert(preview.cook.plan(preview.player, "Fruit Salad"))
assert(#poisonPlan.picked.items == 0 and not preview.cook.planEditor.validate(preview.player, poisonPlan),
    "automatic selection must reject a poisoned berry")

local alternatives = Env.new()
local plan = assert(alternatives.cook.plan(alternatives.player, "Soup"))
local candidate = alternatives.source:AddItem(Env.item("Base.Carrot", 20))
candidate.poisonPower = 5
alternatives.collected.foods[#alternatives.collected.foods + 1] = candidate
for _, item in ipairs(alternatives.cook.planEditor.alternatives(alternatives.player, plan, plan.rows[1].id)) do
    assert(item ~= candidate, "poisoned food must not appear in replacement options")
end
local poisonedSpice = alternatives.source:AddItem(Env.item("Base.Salt", 0))
poisonedSpice.spice = true
poisonedSpice.poisonPower = 4
alternatives.collected.spices[#alternatives.collected.spices + 1] = poisonedSpice
for _, item in ipairs(alternatives.cook.planEditor.alternatives(alternatives.player, plan, plan.rows[#plan.rows].id)) do
    assert(item ~= poisonedSpice, "poisoned seasoning must not appear in replacement options")
end

local changed = Env.new()
local changedPlan = assert(changed.cook.plan(changed.player, "Soup"))
changed.food.poisonPower = 10
local started = changed.cook.start(changed.player, "Soup", changedPlan)
assert(started == false and #changed.queue == 0 and #changed.pot.extra == 0,
    "poisoned food must invalidate an existing plan before actions start")

local late = Env.new()
local latePlan = assert(late.cook.plan(late.player, "Soup"))
assert(late.cook.start(late.player, "Soup", latePlan))
late.duplicateCallbacks = true
late.food.poisonPower = 10
late:drain()
assert(not late:state().active and #late.pot.extra == 0 and not late.on,
    "poisoning after start must stop before consumption and leave stove off")
assert(late.source:contains(late.food) or late.inv:contains(late.food),
    "the rejected ingredient remains available after duplicated callbacks")

local stale = Env.new()
stale.food.stale = true
local stalePlan = assert(stale.cook.plan(stale.player, "Soup"))
assert(stale.cook.start(stale.player, "Soup", stalePlan))
stale:drain()
assert(stale.pot.extra[1] == stale.food:getFullType(),
    "stale but not rotten food is actually added to the dish")
stale.pot.cooked = true
stale.tick()
stale:drain()
assert(not stale:state().active and stale:state().reason == "success" and not stale.on,
    "stale food can complete cooking without leaving the stove on")

print("FOOD SAFETY TESTS PASSED")
