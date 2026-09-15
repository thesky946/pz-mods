package.path = "../42/media/lua/shared/?.lua;./?.lua;" .. package.path
local Env = require "support/cook_env"
local Catalog = require "CookItForMe_Dishes"
local expected = {
    { "Soup", "Base.Pot", "SoupForged", "UI_CookItForMe_DishSoup" },
    { "Stew", "Base.PotForged", "StewForged", "UI_CookItForMe_DishStew" },
    { "Stir fry", "Base.GridlePan", "Stir fry Forged", "UI_CookItForMe_DishStirFry" },
    { "Roasted Vegetables", "Base.RoastingPan", "Roasted Vegetables", "UI_CookItForMe_DishRoast" },
}
for i, entry in ipairs(expected) do
    assert(Catalog.ALL_DISHES[i] == entry[1])
    assert(Catalog.DISHES[entry[1]].label == entry[4])
    assert(Catalog.matchRecipe(entry[3], entry[1]))
    assert(not Catalog.matchRecipe("Other recipe", entry[1]))
    local pot = Env.item(entry[2])
    assert(Catalog.findCookware({ cookware = { pot } }, entry[1]) == pot)
    assert(Catalog.isCookware(entry[2]))
end
assert(not Catalog.matchRecipe("Roasted Vegetables Forged", "Roasted Vegetables"))
assert(not Catalog.isCookware("Base.Saucepan"))
assert(Catalog.isCookware("Base.PanForged"))
local dishes = Catalog.availableDishes({ cookware = { Env.item("Base.Pot"), Env.item("Base.PotForged"), Env.item("Base.Pan") } })
assert(table.concat(dishes, ",") == "Soup,Stew,Stir fry", "order and no duplicate dishes")

-- Use the real scanner collection boundary with non-food objects.
package.loaded.CookItForMe_Scanner = nil
local Scanner = require "CookItForMe_Scanner"
instanceof = function() return false end
local inv, floorBag = Env.container("inventory"), Env.container("bag")
local pot = inv:AddItem(Env.item("Base.PotForged"))
local pan = floorBag:AddItem(Env.item("Base.PanForged"))
inv:AddItem(Env.item("Base.Saucepan"))
local roast = Env.item("Base.RoastingPan")
local collected = Scanner.collectFood({ getInventory = function() return inv end }, {
    containers = { floorBag }, floorItems = { roast },
})
assert(#collected.cookware == 3)
assert(collected.cookware[1] == pan and collected.cookware[2] == roast and collected.cookware[3] == pot)
assert(#collected.foods == 0 and #collected.spices == 0)
print("CATALOG TESTS PASSED")
