package.path = "../42/media/lua/shared/?.lua;./?.lua;" .. package.path
local Env = require "support/cook_env"

local e = Env.new()
local Planner = require "CookItForMe_Planner"
local forged = e.source:AddItem(Env.item("Base.PotForged"))
forged.nonFood = true
e.collected.cookware[#e.collected.cookware + 1] = forged
local spare = e.inv:AddItem(Env.item("Base.Pot"))
spare.nonFood = true
e.collected.cookware[#e.collected.cookware + 1] = spare
local pan = e.source:AddItem(Env.item("Base.Pan"))
pan.nonFood = true
e.collected.cookware[#e.collected.cookware + 1] = pan
local original = assert(Planner.plan(e.player, "Soup"))
assert(original.cookware == e.pot, "the first compatible item stays preselected")
local originalChoose = Planner.chooseCookware
Planner.chooseCookware = function() error("listing vessels must not rebuild every candidate plan") end
local options = Planner.cookwareOptions(e.player, original)
Planner.chooseCookware = originalChoose
assert(#options == 3 and options[1].item == e.pot and options[2].item == forged
    and options[3].item == spare, "every physical compatible item is offered")

local chosen = assert(Planner.chooseCookware(e.player, original, forged))
assert(chosen.cookware == forged and chosen.sources[forged]
    and chosen.sources[e.pot] == nil, "the chosen plan tracks only the selected vessel")
assert(Planner.validate(e.player, chosen), "the chosen plan is ready to start")

local otherFood = e.source:AddItem(Env.item("Base.Carrot", 10))
e.collected.foods[#e.collected.foods + 1] = otherFood
assert(Planner.replace(e.player, chosen, chosen.rows[1].id, otherFood),
    "the player can select a particular ingredient")
local secondManual = e.source:AddItem(Env.item("Base.Carrot", 75))
e.collected.foods[#e.collected.foods + 1] = secondManual
assert(Planner.replace(e.player, chosen, chosen.rows[2].id, secondManual))
local moved = assert(Planner.chooseCookware(e.player, chosen, spare))
local preserved, secondPreserved = false, false
for _, row in ipairs(moved.rows) do
    if row.item == otherFood then preserved = true end
    if row.item == secondManual then secondPreserved = true end
end
assert(preserved and secondPreserved and moved.cookware == spare,
    "switching cookware preserves all compatible manually selected ingredients")
assert(Planner.remove(moved, moved.rows[2].id))
assert(Planner.remove(moved, moved.rows[7].id))
local withRemovals = assert(Planner.chooseCookware(e.player, moved, forged))
assert(#withRemovals.picked.items == 1 and withRemovals.picked.items[1] == otherFood
    and #withRemovals.picked.spices == 0 and withRemovals.rows[2].item == nil,
    "switching cookware keeps removed food and spice slots empty")
local backAgain = assert(Planner.chooseCookware(e.player, withRemovals, spare))
assert(#backAgain.picked.items == 1 and backAgain.picked.items[1] == otherFood
    and #backAgain.picked.spices == 0,
    "removed slots stay empty across repeated cookware changes")
assert(Planner.reset(e.player, moved) and moved.cookware == spare,
    "resetting ingredient edits keeps the chosen vessel for the current plan")

e.inv:Remove(spare)
local valid = Planner.validate(e.player, moved)
assert(not valid, "a selected vessel removed before starting blocks cooking")
assert(not Planner.chooseCookware(e.player, moved, spare),
    "a missing vessel cannot be chosen again")

local e2 = Env.new()
local second = e2.source:AddItem(Env.item("Base.PotForged"))
second.nonFood = true
e2.collected.cookware[#e2.collected.cookware + 1] = second
local nextPlan = assert(e2.cook.plan(e2.player, "Soup"))
local selected = assert(e2.cook.planEditor.chooseCookware(e2.player, nextPlan, second))
assert(e2.cook.start(e2.player, "Soup", selected))
e2:drain()
local transferredSelected = false
for _, event in ipairs(e2.trace) do
    if event == "transfer:Base.PotForged:inventory" then transferredSelected = true end
end
assert(transferredSelected, "the cooking action transfers the chosen physical vessel")

local e3 = Env.new()
local workingPot = e3.source:AddItem(Env.item("Base.PotForged"))
workingPot.nonFood = true
e3.collected.cookware[#e3.collected.cookware + 1] = workingPot
RecipeManager.getEvolvedRecipe = function(item)
    return Env.list(item == e3.pot and {} or { e3.recipe })
end
local auto = assert(e3.cook.plan(e3.player, "Soup"))
assert(auto.cookware == workingPot,
    "automatic preselection skips a vessel without a usable recipe")

local e4 = Env.new()
local secondVessel = e4.source:AddItem(Env.item("Base.PotForged"))
secondVessel.nonFood = true
e4.collected.cookware[#e4.collected.cookware + 1] = secondVessel
local allowed = { Carrot = true, Salt = true }
for i = 1, 5 do
    local item = e4.source:AddItem(Env.item("Base.Food" .. i, i * 10))
    e4.collected.foods[#e4.collected.foods + 1] = item
    allowed[item:getType()] = true
end
for i = 1, 3 do
    local item = e4.source:AddItem(Env.item("Base.Spice" .. i))
    item.spice = true
    e4.collected.spices[#e4.collected.spices + 1] = item
    allowed[item:getType()] = true
end
e4.recipe.getItemsList = function()
    return { get = function(_, name)
        if allowed[name] then return { getUse = function() return 1 end } end
    end }
end
local large = assert(e4.cook.plan(e4.player, "Soup"))
assert(#large.picked.items == 6 and #large.picked.spices == 2)
for i = 1, 2 do
    local item = e4.source:AddItem(Env.item("Base.Extra" .. i, 90 + i))
    e4.collected.foods[#e4.collected.foods + 1] = item
    allowed[item:getType()] = true
    assert(e4.cook.planEditor.replace(e4.player, large, large.rows[i].id, item))
end
for _, index in ipairs({ 3, 4, 7, 8 }) do
    assert(e4.cook.planEditor.remove(large, large.rows[index].id))
end
local selectedLarge = assert(e4.cook.planEditor.chooseCookware(e4.player, large, secondVessel))
for index, row in ipairs(large.rows) do
    assert(selectedLarge.rows[index].item == row.item,
        "cookware change preserves edited six-food/four-spice plan at slot " .. index)
end

local e5 = Env.new()
e5.stoveInv.full = true
local spareStove = { getContainer = function() return Env.container("spare stove") end,
    isBroken = function() return false end }
e5.scan.stoves = { e5.stove, spareStove }
local sharedScan = e5.scan
local alternatePlan = assert(e5.cook.plan(e5.player, "Soup", nil, sharedScan, e5.collected))
assert(alternatePlan.scan.stove == spareStove and sharedScan.stove == e5.stove,
    "a plan may select another stove without changing the shared world scan")

print("COOKWARE CHOICE TESTS PASSED")
