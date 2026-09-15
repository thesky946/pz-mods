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
function FoodLogic.pickIngredients(foods, spices, direction, maxItems, maxSpices, score)
    local sorted = {}
    for _, f in ipairs(foods) do
        table.insert(sorted, f)
    end
    local sortedSpices = {}
    for _, s in ipairs(spices) do
        table.insert(sortedSpices, s)
    end
    local function compare(a, b)
        if score then
            local av, bv = score(a), score(b)
            if av ~= bv then
                if direction == "min" then return av < bv end
                return av > bv
            end
        elseif compareBy(a, b, direction) ~= compareBy(b, a, direction) then
            return compareBy(a, b, direction)
        end
        return a:getFullType() < b:getFullType()
    end
    table.sort(sorted, compare)
    table.sort(sortedSpices, compare)

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
        if #pickedSpices >= math.min(2, maxSpices) then break end
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
function FoodLogic.frozenPenaltyTime(baseTime, penalty, frozenCount, ingredientCount)
    -- Penalize the frozen share, not each ingredient cumulatively. Spices do not count.
    local fraction = math.min(1, math.max(0, frozenCount) / math.max(1, ingredientCount or frozenCount))
    return baseTime * (1 + penalty * fraction)
end

return FoodLogic
