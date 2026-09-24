package.path = "../42/media/lua/shared/?.lua;../42/media/lua/client/?.lua;./?.lua;" .. package.path

local Env = require "support/cook_env"
local env = Env.new()

local KEY_F8, KEY_ESCAPE, KEY_K, KEY_LSHIFT = 66, 1, 37, 42
local KEY_LCONTROL, KEY_LMENU = 29, 56
Keyboard = {
    KEY_F8 = KEY_F8,
    KEY_ESCAPE = KEY_ESCAPE,
    KEY_K = KEY_K,
    KEY_LSHIFT = KEY_LSHIFT,
    KEY_RSHIFT = 54,
    KEY_LCONTROL = KEY_LCONTROL,
    KEY_RCONTROL = 157,
    KEY_LMENU = KEY_LMENU,
    KEY_RMENU = 184,
    isKeyDown = function(key) return Keyboard.down and Keyboard.down[key] or false end,
}

local option
local saveCount = 0
local options = { dict = {}, data = {} }
function options:getOption(id) return self.dict[id] end
function options:addKeyBind(id, name, key)
    option = { id = id, name = name, key = key }
    function option:getValue() return self.key end
    function option:setValue(value)
        self.key = value
        if self.element then self.element.keyCode = value end
    end
    self.dict[id] = option
    self.data[#self.data + 1] = option
    return option
end

local modOptions = { Dict = {}, Data = {} }
function modOptions:getOptions(id) return self.Dict[id] end
function modOptions:create(id, name)
    assert(not self.Dict[id], "Mod Options group must only be created once")
    local created = { modOptionsID = id, name = name, dict = {}, data = {} }
    for key, value in pairs(options) do created[key] = value end
    self.Dict[id] = created
    self.Data[#self.Data + 1] = created
    return created
end
function modOptions:save()
    saveCount = saveCount + 1
    if option and option.element then option.key = option.element.keyCode end
end
PZAPI = { ModOptions = modOptions }

local keyHandler, contextHandler, renderHandler
Events = {
    OnKeyPressed = { Add = function(fn) keyHandler = fn end },
    OnFillWorldObjectContextMenu = { Add = function(fn) contextHandler = fn end },
    OnRenderTick = { Add = function(fn) renderHandler = fn end },
}
local translatedBindName = "Cook It For Me: Open cooking plan"
getText = function(key)
    if key == "UI_CookItForMe_KeybindName" then return translatedBindName end
    return key
end
getKeyName = function(key) return key == KEY_F8 and "F8" or (key == KEY_K and "K" or "Unknown") end
isClient = function() return false end
isServer = function() return false end
ISWorldObjectContextMenu = { Test = false }

local function uiWidget(_, x, y, width, height, title, target, callback)
    local widget = { x = x, y = y, width = width, height = height, title = title, target = target, callback = callback }
    function widget:initialise() end
    function widget:instantiate() end
    function widget:setAnchorLeft() end
    function widget:setAnchorRight() end
    function widget:setVisible(value) self.visible = value end
    function widget:setTitle(value) self.title = value end
    function widget:getName() return self.title end
    return widget
end
ISLabel = { new = function(_, x, y, height, title)
    local widget = uiWidget(nil, x, y, #title * 8, height, title)
    function widget:setTranslation(value) self.translation = value; self.width = #value * 8 end
    function widget:setNameWithoutMoving(value) self.title = value; self.width = #value * 8 end
    function widget:getWidth() return self.width end
    function widget:setX(value) self.x = value end
    return widget
end }
ISButton = { new = uiWidget }
package.loaded["ISUI/ISLabel"] = ISLabel
package.loaded["ISUI/ISButton"] = ISButton
getTextManager = function() return { getFontHeight = function() return 14 end } end
UIFont = { Small = "Small" }
local controlsPanel = { children = {}, scrollHeight = 650 }
function controlsPanel:getScrollHeight() return self.scrollHeight end
function controlsPanel:setScrollHeight(value) self.scrollHeight = value end
function controlsPanel:addChild(child) self.children[#self.children + 1] = child end
local mainOptions = { width = 1000, keyButtonWidth = 140 }
mainOptions.tabs = { getView = function(_, name)
    if name == "UI_optionscreen_keybinding" then return controlsPanel end
end }
local forwardedKey, forwardedShift, forwardedCtrl, forwardedAlt
local vanillaRow = { left = true, btn = { x = 325, y = 560, height = 20 },
    txt = { getName = function() return "Inspect Weapon" end }, keyCode = KEY_K }
MainOptions = {
    instance = mainOptions, keyText = { vanillaRow }, onKeyBindingBtnPress = function() end,
    keyPressHandler = function(key, shift, ctrl, alt)
        forwardedKey, forwardedShift, forwardedCtrl, forwardedAlt = key, shift, ctrl, alt
    end,
}

local openCount, closeCount, openedPlayer, openedEntries = 0, 0
CookItForMe = CookItForMe or {}
CookItForMe.getSettings = function() return { radius = 5 } end
local plannedScans, plannedCollections = {}, {}
CookItForMe.Cook = {
    ALL_DISHES = { "Soup", "Stew", "Salad" },
    DISHES = { Soup = {}, Stew = {}, Salad = { allowCookedIngredients = true } },
    isMultiplayer = function() return isClient() or isServer() end,
    plan = function(player, dish, _, scan, collected)
        plannedScans[dish], plannedCollections[dish] = scan, collected
        return player.planByDish[dish], player.failByDish and player.failByDish[dish]
    end,
}
CookItForMe.CONTEXT_MENU_STOVE_RADIUS = 5
CookItForMe.clientEventsRegistered = false
CookItForMe.keyPressedRegistered = false
CookItForMePlanUI = {
    keyCaptureActive = false,
    new = function(_, player, entries)
        openCount = openCount + 1
        openedPlayer, openedEntries = player, entries
        CookItForMe.planWindow = { player = player, close = function(self)
            assert(CookItForMe.planWindow == self, "only the current plan window closes")
            closeCount = closeCount + 1
            CookItForMe.planWindow = nil
        end }
    end,
    onPlanKeyCapturePressed = function(key)
        if not CookItForMePlanUI.keyCaptureActive then return false end
        CookItForMePlanUI.capturedKey = key
        return true
    end,
}
package.loaded.CookItForMe_Shared = true
package.loaded.CookItForMe_FoodLogic = true
local scanCount, collectCount = 0, 0
local rawFood = { isCooked = function() return false end }
local cookedFood = { isCooked = function() return true end }
package.loaded.CookItForMe_Scanner = {
    scanAround = function()
        scanCount = scanCount + 1
        return { stove = true, containers = {}, floorItems = {} }
    end,
    collectFood = function(_, _, includeCooked)
        collectCount = collectCount + 1
        assert(includeCooked == true, "the shared collection includes salad ingredients")
        return { foods = { rawFood, cookedFood }, spices = {}, cookware = {}, items = {} }
    end,
}
package.loaded.CookItForMe_Cook = true
package.loaded.CookItForMe_PlanUI = true
package.loaded.CookItForMe_Client = nil

local vehicleChecks = 0
local player = { planByDish = { Soup = { id = "soup-plan" }, Stew = nil }, getVehicle = function()
    vehicleChecks = vehicleChecks + 1
    return nil
end }
local players = { [0] = player }
getSpecificPlayer = function(index) return players[index] end
require "CookItForMe_Client"

assert(type(keyHandler) == "function", "the client key handler is registered")
assert(type(contextHandler) == "function", "the context-menu handler remains registered")
assert(option and option.key == KEY_F8, "the shared Mod Options keybind defaults to F8")
assert(CookItForMe.getOpenPlanKey() == KEY_F8, "runtime key reads the Mod Options object")
assert(type(renderHandler) == "function", "the Controls screen receives the shared Mod Options binding")
renderHandler()
assert(#controlsPanel.children == 2 and #MainOptions.keyText == 2,
    "the already-built Controls screen gets one keybind row")
local controlsRow = MainOptions.keyText[2]
assert(controlsRow.isModBind and controlsRow.btn.target == mainOptions
    and controlsRow.btn.callback == MainOptions.onKeyBindingBtnPress
    and controlsRow.txt:getName() == "Cook It For Me: Open cooking plan"
    and controlsRow.btn.internal == controlsRow.txt:getName()
    and option.element == controlsRow,
    "the Controls row uses vanilla key capture and the shared Mod Options option")
assert(controlsRow.btn.x == vanillaRow.btn.x
    and controlsRow.txt.x + controlsRow.txt.width == controlsRow.btn.x - 10
    and controlsRow.btn.y == vanillaRow.btn.y + vanillaRow.btn.height + 12,
    "the mod keybind aligns with vanilla Controls and sits just below the last row")
renderHandler()
assert(#MainOptions.keyText == 2, "render ticks never duplicate the Controls binding")
translatedBindName = "Cook It For Me: Open plan"
renderHandler()
assert(controlsRow.txt:getName() == translatedBindName
    and controlsRow.btn.internal == translatedBindName
    and controlsRow.txt.x + controlsRow.txt.width == controlsRow.btn.x - 10,
    "the Controls row refreshes its translation and stays aligned after a translation reload")
MainOptions.setKeybindDialog = { keybindName = controlsRow.btn.internal }
MainOptions.keyPressHandler(KEY_K, true, false, false)
assert(forwardedKey == KEY_K and forwardedShift == false and forwardedCtrl == false and forwardedAlt == false,
    "Controls capture stores only one key, without modifiers")
MainOptions.setKeybindDialog = nil

CookItForMe.setOpenPlanKey(KEY_K)
assert(option.key == KEY_K and saveCount == 1, "setting a new key updates and saves the shared option")
assert(CookItForMe.getOpenPlanKey() == KEY_K, "runtime reads key changes made through the Controls option")
assert(controlsRow.keyCode == KEY_K, "the plan window immediately updates the Controls row")
renderHandler()
assert(controlsRow.btn.title == "K", "the Controls button refreshes after a plan-window change")

keyHandler(KEY_K)
assert(openCount == 1, "the configured key opens the plan in single-player")
assert(openedPlayer == 0 and openedEntries[1].plan.id == "soup-plan" and openedEntries[2].plan == nil,
    "hotkey builds entries through the same plan builder")
assert(vehicleChecks == 0, "hotkey is independent of vehicle context")
assert(scanCount == 1 and collectCount == 1,
    "opening the catalog scans nearby squares and inventory once")
assert(plannedScans.Soup == plannedScans.Stew and plannedScans.Soup == plannedScans.Salad,
    "all dishes use the same nearby-world scan")
assert(plannedCollections.Soup == plannedCollections.Stew
    and #plannedCollections.Soup.foods == 1 and plannedCollections.Soup.foods[1] == rawFood
    and #plannedCollections.Salad.foods == 2 and plannedCollections.Salad.foods[2] == cookedFood,
    "hot dishes exclude cooked ingredients while salads may include them")

for _, modifier in ipairs({ KEY_LSHIFT, KEY_LCONTROL, KEY_LMENU }) do
    Keyboard.down = { [modifier] = true }
    keyHandler(KEY_K)
    assert(openCount == 1, "a modifier suppresses a single-key binding")
end
Keyboard.down = nil

local firstWindow = CookItForMe.planWindow
keyHandler(KEY_K)
assert(closeCount == 1 and CookItForMe.planWindow == nil and openCount == 1,
    "pressing the hotkey again closes the existing plan without rebuilding it")
keyHandler(KEY_K)
assert(openCount == 2 and CookItForMe.planWindow ~= firstWindow,
    "the hotkey can open a fresh plan after closing the previous one")

CookItForMePlanUI.keyCaptureActive = true
keyHandler(KEY_K)
assert(openCount == 2 and closeCount == 1 and CookItForMePlanUI.capturedKey == KEY_K,
    "key capture consumes the key without closing the plan")
CookItForMePlanUI.keyCaptureActive = false
CookItForMe.planWindow.keyConflictDialog = {}
keyHandler(KEY_K)
assert(closeCount == 1 and CookItForMe.planWindow.keyConflictDialog,
    "an open conflict dialog prevents the hotkey from closing the plan")
CookItForMe.planWindow.keyConflictDialog = nil

local captureHandler = CookItForMePlanUI.onPlanKeyCapturePressed
CookItForMePlanUI.onPlanKeyCapturePressed = nil -- an in-progress Forge Live reload may replace this dependency first
local captureDependencyOk = pcall(keyHandler, KEY_F8)
CookItForMePlanUI.onPlanKeyCapturePressed = captureHandler
assert(captureDependencyOk, "the key event tolerates a partially reloaded Plan UI module")

isClient = function() return true end
keyHandler(KEY_K)
assert(openCount == 2 and closeCount == 1, "the key handler is disabled in multiplayer")
isClient = function() return false end
isServer = function() return true end
keyHandler(KEY_K)
assert(openCount == 2 and closeCount == 1, "the key handler is disabled on a server")
isServer = function() return false end

players[0] = nil
keyHandler(KEY_K)
assert(openCount == 2 and closeCount == 1, "the key handler requires a game player")
players[0] = player

CookItForMe.planWindow:close()
local context = { options = {} }
function context:addOption(_, target, callback)
    self.options[#self.options + 1] = { target = target, callback = callback }
end
contextHandler(0, context, {}, false)
assert(#context.options == 1, "context-menu entry stays available beside a stove")
context.options[1].callback()
assert(openCount == 3 and openedPlayer == 0, "context menu and hotkey share the same opening entry")

controlsRow.keyCode = KEY_F8 -- vanilla MainOptions.keyPressHandler updates this row
modOptions:save() -- vanilla MainOptions:apply saves its linked Mod Options element
assert(option.key == KEY_F8 and CookItForMe.getOpenPlanKey() == KEY_F8,
    "a Controls change updates the same runtime Mod Options value")
controlsRow.keyCode = 0 -- vanilla Controls also offers Clear
modOptions:save()
assert(CookItForMe.getOpenPlanKey() == 0, "clearing in Controls leaves the hotkey unassigned")
keyHandler(KEY_F8)
assert(openCount == 3 and closeCount == 2, "a cleared Controls binding does not reactivate default F8")

print("PLAN HOTKEY TESTS PASSED")
