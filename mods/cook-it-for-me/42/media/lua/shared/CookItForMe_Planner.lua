-- Builds the preview plan; never starts the action queue.
require "CookItForMe_Shared"
local log = CookItForMe.log

local FoodLogic = require "CookItForMe_FoodLogic"
local Scanner = require "CookItForMe_Scanner"
local Catalog = require "CookItForMe_Dishes"
local Forecast = require "CookItForMe_Forecast"
local Planner = {}

-- План готовки без исполнения: всё, что будет использовано (для UI-превью и старта)
-- Возвращает plan или nil + ключ ошибки.
local function buildPlan(player, dishKey)
    local settings = CookItForMe.getSettings(player)
    local scan = Scanner.scanAround(player, settings.radius)
    local collected = Scanner.collectFood(player, scan)
    log(string.format("PLAN SCAN: stove=%s sink=%s containers=%d floorItems=%d radius=%d",
        scan.stove and 1 or 0, scan.sink and 1 or 0, #scan.containers, #scan.floorItems, settings.radius))

    local dish = Catalog.DISHES[dishKey]
    if not dish then return nil, "NotEnough" end

    if not scan.stove then return nil, "NoStove" end
    if scan.stove:isBroken() then return nil, "NoPower" end

    local cookware = Catalog.findCookware(collected, dishKey)
    if not cookware then return nil, "NoCookware" end
    if not scan.stove:getContainer():hasRoomFor(player, cookware) then
        local alternative
        for _, stove in ipairs(scan.stoves or {}) do
            if stove:getContainer():hasRoomFor(player, cookware) then alternative = stove; break end
        end
        if not alternative then return nil, "NoRoom" end
        scan.stove = alternative
    end

    if dish.needsWater then
        if not scan.sink then return nil, "NoSink" end
        if not scan.sink:hasFluid() then return nil, "NoWater" end
    end

    -- эволюционный рецепт по выбранному блюду
    local containers = ArrayList.new()
    for _, cont in ipairs(scan.containers) do containers:add(cont) end
    local recipe = nil
    -- need1ingredient=false: не отсекать рецепты без ингредиентов, фильтруем сами
    local recipes = RecipeManager.getEvolvedRecipe(cookware, player, containers, false)
    log(string.format("PLAN: dish=%s cookware=%s recipes=%d",
        dishKey, tostring(cookware:getFullType()), recipes and recipes:size() or -1))
    for i = 0, (recipes and recipes:size() or 0) - 1 do
        log("  recipe: " .. tostring(recipes:get(i):getUntranslatedName()))
    end
    for i = 0, (recipes and recipes:size() or 0) - 1 do
        local r = recipes:get(i)
        if Catalog.matchRecipe(r:getUntranslatedName(), dishKey) then recipe = r end
    end
    if not recipe then return nil, "NoCookware" end

    -- только ингредиенты, совместимые с рецептом
    -- Read metadata without changing the shared recipe or requiring water in the preview.
    local validFoods, validSpices = {}, {}
    local entries = recipe:getItemsList()
    local function compatible(item)
        local entry = entries:get(item:getType())
        if not entry or entry:getUse() < 0 then return false end
        if entry.getFullType and entry:getFullType() ~= item:getFullType() then return false end
        if item.isNoRecipes and item:isNoRecipes(player) then return false end
        return true
    end
    for _, item in ipairs(collected.foods) do
        if compatible(item) then validFoods[#validFoods + 1] = item end
    end
    for _, item in ipairs(collected.spices) do
        if compatible(item) then validSpices[#validSpices + 1] = item end
    end
    if #validFoods == 0 then return nil, "NotEnough" end

    local direction = FoodLogic.decideDirection(player:getNutrition(), settings)
    -- специи: до 4 = 2 базовых (соль/перец) + 2 по направлению
    local scores = {}
    local picked = FoodLogic.pickIngredients(validFoods, validSpices, direction, recipe:getMaxItems(), 4,
        function(item)
            if scores[item] == nil then scores[item] = Forecast.contribution(player, recipe, item, direction) end
            return scores[item]
        end)

    for _, f in ipairs(picked.items) do
        local tag = f:isFrozen() and " [frozen]" or ""
        log(string.format("  pick: %s (%.0f cal)%s",
            tostring(f:getDisplayName()), f:getCalories(), tag))
    end
    for _, s in ipairs(picked.spices) do
        log("  spice: " .. tostring(s:getDisplayName()))
    end

    local predictedHunger, predictedCalories = Forecast.predict(player, cookware, dish, recipe, picked)

    local sources = {}
    local function remember(item)
        sources[item] = { container = item:getContainer(),
            world = item.getWorldItem and item:getWorldItem() or nil,
            calories = item.getCalories and item:getCalories() or nil,
            hunger = item.getHungerChange and item:getHungerChange() or nil }
    end
    remember(cookware)
    for _, item in ipairs(picked.items) do remember(item) end
    for _, item in ipairs(picked.spices) do remember(item) end
    return {
        player = player, sources = sources,
        dishKey = dishKey,
        dish = dish,
        cookware = cookware,
        recipe = recipe,
        picked = picked,
        direction = direction,
        settings = settings,
        scan = scan,
        weight = player:getNutrition():getWeight(),
        cookingLevel = player:getPerkLevel(Perks.Cooking),
        predictedHunger = predictedHunger,
        predictedCalories = predictedCalories,
    }
end

function Planner.plan(player, dishKey)
    local ok, plan, key = pcall(buildPlan, player, dishKey)
    if not ok then
        CookItForMe.diagnostic("plan failed: " .. tostring(plan))
        return nil, "ActionFailed"
    end
    return plan, key
end

function Planner.validate(player, plan)
    if plan.player ~= player then return false, "PlanChanged" end
    for item, source in pairs(plan.sources or {}) do
        local world = item.getWorldItem and item:getWorldItem() or nil
        if world ~= source.world or (not world and item:getContainer() ~= source.container) then return false, "PlanChanged" end
        if world then
            if not world:getSquare() then return false, "ItemMissing" end
        elseif not source.container or not source.container:contains(item) then return false, "ItemMissing" end
        if item ~= plan.cookware and (item:isRotten() or item:isBurnt() or item:isCooked()) then return false, "PlanChanged" end
        if source.calories and item:getCalories() ~= source.calories then return false, "PlanChanged" end
        if source.hunger and item:getHungerChange() ~= source.hunger then return false, "PlanChanged" end
    end
    local scan = Scanner.scanAround(player, CookItForMe.getSettings(player).radius)
    local collected = Scanner.collectFood(player, scan)
    local available = {}
    for _, list in ipairs({collected.cookware, collected.foods, collected.spices}) do
        for _, item in ipairs(list) do available[item] = true end
    end
    for item in pairs(plan.sources or {}) do if not available[item] then return false, "PlanChanged" end end
    local function contains(list, target, fallback)
        if not list then return fallback == target end
        for _, value in ipairs(list) do if value == target then return true end end
        return false
    end
    local stove = plan.scan.stove
    if not contains(scan.stoves, stove, scan.stove) then return false, "PlanChanged" end
    if stove:isBroken() or not stove:getContainer():isPowered() then return false, "NoPower" end
    if not stove:getContainer():hasRoomFor(player, plan.cookware) then return false, "NoRoom" end
    if plan.dish.needsWater then
        if not contains(scan.sinks, plan.scan.sink, scan.sink) then return false, "NoSink" end
        if not plan.scan.sink:hasFluid() then return false, "NoWater" end
    end
    return true
end
return Planner
