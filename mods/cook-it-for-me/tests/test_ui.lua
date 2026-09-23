package.path = "../42/media/lua/shared/?.lua;../42/media/lua/client/?.lua;./?.lua;" .. package.path
local Env = require "support/cook_env"
local e = Env.new()
package.loaded.CookItForMe_PlanUI = nil
CookItForMePlanUI = nil

local KEY_F8, KEY_ESCAPE, KEY_K, KEY_LSHIFT = 66, 1, 37, 42
Keyboard = {
    KEY_F8 = KEY_F8, KEY_ESCAPE = KEY_ESCAPE, KEY_K = KEY_K,
    KEY_LSHIFT = KEY_LSHIFT, KEY_RSHIFT = 54, KEY_LCONTROL = 29, KEY_RCONTROL = 157,
    KEY_LMENU = 56, KEY_RMENU = 184,
}
getKeyName = function(key) return key == KEY_F8 and "F8" or (key == KEY_K and "K" or "Unknown") end
getText = function(key, ...)
    if select("#", ...) > 0 then return key .. ":" .. table.concat({ ... }, ",") end
    return key
end
local activePlanKey, savedPlanKey = KEY_F8, nil
CookItForMe.getOpenPlanKey = function() return activePlanKey end
CookItForMe.setOpenPlanKey = function(key) activePlanKey, savedPlanKey = key, key; return true end
MainOptions = { keyText = {}, keys = {} }
PZAPI = { ModOptions = { Data = {} } }
local screenW, screenH, fontHeight = 900, 700, 18
local Base = {}
Base.__index = Base
function Base:derive() local c = {}; c.__index = c; return setmetatable(c, { __index = self }) end
function Base:new(x, y, w, h, text, target, callback)
    return setmetatable({ x = x, y = y, width = w, height = h, children = {}, options = {},
        text = text, target = target, callback = callback, anchorTop = true,
        backgroundColor = { a = 1 }, borderColor = { a = 1 }, enable = true }, self)
end
for _, name in ipairs({ "initialise", "instantiate", "setResizable", "enableAcceptColor", "enableCancelColor",
    "setVisible", "removeFromUIManager", "addScrollBars", "setStencilRect", "clearStencilRect", "drawRect", "drawRectBorder", "drawTextureScaled", "prerender", "createChildren" }) do
    Base[name] = function() end
end
function Base:addChild(child) self.children[#self.children + 1] = child end
function Base:instantiate()
    self.engineAnchorTop, self.engineAnchorBottom = self.anchorTop, self.anchorBottom
    self.javaObject = { setConsumeMouseEvents = function(javaObject, value) javaObject.consumesMouseEvents = value end }
end
function Base:addToUIManager() self:createChildren() end
function Base:titleBarHeight() return math.max(16, fontHeight + 1) end
function Base:resizeWidgetHeight() return (fontHeight + 6) / 2 + 2 end
function Base:setX(value) self.x = value end
function Base:setY(value) self.y = value end
function Base:setWidth(value) self.width = value end
function Base:setHeight(value) self.height = value end
function Base:setYScroll(value) self.scroll = value end
function Base:getYScroll() return self.scroll or 0 end
function Base:setScrollHeight(value) self.scrollHeight = value end
function Base:getScrollHeight() return self.scrollHeight or 0 end
function Base:setEnable(value) assert(type(value) == "boolean"); self.enable = value end
function Base:addOption(value) self.options[#self.options + 1] = value end
function Base:addOptionWithData(text, data) self.options[#self.options + 1] = { text = text, data = data } end
function Base:setSelected(index, value) if value == nil then self.selected = index else self.checked = value end end
function Base:setSelectedOption(value) for i, option in ipairs(self.options) do if option == value then self.selected = i end end end
function Base:setDisplayBackground() end
function Base:setAutoHideScrollbar() end
function Base:isMouseOver() return false end
function Base:updateTooltip() end
function Base:drawTextCentre() end
function Base:drawTextRight() end
function Base:getAbsoluteX() return self.x end
function Base:getAbsoluteY() return self.y end
function Base:addScrollChild(child) self:addChild(child) end
function Base:drawText(text, x) assert(x + #text * 6 <= self.width - 14, "wrapped content exceeds viewport") end
for _, name in ipairs({ "ISCollapsableWindow", "ISButton", "ISLabel", "ISComboBox", "ISSpinBox", "ISTickBox", "ISPanel" }) do
    _G[name] = Base:derive()
    package.loaded["ISUI/" .. name] = true
end
ISModalDialog = {}
function ISModalDialog.CalcSize(width, height) return width, height end
function ISModalDialog:new(x, y, width, height, text, yesno, target, onclick, player, param1, param2)
    local modal = { x = x, y = y, width = width, height = height, text = text, target = target,
        onclick = onclick, param1 = param1, param2 = param2 }
    function modal:initialise()
        self.yes = { internal = "YES", setTitle = function(button, title) button.title = title end }
        self.no = { internal = "NO", setTitle = function(button, title) button.title = title end }
    end
    function modal:addToUIManager() end
    function modal:setAlwaysOnTop() end
    function modal:destroy() self.destroyed = true end
    function modal:choose(internal)
        self.onclick(self.target, internal == "YES" and self.yes or self.no, self.param1, self.param2)
    end
    return modal
end
package.loaded["ISUI/ISModalDialog"] = true
-- ISButton does not expose ISPanel:drawText in the game.  Custom button
-- renderers must use its supported centred text API.
ISButton.drawText = false
package.loaded["neatui_framework/scrollview/niscrollbar"] = true
package.loaded["neatui_framework/scrollview/niscrollview"] = Base:derive()
package.loaded["neatui_framework/neattool/neattool_truncatetext"] = true
UIFont = { Small = 1 }
getSpecificPlayer = function() return e.player end
getCore = function() return {
    getScreenWidth = function() return screenW end,
    getScreenHeight = function() return screenH end,
    getKeyBinding = function() error("Core.KeyBinding is not accessible to Lua in Build 42.20.4") end,
} end
getTextManager = function() return { MeasureStringX = function(_, _, text) return #text * fontHeight / 3 end, getFontHeight = function() return fontHeight end } end
local settings = CookItForMe.getSettings(e.player)
assert(settings.finishCooking, "legacy settings enable finishing the dish by default")
settings.panelX, settings.panelY, settings.panelW, settings.panelH = nil, nil, nil, nil
screenW, screenH, fontHeight = 3840, 2160, 36
require "CookItForMe_PlanUI"
local entries = { { key = "Soup", failKey = "NoStove" }, { key = "Stew", failKey = "NoStove" },
    { key = "Stir fry", failKey = "NoStove" }, { key = "Roasted Vegetables", failKey = "NoStove" } }
local panel = CookItForMePlanUI:new(0, entries, 2)
panel:prerender()
assert(panel.width == 2080 and panel.height == 1280,
    "a fresh window scales with the effective PZ font size")
assert(panel.keybindButton.fullTitle == "F8"
    and panel.keybindButton.tooltip == "UI_CookItForMe_KeybindTooltip",
    "the plan UI displays the current Controls assignment")
assert(panel.cookButton.height == 60 and panel.tabButtons[1].height == 96,
    "fresh dashboard controls scale with the effective PZ font size")
assert(panel.x >= 0 and panel.y >= 0 and panel.x + panel.width <= screenW and panel.y + panel.height <= screenH)
assert(panel.activeIndex == 2 and panel.completionSoundTick.checked)
assert(panel.finishCookingButton and panel.finishCookingButton.tooltip == "UI_CookItForMe_SettingsFinishCookingTooltip",
    "the finish-cooking option exposes its explanation on hover")
assert(settings.finishCooking, "finish-cooking option is enabled by default")
assert(panel.finishCookingButton.y == panel.soundButton.y,
    "completion-sound and finish-cooking settings share one row")
assert(panel.soundButton.y == panel.radiusButtons[1].y
    and panel.soundButton.x >= panel.radiusButtons[3].x + panel.radiusButtons[3].width,
    "wide layouts place both settings beside the radius controls")
assert(panel.soundButton.x < panel.finishCookingButton.x
    and math.abs(panel.soundButton.width - panel.finishCookingButton.width) <= 1,
    "completion-sound and finish-cooking settings have equal half-widths")
assert(panel.content.y > panel.finishCookingButton.y + panel.finishCookingButton.height,
    "plan contents begin below the finish-cooking setting")

CookItForMePlanUI.onPlanKeyButton(panel)
assert(CookItForMePlanUI.isCapturingPlanKey(), "clicking the displayed key starts capture")
assert(panel.keybindButton.fullTitle == "..."
    and panel.keybindButton.tooltip == "UI_CookItForMe_KeybindCapture",
    "capture keeps the button compact and explains how to cancel")
CookItForMePlanUI.onPlanKeyCapturePressed(KEY_LSHIFT)
assert(CookItForMePlanUI.isCapturingPlanKey() and activePlanKey == KEY_F8,
    "modifier keys are ignored during capture")
CookItForMePlanUI.onPlanKeyCapturePressed(KEY_ESCAPE)
assert(not CookItForMePlanUI.isCapturingPlanKey() and activePlanKey == KEY_F8 and savedPlanKey == nil,
    "Escape cancels capture without changing or saving the assignment")

CookItForMePlanUI.onPlanKeyButton(panel)
CookItForMePlanUI.onPlanKeyCapturePressed(KEY_K)
assert(activePlanKey == KEY_K and savedPlanKey == KEY_K,
    "a free key immediately updates and saves the shared binding")

activePlanKey = KEY_F8 -- simulate a Controls change while this window is open
panel:prerender()
assert(panel.keybindButton.fullTitle == "F8",
    "the plan UI refreshes its key label from the shared option")

MainOptions.keyText = { {
    keyCode = KEY_F8, shift = false, ctrl = false, alt = false,
    txt = { getName = function() return "Vanilla F8 action" end },
} }
MainOptions.keys = { { key = KEY_F8, value = "VanillaF8Action", shift = false, ctrl = false, alt = false } }
local otherModKey = { type = "keybind", name = "UI_Test_OtherModKey", getValue = function() return KEY_F8 end }
PZAPI.ModOptions.Data = { { data = { otherModKey } } }
activePlanKey = KEY_K
local savesBeforeConflict = savedPlanKey
CookItForMePlanUI.onPlanKeyButton(panel)
CookItForMePlanUI.onPlanKeyCapturePressed(KEY_F8)
local keyConflictDialog = panel.keyConflictDialog
assert(keyConflictDialog and activePlanKey == KEY_K and savedPlanKey == savesBeforeConflict,
    "a conflicting candidate waits for the player's choice before saving")
assert(panel.keyConflictCover and panel.keyConflictCover.javaObject.consumesMouseEvents,
    "the conflict warning blocks clicks on the plan behind it")
assert(type(keyConflictDialog.text) == "string", "dialog body is text: " .. tostring(keyConflictDialog.text))
assert(keyConflictDialog.text:find("Vanilla F8 action", 1, true)
    and keyConflictDialog.text:find("UI_Test_OtherModKey", 1, true),
    "the custom warning identifies vanilla and other-mod assignments")
assert(keyConflictDialog.yes.title == "UI_CookItForMe_KeybindKeepBoth"
    and keyConflictDialog.no.title == "UI_Cancel", "the warning offers Keep both and Cancel")
keyConflictDialog:choose("NO")
assert(activePlanKey == KEY_K and savedPlanKey == savesBeforeConflict,
    "canceling a key conflict preserves the old assignment")

CookItForMePlanUI.onPlanKeyButton(panel)
CookItForMePlanUI.onPlanKeyCapturePressed(KEY_F8)
panel.keyConflictDialog:choose("YES")
assert(activePlanKey == KEY_F8 and savedPlanKey == KEY_F8,
    "choosing Keep both commits and saves the conflicting key")
CookItForMePlanUI.onFinishCookingButton({ player = 0, rebuild = function() end })
assert(not settings.finishCooking, "finish-cooking choice is persisted")
assert(panel.dishRail and panel.summaryCard and panel.content.isNeatScrollView,
    "plan UI must expose the NeatUI dashboard layout")
panel.tabButtons[1]:prerender()
panel.radiusButtons[1]:prerender(); panel.radiusButtons[3]:prerender()
assert(panel.cookButton.engineAnchorTop == false and panel.cookButton.engineAnchorBottom == true,
    "footer anchors must reach the engine before resizing")
CookItForMePlanUI.onCompletionSoundChange(panel, 1, false)
CookItForMe.planWindow = nil
settings.panelW, settings.panelH, settings.panelX, settings.panelY = nil, nil, nil, nil
screenW, screenH, fontHeight = 1920, 1080, 18
local fullHdPanel = CookItForMePlanUI:new(0, entries, 2)
assert(fullHdPanel.width == 1040 and fullHdPanel.height == 640,
    "a standard Full HD setup keeps the established window size")
CookItForMe.planWindow = nil
settings.panelW, settings.panelH, settings.panelX, settings.panelY = nil, nil, nil, nil
screenW, screenH, fontHeight = 1920, 1080, 36
local cappedPanel = CookItForMePlanUI:new(0, entries, 2)
assert(cappedPanel.width == 1580 and cappedPanel.height == 972,
    "large-font defaults stay within the 90 percent screen margin on Full HD")
assert(cappedPanel.cookButton.height == 46,
    "Full HD controls scale only as far as the available screen allows")
CookItForMe.planWindow = nil
screenW, screenH, fontHeight = 900, 700, 18
settings.panelX, settings.panelY, settings.panelW, settings.panelH = 3000, -30, 850, 600
panel = CookItForMePlanUI:new(0, entries, 2)
assert(panel.width == 850 and panel.height == 600, "saved window dimensions override defaults")
assert(not panel.completionSoundTick.checked, "checkbox survives reopening")
assert(not CookItForMe.getSettings(e.player).finishCooking, "finish-cooking choice survives reopening")
panel.width = 560; panel.height = 460; panel.content.width = 544
panel:prerender()
assert(panel.finishCookingButton.y == panel.soundButton.y,
    "compact layout keeps both settings on one row")
local persisted = CookItForMe.getSettings(e.player)
assert(persisted.panelW == 560 and persisted.panelH == 460, "resized panel dimensions persist before closing")
assert(panel.content.y > panel.completionSoundTick.y + 24 and panel.content.height > 0)
assert(panel.soundButton.y >= panel.radiusButtons[1].y + panel.radiusButtons[1].height + 8,
    "compact settings put both controls below radius")
assert(panel.soundButton.x >= panel.content.x and panel.soundButton.x + panel.soundButton.width <= panel.content.x + panel.content.width,
    "compact sound control stays inside the content column")
assert(panel.tabButtons[1].y >= panel:titleBarHeight() + 12 + 50,
    "dish cards must leave a full line below the rail heading")
assert(panel.strategyButtons[1].y >= panel.summaryCard.y + panel.summaryCard.height + 10 + 44,
    "strategy controls must leave a full line below the settings heading")
for _, size in ipairs({ { 900, 700 }, { 560, 460 }, { 800, 600 }, { 560, 460 } }) do
    panel.width, panel.height = size[1], size[2]
    panel:prerender()
    for _, b in ipairs({ panel.cookButton, panel.closeButton }) do
        assert(b.y + b.height < panel.height - panel:resizeWidgetHeight(), "footer stays inside window")
        assert(panel.content.y + panel.content.height < b.y, "content does not cover footer")
    end
    assert(panel.content.width > 200 and panel.content.width < panel.width - 16,
        "dashboard keeps the recipe viewport beside the dish rail")
end
for _, button in ipairs(panel.tabButtons) do
    assert(button.x < panel.content.x and button.y + button.height < panel.cookButton.y,
        "dish cards stay in the left navigation rail")
end
panel.lines = { { kind = "text", text = string.rep("longword", 30) } }
panel.content:prerender()
assert(panel.content:getScrollHeight() > 24)
local previous = panel
panel = CookItForMePlanUI:new(0, entries, 2)
assert(CookItForMe.planWindow == panel and panel ~= previous)
panel:prerender()
assert(panel.cookButton.enable == false and panel.cancelButton == nil)
local function hasColor(draws, hex)
    local r, g, b = math.floor(hex / 65536) / 255, math.floor(hex / 256) % 256 / 255, hex % 256 / 255
    for _, draw in ipairs(draws) do
        if math.abs(draw[1] - r) < 0.001 and math.abs(draw[2] - g) < 0.001 and math.abs(draw[3] - b) < 0.001 then
            return true
        end
    end
    return false
end
local buttonFills = {}
panel.cookButton.drawRect = function(_, x, y, width, height, alpha, r, g, b)
    if x == 1 and y == 1 then buttonFills[#buttonFills + 1] = { r, g, b } end
end
panel.cookButton:prerender()
assert(hasColor(buttonFills, 0xB85C55), "unavailable Cook action has an error fill")
buttonFills = {}
panel.cookButton:setEnable(true)
panel.cookButton:prerender()
assert(hasColor(buttonFills, 0x6FA36F), "available Cook action has a success fill")
local frozenMarks = {}
panel.lines = { { kind = "item", text = "Frozen ingredient", frozen = true } }
panel.details.drawRect = function(_, x, y, width, height, alpha, r, g, b)
    if width == 3 then frozenMarks[#frozenMarks + 1] = { r, g, b } end
end
panel.details:prerender()
assert(hasColor(frozenMarks, 0x7098B8), "frozen ingredients have a blue left marker")
local canceledCooking = false
local originalCancel = CookItForMe.Cook.cancel
CookItForMe.Cook.cancel = function() canceledCooking = true end
panel:close()
CookItForMe.Cook.cancel = originalCancel
assert(CookItForMe.planWindow == nil and not canceledCooking,
    "closing the plan clears the window without cancelling an active cooking session")
local staleWindow = setmetatable({ isCollapsed = false }, CookItForMePlanUI)
assert(pcall(function() staleWindow:prerender() end), "hot-reloaded renderer must tolerate an old open window")
for _, name in ipairs({ "ISCollapsableWindow", "ISButton", "ISLabel", "ISComboBox", "ISSpinBox", "ISTickBox", "ISPanel" }) do package.loaded["ISUI/" .. name] = nil end
print("UI STATE AND LAYOUT TESTS PASSED")
