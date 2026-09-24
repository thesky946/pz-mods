package.path = "../42/media/lua/shared/?.lua;./?.lua;" .. package.path
local Env = require "support/cook_env"
local e = Env.new()
local Planner = require "CookItForMe_Planner"
local extra = e.source:AddItem(Env.item("Base.Carrot", 80))
e.collected.foods[#e.collected.foods + 1] = extra
local substitute = e.source:AddItem(Env.item("Base.Carrot", 20))
e.collected.foods[#e.collected.foods + 1] = substitute
-- B42's isItemUsableInRecipe(..., nil) searches only the player's inventory.
-- Both products are in the nearby cupboard, which is part of this plan's scan.
e.recipe.isItemUsableInRecipe = function(_, _, _, id) return e.inv:contains(id) end
local plan = assert(e.cook.plan(e.player, "Soup"))
local nearbyAlternatives = Planner.alternatives(e.player, plan, plan.rows[1].id)
assert(#nearbyAlternatives == 1 and nearbyAlternatives[1] == substitute,
    "replacement offers a compatible product from the scanned cupboard")
assert(#plan.rows == 7 and plan.rows[1].id ~= plan.rows[2].id,
    "each physical addition and each free recipe place has a stable row")
for i = 3, 6 do
    assert(plan.rows[i].kind == "food" and plan.rows[i].item == nil,
        "the unfilled main-ingredient capacity is visible as empty slots")
end
local first = plan.rows[1]
local originalFirst = first.item
local removed = assert(Planner.remove(plan, first.id))
assert(removed.item == originalFirst and #plan.picked.items == 1 and plan.picked.items[1] ~= originalFirst,
    "removing one duplicate only edits that addition")
assert(plan.rows[1].id == first.id and plan.rows[1].item == nil and #plan.rows == 7,
    "removal leaves the same editable slot in its original position")
assert(Planner.replace(e.player, plan, plan.rows[3].id, originalFirst),
    "a removed physical product can be put in another free slot")
assert(not Planner.undo(plan, removed), "undo must not duplicate one physical product in two slots")
assert(Planner.remove(plan, plan.rows[3].id))
assert(Planner.undo(plan, removed) and #plan.picked.items == 2,
    "undo restores exactly the removed row")
assert(plan.rows[1].id == first.id and plan.rows[1].item == removed.item,
    "undo fills the original slot")
assert(not plan.edited, "undoing all changes clears the edited state")
local replacement = substitute
assert(Planner.replace(e.player, plan, first.id, replacement))
assert(plan.rows[1].id == first.id and plan.rows[1].item == replacement,
    "replacement preserves the row ID")
local replacedRemoval = assert(Planner.remove(plan, first.id))
assert(Planner.undo(plan, replacedRemoval) and plan.edited,
    "undoing a later removal keeps an earlier replacement marked as edited")
assert(not Planner.replace(e.player, plan, first.id, e.spice),
    "a seasoning cannot replace a main ingredient")
local empty = plan.rows[3]
assert(not Planner.replace(e.player, plan, empty.id, originalFirst),
    "a free slot still respects the per-type recipe limit")
local originalItemsList = e.recipe.getItemsList
e.recipe.getItemsList = function()
    local list = originalItemsList()
    return { get = function(_, name)
        if name == "Potato" then return { getUse = function() return 10 end } end
        return list:get(name)
    end }
end
local potato = e.source:AddItem(Env.item("Base.Potato", 30))
e.collected.foods[#e.collected.foods + 1] = potato
assert(Planner.replace(e.player, plan, empty.id, potato),
    "a free slot accepts an available compatible ingredient")
assert(empty.item == potato and #plan.picked.items == 3,
    "filling a slot updates the shown composition")
local removedAgain = assert(Planner.remove(plan, empty.id))
assert(empty.item == nil and Planner.replace(e.player, plan, empty.id, removedAgain.item),
    "a removed ingredient can be added back through its empty slot")
assert(not Planner.undo(plan, removedAgain), "stale undo cannot overwrite a filled slot")
assert(plan.edited, "other manual changes still keep the plan marked as edited")
assert(Planner.reset(e.player, plan), "reset can restore automatic selection")
assert(not plan.edited and #plan.picked.items == 3 and #plan.rows == 7)
local spiceRow = plan.rows[7]
local spiceRemoval = assert(Planner.remove(plan, spiceRow.id))
assert(spiceRow.item == nil and #plan.picked.spices == 0 and #plan.rows == 7,
    "removing a spice also leaves its own empty slot")
assert(Planner.replace(e.player, plan, spiceRow.id, spiceRemoval.item)
    and #plan.picked.spices == 1, "a spice slot accepts a compatible spice")
local unrelated = e.source:AddItem(Env.item("Base.Unrelated", 20))
e.collected.foods[#e.collected.foods + 1] = unrelated
for _, item in ipairs(Planner.alternatives(e.player, plan, plan.rows[1].id)) do
    assert(item ~= unrelated, "replacement list obeys the recipe's ingredient metadata")
end
e.source:Remove(plan.rows[1].item)
local valid, reason, name = Planner.validate(e.player, plan)
assert(not valid and reason == "SelectedUnavailable" and name == plan.rows[1].item:getDisplayName(),
    "a vanished selected item remains identified in the plan")
assert(#e.inv.items == 0 and #e.queue == 0,
    "editing never starts game actions or transfers items")

local e2 = Env.new()
local second = e2.source:AddItem(Env.item("Base.Carrot", 80))
e2.collected.foods[#e2.collected.foods + 1] = second
local edited = assert(e2.cook.plan(e2.player, "Soup"))
assert(#edited.picked.items == 2)
assert(require("CookItForMe_Planner").remove(edited, edited.rows[1].id))
assert(e2.cook.start(e2.player, "Soup", edited))
e2:drain()
local additions = 0
for _, event in ipairs(e2.trace) do if event == "add:Base.Carrot" then additions = additions + 1 end end
assert(additions == 1, "cooking consumes the displayed edited composition")
local e3 = Env.new()
local e3Planner = e3.cook.planEditor
e3.collected.foods = {}
local noFood = assert(e3.cook.plan(e3.player, "Soup"))
assert(#noFood.rows == 7 and #noFood.picked.items == 0 and noFood.rows[6].item == nil,
    "a recipe with no food still presents its six empty slots")
local validNoFood, noFoodReason = e3Planner.validate(e3.player, noFood)
assert(not validNoFood and noFoodReason == "NotEnough",
    "empty slots never make an empty recipe cookable")
e3.collected.foods = { e3.food }
local filled = e3Planner.replace(e3.player, noFood, noFood.rows[1].id, e3.food)
local validFilled, filledReason = e3Planner.validate(e3.player, noFood)
assert(filled and #noFood.picked.items == 1 and validFilled,
    "a product that becomes available can fill a formerly empty plan: " .. tostring(filled)
        .. " count=" .. tostring(#noFood.picked.items) .. " reason=" .. tostring(filledReason))
assert(e3.cook.start(e3.player, "Soup", noFood))
e3:drain()
local filledAdditions = 0
for _, event in ipairs(e3.trace) do if event == "add:Base.Carrot" then filledAdditions = filledAdditions + 1 end end
assert(filledAdditions == 1, "cooking uses the ingredient added to an initially empty plan")
print("PLAN EDIT TESTS PASSED")
