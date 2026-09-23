local Simulator = {}
Simulator.__index = Simulator

local function sortEvents(left, right)
    return left.at < right.at or (left.at == right.at and left.sequence < right.sequence)
end

function Simulator.new(options)
    options = options or {}
    local self = setmetatable({}, Simulator)
    self.faults = options.faults or {}
    self.timeoutMs = options.timeoutMs or 5000
    self.trace = {}
    self.failures = {}
    self.events = {}
    self.sequence = 0
    self.session = 0
    self.state = {
        status = "idle",
        active = false,
        terminal = false,
        wallTimeMs = 0,
        gameplayTimeMs = 0,
        effects = {},
        effectCount = 0,
        itemLocations = {},
        locationItems = {},
        rejectedCallbacks = 0,
    }
    return self
end

function Simulator:_trace(name)
    self.trace[#self.trace + 1] = name
end

function Simulator:_invoke(action, name)
    local callback = action[name]
    if not callback then return nil end
    self:_trace(name)
    return callback(action, self)
end

function Simulator:_fail(status)
    if self.state.terminal then return end
    self.state.status = status
    self.state.active = false
    self.state.terminal = true
    self.failures[#self.failures + 1] = status
end

function Simulator:_pass()
    if self.state.terminal then return end
    self.state.status = "PASS"
    self.state.active = false
    self.state.terminal = true
end

function Simulator:schedule(delayMs, callback)
    self.sequence = self.sequence + 1
    local event = {
        at = self.state.wallTimeMs + (delayMs or 0),
        sequence = self.sequence,
        callback = callback,
        session = self.session,
    }
    self.events[#self.events + 1] = event
    table.sort(self.events, sortEvents)
    return event
end

function Simulator:effectOnce(key, effect)
    if self.state.effects[key] then return false end
    self.state.effects[key] = true
    self.state.effectCount = self.state.effectCount + 1
    if effect then effect() end
    return true
end

function Simulator:place(item, location)
    local locations = self.state.itemLocations
    local oldLocation = locations[item]
    if oldLocation then
        self.state.locationItems[oldLocation][item] = nil
    end
    locations[item] = location
    self.state.locationItems[location] = self.state.locationItems[location] or {}
    self.state.locationItems[location][item] = true
end

function Simulator:assertInvariants()
    local seen = {}
    for location, items in pairs(self.state.locationItems) do
        for item in pairs(items) do
            assert(self.state.itemLocations[item] == location, "item location mismatch")
            assert(not seen[item], "item has multiple locations")
            seen[item] = true
        end
    end
    assert(self.state.effectCount == (function()
        local count = 0
        for _ in pairs(self.state.effects) do count = count + 1 end
        return count
    end)(), "effect count mismatch")
    if self.state.terminal then
        assert(not self.state.active, "terminal session remains active")
    end
    return true
end

function Simulator:_perform(action)
    local function perform()
        self:_invoke(action, "perform")
    end
    local effectKey = action.effectKey or ("perform:" .. self.session)
    self:effectOnce(effectKey, perform)
    if self.faults.duplicateCallback then
        self.state.duplicateCallbacks = (self.state.duplicateCallbacks or 0) + 1
        self:effectOnce(effectKey, perform)
    end
    self:_pass()
end

function Simulator:_run(action)
    if self.state.terminal then return end
    self:_invoke(action, "update")
    if self.faults.vanishAfterStart then
        self.state.vanished = true
        self:_invoke(action, "stop")
        self:_fail("vanished")
        return
    end
    if self:_invoke(action, "isValid") == false then
        self:_invoke(action, "stop")
        self:_fail("invalidated")
        return
    end
    -- Simulator contract: false completion blocks perform; this does not
    -- claim that every vanilla timed action uses the same return semantics.
    if self:_invoke(action, "complete") == false then
        self:_fail("incomplete")
        return
    end
    self:_perform(action)
end

function Simulator:_start(action)
    if self.state.terminal then return end
    if self:_invoke(action, "waitToStart") == true then
        self:schedule(1, function() self:_start(action) end)
        return
    end
    self:_invoke(action, "start")
    self:schedule(0, function() self:_run(action) end)
end

function Simulator:queue(action)
    if not action then
        self:_fail("missing")
        return false
    end
    if self.state.active then return false end
    self.session = self.session + 1
    self.state.status = "queued"
    self.state.active = true
    self.state.terminal = false
    self.state.startedGameplayTimeMs = self.state.gameplayTimeMs
    self:schedule(0, function()
        if self:_invoke(action, "isValidStart") == false then
            self:_invoke(action, "forceCancel")
            self:_fail("rejected")
            return
        end
        if self.faults.forceCancelBeforeStart then
            self:_invoke(action, "forceCancel")
            self:_fail("cancelled")
            return
        end
        self.state.status = "running"
        self:_start(action)
    end)
    return true
end

function Simulator:_advanceClock(targetTime, paused)
    local elapsed = targetTime - self.state.wallTimeMs
    if elapsed < 0 then error("time cannot move backwards") end
    self.state.wallTimeMs = targetTime
    if not paused then
        self.state.gameplayTimeMs = self.state.gameplayTimeMs + elapsed
    end
end

function Simulator:_checkTimeout()
    if self.state.active and self.state.gameplayTimeMs - self.state.startedGameplayTimeMs >= self.timeoutMs then
        self:_fail("stalled")
    end
end

function Simulator:advance(ms, paused)
    if ms < 0 then error("time cannot move backwards") end
    local target = self.state.wallTimeMs + ms
    while self.events[1] and self.events[1].at <= target do
        local event = table.remove(self.events, 1)
        self:_advanceClock(event.at, paused)
        self:_checkTimeout()
        if event.session ~= self.session or self.state.terminal then
            self.state.rejectedCallbacks = self.state.rejectedCallbacks + 1
        else
            event.callback()
            self:_checkTimeout()
        end
    end
    self:_advanceClock(target, paused)
    self:_checkTimeout()
    return self.state
end

function Simulator:runUntilIdle(limitMs)
    local limit = limitMs or self.timeoutMs
    local untilTime = self.state.wallTimeMs + limit
    while self.events[1] and self.state.wallTimeMs <= untilTime do
        local nextTime = self.events[1].at
        if nextTime > untilTime then break end
        self:advance(nextTime - self.state.wallTimeMs)
    end
    if self.state.active then
        self:advance(untilTime - self.state.wallTimeMs)
        if self.state.active then self:_fail("stalled") end
    end
    return self.state
end

return Simulator
