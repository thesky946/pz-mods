package.path = "../42/media/lua/shared/?.lua;./?.lua;" .. package.path
local Env = require "support/cook_env"

local cases = {
    { name = "success", faults = {}, expected = "pass" },
    { name = "reject before start", faults = { rejectBeforeStart = true }, expected = "fail" },
    { name = "force cancel", faults = { forceCancelBeforeStart = true }, expected = "fail" },
    { name = "item disappears", faults = { itemDisappears = true }, expected = "fail" },
    { name = "destination fills", faults = { destinationBecomesFull = true }, expected = "fail" },
    { name = "duplicate callback", faults = { duplicateCallback = true }, expected = "pass" },
    { name = "stale callback", faults = { staleCallbackAfterSession = true }, expected = "pass" },
}

for _, case in ipairs(cases) do
    local observation = Env.new():runScenario("cook.transfer.container.success", case.faults)
    assert(observation.status == case.expected, case.name .. ": unexpected status")
    assert(observation.sessionActive == false, case.name .. ": session did not terminate")
    assert(observation.sourceContains ~= observation.destinationContains, case.name .. ": item was lost or duplicated")
    assert(observation.effectCount == (case.expected == "pass" and 1 or 0), case.name .. ": transfer effect count")
    assert(observation.stoveActive == false, case.name .. ": transfer scenario changed stove state")
    if case.expected == "pass" then
        assert(not observation.sourceContains and observation.destinationContains, case.name .. ": destination does not own item")
        assert(observation.failureReason == nil, case.name .. ": successful scenario reports failure")
        local expectedCallbacks = case.faults.staleCallbackAfterSession and 0 or 1
        assert(observation.callbackCount == expectedCallbacks, case.name .. ": callback delivery count")
        if case.faults.duplicateCallback then
            assert(observation.callbackAttempts == 2, case.name .. ": duplicate callback was not attempted")
        elseif case.faults.staleCallbackAfterSession then
            assert(observation.callbackAttempts == 0, case.name .. ": stale callback reached the session")
            assert(observation.rejectedCallbackCount == 1, case.name .. ": stale callback was not rejected")
        else
            assert(observation.callbackAttempts == 1, case.name .. ": callback attempt count")
            assert(observation.rejectedCallbackCount == 0, case.name .. ": callback was unexpectedly rejected")
        end
    else
        assert(observation.sourceContains and not observation.destinationContains, case.name .. ": failed transfer moved item")
        assert(observation.failureReason ~= nil, case.name .. ": failure reason is absent")
    end
end

local ordered = Env.new()
local order = {}
local first = ISInventoryTransferAction:new(ordered.player, ordered.pot, ordered.source, ordered.inv, nil)
first:setOnComplete(function() order[#order + 1] = "callback" end)
local second = ISInventoryTransferAction:new(ordered.player, ordered.food, ordered.source, ordered.inv, nil)
local secondPerform = second.perform
second.perform = function(self)
    order[#order + 1] = "next-action"
    secondPerform(self)
end
ISTimedActionQueue.add(first)
ISTimedActionQueue.add(second)
ordered:drain()
assert(table.concat(order, ",") == "callback,next-action", "drain must deliver completion before the next action")

local replacement = Env.new():runScenario("cook.recipe.replacement.success")
assert(replacement.status == "pass", "replacement scenario failed")
assert(replacement.sessionActive == false, "replacement session did not terminate")
assert(replacement.oldObjectPresent == false, "old cookware object remains present")
assert(replacement.resultFullType == "Base.CookedDish", "replacement has the wrong full type")
assert(replacement.effectCount == 1, "ingredient effect did not occur exactly once")
assert(replacement.resultLocationCount == 1, "replacement does not have exactly one location")
assert(replacement.destinationContains and not replacement.sourceContains, "replacement is not owned by the destination")
assert(replacement.stoveActive == false, "replacement scenario left the stove active")
assert(replacement.failureReason == nil, "replacement scenario reports a failure")

print("SIMULATED SCENARIO TESTS PASSED")
