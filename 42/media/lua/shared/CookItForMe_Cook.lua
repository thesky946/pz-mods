-- Cook It For Me: цикл приготовления (singleplayer, B42)
-- Полный цикл: ходьба, кастрюля, вода, ингредиенты, плита, нагрев, готовность, возврат.

require "CookItForMe_Shared"
local FoodLogic = require "CookItForMe_FoodLogic"
local Scanner = require "CookItForMe_Scanner"
-- TimedActions (ISWalkToTimedAction, ISInventoryTransferAction, ISTakeWaterAction,
-- ISAddItemInRecipe) — ванильные глобалы, загружены игрой; модовый require их не резолвит.

-- Все логи цикла — под дебаг-флагом (CookItForMe.Debug в настройках песочницы)
local log = CookItForMe.log

CookItForMe.Cook = CookItForMe.Cook or {}
local Cook = CookItForMe.Cook

Cook.active = false
Cook.cooking = false
Cook.pot = nil
Cook.stove = nil
Cook.weTurnedStoveOn = false
Cook.addedCount = 0
-- отложенное продолжение цепочки (пауза между добавлениями ингредиентов)
Cook.delayUntil = nil
Cook.delayNext = nil

local function delayedNext(ms, next)
    Cook.delayUntil = getTimestampMs() + ms
    Cook.delayNext = next
end

-- Блюда: посуда + вода + имя эволюционного рецепта (по media/scripts B42)
local DISHES = {
    Soup = { recipeName = "Soup", bases = { "Base.Pot", "Base.PotForged" }, needsWater = true },
    Stew = { recipeName = "Stew", bases = { "Base.Pot", "Base.PotForged" }, needsWater = true },
    ["Stir fry"] = { recipeName = "Stir fry", bases = { "Base.Pan", "Base.PanForged", "Base.GridlePan" }, needsWater = false },
    ["Roasted Vegetables"] = { recipeName = "Roasted Vegetables", bases = { "Base.RoastingPan" }, needsWater = false },
}

local DISH_ORDER = { "Soup", "Stew", "Stir fry", "Roasted Vegetables" }
Cook.ALL_DISHES = DISH_ORDER
Cook.DISHES = DISHES

-- Какие блюда можно приготовить из собранной посуды (в фиксированном порядке)
function Cook.availableDishes(collected)
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

function Cook.findCookware(collected, dishKey)
    local dish = DISHES[dishKey]
    for _, c in ipairs(collected.cookware) do
        for _, ft in ipairs(dish.bases) do
            if c:getFullType() == ft then return c end
        end
    end
    return nil
end

function Cook.fail(player, key)
    Cook.active = false
    Cook.cooking = false
    local msg = getText("UI_CookItForMe_" .. key)
    log("FAIL: " .. msg)
    player:Say(msg)
end

-- Рецепты в B42 имеют суффиксы (Soup, SoupForged, Stir fry Forged...): матчим по префиксу
local function matchRecipe(untranslatedName, dishKey)
    if dishKey == "Soup" then
        return untranslatedName == "Soup" or string.find(untranslatedName, "^Soup") ~= nil
    end
    if dishKey == "Stew" then
        return untranslatedName == "Stew" or string.find(untranslatedName, "^Stew") ~= nil
    end
    if dishKey == "Stir fry" then
        return string.find(untranslatedName, "^Stir fry") ~= nil
    end
    return untranslatedName == dishKey
end

-- План готовки без исполнения: всё, что будет использовано (для UI-превью и старта)
-- Возвращает plan или nil + ключ ошибки.
function Cook.plan(player, dishKey)
    local settings = CookItForMe.getSettings(player)
    local scan = Scanner.scanAround(player, settings.radius)
    local collected = Scanner.collectFood(player, scan)
    log(string.format("PLAN SCAN: stove=%s sink=%s containers=%d floorItems=%d radius=%d",
        scan.stove and 1 or 0, scan.sink and 1 or 0, #scan.containers, #scan.floorItems, settings.radius))

    local dish = DISHES[dishKey]
    if not dish then return nil, "NotEnough" end

    if not scan.stove then return nil, "NoStove" end
    if scan.stove:isBroken() then return nil, "NoPower" end

    local cookware = Cook.findCookware(collected, dishKey)
    if not cookware then return nil, "NoCookware" end

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
    for i = 0, recipes:size() - 1 do
        local r = recipes:get(i)
        if matchRecipe(r:getUntranslatedName(), dishKey) then recipe = r end
    end
    if not recipe then return nil, "NoCookware" end

    -- только ингредиенты, совместимые с рецептом
    -- замороженные: разрешаем рецепту принять их ДО фильтрации
    local hasFrozen = false
    for _, f in ipairs(collected.foods) do
        if f:isFrozen() then hasFrozen = true break end
    end
    if hasFrozen and not recipe:isAllowFrozenItem() then
        recipe:setAllowFrozenItem(true)
        log("recipe: frozen items allowed BEFORE filtering")
    end

    log(string.format("COLLECT: foods=%d spices=%d frozenFoods=%d",
        #collected.foods, #collected.spices, hasFrozen and 1 or 0))

    local validIds = {}
    local validFoods = {}
    local validSpices = {}
    -- специи: берём все собранные, валидность проверяется в stepAdd динамически
    for _, s in ipairs(collected.spices) do
        table.insert(validSpices, s)
    end
    if dish.needsWater then
        -- супы/рагу: пробуем статичные списки рецепта (не требуют воду)
        local okM, possible = pcall(function() return recipe:getPossibleItems() end)
        if okM and possible and possible:size() > 0 then
            for i = 0, possible:size() - 1 do
                local ft = possible:get(i):getFullType()
                if ft then validIds[ft] = true end
            end
            for _, f in ipairs(collected.foods) do
                if validIds[f:getFullType()] then table.insert(validFoods, f) end
            end
        end
        if #validFoods == 0 then
            local okM2, itemsMap = pcall(function() return recipe:getItemsList() end)
            if okM2 and itemsMap then
                for _, f in ipairs(collected.foods) do
                    -- ключ itemsList — короткое имя предмета (getType()), не fullType
                    if itemsMap:get(f:getType()) ~= nil then table.insert(validFoods, f) end
                end
            end
        end
        if #validFoods == 0 then
            log("VALID: recipe item lists empty/unavailable, fallback to all")
            for _, f in ipairs(collected.foods) do
                table.insert(validFoods, f)
            end
        end
    else
        local validList = recipe:getItemsCanBeUse(player, cookware, containers)
        for i = 0, validList:size() - 1 do
            validIds[validList:get(i)] = true
        end
        for _, f in ipairs(collected.foods) do
            if validIds[f] then table.insert(validFoods, f) end
        end
    end
    log(string.format("VALID: foods=%d spices=%d (recipe allows frozen=%s)",
        #validFoods, #validSpices, tostring(recipe:isAllowFrozenItem())))
    -- диагностика уникальных типов
    local uniqueTypes = {}
    for _, f in ipairs(validFoods) do
        uniqueTypes[f:getFullType()] = true
    end
    local uniqCount = 0
    for _ in pairs(uniqueTypes) do uniqCount = uniqCount + 1 end
    log(string.format("  valid unique types: %d", uniqCount))

    if #validFoods == 0 then return nil, "NotEnough" end

    local direction = FoodLogic.decideDirection(player:getNutrition(), settings)
    -- специи: до 4 = 2 базовых (соль/перец) + 2 по направлению
    local picked = FoodLogic.pickIngredients(validFoods, validSpices, direction, recipe:getMaxItems(), 4)

    for _, f in ipairs(picked.items) do
        local tag = f:isFrozen() and " [frozen]" or ""
        log(string.format("  pick: %s (%.0f cal)%s",
            tostring(f:getDisplayName()), f:getCalories(), tag))
    end
    for _, s in ipairs(picked.spices) do
        log("  spice: " .. tostring(s:getDisplayName()))
    end

    -- точный прогноз сытости и калорий: симуляция addItem на клонах.
    -- addItem кладёт результат в инвентарь персонажа, поэтому чистим его после.
    local inv = player:getInventory()
    local before = {}
    local itemsBefore = inv:getItems()
    for i = 0, itemsBefore:size() - 1 do
        before[itemsBefore:get(i)] = true
    end

    local predictedHunger = nil
    local predictedCalories = nil
    local okSim, simHunger, simCal, simItems = pcall(function()
        local resultPot = cookware:createCloneItem()
        -- для супов/рагу наполняем клон водой, иначе addItem/валидация не работают
        if dish.needsWater then
            local fc = resultPot:getFluidContainer()
            if fc then fc:adjustSpecificFluidAmount(Fluid.Water, fc:getCapacity()) end
        end
        -- добавляем выбранные ингредиенты; фиксируем только реально добавленные
        local acceptedItems = {}
        for _, f in ipairs(picked.items) do
            local before = resultPot:haveExtraItems() and resultPot:getExtraItems():size() or 0
            local c = f:createCloneItem()
            local newPot = recipe:addItem(resultPot, c, player)
            resultPot = newPot or resultPot
            local after = resultPot:haveExtraItems() and resultPot:getExtraItems():size() or 0
            if after > before then
                table.insert(acceptedItems, f)
            end
        end
        for _, s in ipairs(picked.spices) do
            local c = s:createCloneItem()
            resultPot = recipe:addItem(resultPot, c, player) or resultPot
        end
        return -resultPot:getBaseHunger() * 100, resultPot:getCalories(), acceptedItems
    end)

    -- чистка: удаляем всё, что симуляция добавила в инвентарь
    local spawned = {}
    local itemsAfter = inv:getItems()
    for i = 0, itemsAfter:size() - 1 do
        local it = itemsAfter:get(i)
        if not before[it] then
            table.insert(spawned, it)
        end
    end
    for _, it in ipairs(spawned) do
        inv:Remove(it)
        log("  cleaned spawn: " .. tostring(it:getFullType()))
    end

    if okSim and simHunger and simHunger > 0 then
        predictedHunger = math.floor(simHunger + 0.5)
        predictedCalories = math.floor((simCal or 0) + 0.5)
        log(string.format("  predicted (sim): hunger=%s cal=%s", tostring(predictedHunger), tostring(predictedCalories)))
    else
        log("  hunger sim failed: " .. tostring(simHunger))
    end

    return {
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

-- Текущее блюдо мода — строго по ссылке Cook.pot. НЕ ищем по haveExtraItems,
-- иначе при готовом блюде в инвентаре (прошлый прогон) вернём чужое.
local function findPotInInventory(player)
    return Cook.pot
end

-- Блюдо на поверхности плиты (предмет мог замениться на ResultItem при готовке)
local function findOnStove()
    if not Cook.stove then return nil end
    local cont = Cook.stove:getContainer()
    if not cont then return nil end
    local items = cont:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it == Cook.pot or it:haveExtraItems() or it:getFullType() == Cook.resultType then
            return it
        end
    end
    return nil
end

-- «Тик» цепочки: мгновенный walk на свой квадрат с setOnComplete — проверенный
-- ванильный механизм продолжения очереди (свой StepAction без анимации не завершался)
local function makeTick(player, callback)
    local walk = ISWalkToTimedAction:new(player, player:getCurrentSquare())
    walk:setOnComplete(function()
        callback()
    end)
    return walk
end

-- Ходьба к СОСЕДНЕМУ свободному квадрату (мебель/плита/раковина занимают свой квадрат,
-- walk прямо на него висит вечно)
local function addWalk(player, sq, logName)
    if sq == nil then
        log("  WARN no square to walk: " .. logName)
        return
    end
    local adjacent = AdjacentFreeTileFinder.Find(sq, player)
    if adjacent == nil then
        log("  WARN no adjacent square: " .. logName)
        return
    end
    if adjacent == player:getCurrentSquare() then
        log("  no walk needed: " .. logName)
        return
    end
    log(string.format("  walk to %d,%d (%s)", adjacent:getX(), adjacent:getY(), logName))
    ISTimedActionQueue.add(ISWalkToTimedAction:new(player, adjacent))
end

local function stepTake(player, item, next)
    local inv = player:getInventory()
    local src = item:getContainer()
    log(string.format("STEP take: %s src=%s",
        tostring(item:getDisplayName()), src and tostring(src:getType()) or "nil"))
    if src == inv then log("  already in inventory") next() return end
    local sq = nil
    if src and src:getSourceGrid() then sq = src:getSourceGrid() end
    if not sq and item:getSquare() then sq = item:getSquare() end
    addWalk(player, sq, "take " .. tostring(item:getDisplayName()))
    local transfer = ISInventoryTransferAction:new(player, item, src, inv, nil)
    transfer:setOnComplete(function()
        log("  taken")
        next()
    end)
    ISTimedActionQueue.add(transfer)
end

local function stepWater(player, cookware, sink, next)
    log("STEP water: fill from sink")
    addWalk(player, sink:getSquare(), "sink")
    ISTimedActionQueue.add(ISTakeWaterAction:new(player, cookware, sink, sink:isTaintedWater()))
    ISTimedActionQueue.add(makeTick(player, function()
        log("  water filled")
        next()
    end))
end

local function stepAdd(player, recipe, usedItem, next, originalSrc)
    log("STEP add: " .. tostring(usedItem:getDisplayName()))
    local inv = player:getInventory()
    local src = usedItem:getContainer()
    -- сохраняем исходный контейнер между рекурсией (после переноса src == inv)
    originalSrc = originalSrc or src
    if src ~= inv then
        -- сначала перенести предмет в инвентарь (isItemUsableInRecipe требует доступность)
        local sq = nil
        if src and src:getSourceGrid() then sq = src:getSourceGrid() end
        if not sq and usedItem:getSquare() then sq = usedItem:getSquare() end
        addWalk(player, sq, "take " .. tostring(usedItem:getDisplayName()))
        local transfer = ISInventoryTransferAction:new(player, usedItem, src, inv, nil)
        transfer:setOnComplete(function()
            log("  ingredient taken")
            stepAdd(player, recipe, usedItem, next, originalSrc)
        end)
        ISTimedActionQueue.add(transfer)
        return
    end
    local baseItem = findPotInInventory(player)
    -- диагностика валидации
    log(string.format("  VALIDATE: base=%s extraItems=%s baseCont=%s usedCont=%s",
        tostring(baseItem and baseItem:getFullType()),
        tostring(baseItem and baseItem:haveExtraItems()),
        tostring(baseItem and baseItem:getContainer() and baseItem:getContainer():getType()),
        tostring(usedItem:getContainer() and usedItem:getContainer():getType())))
    local ok, usable = pcall(function()
        return recipe:isItemUsableInRecipe(player, baseItem, usedItem:getID())
    end)
    if not ok or not usable then
        log("  SKIP not usable: " .. tostring(usedItem:getFullType()) .. " (pcall=" .. tostring(ok) .. ")")
        -- вернуть неиспользованный предмет обратно, откуда взяли
        if originalSrc and originalSrc ~= inv then
            local back = ISInventoryTransferAction:new(player, usedItem, inv, originalSrc, nil)
            back:setOnComplete(function() next() end)
            ISTimedActionQueue.add(back)
            return
        end
        next()
        return
    end
    log("  validated, direct add")
    -- прямое добавление (ванильное ISAddItemInRecipe в авто-контексте не завершается)
    local okAdd, newPot = pcall(function()
        return recipe:addItem(baseItem, usedItem, player)
    end)
    if not okAdd then
        log("  ADD FAIL: " .. tostring(newPot))
        if originalSrc and originalSrc ~= inv then
            local back = ISInventoryTransferAction:new(player, usedItem, inv, originalSrc, nil)
            back:setOnComplete(function() next() end)
            ISTimedActionQueue.add(back)
            return
        end
        next()
        return
    end
    Cook.pot = newPot or baseItem
    -- addItem оставляет блюдо в detached-контейнере "none" — гарантируем инвентарь
    if Cook.pot:getContainer() ~= inv then
        local c = Cook.pot:getContainer()
        if c then c:Remove(Cook.pot) end
        inv:AddItem(Cook.pot)
        log("  dish moved to player inventory")
    end
    ISAddItemInRecipe.checkName(Cook.pot, recipe)
    ISAddItemInRecipe.checkTemperature(Cook.pot, usedItem, recipe)
    Cook.addedCount = Cook.addedCount + 1
    log(string.format("  HUNGER: itemBase=%.2f potBase=%.2f potHunger=%.2f",
        usedItem:getBaseHunger(), Cook.pot:getBaseHunger(), Cook.pot:getHungerChange()))
    log("  added, pot=" .. tostring(Cook.pot and Cook.pot:getName()))
    -- ванильный звук добавления + пауза, чтобы чувствовался процесс
    local soundName = recipe:getAddIngredientSound() or "AddItemInRecipe"
    player:getEmitter():playSoundImpl(soundName, nil)
    -- любой остаток (рис/специи с uses и т.п.), что не израсходован блюдом, возвращаем на место
    if usedItem:getContainer() == inv and originalSrc ~= inv then
        log("  returning leftover " .. tostring(usedItem:getFullType()) .. " to " .. tostring(originalSrc:getType()))
        local back = ISInventoryTransferAction:new(player, usedItem, inv, originalSrc, nil)
        back:setOnComplete(function() delayedNext(500, next) end)
        ISTimedActionQueue.add(back)
        return
    end
    delayedNext(500, next)
end

local function stepToStove(player, stove, next)
    log("STEP to stove")
    local inv = player:getInventory()
    local baseItem = Cook.pot

    if not baseItem or not baseItem:getContainer() then
        log("  FAIL: dish not found anywhere, aborting")
        Cook.fail(player, "NoCookware")
        return
    end

    -- если блюдо в другом контейнере (тумбочка и т.п.) — сначала вернуть в инвентарь
    local cont = baseItem:getContainer()
    if cont ~= inv then
        log("  dish in " .. tostring(cont:getType()) .. ", retrieving to inventory")
        local sq = cont:getSourceGrid() or baseItem:getSquare()
        addWalk(player, sq, "retrieve dish")
        local takeBack = ISInventoryTransferAction:new(player, baseItem, cont, inv, nil)
        takeBack:setOnComplete(function()
            log("  dish retrieved")
            stepToStove(player, stove, next)
        end)
        ISTimedActionQueue.add(takeBack)
        return
    end

    log("  pot=" .. tostring(baseItem:getFullType()) .. " cont=" .. tostring(baseItem:getContainer():getType()))
    addWalk(player, stove:getSquare(), "stove")
    local transfer = ISInventoryTransferAction:new(player, baseItem, player:getInventory(), stove:getContainer(), nil)
    transfer:setOnComplete(function()
        log("  pot on stove")
        next()
    end)
    ISTimedActionQueue.add(transfer)
end

-- Включение плиты + штраф заморозки; дальше поллинг готовности в onTick
local function stepHeat(player, stove, recipe, settings, next)
    ISTimedActionQueue.add(makeTick(player, function()
        -- не варим пустую посуду: если ничего не добавилось — ошибка
        if Cook.addedCount == 0 then
            log("  FAIL: no ingredients were added, aborting")
            Cook.fail(player, "NotEnough")
            return
        end
        if not stove:Activated() then
            stove:Toggle()
            Cook.weTurnedStoveOn = stove:Activated()
        end
        if not stove:Activated() then
            Cook.fail(player, "NoPower")
            return
        end
        log("stove ON, cooking...")

        -- штраф времени готовки за замороженные ингредиенты:
        -- готовность наступает при cookingTime > minutesToCook, поэтому увеличиваем порог
        local pot = findOnStove()
        if pot and Cook.frozenCount > 0 then
            local base = pot:getMinutesToCook()
            pot:setMinutesToCook(FoodLogic.frozenPenaltyTime(base, Cook.frozenPenalty, Cook.frozenCount))
            log(string.format("frozen penalty: minutesToCook %.0f -> %.0f", base, pot:getMinutesToCook()))
        end

        Cook.stove = stove
        Cook.resultType = recipe:getResultItem()
        Cook.heatStart = getTimestampMs()
        Cook.debugFast = settings.debugFast
        Cook.cooking = true
        -- next() не вызываем: завершение — в onTick по готовности
    end))
end

function Cook.start(player, dishKey, plan)
    if Cook.active then
        -- прошлый цикл прервался, не сбросив флаг — чистим и стартуем заново
        log("COOK START: resetting stale active state")
        Cook.active = false
        Cook.cooking = false
        Cook.delayNext = nil
        Cook.delayUntil = nil
    end
    log(string.format("COOK START: dish=%s plan=%s", tostring(dishKey), tostring(plan ~= nil)))
    Cook.active = true
    Cook.pot = nil
    Cook.stove = nil
    Cook.weTurnedStoveOn = false

    if not plan then
        plan, failKey = Cook.plan(player, dishKey)
        if not plan then Cook.fail(player, failKey) return end
    end

    local settings = plan.settings
    local scan = plan.scan
    local recipe = plan.recipe
    local picked = plan.picked
    local cookware = plan.cookware

    log(string.format("recipe: %s maxItems=%d cookable=%s",
        recipe:getUntranslatedName(), recipe:getMaxItems(), tostring(recipe:isCookable())))
    log(string.format("START: dish=%s direction=%s foods=%d spices=%d frozen=%d",
        plan.dishKey, plan.direction, #picked.items, #picked.spices, picked.frozenCount))

    if picked.frozenCount > 0 and not recipe:isAllowFrozenItem() then
        recipe:setAllowFrozenItem(true)
        log("recipe: frozen items allowed by mod")
    end

    Cook.frozenCount = picked.frozenCount
    Cook.frozenPenalty = settings.frozenPenalty

    Cook.pot = cookware

    local steps = {}
    table.insert(steps, function(next) stepTake(player, cookware, next) end)
    if plan.dish.needsWater then
        table.insert(steps, function(next) stepWater(player, cookware, scan.sink, next) end)
    end
    for _, f in ipairs(picked.items) do
        table.insert(steps, function(next) stepAdd(player, recipe, f, next) end)
    end
    for _, s in ipairs(picked.spices) do
        table.insert(steps, function(next) stepAdd(player, recipe, s, next) end)
    end
    table.insert(steps, function(next) stepToStove(player, scan.stove, next) end)
    table.insert(steps, function(next) stepHeat(player, scan.stove, recipe, settings, next) end)

    local function run(idx)
        if idx > #steps then
            -- завершение произойдёт в onTick по готовности
            return
        end
        steps[idx](function() run(idx + 1) end)
    end
    run(1)
end

-- Поллинг готовности + отмена при угрозе
local function onTick()
    if not Cook.active then return end
    local player = getPlayer()
    if not player then return end

    -- пауза между шагами цепочки
    if Cook.delayNext and getTimestampMs() >= Cook.delayUntil then
        local n = Cook.delayNext
        Cook.delayNext = nil
        Cook.delayUntil = nil
        n()
    end

    -- зомби в радиусе 10 тайлов на том же этаже -> отмена цикла
    local zs = player:getCell():getZombieList()
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    for i = 0, zs:size() - 1 do
        local z = zs:get(i)
        if z:getZ() == pz then
            local dx, dy = z:getX() - px, z:getY() - py
            if math.sqrt(dx * dx + dy * dy) < 10 then
                if Cook.weTurnedStoveOn and Cook.stove and Cook.stove:Activated() then
                    Cook.stove:Toggle()
                end
                ISTimedActionQueue.clear(player)
                Cook.active = false
                Cook.cooking = false
                log("cancelled: zombie nearby")
                player:Say(getText("UI_CookItForMe_CancelledThreat"))
                return
            end
        end
    end

    if not Cook.cooking then return end

    -- debug-ускорение: форсируем готовность через 5 секунд нагрева
    if Cook.debugFast and getTimestampMs() - Cook.heatStart > 5000 then
        local pot = findOnStove()
        if pot then pot:setCooked(true) end
    end

    local pot = findOnStove()
    if not pot then
        -- таймаут: плита не готовит / блюда нет на плите
        if getTimestampMs() - Cook.heatStart > 600000 then
            Cook.cooking = false
            Cook.fail(player, "NoPower")
        end
        return
    end

    local cooked = pot:isCooked() or pot:getFullType() == Cook.resultType
    local burnt = pot:isBurnt()
    if not cooked and not burnt then return end

    -- при готовности сразу выключаем плиту и забираем блюдо
    Cook.cooking = false
    log(string.format("COOK TIME: %.0fs (frozen=%d)",
        (getTimestampMs() - Cook.heatStart) / 1000, Cook.frozenCount or 0))
    if Cook.stove and Cook.stove:Activated() then
        Cook.stove:Toggle()
        log("stove OFF")
    end

    ISTimedActionQueue.add(ISInventoryTransferAction:new(player, pot, pot:getContainer(), player:getInventory(), nil))
    ISTimedActionQueue.add(makeTick(player, function()
        local name = pot:getName()
        local hungerPts = math.floor(-pot:getBaseHunger() * 100 + 0.5)
        log(string.format("DONE HUNGER: potBase=%.2f potHunger=%.2f", pot:getBaseHunger(), pot:getHungerChange()))
        log("DONE: " .. tostring(name) .. " cooked=" .. tostring(pot:isCooked()) .. " burnt=" .. tostring(pot:isBurnt()))
        if burnt then
            player:Say(getText("UI_CookItForMe_Burnt") .. ": " .. name)
        else
            player:Say(getText("UI_CookItForMe_Done") .. ": " .. name .. " (" .. getText("UI_CookItForMe_PlanHunger", tostring(hungerPts)) .. ")")
        end
        Cook.active = false
    end))
end

-- Регистрация один раз: reloadLua() не должен плодить тикеры
if not CookItForMe.Cook.onTickRegistered then
    CookItForMe.Cook.onTickRegistered = true
    Events.OnTick.Add(onTick)
end

return Cook
