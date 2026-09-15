-- One cooking run: action ownership, stove monitoring and terminal outcomes.
require "CookItForMe_Shared"
local Actions = require "CookItForMe_Actions"
local Executor = { REVISION = "reliable-executor-4" }

function Executor.new(session)
    local execution = {}
    local function finish(reason, key)
        if not session.active then return end
        local stage = session.stage
        session:finish(reason)
        if reason ~= "success" and session.weTurnedStoveOn and session.stove then
            local ok, err = pcall(function()
                if session.stove:Activated() then session.stove:Toggle() end
            end)
            if not ok then CookItForMe.diagnostic("stove cleanup failed: " .. tostring(err)) end
        end
        local queue = ISTimedActionQueue.getTimedActionQueue(session.player)
        local current = queue.queue[1]
        for i = #queue.queue, 1, -1 do
            local action = queue.queue[i]
            if session.pending[action] and action ~= current then
                table.remove(queue.queue, i)
                if action.forceCancel then pcall(action.forceCancel, action) end
            end
        end
        if current and session.pending[current] then
            current.preserveOtherActions = true
            if current.forceStop then pcall(current.forceStop, current)
            else table.remove(queue.queue, 1) end
        end
        session.pending = {}
        CookItForMe.diagnostic("finish: " .. reason .. " stage=" .. tostring(stage) .. " reason=" .. tostring(key))
        if key then pcall(function() session.player:Say(getText("UI_CookItForMe_" .. key)) end) end
    end
    function execution.fail(key) finish("error", key) end
    function execution.cancel() finish("cancelled", "ActionInterrupted") end
    session.onError = function(err)
        CookItForMe.diagnostic("exception: " .. tostring(err))
        execution.fail("ActionFailed")
    end
    local actions = Actions.new(session, execution.fail)
    function execution.start()
        local player, plan = session.player, session.plan
        CookItForMe.diagnostic("start: " .. plan.dishKey .. " executor=" .. Executor.REVISION .. " actions=" .. Actions.REVISION)
        local steps = {}
        steps[#steps + 1] = function(next) actions.take(player, plan.cookware, next) end
        if plan.dish.needsWater then
            steps[#steps + 1] = function(next) actions.water(player, plan.cookware, plan.scan.sink, next) end
        end
        for _, item in ipairs(plan.picked.items) do
            steps[#steps + 1] = function(next) actions.add(player, plan.recipe, item, next) end
        end
        for _, item in ipairs(plan.picked.spices) do
            steps[#steps + 1] = function(next) actions.add(player, plan.recipe, item, next) end
        end
        steps[#steps + 1] = function(next) actions.toStove(player, plan.scan.stove, next) end
        steps[#steps + 1] = function() actions.heat(player, plan.scan.stove, plan.recipe, plan.settings) end
        session.lastTickAt = getTimestampMs()
        session:run(steps)
    end
    function execution.tick()
        if not session.active then return end
        local player = session.player
        local now = getTimestampMs()
        local dt = math.max(0, math.min(1000, now - (session.lastTickAt or now)))
        session.lastTickAt = now
        if getGameSpeed and getGameSpeed() == 0 then return end
        local zombies = player:getCell():getZombieList()
        for i = 0, zombies:size() - 1 do
            local z = zombies:get(i)
            local dx, dy = z:getX() - player:getX(), z:getY() - player:getY()
            if z:getZ() == player:getZ() and dx * dx + dy * dy < 100 then
                finish("cancelled", "CancelledThreat"); return
            end
        end
        actions.monitor(dt)
        if not session.active then return end
        session:advance(now)
        if not session.active or not session.cooking then return end
        local pot = actions.findOnStove()
        if not pot then execution.fail("ItemMissing"); return end
        if not session.stove:Activated() or not session.stove:getContainer():isPowered() then
            execution.fail("NoPower"); return
        end
        if session.debugFast and now - session.heatStart > 5000 then pot:setCooked(true) end
        local burnt = pot:isBurnt()
        if not pot:isCooked() and not burnt then
            local progress, heat = pot:getCookingTime(), pot:getHeat()
            local freezing = pot:getFreezingTime()
            if progress > (session.lastCookingTime or 0) or heat > (session.lastHeat or 0)
                or freezing < (session.lastFreezingTime or freezing) then
                session.heatIdle = 0
            else session.heatIdle = (session.heatIdle or 0) + dt end
            session.lastCookingTime, session.lastHeat = progress, heat
            session.lastFreezingTime = freezing
            if session.heatIdle >= 120000 then execution.fail("NoHeat") end
            return
        end
        session.cooking = false
        session.stove:Toggle()
        if session.stove:Activated() then execution.fail("StoveStillOn"); return end
        session.stage = "retrieving"
        actions.move(player, pot, player:getInventory(), function()
            if session.stove:Activated() then execution.fail("StoveStillOn"); return end
            finish("success")
            local key = burnt and "Burnt" or "Done"
            player:Say(getText("UI_CookItForMe_" .. key) .. ": " .. pot:getName())
            if not burnt and CookItForMe.getSettings(player).completionSound then
                local ok, err = pcall(function() getSoundManager():playUISound("StoveTimerExpired") end)
                if not ok then CookItForMe.diagnostic("completion sound failed: " .. tostring(err)) end
            end
        end)
    end
    return execution
end
return Executor
