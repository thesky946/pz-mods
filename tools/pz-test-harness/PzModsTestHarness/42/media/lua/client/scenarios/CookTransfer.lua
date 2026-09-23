local Adapter = {}
local SCENARIO_ID = "cook.transfer.container.success"

local function gameBuild()
    return tostring(getCore():getVersionNumber())
end

local function makeFinisher(context, finish)
    context.cleanup = context.cleanup or {}
    context.createdItemIds = context.createdItemIds or {}
    local finished = false
    return function(raw)
        if finished then return false end
        finished = true
        local cleanupFailures = {}
        for index = #context.cleanup, 1, -1 do
            local ok, err = pcall(context.cleanup[index])
            if not ok then cleanupFailures[#cleanupFailures + 1] = tostring(err) end
        end
        context.cleanup = {}
        raw = type(raw) == "table" and raw or {}
        raw.gameBuild = gameBuild()
        raw.cleanup = {
            status = #cleanupFailures == 0 and "pass" or "fail",
            failures = cleanupFailures,
        }
        finish(raw)
        return true
    end
end

local function recordItem(context, item)
    context._createdItems = context._createdItems or {}
    if context._createdItems[item] then return end
    context._createdItems[item] = true
    context.createdItemIds[#context.createdItemIds + 1] = item:getID()
    context.cleanup[#context.cleanup + 1] = function()
        local container = item:getContainer()
        if container then container:Remove(item) end
        if item:getContainer() then error("run-owned item cleanup failed: " .. tostring(item:getID())) end
    end
end

local function failure(done, message, observed)
    done({ status = "fail", failures = { message }, observed = observed or {} })
end

local function run(context, finish)
    local done = makeFinisher(context, finish)
    if not context.player then
        failure(done, "player fixture is missing")
        return
    end

    local ok, err = pcall(function()
        local player = context.player
        local destination = player:getInventory()
        local bag = destination:AddItem("Base.Bag_NormalHikingBag")
        if not bag then failure(done, "failed to create source container item"); return end
        recordItem(context, bag)

        local source = bag:getInventory()
        if not source then failure(done, "created source item has no inner container"); return end
        local item = source:AddItem("Base.Spoon")
        if not item then failure(done, "failed to create nested transfer item"); return end
        recordItem(context, item)

        if item:getContainer() ~= source or not source:contains(item) then
            failure(done, "nested item source ownership was not established")
            return
        end
        if not destination:hasRoomFor(player, item) then
            failure(done, "player inventory has no room for transfer")
            return
        end

        local action = ISInventoryTransferAction:new(player, item, source, destination, nil)
        if not action then failure(done, "vanilla transfer action could not be created"); return end

        local function complete()
            local sourceContains = source:contains(item)
            local destinationContains = destination:contains(item) and item:getContainer() == destination
            local observed = {
                itemId = item:getID(),
                sourceContains = sourceContains,
                destinationContains = destinationContains,
                exactIdentity = destinationContains,
                sessionTerminal = true,
            }
            if sourceContains or not destinationContains then
                failure(done, "exact transfer object did not reach player inventory", observed)
                return
            end
            done({ status = "pass", failures = {}, observed = observed })
        end
        action:setOnComplete(function()
            local callbackOk, callbackError = pcall(complete)
            if not callbackOk then failure(done, "transfer completion failed: " .. tostring(callbackError)) end
        end)

        local originalStop = action.stop
        action.stop = function(self)
            if originalStop then pcall(originalStop, self) end
            failure(done, "transfer action cancelled")
        end
        local originalForceCancel = action.forceCancel
        action.forceCancel = function(self)
            if originalForceCancel then pcall(originalForceCancel, self) end
            failure(done, "transfer action force-cancelled")
        end

        if not ISTimedActionQueue.add(action) then
            failure(done, "vanilla transfer action was rejected before start")
        end
    end)
    if not ok then failure(done, "transfer setup failed: " .. tostring(err)) end
end

function Adapter.register(registry)
    if registry[SCENARIO_ID] == nil then registry[SCENARIO_ID] = run end
end

return Adapter
