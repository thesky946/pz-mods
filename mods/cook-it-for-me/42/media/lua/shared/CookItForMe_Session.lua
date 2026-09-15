-- State and continuations of one cooking run. No PZ API or global player.
local Session = {}
Session.__index = Session

function Session.new(player, plan)
    return setmetatable({
        player = player,
        plan = plan,
        active = true,
        cooking = false,
        pot = plan.cookware,
        weTurnedStoveOn = false,
        addedCount = 0,
        frozenCount = 0,
        stage = "preparing",
        pending = {},
        frozenPenalty = plan.settings.frozenPenalty,
    }, Session)
end

function Session:finish(reason)
    self.active = false
    self.cooking = false
    self.delayUntil = nil
    self.delayNext = nil
    self.reason = reason or self.reason
    self.stage = reason == "success" and "done" or "stopped"
end

-- Callbacks always belong to this run, even after another run has started.
function Session:guard(callback)
    local called = false
    return function(...)
        if not self.active or called then return end
        called = true
        local ok, value = pcall(callback, ...)
        if not ok then
            if self.onError then self.onError(value) else error(value) end
        end
        return value
    end
end

function Session:defer(now, milliseconds, callback)
    if not self.active then return end
    self.delayUntil = now + milliseconds
    self.delayNext = self:guard(callback)
end

function Session:advance(now)
    if not self.active then return end
    if self.delayNext and now >= self.delayUntil then
        local callback = self.delayNext
        self.delayNext, self.delayUntil = nil, nil
        callback()
    end
end

function Session:run(steps)
    local function run(index)
        if not self.active or index > #steps then return end
        steps[index](self:guard(function() run(index + 1) end))
    end
    run(1)
end

return Session
