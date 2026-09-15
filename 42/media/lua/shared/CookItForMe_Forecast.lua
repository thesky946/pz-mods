-- Read-only forecast based on B42 EvolvedRecipe.addItem/useSpice/checkUniqueRecipe.
require "CookItForMe_Shared"
local log = CookItForMe.log
local Forecast = {}

-- Match Java float round-to-nearest-even, including partial-portion boundaries.
local function float(n)
    assert(n == n and n ~= math.huge and n ~= -math.huge, "non-finite nutrition")
    if n == 0 then return 0 end
    local sign = n < 0 and -1 or 1
    local magnitude = math.abs(n)
    assert(magnitude <= 3.4028234663852886e38, "nutrition float overflow")
    local exponent = math.floor(math.log(magnitude) / math.log(2))
    local power = 2 ^ exponent
    if magnitude < power then exponent = exponent - 1
    elseif magnitude >= power * 2 then exponent = exponent + 1 end
    local shift = math.max(exponent - 23, -149)
    local scaled = magnitude / 2 ^ shift
    local rounded = math.floor(scaled)
    local remainder = scaled - rounded
    if remainder > 0.5 or (remainder == 0.5 and rounded % 2 == 1) then rounded = rounded + 1 end
    return sign * rounded * 2 ^ shift
end

local function applyBonuses(hunger, extra, recipes)
    for _, recipe in ipairs(recipes) do
        if #extra == #recipe.items then
            local counts = {}
            for _, name in ipairs(extra) do counts[name] = (counts[name] or 0) + 1 end
            local matches = true
            for _, name in ipairs(recipe.items) do
                if (counts[name] or 0) == 0 then matches = false break end
                counts[name] = counts[name] - 1
            end
            if matches then hunger = float(hunger - float(recipe.hunger / 100)) end
        end
    end
    return hunger
end

-- Pure numeric input; hunger uses the game's negative units.
-- Planner selects distinct, uncooked, non-rotten Food objects.
function Forecast.calculate(input)
    local level = input.level
    assert(level >= 0 and level <= 10, "unsupported cooking level")
    local hunger, calories = float(input.hunger or 0), float(input.calories or 0)
    local extra, spices = {}, {}
    local multiplier = float(float(level / 15) + 1)
    for _, item in ipairs(input.items) do
        if item.use >= 0 then
            local use = float(item.use / 100)
            local raw = float(item.rawHunger)
            if item.spice then
                if not spices[item.fullType] then
                    -- Spices add calories, not hunger, without the ordinary
                    -- ingredient's 3%-per-level consumption discount.
                    local ratio = raw == 0 and (use > 0 and 1 or 0) or math.min(1, math.abs(float(use / raw)))
                    calories = float(calories + float(float(item.calories * multiplier) * ratio))
                    spices[item.fullType] = true
                end
            else
                local available = math.abs(float(item.hunger))
                if available < use then use = float(math.floor(available * 100) / 100) end
                hunger = float(hunger - use)
                local consumed = float(use - float(float((3 * level) / 100) * use))
                local ratio = raw == 0 and (consumed > 0 and 1 or 0) or math.min(1, math.abs(float(consumed / raw)))
                calories = float(calories + float(float(item.calories * multiplier) * ratio))
                extra[#extra + 1] = item.fullType
                -- Intermediate unique-recipe bonuses remain after later additions.
                hunger = applyBonuses(hunger, extra, input.uniqueRecipes or {})
            end
        end
    end
    return -hunger * 100, calories
end

local function snapshot(player, cookware, recipe, picked)
    local input = { level = player:getPerkLevel(Perks.Cooking), hunger = 0, calories = 0, items = {}, uniqueRecipes = {} }
    -- Catalog starts with empty cookware; existing dishes need extra state.
    assert(not cookware:haveExtraItems(), "existing dish is unsupported")
    if instanceof(cookware, "Food") then
        input.hunger, input.calories = cookware:getBaseHunger(), cookware:getCalories()
    end
    local seen = {}
    local function add(item)
        assert(not seen[item], "repeated physical ingredient")
        seen[item] = true
        assert(instanceof(item, "Food"), "non-food ingredient")
        assert(not item:isRotten() and not item:isCooked() and not item:isBurnt(), "ingredient state changed")
        local entry = recipe:getItemsList():get(item:getType())
        if not entry then return end -- incompatible collected spice
        input.items[#input.items + 1] = {
            fullType = item:getFullType(), use = entry:getUse(), spice = item:isSpice(),
            hunger = item:getHungerChange(), rawHunger = item:getHungChange(), calories = item:getCalories(),
        }
    end
    for _, item in ipairs(picked.items) do add(item) end
    for _, item in ipairs(picked.spices) do add(item) end
    local uniques = ScriptManager.instance:getAllUniqueRecipes()
    local resultType = recipe:getResultItem():match("[^.]+$")
    for i = 0, uniques:size() - 1 do
        local unique = uniques:get(i)
        if unique:getBaseRecipe() == resultType then
            local names, list = {}, unique:getItems()
            for j = 0, list:size() - 1 do names[#names + 1] = list:get(j) end
            input.uniqueRecipes[#input.uniqueRecipes + 1] = { items = names, hunger = unique:getHungerBonus() }
        end
    end
    return input
end

function Forecast.predict(player, cookware, dish, recipe, picked)
    local ok, hunger, calories = pcall(function()
        return Forecast.calculate(snapshot(player, cookware, recipe, picked))
    end)
    if not ok or not hunger or hunger <= 0 then
        log("  forecast unavailable: " .. tostring(hunger))
        return nil, nil -- Never fall back to addItem, even on API failure.
    end
    hunger, calories = math.floor(hunger + 0.5), math.floor(calories + 0.5)
    log(string.format("  predicted (formula): hunger=%s cal=%s", tostring(hunger), tostring(calories)))
    return hunger, calories
end

function Forecast.contribution(player, recipe, item, direction)
    local entry = recipe:getItemsList():get(item:getType())
    if not entry then return 0 end
    local hunger, calories = Forecast.calculate({ level = player:getPerkLevel(Perks.Cooking), items = {
        { fullType = item:getFullType(), use = entry:getUse(), spice = item:isSpice(),
          hunger = item:getHungerChange(), rawHunger = item:getHungChange(), calories = item:getCalories() }
    } })
    return direction == "hunger" and hunger or calories
end
return Forecast
