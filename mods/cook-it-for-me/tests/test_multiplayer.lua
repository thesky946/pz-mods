package.path = "../42/media/lua/shared/?.lua;../42/media/lua/client/?.lua;./?.lua;" .. package.path
local Env = require "support/cook_env"
local e = Env.new()

local registered
Events.OnFillWorldObjectContextMenu = { Add = function(callback) registered = callback end }
ISWorldObjectContextMenu = { Test = false }
getSpecificPlayer = function() return e.player end
package.loaded.CookItForMe_PlanUI = true
CookItForMePlanUI = { new = function() error("multiplayer must not open the plan UI") end }

isClient = function() return true end
require "CookItForMe_Client"
assert(type(registered) == "function", "context handler registered")

local context = { count = 0, addOption = function(self) self.count = self.count + 1 end }
CookItForMe.onFillWorldObjectContextMenu(0, context, {}, false)
assert(context.count == 0, "multiplayer hides the context-menu entry")

isClient = function() return false end
CookItForMe.onFillWorldObjectContextMenu(0, context, {}, false)
assert(context.count == 1, "single-player keeps the context-menu entry")
isClient = nil

print("MULTIPLAYER GUARD TESTS PASSED")
