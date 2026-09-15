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
}

local DISH_ORDER = { "Soup", "Stew", "Stir fry", "Roasted Vegetables" }
Catalog.ALL_DISHES = DISH_ORDER
Catalog.DISHES = DISHES

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

function Catalog.findCookware(collected, dishKey)
    local dish = DISHES[dishKey]
    for _, c in ipairs(collected.cookware) do
        for _, ft in ipairs(dish.bases) do
            if c:getFullType() == ft then return c end
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

function Catalog.matchRecipe(name, dishKey)
    local dish = DISHES[dishKey]
    if not dish then return false end
    if dish.recipePrefix then
        return name:sub(1, #dish.recipeName) == dish.recipeName
    end
    return name == dish.recipeName
end

return Catalog
