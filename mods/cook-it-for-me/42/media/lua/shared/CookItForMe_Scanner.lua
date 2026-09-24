-- Cook It For Me: сканер окружения и сбор еды (singleplayer, B42)

local Scanner = {}
local Catalog = require "CookItForMe_Dishes"

-- Посуда для блюд на плите (уточнено по media/scripts B42):
-- суп/рагу: Pot, PotForged; жаркое: Pan, PanForged, GridlePan; овощное жаркое: RoastingPan.
-- Saucepan в B42 для супа не подходит (только паста/рис через WaterSaucepan*).

local function isSinkObject(o)
    if instanceof(o, "IsoWorldInventoryObject") then return false end
    local spriteName = o:getSpriteName()
    if spriteName and spriteName:match("^fixtures_sinks_01_%d+$") then return true end
    -- Include plumbed/custom fixtures too; water availability is checked by the planner.
    return o:getUsesExternalWaterSource() or o:hasExternalWaterSource()
end

-- scanAround(player, radius, includeStoves) -> { stove, sink, containers = {ItemContainer...}, floorItems = {InventoryItem...} }
-- radius == 0: 3x3 вокруг игрока + canReachTo, как у proximity inventory в ванили.
function Scanner.scanAround(player, radius, includeStoves)
    includeStoves = includeStoves ~= false
    radius = math.max(1, math.min(30, math.floor(tonumber(radius) or 1)))
    local cx, cy, cz = math.floor(player:getX()), math.floor(player:getY()), player:getZ()
    local cell = getCell()
    local playerSquare = player:getCurrentSquare()
    local result = { stove = nil, sink = nil, containers = {}, floorItems = {}, stoves = {}, sinks = {} }

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

    -- Flood through walkable tiles; inspect furniture only from a reachable tile.
    -- Runtime pathfinding still validates doors/obstacles that change after preview.
    local reachable, frontier = {}, { playerSquare }
    if playerSquare then reachable[playerSquare] = true end
    local head = 1
    while head <= #frontier do
        local from = frontier[head]; head = head + 1
        for dy = -1, 1 do
            for dx = -1, 1 do
                local x, y = from:getX() + dx, from:getY() + dy
                if math.abs(x - cx) <= radius and math.abs(y - cy) <= radius then
                    local next = cell:getGridSquare(x, y, cz)
                    if next and not reachable[next] and next:isFree(false) and from:canReachTo(next) then
                        reachable[next] = true; frontier[#frontier + 1] = next
                    end
                end
            end
        end
    end
    local accessible = {}
    for _, sq in ipairs(squares) do
        local canAccess = reachable[sq]
        for dy = -1, 1 do
            for dx = -1, 1 do
                local neighbor = cell:getGridSquare(sq:getX() + dx, sq:getY() + dy, cz)
                if neighbor and reachable[neighbor] and neighbor:canReachTo(sq) then canAccess = true end
            end
        end
        if canAccess then accessible[#accessible + 1] = sq end
    end
    squares = accessible
    table.sort(squares, function(a, b)
        local ad = (a:getX() - cx)^2 + (a:getY() - cy)^2
        local bd = (b:getX() - cx)^2 + (b:getY() - cy)^2
        return ad < bd
    end)
    for _, sq in ipairs(squares) do
        local objs = sq:getObjects()
        for i = 0, objs:size() - 1 do
            local o = objs:get(i)
            if instanceof(o, "IsoStove") then
                if includeStoves and not o:isMicrowave() then
                    if not o:isBroken() and o:getContainer() and o:getContainer():isPowered()
                        and AdjacentFreeTileFinder.Find(sq, player) then
                        result.stoves[#result.stoves + 1] = o
                        if not result.stove then result.stove = o end
                    end
                end
            elseif isSinkObject(o) then
                -- Detect the fixture independently of its current water state. Planner
                -- reports NoWater when hasFluid() is false; that must not look like NoSink.
                if AdjacentFreeTileFinder.Find(sq, player) then
                    result.sinks[#result.sinks + 1] = o
                    if not result.sink then result.sink = o end
                end
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
function Scanner.collectFood(player, scan, includeCooked)
    local out = { foods = {}, spices = {}, cookware = {} }

    local seenItems, seenContainers = {}, {}
    local addItem
    local function visit(container)
        if not container or seenContainers[container] then return end
        seenContainers[container] = true
        local items = container:getItems()
        for i = 0, items:size() - 1 do addItem(items:get(i)) end
    end
    addItem = function(item)
        if item == nil or seenItems[item] then return end
        seenItems[item] = true
        if item.IsInventoryContainer and item:IsInventoryContainer() then
            visit(item:getInventory()); return
        end
        if not instanceof(item, "Food") then
            if Catalog.isCookware(item:getFullType()) then
                table.insert(out.cookware, item)
            end
            return
        end
        if item:isRotten() or item:isBurnt() or (item:isCooked() and not includeCooked) then return end
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

    for _, cont in ipairs(scan.containers) do visit(cont) end
    for _, item in ipairs(scan.floorItems) do addItem(item) end
    visit(player:getInventory())
    return out
end

return Scanner
