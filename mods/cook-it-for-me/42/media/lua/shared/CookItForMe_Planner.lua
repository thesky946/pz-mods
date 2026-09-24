-- Builds the preview plan; never starts the action queue.
require "CookItForMe_Shared"
local log = CookItForMe.log

local FoodLogic = require "CookItForMe_FoodLogic"
local Scanner = require "CookItForMe_Scanner"
local Catalog = require "CookItForMe_Dishes"
local Forecast = require "CookItForMe_Forecast"
local Planner = {}

local function compatible(recipe, player, item, dish, settings)
    if not Catalog.isSafeIngredient(item) then return false end
    local entry = recipe:getItemsList():get(item:getType())
    if not entry or entry:getUse() < 0 then return false end
    if entry.getFullType and entry:getFullType() ~= item:getFullType() then return false end
    if item.isNoRecipes and item:isNoRecipes(player) then return false end
    if dish.allowCookedIngredients then
        if not recipe:needToBeCooked(item) then return false end
    elseif item:isCooked() then return false end
    if item:isFrozen() and not Catalog.allowsFrozen(dish, settings) then return false end
    return true
end

local function remember(plan, item)
    plan.sources[item] = { container = item:getContainer(),
        world = item.getWorldItem and item:getWorldItem() or nil,
        calories = item.getCalories and item:getCalories() or nil,
        hunger = item.getHungerChange and item:getHungerChange() or nil }
end

local function syncPicked(plan)
    plan.picked.items, plan.picked.spices = {}, {}
    plan.picked.frozenCount = 0
    plan.edited = false
    local prepItems, prepComplete = {}, true
    for _, row in ipairs(plan.rows) do
        if row.item ~= row.originalItem or row.removedItem then plan.edited = true end
        if row.kind == "prep" then
            if row.item then prepItems[row.prepIndex] = row.item else prepComplete = false end
        elseif row.item then
            local list = row.kind == "food" and plan.picked.items or plan.picked.spices
            list[#list + 1] = row.item
            if row.kind == "food" and row.item:isFrozen() then
                plan.picked.frozenCount = plan.picked.frozenCount + 1
            end
        end
    end
    if plan.prep then plan.prep.items = prepComplete and prepItems or {} end
    plan.predictedHunger, plan.predictedCalories = Forecast.predict(plan.player, plan.recipeBase or plan.cookware,
        plan.dish, plan.recipe, plan.picked)
end

local function findRow(plan, id)
    for i, row in ipairs(plan.rows or {}) do if row.id == id then return row, i end end
end

-- План готовки без исполнения: всё, что будет использовано (для UI-превью и старта)
-- Возвращает plan или nil + ключ ошибки.
local function buildPlan(player, dishKey, selectedCookware, sharedScan, sharedCollected)
    local settings = CookItForMe.getSettings(player)
    local dish = Catalog.DISHES[dishKey]
    if not dish then return nil, "NotEnough" end
    local needsHeat = settings.finishCooking and dish.needsHeat ~= false
    local scan = sharedScan or Scanner.scanAround(player, settings.radius, needsHeat)
    if sharedScan then
        scan = {
            stove = needsHeat and sharedScan.stove or nil,
            stoves = needsHeat and sharedScan.stoves or {},
            sink = sharedScan.sink, sinks = sharedScan.sinks,
            containers = sharedScan.containers, floorItems = sharedScan.floorItems,
        }
    end
    local collected = sharedCollected or Scanner.collectFood(player, scan, dish.allowCookedIngredients)
    log(string.format("PLAN SCAN: stove=%s sink=%s containers=%d floorItems=%d radius=%d",
        scan.stove and 1 or 0, scan.sink and 1 or 0, #scan.containers, #scan.floorItems, settings.radius))

    local cookware = Catalog.findCookware(collected, dishKey, true)
    if selectedCookware then
        cookware = nil
        for _, candidate in ipairs(collected.cookware) do
            if candidate == selectedCookware then
                for _, fullType in ipairs(dish.bases) do
                    if candidate:getFullType() == fullType and Catalog.isUsableBase(dish, candidate) then
                        cookware = candidate
                        break
                    end
                end
                break
            end
        end
    end
    if not cookware then
        if Catalog.findCookware(collected, dishKey) then
            return nil, "NoEmptyBowl"
        end
        return nil, "NoCookware"
    end

    if needsHeat then
        local stove = scan.stove
        if not stove then return nil, "NoStove" end
        if stove:isBroken() then return nil, "NoPower" end
        if not stove:getContainer():hasRoomFor(player, cookware) then
            local alternative
            for _, candidate in ipairs(scan.stoves or {}) do
                if candidate:getContainer():hasRoomFor(player, cookware) then alternative = candidate; break end
            end
            if not alternative then return nil, "NoRoom" end
            scan.stove = alternative
        end
    end

    if dish.needsWater then
        if not scan.sink then return nil, "NoSink" end
        if not scan.sink:hasFluid() then return nil, "NoWater" end
    end

    local prep, recipeBase = nil, cookware
    if Catalog.hasPrep(dish) then
        local definition = assert(dish.prep)[cookware:getFullType()]
        local items = Catalog.selectPrep(dish, cookware, collected.items or {}, settings)
        if not items then return nil, "NotEnough" end
        local craftRecipe = ScriptManager.instance:getCraftRecipe(definition.recipe)
        if not craftRecipe then return nil, "RecipeUnavailable" end
        recipeBase = instanceItem(definition.base)
        if not recipeBase then return nil, "ActionFailed" end
        prep = { recipe = craftRecipe, expected = definition.base, items = items, count = #items }
    end

    -- эволюционный рецепт по выбранному блюду
    local containers = ArrayList.new()
    for _, cont in ipairs(scan.containers) do containers:add(cont) end
    local recipe = nil
    -- need1ingredient=false: не отсекать рецепты без ингредиентов, фильтруем сами
    local recipes = RecipeManager.getEvolvedRecipe(recipeBase, player, containers, false)
    log(string.format("PLAN: dish=%s cookware=%s recipes=%d",
        dishKey, tostring(recipeBase:getFullType()), recipes and recipes:size() or -1))
    for i = 0, (recipes and recipes:size() or 0) - 1 do
        log("  recipe: " .. tostring(recipes:get(i):getUntranslatedName()))
    end
    for i = 0, (recipes and recipes:size() or 0) - 1 do
        local r = recipes:get(i)
        if Catalog.matchRecipe(r:getUntranslatedName(), dishKey, recipeBase:getFullType())
            and (not dish.results or dish.results[recipeBase:getFullType()] == r:getFullResultItem()) then recipe = r end
    end
    if not recipe then return nil, "NoCookware" end

    -- только ингредиенты, совместимые с рецептом
    -- Read metadata without changing the shared recipe or requiring water in the preview.
    local validFoods, validSpices = {}, {}
    local prepItems = {}
    if prep then for _, item in ipairs(prep.items) do prepItems[item] = true end end
    for _, item in ipairs(collected.foods) do
        if not prepItems[item] and compatible(recipe, player, item, dish, settings) then
            validFoods[#validFoods + 1] = item
        end
    end
    for _, item in ipairs(collected.spices) do
        if compatible(recipe, player, item, dish, settings) then validSpices[#validSpices + 1] = item end
    end
    local direction = FoodLogic.decideDirection(player:getNutrition(), settings)
    -- специи: до 4 = 2 базовых (соль/перец) + 2 по направлению
    local scores = {}
    local picked = FoodLogic.pickIngredients(validFoods, validSpices, direction,
        recipe:getMaxItems(), 4,
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

    local predictedHunger, predictedCalories = Forecast.predict(player, recipeBase, dish, recipe, picked)

    local plan = {
        player = player, sources = {}, rows = {}, nextRowId = 1,
        dishKey = dishKey,
        dish = dish,
        needsHeat = needsHeat,
        cookware = cookware,
        recipeBase = recipeBase,
        prep = prep,
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
    remember(plan, cookware)
    if prep then
        for index, item in ipairs(prep.items) do
            plan.rows[#plan.rows + 1] = { id = plan.nextRowId, kind = "prep", prepIndex = index,
                item = item, originalItem = item }
            plan.nextRowId = plan.nextRowId + 1
            remember(plan, item)
        end
    end
    for _, kind in ipairs({ "food", "spice" }) do
        local groupItems = kind == "food" and picked.items or picked.spices
        for _, item in ipairs(groupItems) do
            plan.rows[#plan.rows + 1] = { id = plan.nextRowId, kind = kind, item = item, originalItem = item }
            plan.nextRowId = plan.nextRowId + 1
            remember(plan, item)
        end
        if kind == "food" then
            for _ = #picked.items + 1, recipe:getMaxItems() do
                plan.rows[#plan.rows + 1] = { id = plan.nextRowId, kind = kind }
                plan.nextRowId = plan.nextRowId + 1
            end
        end
    end
    return plan
end

function Planner.remove(plan, id)
    local row = findRow(plan, id)
    if not row or not row.item then return nil end
    local item = row.item
    row.item = nil
    row.removedItem = row.originalItem and item or nil
    plan.sources[item] = nil
    syncPicked(plan)
    return { row = row, item = item }
end

function Planner.undo(plan, removal)
    if not removal or not removal.row then return false end
    local row = findRow(plan, removal.row.id)
    if row ~= removal.row or row.item then return false end
    for _, other in ipairs(plan.rows) do
        if other.item == removal.item then return false end
    end
    row.item = removal.item
    row.removedItem = nil
    remember(plan, removal.item)
    syncPicked(plan)
    return true
end

function Planner.alternatives(player, plan, id)
    local row = findRow(plan, id)
    if not row then return {} end
    local scan = Scanner.scanAround(player, CookItForMe.getSettings(player).radius, plan.needsHeat)
    local collected = Scanner.collectFood(player, scan, plan.dish.allowCookedIngredients)
    if row.kind == "prep" then
        local used = { [plan.cookware] = true }
        for _, other in ipairs(plan.rows) do if other ~= row and other.item then used[other.item] = true end end
        local result = {}
        for _, item in ipairs(collected.items or {}) do
            if item ~= row.item and not used[item]
                and Catalog.prepSlotAccepts(plan.dish, row.prepIndex, item, plan.settings) then
                result[#result + 1] = item
            end
        end
        return result
    end
    local pool = row.kind == "food" and collected.foods or collected.spices
    local used, typeCount = {}, {}
    for _, other in ipairs(plan.rows) do
        if other ~= row and other.item then
            used[other.item] = true
            local ft = other.item:getFullType()
            typeCount[ft] = (typeCount[ft] or 0) + 1
        end
    end
    local result = {}
    for _, item in ipairs(pool) do
        local ft = item:getFullType()
        local isPrep = false
        if plan.prep then
            for _, prepItem in ipairs(plan.prep.items) do if item == prepItem then isPrep = true; break end end
        end
        local limit = row.kind == "food" and 2 or 1
        -- The execution path transfers the chosen item to player inventory first.
        -- B42's isItemUsableInRecipe searches only that inventory when called
        -- without containers, so it rejects valid nearby items at preview time.
        if not isPrep and item ~= row.item and not used[item] and (typeCount[ft] or 0) < limit
            and compatible(plan.recipe, player, item, plan.dish, plan.settings) then
            result[#result + 1] = item
        end
    end
    return result
end

function Planner.replace(player, plan, id, item)
    local row = findRow(plan, id)
    if not row then return false end
    local allowed = false
    for _, candidate in ipairs(Planner.alternatives(player, plan, id)) do
        if candidate == item then allowed = true break end
    end
    if not allowed then return false end
    if row.item then plan.sources[row.item] = nil end
    row.item = item
    row.removedItem = nil
    remember(plan, item)
    syncPicked(plan)
    return true
end

function Planner.reset(player, plan)
    local fresh, key = Planner.plan(player, plan.dishKey,
        plan.cookwareChosen and plan.cookware or nil)
    if not fresh then return false, key end
    fresh.cookwareChosen = plan.cookwareChosen
    for k, value in pairs(fresh) do plan[k] = value end
    plan.edited = false
    return true
end

function Planner.rowAvailable(player, plan, row, available)
    if not row.item then return nil end
    local item, source = row.item, plan.sources[row.item]
    if not source or (instanceof(item, "Food") and not Catalog.isSafeIngredient(item)) then return false end
    local world = item.getWorldItem and item:getWorldItem() or nil
    if world ~= source.world or (not world and item:getContainer() ~= source.container) then return false end
    if world then
        if not world:getSquare() then return false end
    elseif not source.container or not source.container:contains(item) then return false end
    if source.calories and item:getCalories() ~= source.calories then return false end
    if source.hunger and item:getHungerChange() ~= source.hunger then return false end
    if row.kind == "prep" then
        if not Catalog.prepSlotAccepts(plan.dish, row.prepIndex, item, plan.settings) then return false end
    elseif not compatible(plan.recipe, player, item, plan.dish, plan.settings) then return false end
    return available[item] == true
end

function Planner.rowAvailability(player, plan, scan, collected)
    scan = scan or Scanner.scanAround(player, CookItForMe.getSettings(player).radius, plan.needsHeat)
    collected = collected or Scanner.collectFood(player, scan, plan.dish.allowCookedIngredients)
    local available = {}
    for _, list in ipairs({ collected.foods, collected.spices, collected.items or {} }) do
        for _, item in ipairs(list) do available[item] = true end
    end
    local status = {}
    for _, row in ipairs(plan.rows) do
        if row.item then status[row.id] = Planner.rowAvailable(player, plan, row, available) end
    end
    return status
end

function Planner.plan(player, dishKey, selectedCookware, scan, collected)
    if not selectedCookware and Catalog.DISHES[dishKey] then
        local dish = Catalog.DISHES[dishKey]
        local settings = CookItForMe.getSettings(player)
        local needsHeat = settings.finishCooking and dish.needsHeat ~= false
        scan = scan or Scanner.scanAround(player, settings.radius, needsHeat)
        collected = collected or Scanner.collectFood(player, scan, dish.allowCookedIngredients)
        local firstFailure
        for _, candidate in ipairs(collected.cookware) do
            for _, fullType in ipairs(dish.bases) do
                if candidate:getFullType() == fullType and Catalog.isUsableBase(dish, candidate) then
                    local ok, candidatePlan, key = pcall(buildPlan, player, dishKey, candidate, scan, collected)
                    if ok and candidatePlan then return candidatePlan end
                    if not ok then
                        CookItForMe.diagnostic("plan failed: " .. tostring(candidatePlan))
                        key = "ActionFailed"
                    end
                    firstFailure = firstFailure or key
                    break
                end
            end
        end
        ---@diagnostic disable-next-line: unnecessary-if -- Build 42 recipes can reject one base while another works.
        if firstFailure then return nil, firstFailure end
    end
    local ok, plan, key = pcall(buildPlan, player, dishKey, selectedCookware, scan, collected)
    if not ok then
        CookItForMe.diagnostic("plan failed: " .. tostring(plan))
        return nil, "ActionFailed"
    end
    return plan, key
end

local function keepComposition(player, oldPlan, fresh)
    local defaults, removed = { prep = {}, food = {}, spice = {} }, {}
    for _, row in ipairs(fresh.rows) do
        local list = defaults[row.kind]
        list[#list + 1] = row.item
        if row.item then fresh.sources[row.item] = nil end
        row.item = nil
        row.removedItem = nil
    end
    syncPicked(fresh)
    for _, row in ipairs(oldPlan.rows or {}) do
        if not row.item and (row.removedItem or row.originalItem) then
            removed[row.removedItem or row.originalItem] = true
        end
    end
    local positions = { prep = 0, food = 0, spice = 0 }
    local used = {}
    for _, oldRow in ipairs(oldPlan.rows or {}) do
        local kind = oldRow.kind
        positions[kind] = positions[kind] + 1
        local newRow
        local count = 0
        for _, row in ipairs(fresh.rows) do
            if row.kind == kind then
                count = count + 1
                if count == positions[kind] then newRow = row break end
            end
        end
        ---@diagnostic disable-next-line: unnecessary-if -- A different cookware recipe can have fewer slots.
        if newRow then
            if oldRow.item and Planner.replace(player, fresh, newRow.id, oldRow.item) then
                used[oldRow.item] = true
            elseif oldRow.item then
                for _, fallback in ipairs(defaults[kind]) do
                    if fallback and not used[fallback] and not removed[fallback]
                        and Planner.replace(player, fresh, newRow.id, fallback) then
                        used[fallback] = true
                        break
                    end
                end
            else
                newRow.removedItem = oldRow.removedItem or oldRow.originalItem
            end
        end
    end
    syncPicked(fresh)
end

function Planner.chooseCookware(player, oldPlan, item, scan, collected)
    if not oldPlan or not item then return nil end
    local fresh = Planner.plan(player, oldPlan.dishKey, item, scan, collected)
    if not fresh then return nil end
    keepComposition(player, oldPlan, fresh)
    if not Planner.validate(player, fresh) then return nil end
    fresh.cookwareChosen = true
    return fresh
end

function Planner.cookwareOptions(player, plan, scan, collected)
    if not plan then return {} end
    scan = scan or Scanner.scanAround(player, CookItForMe.getSettings(player).radius, plan.needsHeat)
    collected = collected or Scanner.collectFood(player, scan, plan.dish.allowCookedIngredients)
    local options = {}
    for _, item in ipairs(collected.cookware) do
        for _, fullType in ipairs(plan.dish.bases) do
            if item:getFullType() == fullType and Catalog.isUsableBase(plan.dish, item) then
                options[#options + 1] = { item = item }
                break
            end
        end
    end
    return options
end

function Planner.validate(player, plan, rowStatus, scan, collected)
    if plan.player ~= player then return false, "PlanChanged" end
    if Catalog.DISHES[plan.dishKey] ~= plan.dish then return false, "PlanChanged" end
    if not Catalog.isUsableBase(plan.dish, plan.cookware) then
        return false, "NoEmptyBowl"
    end
    if plan.prep and #plan.prep.items ~= plan.prep.count then return false, "NotEnough" end
    if #plan.picked.items == 0 then return false, "NotEnough" end
    rowStatus = rowStatus or Planner.rowAvailability(player, plan)
    for _, row in ipairs(plan.rows) do
        if row.kind == "prep" and row.item
            and not Catalog.prepSlotAccepts(plan.dish, row.prepIndex, row.item, plan.settings) then
            return false, "PlanChanged"
        end
        if row.item and not rowStatus[row.id] then return false, "SelectedUnavailable", row.item:getDisplayName() end
    end
    for item, source in pairs(plan.sources or {}) do
        local world = item.getWorldItem and item:getWorldItem() or nil
        if world ~= source.world or (not world and item:getContainer() ~= source.container) then return false, "PlanChanged" end
        if world then
            if not world:getSquare() then return false, "ItemMissing" end
        elseif not source.container or not source.container:contains(item) then return false, "ItemMissing" end
        local isPrep = false
        if plan.prep then
            for _, prepItem in ipairs(plan.prep.items) do if item == prepItem then isPrep = true; break end end
        end
        if isPrep and item:isBroken() then return false, "PlanChanged" end
        if item ~= plan.cookware and instanceof(item, "Food")
            and (not Catalog.isSafeIngredient(item)
                or (isPrep and item:isFrozen() and not Catalog.allowsFrozen(plan.dish, plan.settings))
                or (not isPrep and not compatible(plan.recipe, player, item, plan.dish, plan.settings))) then
            return false, "PlanChanged"
        end
        if source.calories and item:getCalories() ~= source.calories then return false, "PlanChanged" end
        if source.hunger and item:getHungerChange() ~= source.hunger then return false, "PlanChanged" end
    end
    scan = scan or Scanner.scanAround(player, CookItForMe.getSettings(player).radius, plan.needsHeat)
    collected = collected or Scanner.collectFood(player, scan, plan.dish.allowCookedIngredients)
    local available = {}
    for _, list in ipairs({collected.cookware, collected.foods, collected.spices, collected.items or {}}) do
        for _, item in ipairs(list) do available[item] = true end
    end
    for item in pairs(plan.sources or {}) do if not available[item] then return false, "PlanChanged" end end
    local function contains(list, target, fallback)
        if not list then return fallback == target end
        for _, value in ipairs(list) do if value == target then return true end end
        return false
    end
    if plan.needsHeat then
        local stove = plan.scan.stove
        if not contains(scan.stoves, stove, scan.stove) then return false, "PlanChanged" end
        if stove:isBroken() or not stove:getContainer():isPowered() then return false, "NoPower" end
        if not stove:getContainer():hasRoomFor(player, plan.cookware) then return false, "NoRoom" end
    end
    if plan.dish.needsWater then
        if not contains(scan.sinks, plan.scan.sink, scan.sink) then return false, "NoSink" end
        if not plan.scan.sink:hasFluid() then return false, "NoWater" end
    end
    return true
end
return Planner
