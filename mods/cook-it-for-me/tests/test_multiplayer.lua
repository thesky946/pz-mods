package.path = "../42/media/lua/shared/?.lua;../42/media/lua/client/?.lua;./?.lua;" .. package.path
local Env = require "support/cook_env"
local e = Env.new()
local scannedRadius
package.loaded.CookItForMe_Scanner.scanAround = function(_, radius)
    scannedRadius = radius
    return e.scan
end

local registered, keyHandler
Events.OnFillWorldObjectContextMenu = { Add = function(callback) registered = callback end }
Events.OnKeyPressed = { Add = function(callback) keyHandler = callback end }
Events.OnRenderTick = { Add = function() end }
package.loaded["ISUI/ISLabel"] = true
package.loaded["ISUI/ISButton"] = true
ISWorldObjectContextMenu = { Test = false }
getSpecificPlayer = function() return e.player end
package.loaded.CookItForMe_PlanUI = true
CookItForMePlanUI = {
    new = function() error("multiplayer must not open the plan UI") end,
    onPlanKeyCapturePressed = function() return false end,
}

Keyboard = {
    KEY_F8 = 66, KEY_LSHIFT = 42, KEY_RSHIFT = 54,
    KEY_LCONTROL = 29, KEY_RCONTROL = 157, KEY_LMENU = 56, KEY_RMENU = 184,
    isKeyDown = function() return false end,
}
local keyOption
local keyOptions = { dict = {} }
function keyOptions:getOption(id) return self.dict[id] end
function keyOptions:addKeyBind(id, name, key)
    keyOption = { key = key }
    function keyOption:getValue() return self.key end
    function keyOption:setValue(value) self.key = value end
    self.dict[id] = keyOption
    return keyOption
end
PZAPI = { ModOptions = { Dict = {}, Data = {} } }
function PZAPI.ModOptions:getOptions(id) return self.Dict[id] end
function PZAPI.ModOptions:create(id)
    keyOptions.modOptionsID = id
    self.Dict[id] = keyOptions
    self.Data[#self.Data + 1] = keyOptions
    return keyOptions
end
function PZAPI.ModOptions:save() end

isClient = function() return true end
require "CookItForMe_Client"
assert(type(registered) == "function", "context handler registered")
assert(type(keyHandler) == "function", "hotkey handler registered")

local context = { count = 0, addOption = function(self) self.count = self.count + 1 end }
CookItForMe.onFillWorldObjectContextMenu(0, context, {}, false)
assert(context.count == 0, "multiplayer hides the context-menu entry")
keyHandler(Keyboard.KEY_F8)
assert(context.count == 0, "multiplayer hotkey does not open the plan")

isClient = function() return false end
e.scan.stove = nil
CookItForMe.onFillWorldObjectContextMenu(0, context, {}, false)
assert(context.count == 0, "single-player hides the context-menu entry without a nearby stove")

e.scan.stove = e.stove
CookItForMe.onFillWorldObjectContextMenu(0, context, {}, false)
assert(context.count == 1, "single-player shows the context-menu entry near a stove")
assert(scannedRadius == CookItForMe.CONTEXT_MENU_STOVE_RADIUS, "context-menu scan uses its dedicated radius")
isClient = nil

print("MULTIPLAYER GUARD TESTS PASSED")
