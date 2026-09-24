package.path = "../42/media/lua/shared/?.lua;./?.lua;" .. package.path
local Env = require "support/cook_env"

for _, initialSpeed in ipairs({ 1, 2, 3, 4 }) do
    local e = Env.new("Stew")
    local speed, displayedSpeed, multiplier, running = initialSpeed, initialSpeed, ({ 1, 5, 20, 40 })[initialSpeed], {}
    getGameSpeed = function() return speed end
    -- In B42, setGameSpeed delegates to SpeedControls.SetCurrentGameSpeed,
    -- which resets GameTime's multiplier to 1. The HUD highlight reads that multiplier.
    setGameSpeed = function(value) speed, displayedSpeed, multiplier = value, value, 1 end
    getGameTime = function() return {
        setMultiplier = function(_, value) multiplier = value end,
    } end
    e.player.getVehicle = function() return nil end
    local newWalk = ISWalkToTimedAction.new
    ISWalkToTimedAction.new = function(...)
        local a = newWalk(...)
        a.isValid = function() return getGameSpeed() <= 2 end
        return a
    end
    -- A real walk is needed after gathering ingredients, as in the reported stall.
    local stoveSquare = { getX = function() return 1 end, getY = function() return 1 end }
    e.stove.getSquare = function() return stoveSquare end
    e.stoveInv.getSourceGrid = function() return stoveSquare end
    AdjacentFreeTileFinder.Find = function(square) return square end
    e.player.getCharacterActions = function() return Env.list(running) end
    -- The vanilla speed-reset decision from ISTimedActionQueue.onTick.
    ISTimedActionQueue.isPlayerDoingAction = function(player)
        return player == e.player and #running > 0
    end
    local function vanillaTick()
        if ISTimedActionQueue.isPlayerDoingAction(e.player) then
            ISTimedActionQueue.shouldResetGameSpeed = true
        elseif ISTimedActionQueue.shouldResetGameSpeed then
            ISTimedActionQueue.shouldResetGameSpeed = false
            if speed > 1 then setGameSpeed(1) end
        end
    end
    e.cook.start(e.player, "Stew", assert(e.cook.plan(e.player, "Stew")))
    local function drain()
        for _ = 1, 100 do
            local a = table.remove(e.queue, 1)
            if a then
                if a.kind == "walk" then
                    assert(a:isValid(), "real walk rejected at speed " .. speed)
                    local walkingSpeed = speed
                    speed, displayedSpeed, multiplier = 4, 4, 40
                    assert(a:isValid() and speed == 2, "acceleration during walking remains valid")
                    assert(displayedSpeed == 2, "speed controls must show the walking speed")
                    assert(multiplier == 5, "walking speed and HUD highlight must match")
                    speed, displayedSpeed, multiplier = 0, 0, 1
                    assert(a:isValid() and speed == 0, "validation must not unpause")
                    speed, displayedSpeed, multiplier = walkingSpeed, walkingSpeed, walkingSpeed == 2 and 5 or 1
                end
                -- Vanilla WalkToTimedAction starts pathfinding and rejects speed > 2.
                -- It must not be used as an idle callback after putting food on the stove.
                if e.pot.container == e.stoveInv or e.pot.cooked then
                    assert(a.kind ~= "walk", "heating/retrieval must not enqueue artificial walking")
                end
                a.action = {}
                running = { a.action }
                vanillaTick()
                if a.perform then a.perform() end
                if a.callback then a.callback() end
                running = {}
                vanillaTick()
            else
                e.now = e.now + 500
                e.tick()
                vanillaTick()
                if #e.queue == 0 and not e:state().delayNext then return end
            end
        end
        error("queue did not settle")
    end
    drain()
    assert(speed == math.min(initialSpeed, 2), "walking caps only unsupported speeds")
    assert(multiplier == ({ 1, 5, 5, 5 })[initialSpeed], "walking keeps the selected speed multiplier")
    -- Manual speed changes during heating must also remain untouched.
    speed, displayedSpeed, multiplier = 0, 0, 1
    e.tick()
    vanillaTick()
    assert(speed == 0, "manual pause")
    speed, displayedSpeed, multiplier = initialSpeed, initialSpeed, ({ 1, 5, 20, 40 })[initialSpeed]
    e.pot.cooked = true
    e.tick()
    drain()
    assert(speed == initialSpeed, "retrieval/completion must preserve speed")

    -- An unrelated action still uses vanilla auto-reset, even after our hook.
    speed, displayedSpeed, multiplier = 3, 3, 20
    running = { {} }
    vanillaTick()
    running = {}
    vanillaTick()
    assert(speed == 1, "unrelated action must retain vanilla reset")

    -- A threat or another system can lower speed; the mod never restores it.
    speed, displayedSpeed, multiplier = 1, 1, 1
    e.tick()
    vanillaTick()
    assert(speed == 1, "external reset must not be reversed")
end
getGameSpeed, setGameSpeed, getGameTime = nil, nil, nil
print("SPEED TESTS PASSED")
