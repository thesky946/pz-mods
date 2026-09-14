-- Cook It For Me: сканер окружения и сбор еды (singleplayer, B42)

local Scanner = {}

-- Посуда для блюд на плите (уточнено по media/scripts B42):
-- суп/рагу: Pot, PotForged; жаркое: Pan, PanForged, GridlePan; овощное жаркое: RoastingPan.
-- Saucepan в B42 для супа не подходит (только паста/рис через WaterSaucepan*).
local COOKWARE = {
    ["Base.Pot"] = true,
    ["Base.PotForged"] = true,
    ["Base.Pan"] = true,
    ["Base.PanForged"] = true,
    ["Base.GridlePan"] = true,
    ["Base.RoastingPan"] = true,
}

local function isSinkObject(o)
    if instanceof(o, "IsoWorldInventoryObject") then return false end
    -- IsoObject в B42 не имеет isWaterSource(); раковина = внешний водопровод
    return o:getUsesExternalWaterSource() or o:hasExternalWaterSource()
end

-- scanAround(player, radius) -> { stove, sink, containers = {ItemContainer...}, floorItems = {InventoryItem...} }
-- radius == 0: 3x3 вокруг игрока + canReachTo, как у proximity inventory в ванили.
function Scanner.scanAround(player, radius)
    local cx, cy, cz = math.floor(player:getX()), math.floor(player:getY()), player:getZ()
    local cell = getCell()
    local playerSquare = player:getCurrentSquare()
    local result = { stove = nil, sink = nil, containers = {}, floorItems = {} }

    local squares = {}
    for dy = -radius, radius do
        for dx = -radius, radius do
            local sq = cell:getGridSquare(cx + dx, cy + dy, cz)
            if sq then
                -- не сквозь стены (проверяем только ближний 3x3, как ваниль)
                if math.abs(dx) <= 1 and math.abs(dy) <= 1 and playerSquare and sq ~= playerSquare then
                    if not playerSquare:canReachTo(sq) then
                        sq = nil
                    end
                end
                if sq then table.insert(squares, sq) end
            end
        end
    end

    for _, sq in ipairs(squares) do
        local objs = sq:getObjects()
        for i = 0, objs:size() - 1 do
            local o = objs:get(i)
            if instanceof(o, "IsoStove") and not o:isMicrowave() then
                if not result.stove then result.stove = o end
            elseif isSinkObject(o) then
                if not result.sink then result.sink = o end
            elseif o:getContainerCount() > 0 and not instanceof(o, "IsoDeadBody") then
                -- объект может иметь несколько контейнеров (холодильник = fridge + freezer)
                for c = 0, o:getContainerCount() - 1 do
                    local cont = o:getContainerByIndex(c)
                    if cont then table.insert(result.containers, cont) end
                end
            end
        end

        local static = sq:getStaticMovingObjects()
        for i = 0, static:size() - 1 do
            local o = static:get(i)
            if o:getContainerCount() > 0 then
                for c = 0, o:getContainerCount() - 1 do
                    local cont = o:getContainerByIndex(c)
                    if cont then table.insert(result.containers, cont) end
                end
            end
        end

        local wobs = sq:getWorldObjects()
        for i = 0, wobs:size() - 1 do
            local o = wobs:get(i)
            local item = o:getItem()
            if item then
                if item:IsInventoryContainer() then
                    table.insert(result.containers, item:getInventory())
                else
                    table.insert(result.floorItems, item)
                end
            end
        end
    end

    return result
end

-- Сбор еды: из контейнеров скана + пола + главного инвентаря игрока.
-- Возвращает { foods = {}, spices = {}, cookware = {} } (реальные InventoryItem).
-- Исключаются: протухшее, уже приготовленное, сгоревшее; не-еда
-- (антибиотики/сигареты/мусор в B42 — тоже класс Food, отсекаются ванильным isItemFood).
-- Замороженные допускаются.
function Scanner.collectFood(player, scan)
    local out = { foods = {}, spices = {}, cookware = {} }

    local function addItem(item)
        if item == nil then return end
        if not instanceof(item, "Food") then
            if COOKWARE[item:getFullType()] then
                table.insert(out.cookware, item)
            end
            return
        end
        if item:isRotten() or item:isCooked() or item:isBurnt() then return end
        if item:isSpice() then
            table.insert(out.spices, item)
            return
        end
        if not isItemFood(item:getFullType()) then return end
        -- готовые блюда (составные) не берём как ингредиенты
        if item:haveExtraItems() then return end
        -- getBaseHunger() у еды отрицательный (снижает голод); у сигарет/лекарств 0
        if item:getBaseHunger() >= 0 then return end
        table.insert(out.foods, item)
    end

    for _, cont in ipairs(scan.containers) do
        local items = cont:getItems()
        for i = 0, items:size() - 1 do
            addItem(items:get(i))
        end
    end

    for _, item in ipairs(scan.floorItems) do
        addItem(item)
    end

    local invItems = player:getInventory():getItems()
    for i = 0, invItems:size() - 1 do
        addItem(invItems:get(i))
    end

    return out
end

return Scanner
