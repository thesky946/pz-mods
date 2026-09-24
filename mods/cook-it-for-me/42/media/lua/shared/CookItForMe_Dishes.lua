-- Dish definitions shared by planning, scanning and UI.
local Catalog = {}

-- Блюда: посуда + вода + имя эволюционного рецепта (по media/scripts B42)
local DISHES = {
    Soup = {
        recipeName = "Soup", recipePrefix = true, label = "UI_CookItForMe_DishSoup",
        bases = { "Base.Pot", "Base.PotForged" }, needsWater = true,
    },
    Stew = {
        recipeName = "Stew", recipePrefix = true, label = "UI_CookItForMe_DishStew",
        bases = { "Base.Pot", "Base.PotForged" }, needsWater = true,
    },
    ["Stir fry"] = {
        recipeName = "Stir fry", recipePrefix = true, label = "UI_CookItForMe_DishStirFry",
        bases = { "Base.Pan", "Base.PanForged", "Base.GridlePan" }, needsWater = false,
    },
    ["Roasted Vegetables"] = {
        recipeName = "Roasted Vegetables", label = "UI_CookItForMe_DishRoast",
        bases = { "Base.RoastingPan" }, needsWater = false,
    },
    Salad = {
        recipeNames = { ["Base.Bowl"] = "Salad", ["Base.ClayBowl"] = "SaladClay" },
        label = "UI_CookItForMe_DishSalad",
        bases = { "Base.Bowl", "Base.ClayBowl" }, needsWater = false,
        needsHeat = false, allowCookedIngredients = true,
        results = { ["Base.Bowl"] = "Base.Salad", ["Base.ClayBowl"] = "Base.SaladClay" },
    },
    ["Fruit Salad"] = {
        recipeNames = { ["Base.Bowl"] = "FruitSalad", ["Base.ClayBowl"] = "FruitSaladClay" },
        label = "UI_CookItForMe_DishFruitSalad",
        bases = { "Base.Bowl", "Base.ClayBowl" }, needsWater = false,
        needsHeat = false, allowCookedIngredients = true,
        results = { ["Base.Bowl"] = "Base.FruitSalad", ["Base.ClayBowl"] = "Base.FruitSaladClay" },
    },
    Omelette = {
        label = "UI_CookItForMe_DishOmelette", needsWater = false,
        bases = { "Base.Pan", "Base.PanForged" },
        prep = {
            ["Base.Pan"] = { recipe = "CookItForMePrepareOmelette", base = "Base.OmeletteRecipe" },
            ["Base.PanForged"] = { recipe = "CookItForMePrepareOmelette", base = "Base.OmeletteRecipeForged" },
        },
        recipeNames = { ["Base.OmeletteRecipe"] = "Omelette", ["Base.OmeletteRecipeForged"] = "Omelette Forged" },
        results = { ["Base.OmeletteRecipe"] = "Base.OmeletteRecipe", ["Base.OmeletteRecipeForged"] = "Base.OmeletteRecipeForged" },
    },
    Pasta = {
        label = "UI_CookItForMe_DishPasta", needsWater = true,
        bases = { "Base.Saucepan", "Base.SaucepanCopper", "Base.Pot", "Base.PotForged" },
        prep = {
            ["Base.Saucepan"] = { recipe = "CookItForMePlacePastaInSaucepan2", base = "Base.WaterSaucepanPasta" },
            ["Base.SaucepanCopper"] = { recipe = "CookItForMePlacePastaInSaucepan2", base = "Base.WaterSaucepanPastaCopper" },
            ["Base.Pot"] = { recipe = "CookItForMePlacePastaInCookingPot2", base = "Base.WaterPotPasta" },
            ["Base.PotForged"] = { recipe = "CookItForMePlacePastaInCookingPot2", base = "Base.WaterPotForgedPasta" },
        },
        recipeNames = {
            ["Base.WaterSaucepanPasta"] = "PastaPan", ["Base.WaterSaucepanPastaCopper"] = "PastaPanCopper",
            ["Base.WaterPotPasta"] = "PastaPot", ["Base.WaterPotForgedPasta"] = "PastaPotForged",
        },
        results = {
            ["Base.WaterSaucepanPasta"] = "Base.PastaPan", ["Base.WaterSaucepanPastaCopper"] = "Base.PastaPanCopper",
            ["Base.WaterPotPasta"] = "Base.PastaPot", ["Base.WaterPotForgedPasta"] = "Base.PastaPotForged",
        },
        requiredTag = "base:pasta",
    },
    Rice = {
        label = "UI_CookItForMe_DishRice", needsWater = true,
        bases = { "Base.Saucepan", "Base.SaucepanCopper", "Base.Pot", "Base.PotForged" },
        prep = {
            ["Base.Saucepan"] = { recipe = "CookItForMePlaceRiceInSaucepan2", base = "Base.WaterSaucepanRice" },
            ["Base.SaucepanCopper"] = { recipe = "CookItForMePlaceRiceInSaucepan2", base = "Base.WaterSaucepanRiceCopper" },
            ["Base.Pot"] = { recipe = "CookItForMePlaceRiceInCookingPot2", base = "Base.WaterPotRice" },
            ["Base.PotForged"] = { recipe = "CookItForMePlaceRiceInCookingPot2", base = "Base.WaterPotForgedRice" },
        },
        recipeNames = {
            ["Base.WaterSaucepanRice"] = "RicePan", ["Base.WaterSaucepanRiceCopper"] = "RicePanCopper",
            ["Base.WaterPotRice"] = "RicePot", ["Base.WaterPotForgedRice"] = "RicePotForged",
        },
        results = {
            ["Base.WaterSaucepanRice"] = "Base.RicePan", ["Base.WaterSaucepanRiceCopper"] = "Base.RicePanCopper",
            ["Base.WaterPotRice"] = "Base.RicePot", ["Base.WaterPotForgedRice"] = "Base.RicePotForged",
        },
        requiredIngredient = "Base.Rice",
    },
}

local DISH_ORDER = { "Soup", "Stew", "Stir fry", "Roasted Vegetables", "Salad", "Fruit Salad",
    "Omelette", "Pasta", "Rice" }
Catalog.ALL_DISHES = DISH_ORDER
Catalog.DISHES = DISHES

function Catalog.hasPrep(dish)
    return dish.prep ~= nil
end

function Catalog.isSafeIngredient(item)
    return not item:isRotten() and not item:isBurnt() and item:getPoisonPower() <= 0
end

local function tagged(item, name)
    return item:hasTag(ItemTag.get(ResourceLocation.of(name)))
end

function Catalog.prepSlotAccepts(dish, index, item, settings)
    if not item or not dish.prep then return false end
    if dish == DISHES.Omelette and index == 1 then
        return not item:isBroken() and tagged(item, "base:mixingutensil")
    end
    if not instanceof(item, "Food") or not Catalog.isSafeIngredient(item) or item:isCooked()
        or (item:isFrozen() and not Catalog.allowsFrozen(dish, settings)) then return false end
    if dish == DISHES.Omelette then return index <= 3 and tagged(item, "base:egg") end
    if index ~= 1 then return false end
    return (dish.requiredTag and tagged(item, dish.requiredTag))
        or (dish.requiredIngredient and item:getFullType() == dish.requiredIngredient) or false
end

function Catalog.selectPrep(dish, cookware, items, settings)
    if not dish.prep or not dish.prep[cookware:getFullType()] then return nil end
    local selected = {}
    if dish == DISHES.Omelette then
        local utensil, eggs = nil, {}
        for _, item in ipairs(items) do
            if not utensil and Catalog.prepSlotAccepts(dish, 1, item, settings) then utensil = item end
            if #eggs < 2 and Catalog.prepSlotAccepts(dish, 2, item, settings) then
                eggs[#eggs + 1] = item
            end
        end
        if not utensil or #eggs < 2 then return nil end
        return { utensil, eggs[1], eggs[2] }
    end
    for _, item in ipairs(items) do
        if Catalog.prepSlotAccepts(dish, 1, item, settings) then
            selected[1] = item
            break
        end
    end
    return selected[1] and selected or nil
end

-- The current policy allows frozen food for every dish. A future player
-- preference belongs here; callers should not decide frozen rules themselves.
function Catalog.allowsFrozen(_dish, _settings)
    return true
end

-- Какие блюда можно приготовить из собранной посуды (в фиксированном порядке)
function Catalog.availableDishes(collected)
    local out = {}
    for _, key in ipairs(DISH_ORDER) do
        local dish = DISHES[key]
        for _, c in ipairs(collected.cookware) do
            for _, ft in ipairs(dish.bases) do
                if c:getFullType() == ft then
                    table.insert(out, key)
                    c = nil
                    break
                end
            end
            if not c then break end
        end
    end
    return out
end

function Catalog.isUsableBase(dish, item)
    if not dish.results or dish.prep then return true end
    local fluid = item:getFluidContainer()
    return fluid and fluid:isEmpty()
end

function Catalog.findCookware(collected, dishKey, requireUsable)
    local dish = DISHES[dishKey]
    for _, c in ipairs(collected.cookware) do
        for _, ft in ipairs(dish.bases) do
            if c:getFullType() == ft and (not requireUsable or Catalog.isUsableBase(dish, c)) then return c end
        end
    end
    return nil
end

-- Derived from the same definitions; no separate cookware whitelist.
function Catalog.isCookware(fullType)
    for _, key in ipairs(DISH_ORDER) do
        for _, base in ipairs(DISHES[key].bases) do
            if base == fullType then return true end
        end
    end
    return false
end

function Catalog.matchRecipe(name, dishKey, baseFullType)
    local dish = DISHES[dishKey]
    if not dish then return false end
    if dish.recipeNames then
        local expected = dish.recipeNames[baseFullType]
        return expected ~= nil and name == expected
    end
    if dish.recipePrefix then
        return name:sub(1, #dish.recipeName) == dish.recipeName
    end
    return name == dish.recipeName
end

return Catalog
