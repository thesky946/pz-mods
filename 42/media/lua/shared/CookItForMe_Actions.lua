-- Game actions for one session. Keep PZ workarounds at this boundary.
require "CookItForMe_Shared"
if not ISGrabItemAction then require "TimedActions/ISGrabItemAction" end
local FoodLogic = require "CookItForMe_FoodLogic"
local log = CookItForMe.log
local Actions = {}
Actions.REVISION = "reliable-actions-4"

-- Vanilla uses this predicate only to arm its end-of-action speed reset.
-- Exclude our exact actions, not all activity while cooking. Walking separately limits unsupported speeds. Never change the player's auto-reset option: other actions/threats keep control.
local function speedPolicy()
    local queue = ISTimedActionQueue
    if queue.cookItForMeSpeedPolicy then return queue.cookItForMeSpeedPolicy end
    if type(queue.isPlayerDoingAction) ~= "function" then return nil end
    local policy = { actions = setmetatable({}, { __mode = "k" }) }
    local original = queue.isPlayerDoingAction
    queue.isPlayerDoingAction = function(player)
        if not original(player) then return false end
        local running = player:getCharacterActions()
        if running:size() == 0 then return true end -- climbing, opening doors, etc.
        for i = 0, running:size() - 1 do
            local owned = false
            for action in pairs(policy.actions) do
                if action.action == running:get(i) then owned = true break end
            end
            if not owned then return true end
        end
        return false
    end
    queue.cookItForMeSpeedPolicy = policy
    return policy
end

function Actions.enqueue(action)
    local policy = speedPolicy()
    if policy then policy.actions[action] = true end
    return ISTimedActionQueue.add(action)
end

function Actions.new(session, fail)
    local function track(action, callback, stage)
        action.cookItForMeSession = session
        local entry = { action = action, elapsed = 0, missing = 0 }
        session.pending[action] = entry
        session.stage = stage or session.stage
        local itemName = action.item and action.item.getFullType and action.item:getFullType() or ""
        CookItForMe.diagnostic("action: " .. tostring(session.stage) .. " " .. itemName)
        local complete = session:guard(function()
            session.pending[action] = nil
            callback()
        end)
        local nativeCallback = action.setOnComplete ~= nil
        if nativeCallback then
            action:setOnComplete(complete)
        end
        local perform = action.perform
        action.perform = function(self)
            local ok, err = pcall(perform, self)
            if not ok then session.onError(err); return end
            if not nativeCallback then complete() end
        end
        local stop = action.stop
        action.stop = function(self)
            local saved = {}
            if self.preserveOtherActions then
                local queue = ISTimedActionQueue.getTimedActionQueue(session.player).queue
                for i = #queue, 1, -1 do
                    if queue[i] ~= self and queue[i].cookItForMeSession ~= session then
                        table.insert(saved, 1, table.remove(queue, i))
                    end
                end
            end
            if stop then pcall(stop, self) end
            if session.active then fail("ActionInterrupted") end
            for _, queued in ipairs(saved) do ISTimedActionQueue.add(queued) end
        end
        local forceCancel = action.forceCancel
        action.forceCancel = function(self)
            if forceCancel then pcall(forceCancel, self) end
            -- Queue mutation may still be in progress. The monitor handles removal.
            entry.cancelled = true
        end
        return action
    end

    local function enqueue(action)
        if not session.active then return end
        Actions.enqueue(action)
    end

    local function walkTo(player, square, callback)
        if not square then callback(); return end -- character inventory
        local adjacent = AdjacentFreeTileFinder.Find(square, player)
        if not adjacent then fail("NoPath"); return end
        if adjacent == player:getCurrentSquare() then callback(); return end
        local action = ISWalkToTimedAction:new(player, adjacent)
        local valid = action.isValid
        if valid then
            action.isValid = function(self)
                if not player:getVehicle() and getGameSpeed() > 2 then
                    log("walk: reducing game speed to 2 for vanilla pathfinding")
                    setGameSpeed(2)
                end
                return valid(self)
            end
        end
        enqueue(track(action, callback, "walking"))
    end

    local function worldItem(item)
        return item.getWorldItem and item:getWorldItem() or nil
    end

    local function sourceOf(item)
        local world = worldItem(item)
        if world and world:getSquare() then
            return { world = world, square = world:getSquare() }
        end
        local container = item:getContainer()
        if not container then return nil end
        local outer = container.getOutermostContainer and container:getOutermostContainer() or container
        local square = outer:getSourceGrid()
        if not square and outer.getContainingItem then
            local bag = outer:getContainingItem()
            local world = bag and worldItem(bag)
            square = world and world:getSquare() or nil
        end
        return { container = container, square = square }
    end

    local function move(player, item, destination, callback)
        local src = sourceOf(item)
        if not src then fail("ItemMissing"); return end
        if src.container == destination then callback(); return end
        local square = destination == player:getInventory() and src.square or destination:getSourceGrid()
        walkTo(player, square, function()
            if not destination:hasRoomFor(player, item) then fail("NoRoom"); return end
            local action
            if src.world then
                if not src.world:getSquare() then fail("ItemMissing"); return end
                action = ISGrabItemAction:new(player, src.world, 50)
            else
                if item:getContainer() ~= src.container or not src.container:contains(item) then
                    fail("ItemMissing"); return
                end
                action = ISInventoryTransferAction:new(player, item, src.container, destination, nil)
            end
            enqueue(track(action, function()
                local arrived = item:getContainer() == destination and destination:contains(item)
                if destination:getType() == "floor" then
                    local world = worldItem(item)
                    arrived = world and world:getSquare() == destination:getSourceGrid()
                end
                if not arrived then fail("TransferFailed"); return end
                callback()
            end, "transferring"))
        end)
    end

    local function take(player, item, callback)
        move(player, item, player:getInventory(), callback)
    end

    local function water(player, cookware, sink, callback)
        walkTo(player, sink:getSquare(), function()
            if not sink:hasFluid() then fail("NoWater"); return end
            local action = ISTakeWaterAction:new(player, cookware, sink, sink:isTaintedWater())
            enqueue(track(action, function()
                local fluid = cookware:getFluidContainer()
                if not fluid or fluid:getAmount() / fluid:getCapacity() < 0.9 then
                    fail("NoWater"); return
                end
                callback()
            end, "water"))
        end)
    end

    local function add(player, recipe, ingredient, callback)
        local original = sourceOf(ingredient)
        if not original then fail("ItemMissing"); return end
        take(player, ingredient, function()
            if ingredient:isRotten() or ingredient:isBurnt() or ingredient:isCooked() then
                fail("PlanChanged"); return
            end
            local usable = CookItForMe.withFrozenRecipe(recipe, function()
                return recipe:isItemUsableInRecipe(player, session.pot, ingredient:getID())
            end)
            if not usable then fail("PlanChanged"); return end
            local frozen = ingredient:isFrozen()
            session.stage = "adding"
            local previous = session.pot
            local result = CookItForMe.withFrozenRecipe(recipe, function()
                return recipe:addItem(previous, ingredient, player)
            end)
            -- addItem must never be retried: it may have already consumed the ingredient.
            session.pot = result or previous
            local inv = player:getInventory()
            if session.pot:getContainer() ~= inv then
                local container = session.pot:getContainer()
                if container then container:Remove(session.pot) end
                inv:AddItem(session.pot)
            end
            ISAddItemInRecipe.checkName(session.pot, recipe)
            ISAddItemInRecipe.checkTemperature(session.pot, ingredient, recipe)
            if not ingredient:isSpice() then
                session.addedCount = session.addedCount + 1
                if frozen then session.frozenCount = session.frozenCount + 1 end
            end
            pcall(function() player:getEmitter():playSoundImpl(recipe:getAddIngredientSound() or "AddItemInRecipe", nil) end)
            local function nextStep() session:defer(getTimestampMs(), 500, callback) end
            if ingredient:getContainer() == inv and original.container ~= inv then
                local dest = original.container
                if original.world then dest = ItemContainer.new("floor", original.square, nil) end
                move(player, ingredient, dest, nextStep)
            else nextStep() end
        end)
    end

    local function findOnStove()
        if not session.stove or not session.pot then return nil end
        local container = session.stove:getContainer()
        if container and session.pot:getContainer() == container and container:contains(session.pot) then
            return session.pot
        end
        return nil -- same type or extra ingredients do not establish ownership
    end

    local function toStove(player, stove, callback)
        if session.addedCount == 0 then fail("NotEnough"); return end
        session.stove = stove
        move(player, session.pot, stove:getContainer(), callback)
    end

    local function heat(player, stove, recipe, settings)
        session.stove = stove
        local pot = findOnStove()
        if not pot then fail("ItemMissing"); return end
        if stove:isBroken() or not stove:getContainer():isPowered() then fail("NoPower"); return end
        if session.frozenCount > 0 and not session.penaltyApplied then
            local cook, burn = pot:getMinutesToCook(), pot:getMinutesToBurn()
            local adjusted = FoodLogic.frozenPenaltyTime(cook, session.frozenPenalty, session.frozenCount, session.addedCount)
            pot:setMinutesToCook(adjusted)
            pot:setMinutesToBurn(adjusted + math.max(1, burn - cook))
            session.penaltyApplied = true
        end
        if not stove:Activated() then
            session.weTurnedStoveOn = true -- record before Toggle, including exceptions
            stove:Toggle()
        end
        if not stove:Activated() then fail("NoPower"); return end
        session.resultType = recipe:getFullResultItem()
        session.heatStart = getTimestampMs()
        session.debugFast = settings.debugFast
        session.cooking = true
        session.stage = "heating"
        session.heatIdle = 0
        session.lastCookingTime = pot:getCookingTime()
        session.lastHeat = pot:getHeat()
        session.lastFreezingTime = pot:getFreezingTime()
        CookItForMe.diagnostic("heating: " .. pot:getFullType())
    end

    local function monitor(dt)
        local queue = ISTimedActionQueue.getTimedActionQueue(session.player).queue
        for action, entry in pairs(session.pending) do
            local present = false
            for _, queued in ipairs(queue) do if queued == action then present = true; break end end
            if present then entry.missing = 0 else entry.missing = entry.missing + dt end
            if queue[1] == action then entry.elapsed = entry.elapsed + dt end
            if entry.cancelled or entry.missing >= 500 or entry.elapsed >= 120000 then
                fail("ActionInterrupted"); return
            end
        end
    end

    return { take = take, water = water, add = add, toStove = toStove, heat = heat,
        findOnStove = findOnStove, onComplete = track, monitor = monitor, move = move }
end

return Actions
