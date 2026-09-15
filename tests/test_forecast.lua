package.path = "../42/media/lua/shared/?.lua;./?.lua;" .. package.path
local Env = require "support/cook_env"
local e = Env.new()
local xp, calls = 99, 0
local originalAdd = e.recipe.addItem
e.recipe.addItem = function(...)
    xp, calls = xp + 3, calls + 1
    return originalAdd(...)
end
for i = 1, 10 do
    assert(e.cook.plan(e.player, "Soup"))
end
assert(xp == 99 and calls == 0, "opening/rebuilding plans must never call addItem or award XP")
assert(#e.inv.items == 0 and e.food.calories == 40 and #e.pot.extra == 0)
e.cook.start(e.player, "Soup", assert(e.cook.plan(e.player, "Soup")))
e:drain()
assert(calls > 0 and xp > 99, "actual cooking must retain engine XP")

local Forecast = require "CookItForMe_Forecast"
local function near(actual, expected)
    assert(math.abs(actual - expected) < 0.0001, tostring(actual) .. " ~= " .. tostring(expected))
end
local function food(name, use, hunger, calories, spice, raw)
    return { fullType = name, use = use, hunger = hunger, rawHunger = raw or hunger, calories = calories, spice = spice }
end
-- Hand-calculated fixtures: 10 hunger units out of a 20-unit, 200-calorie food.
for _, case in ipairs({ {0, 100}, {3, 109.2}, {10, 116.6666667} }) do
    local h, c = Forecast.calculate({ level = case[1], items = { food("Carrot", 10, -0.2, 200) } })
    near(h, 10)
    near(c, case[2])
end
-- Low remainder truncation matches Java's two-decimal DOWN on a float.
local h, c = Forecast.calculate({ level = 0, items = { food("Carrot", 10, -0.03, 30) } })
near(h, 2)
near(c, 20)
-- Stale food: available hunger is modified, calorie ratio uses raw hunger.
h, c = Forecast.calculate({ level = 0, items = { food("Carrot", 10, -0.075, 200, false, -0.2) } })
near(h, 7)
near(c, 70)
-- Oil contributes calories without hunger; duplicate spice types count once.
h, c = Forecast.calculate({ level = 3, items = {
    food("Carrot", 10, -0.2, 200), food("Oil", 2, -0.1, 1000, true), food("Oil", 2, -0.1, 1000, true),
} })
near(h, 10)
near(c, 349.2)
-- Small spice remnants cap at the whole item's nutrition (no portion truncation).
h, c = Forecast.calculate({ level = 0, items = { food("Carrot", 10, -0.2, 200), food("Oil", 2, -0.01, 50, true) } })
near(c, 150)
-- Unique recipe multiset: two equal types require two physical ingredients.
local unique = { { items = { "Carrot", "Carrot" }, hunger = 5 } }
h, c = Forecast.calculate({ level = 0, uniqueRecipes = unique, items = {
    food("Carrot", 10, -0.2, 200), food("Carrot", 10, -0.2, 200), food("Onion", 10, -0.2, 200),
} })
near(h, 35) -- intermediate bonus retained after onion
near(c, 300)
h = Forecast.calculate({ level = 0, uniqueRecipes = unique, items = {
    food("Carrot", 10, -0.2, 200), food("Onion", 10, -0.2, 200),
} })
near(h, 20)
h, c = Forecast.calculate({ level = 0, items = { food("Excluded", -1, -0.2, 200) } })
near(h, 0)
near(c, 0)

-- API failure must not execute the recipe as a fallback; counters stay unknown.
e = Env.new()
e.forecastError = true
e.recipe.addItem = function() error("preview called mutation API") end
local plan = assert(e.cook.plan(e.player, "Soup"))
assert(plan.predictedHunger == nil and plan.predictedCalories == nil)
assert(#e.inv.items == 0 and #e.queue == 0)
e.forecastError = false
e.food.frozen = true
plan = assert(e.cook.plan(e.player, "Soup"))
assert(plan.predictedHunger == 10 and plan.predictedCalories == 44)
-- No clone creation or access to the player's inventory is needed by Forecast.
e.pot.createCloneItem = function() error("clone creation") end
e.player.getInventory = function() error("player inventory access") end
h, c = Forecast.predict(e.player, e.pot, {}, e.recipe, plan.picked)
assert(h == 10 and c == 44)
for _, state in ipairs({ "rotten", "cooked", "burnt" }) do
    e.food[state] = true
    h, c = Forecast.predict(e.player, e.pot, {}, e.recipe, plan.picked)
    assert(h == nil and c == nil, "changed food state should invalidate forecast")
    e.food[state] = false
end
print("FORECAST TESTS PASSED")
