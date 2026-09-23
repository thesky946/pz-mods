package.path = "./?.lua;" .. package.path

local Simulator = require "support/action_simulator"

local function assertTrace(simulator, expected)
    assert(#simulator.trace == #expected, "trace length")
    for index, event in ipairs(expected) do
        assert(simulator.trace[index] == event, "trace[" .. index .. "]")
    end
end

local success = Simulator.new()
success:queue({
    isValidStart = function() return true end,
    waitToStart = function() return false end,
    start = function() end,
    update = function() end,
    complete = function() return true end,
    perform = function() end,
})
success:runUntilIdle()
assertTrace(success, { "isValidStart", "waitToStart", "start", "update", "complete", "perform" })

local rejected = Simulator.new()
rejected:queue({ isValidStart = function() return false end, forceCancel = function() end })
rejected:runUntilIdle()
assertTrace(rejected, { "isValidStart", "forceCancel" })

local invalidated = Simulator.new()
invalidated:queue({
    isValidStart = function() return true end,
    start = function() end,
    update = function() end,
    isValid = function() return false end,
    stop = function() end,
})
invalidated:runUntilIdle()
assertTrace(invalidated, { "isValidStart", "start", "update", "isValid", "stop" })

local incomplete = Simulator.new()
incomplete:queue({
    isValidStart = function() return true end,
    complete = function() return false end,
    perform = function() error("perform must not run") end,
})
incomplete:runUntilIdle()
assert(incomplete.state.status == "incomplete", "false complete must be terminal")

local cancelled = Simulator.new({ faults = { forceCancelBeforeStart = true } })
cancelled:queue({
    isValidStart = function() return true end,
    forceCancel = function() end,
    start = function() end,
})
cancelled:runUntilIdle()
assertTrace(cancelled, { "isValidStart", "forceCancel" })
assert(cancelled.state.status == "cancelled", "force cancel before start")

local vanished = Simulator.new({ faults = { vanishAfterStart = true } })
vanished:queue({
    isValidStart = function() return true end,
    start = function() end,
    update = function() end,
    stop = function() end,
})
vanished:runUntilIdle()
assert(vanished.state.status == "vanished" and vanished.state.vanished, "vanished result remains visible")

local duplicate = Simulator.new({ faults = { duplicateCallback = true } })
local effects = 0
duplicate:queue({
    isValidStart = function() return true end,
    perform = function(_, sim) sim:effectOnce("transfer", function() effects = effects + 1 end) end,
})
duplicate:runUntilIdle()
assert(duplicate.state.duplicateCallbacks == 1, "duplicate callback was injected")
assert(effects == 1 and duplicate.state.effectCount == 2, "each guarded effect executes once")

local stale = Simulator.new()
local staleRan = false
stale:queue({
    isValidStart = function() return true end,
    start = function(_, sim) sim:schedule(10, function() staleRan = true end) end,
})
stale:runUntilIdle()
stale:advance(10)
assert(not staleRan and stale.state.rejectedCallbacks == 1, "terminal callback is ignored")

local paused = Simulator.new({ timeoutMs = 5 })
paused:queue({ isValidStart = function() return true end, waitToStart = function() return true end })
paused:advance(10, true)
assert(paused.state.wallTimeMs == 10 and paused.state.gameplayTimeMs == 0, "pause advances wall time only")
assert(paused.state.active, "pause cannot timeout action")

local stalled = Simulator.new({ timeoutMs = 5 })
stalled:queue({ isValidStart = function() return true end, waitToStart = function() return true end })
stalled:runUntilIdle()
assert(stalled.state.status == "stalled" and stalled.state.status ~= "PASS", "timeout never passes")
assert(stalled.failures[1] == "stalled", "timeout is reported")

local invariant = Simulator.new()
local item = {}
invariant:place(item, "source")
invariant:place(item, "destination")
invariant:effectOnce("move", function() end)
assert(invariant:assertInvariants(), "unique location and at-most-once effects")

local ordered = Simulator.new()
ordered:schedule(10, function() ordered.trace[#ordered.trace + 1] = "late" end)
ordered:schedule(5, function() ordered.trace[#ordered.trace + 1] = "early-first" end)
ordered:schedule(5, function() ordered.trace[#ordered.trace + 1] = "early-second" end)
ordered:advance(10)
assertTrace(ordered, { "early-first", "early-second", "late" })

local reused = Simulator.new()
local reusedPerforms = 0
local reusableAction = {
    isValidStart = function() return true end,
    perform = function() reusedPerforms = reusedPerforms + 1 end,
}
reused:queue(reusableAction)
reused:runUntilIdle()
reused:queue(reusableAction)
reused:runUntilIdle()
assert(reused.state.status == "PASS" and reusedPerforms == 2, "default perform guard is scoped to its session")

local explicit = Simulator.new()
local explicitPerforms = 0
local explicitlyGuarded = {
    isValidStart = function() return true end,
    effectKey = "cross-callback",
    perform = function() explicitPerforms = explicitPerforms + 1 end,
}
explicit:queue(explicitlyGuarded)
explicit:runUntilIdle()
explicit:queue(explicitlyGuarded)
explicit:runUntilIdle()
assert(explicitPerforms == 1, "explicit effect key remains cross-callback guard")

print("ACTION SIMULATOR TESTS PASSED")
