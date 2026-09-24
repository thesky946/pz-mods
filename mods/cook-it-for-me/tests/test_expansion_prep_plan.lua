package.path = "../42/media/lua/shared/?.lua;./?.lua;" .. package.path
local Env = require "support/cook_env"
local e = Env.new()
ItemTag, ResourceLocation = { get = function(v) return v end }, { of = function(v) return v end }
local pan = e.source:AddItem(Env.item("Base.Pan"))
local egg1 = e.source:AddItem(Env.item("Base.Egg"))
local egg2 = e.source:AddItem(Env.item("Base.EggChicken"))
local spareEgg = e.source:AddItem(Env.item("Base.Egg"))
egg1.frozen, egg2.frozen = true, true
local whisk = e.source:AddItem(Env.item("Base.Whisk"))
local spareUtensil = e.source:AddItem(Env.item("Base.Fork"))
whisk.nonFood = true
spareUtensil.nonFood = true
whisk.isRotten = nil
whisk.isBurnt = nil
whisk.getCalories = nil
whisk.getHungerChange = nil
local carrot = e.source:AddItem(Env.item("Base.Carrot", 30))
egg1.hasTag = function(_, tag) return tag == "base:egg" end
egg2.hasTag = egg1.hasTag
spareEgg.hasTag = egg1.hasTag
whisk.hasTag = function(_, tag) return tag == "base:mixingutensil" end
spareUtensil.hasTag = whisk.hasTag
pan.hasTag = function() return false end
carrot.hasTag = function() return false end
e.collected.cookware = { pan }
e.collected.items = { pan, egg1, egg2, whisk, carrot, spareEgg, spareUtensil }
e.collected.foods = { carrot }
e.collected.spices = {}
e.recipe.getUntranslatedName = function() return "Omelette" end
e.recipe.getResultItem = function() return "OmeletteRecipe" end
e.recipe.getFullResultItem = function() return "Base.OmeletteRecipe" end
e.recipe.getMaxItems = function() return 3 end
e.recipe.getItemsList = function() return { get = function(_, name)
    if name == "Carrot" then return { getUse = function() return 10 end } end
end } end
instanceItem = function(typeName) return Env.item(typeName) end
ScriptManager.instance.getCraftRecipe = function() return nil end
local missingPlan, missingReason = e.cook.plan(e.player, "Omelette")
assert(not missingPlan and missingReason == "RecipeUnavailable",
    "unloaded preparation recipe must explain why omelette cannot start")
local recipeTags = { "Cooking" }
local modRecipe = {
    getName = function() return "CookItForMePrepareOmelette" end,
    getInputs = function() return Env.list({ {}, {}, {} }) end,
    requiresSpecificWorkstation = function() return recipeTags[1] ~= "InHandCraft" end,
    getModTags = function() return { add = function(_, value) recipeTags[1] = value end } end,
    setTags = function() end,
}
ScriptManager.instance.getCraftRecipe = function(_, name)
    return name == "CookItForMePrepareOmelette" and modRecipe
end
local plan = assert(e.cook.plan(e.player, "Omelette"))
assert(plan.prep.recipe:getName() == "CookItForMePrepareOmelette")
assert(plan.prep.expected == "Base.OmeletteRecipe")
assert(plan.prep.items[1] == whisk and plan.prep.items[2] == egg1 and plan.prep.items[3] == egg2)
assert(plan.picked.items[1] == carrot)
local prepRows = {}
for _, row in ipairs(plan.rows) do if row.kind == "prep" then prepRows[#prepRows + 1] = row end end
assert(#prepRows == 3 and prepRows[1].item == whisk and prepRows[2].item == egg1)
local edited = assert(e.cook.plan(e.player, "Omelette"))
local removed = assert(e.cook.planEditor.remove(edited, edited.rows[2].id))
local incomplete, incompleteReason = e.cook.validatePlan(e.player, edited)
assert(not incomplete and incompleteReason == "NotEnough", "missing egg disables cooking before transfer")
local alternatives = e.cook.planEditor.alternatives(e.player, edited, edited.rows[2].id)
local spareAvailable, duplicateOffered = false, false
for _, candidate in ipairs(alternatives) do
    if candidate == spareEgg then spareAvailable = true end
    if candidate == egg2 then duplicateOffered = true end
end
assert(spareAvailable, "a spare egg can refill a preparation slot")
assert(not duplicateOffered, "the same egg cannot fill two preparation slots")
assert(e.cook.planEditor.undo(edited, removed) and edited.prep.items[2] == egg1)
assert(e.cook.planEditor.replace(e.player, edited, edited.rows[2].id, spareEgg))
assert(edited.prep.items[2] == spareEgg and edited.prep.items[3] == egg2)
assert(e.cook.planEditor.replace(e.player, edited, edited.rows[1].id, spareUtensil)
    and edited.prep.items[1] == spareUtensil, "the mixing utensil can be replaced")
assert(e.cook.validatePlan(e.player, edited), "edited preparation remains valid")
whisk.broken = true
local valid, reason = e.cook.validatePlan(e.player, plan)
assert(not valid and reason == "PlanChanged", "broken prep utensil invalidates the plan")
whisk.broken = false
local Catalog = require "CookItForMe_Dishes"
local allowsFrozen = Catalog.allowsFrozen
Catalog.allowsFrozen = function() return false end
valid, reason = e.cook.validatePlan(e.player, plan)
assert(not valid and reason == "PlanChanged", "strict frozen policy invalidates an existing prep plan")
local strictPlan, strictReason = e.cook.plan(e.player, "Omelette")
assert(not strictPlan and strictReason == "NotEnough", "strict policy cannot plan with only frozen eggs")
Catalog.allowsFrozen = allowsFrozen
local crafts = 0
HandcraftLogic = { new = function(_, _, surface)
    local logic = { surface = surface }
    function logic:setContainers() end
    function logic:setRecipe(recipe) self.recipe = recipe end
    function logic:setManualSelectInputs() end
    function logic:clearManualInputs() end
    function logic:setManualInputsFor() return true end
    function logic:canPerformCurrentRecipe()
        local source = assert(io.open("../42/media/scripts/cookitforme_preparations.txt", "r"))
        local script = source:read("*a"); source:close()
        local eggFlags = script:match("craftRecipe%s+CookItForMePrepareOmelette.-item%s+2%s+tags%[base:egg%]%s+flags%[([^%]]+)%]")
        return self.surface == nil and not self.recipe:requiresSpecificWorkstation()
            and (not egg1:isFrozen() or eggFlags:find("AllowFrozenItem", 1, true))
    end
    return logic
end }
ISHandcraftAction = { FromLogic = function()
    return { perform = function()
        crafts = crafts + 1
        e.inv:Remove(pan); e.inv:Remove(egg1); e.inv:Remove(egg2)
        e.inv:AddItem(Env.item("Base.OmeletteRecipe"))
    end, stop = function() end }
end }
assert(e.cook.start(e.player, "Omelette", plan))
e:drain()
local result = e:state().pot
assert(crafts == 1 and result:getFullType() == "Base.OmeletteRecipe" and e.stoveInv:contains(result))
assert(not modRecipe:requiresSpecificWorkstation(), "loaded recipe must be made portable before crafting")
assert(e.inv:contains(whisk) and result:haveExtraItems() and result.extra[1] == "Base.Carrot")
result:setCooked(true)
e.tick(); e:drain()
assert(not e:state().active and e:state().reason == "success" and e.inv:contains(result) and not e.on)
print("EXPANSION PREP PLAN TESTS PASSED")
