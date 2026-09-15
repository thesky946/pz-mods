-- Офлайн-тест чистых функций CookItForMe_FoodLogic (куски 6, 7, 7b)
-- Запуск: lua tests/test_foodlogic.lua

local FoodLogic = dofile("../42/media/lua/shared/CookItForMe_FoodLogic.lua")

local function assertEq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("FAIL %s: expected %s, got %s", msg, tostring(expected), tostring(actual)))
    end
end

local function mock(fullType, calories, frozen, baseHunger)
    return {
        getFullType = function() return fullType end,
        getCalories = function() return calories end,
        isFrozen = function() return frozen or false end,
        getBaseHunger = function() return baseHunger or 0 end,
    }
end

-- === Кусок 6: decideDirection (3 режима) ===
assertEq(FoodLogic.decideDirection(nil, { strategy = "max" }), "max", "strategy max")
assertEq(FoodLogic.decideDirection(nil, { strategy = "min" }), "min", "strategy min")
assertEq(FoodLogic.decideDirection(nil, { strategy = "hunger" }), "hunger", "strategy hunger")

-- === Кусок 7: pickIngredients ===
local foods = {
    mock("A", 100, false, -10), mock("A", 90, true, -90), mock("A", 80, false, -80),
    mock("B", 70, true, -5), mock("B", 60, false, -60),
    mock("C", 50, false, -50),
    mock("D", 40, false, -100),
    mock("E", 30, false, -30),
}
local spices = { mock("Salt", 0), mock("Pepper", 0), mock("Salt", 0), mock("Oil", 120, false, 20), mock("Sugar", 50, false, 10) }

local picked = FoodLogic.pickIngredients(foods, spices, "max", 6)
assertEq(#picked.items, 6, "max: 6 items")
local counts = {}
for _, f in ipairs(picked.items) do counts[f:getFullType()] = (counts[f:getFullType()] or 0) + 1 end
for _, c in pairs(counts) do assertEq(c <= 2, true, "max: no 3rd repeat") end
local sum = 0
for _, f in ipairs(picked.items) do sum = sum + f:getCalories() end
assertEq(sum, 410, "max: greedy sum (100+90+70+60+50+40)")
assertEq(picked.frozenCount, 2, "max: frozenCount (A90, B70)")
-- специи: 2 базовых (Salt, Pepper) + 2 по направлению (Oil, Sugar) = 4
assertEq(#picked.spices, 4, "spices: 2 basic + 2 directed")
assertEq(picked.spices[1]:getFullType(), "Pepper", "spices: basic first")
assertEq(picked.spices[2]:getFullType(), "Salt", "spices: basic second")
assertEq(picked.spices[3]:getFullType(), "Oil", "spices: max directed")
assertEq(picked.spices[4]:getFullType(), "Sugar", "spices: max directed 2")

local pickedMin = FoodLogic.pickIngredients(foods, spices, "min", 6)
local sumMin = 0
for _, f in ipairs(pickedMin.items) do sumMin = sumMin + f:getCalories() end
assertEq(sumMin, 330, "min: greedy sum (30+40+50+60+70+80)")

-- hunger: по сытности (getBaseHunger отрицательный: чем сытнее, тем ниже)
local pickedHunger = FoodLogic.pickIngredients(foods, spices, "hunger", 6)
local hungerSum = 0
for _, f in ipairs(pickedHunger.items) do hungerSum = hungerSum + f:getBaseHunger() end
-- сортировка asc: D(-100), A(-90), A(-80), B(-60), C(-50), E(-30) -> сумма -410
assertEq(hungerSum, -410, "hunger: greedy sum by hungerChange (most negative first)")
assertEq(pickedHunger.items[1]:getFullType(), "D", "hunger: most filling first")

-- меньше 3 уникальных типов: кладём сколько возможно без 3-го повтора
local few = { mock("A", 100), mock("A", 90), mock("A", 80), mock("B", 70), mock("B", 60), mock("B", 50) }
local pickedFew = FoodLogic.pickIngredients(few, {}, "max", 6)
assertEq(#pickedFew.items, 4, "few types: max 4 without 3rd repeat")

-- лимит специй
local pickedLimited = FoodLogic.pickIngredients(foods, spices, "max", 6, 1)
assertEq(#pickedLimited.spices, 1, "maxSpices limit works")
assertEq(pickedLimited.spices[1]:getFullType(), "Pepper", "max: basic spice has priority")

-- === Кусок 7b: frozenPenaltyTime ===
assertEq(FoodLogic.frozenPenaltyTime(100, 0.5, 2, 4), 125, "half frozen: +25 percent")
assertEq(FoodLogic.frozenPenaltyTime(100, 0.5, 0, 4), 100, "fresh unchanged")
assertEq(FoodLogic.frozenPenaltyTime(60, 0.5, 1, 1), 90, "single frozen: +50 percent")
assertEq(FoodLogic.frozenPenaltyTime(100, 0.5, 6, 6), 150, "all frozen: capped at +50 percent")
assertEq(FoodLogic.frozenPenaltyTime(100, 0.5, 0, 0), 100, "empty input is safe")

print("ALL TESTS PASSED")
