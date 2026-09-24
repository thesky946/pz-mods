package.path = "../42/media/lua/shared/?.lua;./?.lua;" .. package.path
local script = assert(io.open("../42/media/scripts/cookitforme_preparations.txt", "r"))
local source = script:read("*a")
script:close()
assert(source:match("^%s*module%s+Base%s*{"),
    "PZ ScriptManager ignores a script when a // comment precedes its module token")
local omeletteInputs = assert(source:match("craftRecipe%s+CookItForMePrepareOmelette.-item%s+2%s+tags%[base:egg%]%s+flags%[([^%]]+)%]"))
assert(omeletteInputs:find("AllowFrozenItem", 1, true),
    "the omelette preparation must accept frozen eggs selected by the planner")
local frozenDryInputs = 0
for line in source:gmatch("[^\r\n]+") do
    if line:find("item 10 ", 1, true) and line:find("flags[AllowFrozenItem]", 1, true) then
        frozenDryInputs = frozenDryInputs + 1
    end
end
assert(frozenDryInputs == 4, "all pasta and rice preparations must accept frozen dry goods selected by the planner")
local portableRecipes = 0
for line in source:gmatch("[^\r\n]+") do
    if line:find("Tags = InHandCraft;Cooking,", 1, true) then portableRecipes = portableRecipes + 1 end
end
assert(portableRecipes == 5, "all preparation recipes must be handcrafts without a workstation")
local Catalog = require "CookItForMe_Dishes"

local expected = {
    Omelette = { "Base.Pan", "Base.OmeletteRecipe", "CookItForMePrepareOmelette", "Omelette" },
    Pasta = { "Base.Saucepan", "Base.WaterSaucepanPasta", "CookItForMePlacePastaInSaucepan2", "PastaPan" },
    Rice = { "Base.Pot", "Base.WaterPotRice", "CookItForMePlaceRiceInCookingPot2", "RicePot" },
}
for key, case in pairs(expected) do
    local dish = assert(Catalog.DISHES[key])
    assert(Catalog.isCookware(case[1]))
    assert(Catalog.matchRecipe(case[4], key, case[2]))
    assert(not Catalog.matchRecipe("Soup", key, case[2]))
    if case[3] then assert(dish.prep[case[1]].recipe == case[3]) end
end
ItemTag, ResourceLocation = { get = function(v) return v end }, { of = function(v) return v end }
local function item(typeName, tags)
    return { getFullType = function() return typeName end, hasTag = function(_, tag) return tags and tags[tag] or false end,
        isCooked = function() return false end, isRotten = function() return false end, isBurnt = function() return false end,
        getPoisonPower = function() return 0 end,
        isBroken = function() return false end, isFrozen = function(self) return self.frozen or false end,
        food = typeName ~= "Base.Pan" and typeName ~= "Base.Whisk" }
end
instanceof = function(value, class) return class == "Food" and value.food end
local pan = item("Base.Pan")
local eggs = { item("Base.Egg", { ["base:egg"] = true }), item("Base.EggChicken", { ["base:egg"] = true }) }
local whisk = item("Base.Whisk", { ["base:mixingutensil"] = true })
pan.isRotten, pan.isCooked, whisk.isRotten, whisk.isCooked = nil, nil, nil, nil
local prep = assert(Catalog.selectPrep(Catalog.DISHES.Omelette, pan, { eggs[1], whisk, eggs[2] }))
assert(#prep == 3 and prep[1] == whisk and prep[2] == eggs[1] and prep[3] == eggs[2])
eggs[1].getPoisonPower = function() return 4 end
assert(not Catalog.selectPrep(Catalog.DISHES.Omelette, pan, { eggs[1], whisk, eggs[2] }),
    "poisoned food cannot be used as a preparation input")
eggs[1].getPoisonPower = function() return 0 end
assert(not Catalog.selectPrep(Catalog.DISHES.Omelette, pan, { eggs[1], whisk }))
assert(Catalog.selectPrep(Catalog.DISHES.Rice, item("Base.Pot"), { item("Base.Rice") })[1]:getFullType() == "Base.Rice")
local allowsFrozen = Catalog.allowsFrozen
Catalog.allowsFrozen = function() return false end
eggs[1].frozen = true
assert(not Catalog.selectPrep(Catalog.DISHES.Omelette, pan, { eggs[1], whisk, eggs[2] }),
    "a future strict policy must reject frozen prep eggs")
local freshEgg = item("Base.Egg", { ["base:egg"] = true })
local strictOmelette = assert(Catalog.selectPrep(Catalog.DISHES.Omelette, pan, { eggs[1], whisk, eggs[2], freshEgg }))
assert(strictOmelette[2] == eggs[2] and strictOmelette[3] == freshEgg)
local frozenRice = item("Base.Rice"); frozenRice.frozen = true
assert(not Catalog.selectPrep(Catalog.DISHES.Rice, item("Base.Pot"), { frozenRice }),
    "a future strict policy must reject frozen dry goods")
Catalog.allowsFrozen = allowsFrozen
print("EXPANSION TESTS PASSED")
