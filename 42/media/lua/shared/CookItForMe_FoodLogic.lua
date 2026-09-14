-- Cook It For Me: чистые функции логики еды (без зависимостей от PZ API — тестируются офлайн)

local FoodLogic = {}

-- Направление готовки: settings.strategy = "max" | "min" | "hunger"
function FoodLogic.decideDirection(nutrition, settings)
    return settings.strategy
end

-- Компаратор сортировки: "max"/"min" по калориям, "hunger" по сытности.
-- getBaseHunger() у еды отрицательный (скриптовый HungerChange): чем сытнее, тем ниже -> самые низкие первыми.
local function compareBy(a, b, direction)
    if direction == "hunger" then
        return a:getBaseHunger() < b:getBaseHunger()
    end
    if direction == "max" then
        return a:getCalories() > b:getCalories()
    end
    return a:getCalories() < b:getCalories()
end

-- Жадный выбор ингредиентов.
-- foods/spices: массивы объектов с getFullType(), getCalories(), getHungerChange(), isFrozen()
-- Правила: до maxItems штук, не более 2 повторов одного fullType.
-- Специи (до maxSpices, по 1 каждого fullType):
--   1) базовые (соль/перец/травы, <10 ккал) — до 2, всегда;
--   2) по направлению (max - калорийные, min - низкокалорийные, hunger - сытные) — остаток.
-- Замороженные допустимы.
-- Возвращает { items = {...}, spices = {...}, frozenCount = n }
function FoodLogic.pickIngredients(foods, spices, direction, maxItems, maxSpices)
    local sorted = {}
    for _, f in ipairs(foods) do
        table.insert(sorted, f)
    end
    local sortedSpices = {}
    for _, s in ipairs(spices) do
        table.insert(sortedSpices, s)
    end
    table.sort(sorted, function(a, b) return compareBy(a, b, direction) end)
    table.sort(sortedSpices, function(a, b) return compareBy(a, b, direction) end)

    local items, counts, frozenCount = {}, {}, 0
    for _, f in ipairs(sorted) do
        if #items >= maxItems then break end
        local ft = f:getFullType()
        if (counts[ft] or 0) < 2 then
            table.insert(items, f)
            counts[ft] = (counts[ft] or 0) + 1
            if f:isFrozen() then frozenCount = frozenCount + 1 end
        end
    end

    maxSpices = maxSpices or math.huge
    local pickedSpices, seenSpice = {}, {}
    -- 1) базовые: до 2
    for _, s in ipairs(sortedSpices) do
        if #pickedSpices >= maxSpices then break end
        local ft = s:getFullType()
        if not seenSpice[ft] and s:getCalories() < 10 then
            seenSpice[ft] = true
            table.insert(pickedSpices, s)
        end
    end
    -- 2) по направлению: остаток
    for _, s in ipairs(sortedSpices) do
        if #pickedSpices >= maxSpices then break end
        local ft = s:getFullType()
        if not seenSpice[ft] and s:getCalories() >= 10 then
            seenSpice[ft] = true
            table.insert(pickedSpices, s)
        end
    end

    return { items = items, spices = pickedSpices, frozenCount = frozenCount }
end

-- Штраф времени готовки за замороженные ингредиенты
function FoodLogic.frozenPenaltyTime(baseTime, penalty, frozenCount)
    return baseTime * (1 + penalty * frozenCount)
end

return FoodLogic
