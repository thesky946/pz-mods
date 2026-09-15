package.path = "../42/media/lua/shared/?.lua;" .. package.path
local Session = require "CookItForMe_Session"
local plan = { cookware = {}, picked = { frozenCount = 1 }, settings = { frozenPenalty = 0.5 } }
local a, b = Session.new({}, plan), Session.new({}, plan)
local calls = 0
a:defer(100, 500, function() calls = calls + 1 end)
a:advance(599)
assert(calls == 0)
a:advance(600)
a:advance(601)
assert(calls == 1, "delay runs once, at its boundary")
local saved = a:guard(function() calls = calls + 1 end)
a:defer(700, 500, saved)
a:finish()
a:finish()
saved()
a:advance(2000)
assert(calls == 1 and a.delayNext == nil and a.delayUntil == nil)
assert(b.active and b.addedCount == 0, "sessions do not share mutable state")
local nextStep
b:run({
    function(next) nextStep = next end,
    function() error("finished session must not advance") end,
})
b:finish()
nextStep()
assert(not b.active and not b.cooking)
assert(b.plan == plan and b.pot == plan.cookware, "preserve exact preview references")
print("SESSION TESTS PASSED")
