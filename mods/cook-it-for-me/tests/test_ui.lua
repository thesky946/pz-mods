package.path = "../42/media/lua/shared/?.lua;../42/media/lua/client/?.lua;./?.lua;" .. package.path
local Env = require "support/cook_env"
local Catalog = require "CookItForMe_Dishes"
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
        text = text, title = text, target = target, callback = callback, anchorTop = true,
        backgroundColor = { a = 1 }, borderColor = { a = 1 }, enable = true }, self)
end
for _, name in ipairs({ "initialise", "instantiate", "setResizable", "enableAcceptColor", "enableCancelColor",
    "setVisible", "removeFromUIManager", "addScrollBars", "setStencilRect", "clearStencilRect", "drawRect", "drawRectBorder", "drawTextureScaled", "prerender", "createChildren" }) do
    Base[name] = function() end
end
function Base:addChild(child) child.parent = self; self.children[#self.children + 1] = child end
function Base:setResizable(value) self.resizable = value end
function Base:instantiate()
    self.engineAnchorTop, self.engineAnchorBottom = self.anchorTop, self.anchorBottom
    self.javaObject = { setConsumeMouseEvents = function(javaObject, value) javaObject.consumesMouseEvents = value end }
end
function Base:addToUIManager() self.onManager = true; self:createChildren() end
function Base:removeFromUIManager() self.onManager = false end
function Base:titleBarHeight() return math.max(16, fontHeight + 1) end
function Base:resizeWidgetHeight() return (fontHeight + 6) / 2 + 2 end
function Base:setX(value) self.x = value end
function Base:setY(value) self.y = value end
function Base:setWidth(value) self.width = value end
function Base:setHeight(value) self.height = value end
function Base:setYScroll(value) self.scroll = value end
function Base:setVisible(value) self.visible = value end
function Base:bringToTop() end
function Base:setAlwaysOnTop(value) self.alwaysOnTop = value end
function Base:setText(value) self.text = value end
function Base:getText() return self.text end
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
for _, name in ipairs({ "ISCollapsableWindow", "ISButton", "ISLabel", "ISComboBox", "ISSpinBox", "ISTickBox", "ISPanel", "ISTextEntryBox" }) do
    _G[name] = Base:derive()
    package.loaded["ISUI/" .. name] = true
end
ISComboBox.setEnable = false -- the installed B42 combo has no setEnable method
function ISTextEntryBox:new(text, x, y, width, height)
    return Base.new(self, x, y, width, height, text)
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
NeatTool = { truncateText = function(value, width) return value:sub(1, math.floor(width / 6)) end }
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
settings.pickerW, settings.pickerH = nil, nil
screenW, screenH, fontHeight = 3840, 2160, 36
require "CookItForMe_PlanUI"
local entries = { { key = "Soup", failKey = "NoStove" }, { key = "Stew", failKey = "NoStove" },
    { key = "Stir fry", failKey = "NoStove" }, { key = "Roasted Vegetables", failKey = "NoStove" } }
local panel = CookItForMePlanUI:new(0, entries, 2)
panel:prerender()
assert(panel.ingredientSort.key == "hunger" and panel.ingredientSort.descending
    and panel.pickerSort.key == "hunger" and panel.pickerSort.descending,
    "new players see highest hunger relief first in both tables")
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
assert(panel.dishNav.y >= panel:titleBarHeight() + 12 + 44 and panel.tabButtons[1].y == 0,
    "scrolling dish cards start below the rail heading")
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
    assert(button.parent == panel.dishNav and panel.dishNav.x + button.x < panel.content.x,
        "dish cards stay in the scrolling left navigation rail")
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
local cookTextColor
panel.cookButton.drawTextCentre = function(_, title, x, y, r, g, b)
    cookTextColor = { r, g, b }
end
panel.cookButton:prerender()
assert(hasColor(buttonFills, 0x6FA36F), "available Cook action has a success fill")
assert(cookTextColor and hasColor({ cookTextColor }, 0xF0ECE4),
    "available Cook action keeps its light label on the green button")
local plan = assert(e.cook.plan(e.player, "Soup"))
panel.entries[2].plan = plan
panel:refreshIngredients()
panel.details:prerender()
local emptyRow = panel.rowWidgets["Stew:" .. plan.rows[2].id]
assert(emptyRow and emptyRow.data.empty and emptyRow.nameButton.rowId == plan.rows[2].id,
    "unfilled recipe capacity appears as clickable rows with stable plan IDs")
emptyRow:prerender()
assert(emptyRow.nameButton.enable and emptyRow.replaceButton.visible == false
    and emptyRow.removeButton.visible == false,
    "an empty slot has one clear add action and no removal controls")
emptyRow.nameButton.callback(panel, emptyRow.nameButton)
assert(panel.pickerVisible and panel.pickerRowId == plan.rows[2].id
    and panel.pickerTitle == getText("UI_CookItForMe_AddFoodTitle"),
    "clicking an empty main slot opens the existing compatible-item picker")
assert(panel.picker.onManager and panel.picker.parent == nil and panel.picker.moveWithMouse
    and panel.picker.alwaysOnTop and panel.picker.keepOnScreen,
    "the picker is a movable top-level window above the ingredient table")
assert(panel.pickerScroll.y + panel.pickerScroll.height < panel.pickerCancel.y
    and panel.pickerCancel.y + panel.pickerCancel.height < panel.picker.height,
    "search results and Close fit inside the picker")
local pickerX, pickerY = panel.picker.x + 15, panel.picker.y + 10
panel.picker:setX(pickerX); panel.picker:setY(pickerY)
panel:prerender()
assert(panel.picker.x == pickerX and panel.picker.y == pickerY,
    "the main window does not snap a dragged picker back to its original position")
assert(panel.pickerEmpty and panel.pickerEmptyText == "UI_CookItForMe_NoAdditions",
    "an unfillable slot explains why no item can be added")
local openPicker = panel.picker
openPicker:close()
assert(not openPicker.onManager and not panel.pickerVisible,
    "the picker title-bar close button removes its independent window")
local foodRow = panel.rowWidgets["Stew:1"]
assert(foodRow and foodRow.removeButton.rowId == plan.rows[1].id,
    "ingredient actions keep the plan row ID")
foodRow:prerender()
assert(foodRow.replaceButton.width > 0 and foodRow.removeButton.x > foodRow.replaceButton.x,
    "ingredient controls occupy stable columns")
assert(foodRow.removeButton.width >= foodRow.removeButton.height,
    "the remove control has a comfortable square click target")
local iconParts = 0
foodRow.replaceButton.drawRect = function(b, x, y, width, height, alpha)
    if width <= b.width * .6 and height <= b.height * .25 and alpha >= .5 then
        assert(x >= 0 and y >= 0 and x + width <= b.width and y + height <= b.height,
            "swap icon stays inside its button")
        iconParts = iconParts + 1
    end
end
foodRow.replaceButton.drawTextCentre = function() error("Replace must render an icon instead of a text label") end
foodRow.replaceButton:prerender()
assert(iconParts >= 6 and foodRow.replaceButton.tooltip == getText("UI_CookItForMe_ReplaceTitle", foodRow.data.name),
    "the swap icon uses visible filled shapes and keeps its localized tooltip")
foodRow.replaceButton.drawRect = nil
foodRow.replaceButton.drawTextCentre = nil
local metrics = {}
foodRow.drawTextRight = function(_, value) metrics[#metrics + 1] = value end
local savedRowWidth = foodRow.width
foodRow:setWidth(2200)
foodRow:prerender()
assert(foodRow.removeButton.text == "x" and #metrics == 2
    and metrics[1] == tostring(foodRow.data.calories) and metrics[2] == "10",
    "the row shows calorie and hunger contributions from the selected ingredient")
local headers = {}
panel.tableHeader:setWidth(2200)
panel.tableHeader.drawText = function(_, value) headers[#headers + 1] = value end
panel.tableHeader.drawTextRight = function(_, value) headers[#headers + 1] = value end
panel.tableHeader:prerender()
assert(#headers == 4 and headers[1] == "UI_CookItForMe_Ingredient"
    and headers[2] == "UI_CookItForMe_CalInDish" and headers[3] == "UI_CookItForMe_HungerInDish"
    and headers[4] == "UI_CookItForMe_Actions",
    "the ingredient table labels both nutrition contributions")
local originalRows = plan.rows
local alpha = Env.item("Base.Carrot", 10)
alpha.hunger = -0.05
alpha.getDisplayName = function() return "Alpha" end
local zulu = Env.item("Base.Carrot", 100)
zulu.hunger = -0.3
zulu.getDisplayName = function() return "Zulu" end
local spiceA = Env.item("Base.Salt", 0)
spiceA.spice = true
spiceA.getDisplayName = function() return "A spice" end
local spiceZ = Env.item("Base.Salt", 0)
spiceZ.spice = true
spiceZ.getDisplayName = function() return "Z spice" end
plan.rows = {
    { id = 102, kind = "food", item = zulu }, { id = 103, kind = "food" },
    { id = 101, kind = "food", item = alpha },
    { id = 202, kind = "spice", item = spiceZ }, { id = 201, kind = "spice", item = spiceA },
}
panel:refreshIngredients()
assert(panel.lines[2].id == 102 and panel.lines[3].id == 101 and panel.lines[4].id == 103,
    "new plans show highest hunger relief first and empty slots last: "
        .. tostring(panel.lines[2].id) .. "/" .. tostring(panel.lines[3].id) .. "/" .. tostring(panel.lines[4].id))
local sortButtons = panel.ingredientSortButtons
assert(sortButtons and sortButtons.name and sortButtons.calories and sortButtons.hunger,
    "all three plan table headings are clickable")
panel.tableHeader:prerender()
assert(sortButtons.name.width > 0 and sortButtons.calories.x >= sortButtons.name.width
    and sortButtons.hunger.x >= sortButtons.calories.x + sortButtons.calories.width,
    "plan sort hit areas follow their visible header columns")
sortButtons.name.callback(panel, sortButtons.name)
assert(settings.ingredientSortKey == "name" and not settings.ingredientSortDescending,
    "plan sorting is saved per player")
assert(panel.lines[2].id == 101 and panel.lines[3].id == 102 and panel.lines[4].id == 103
    and panel.lines[5].kind == "group" and panel.lines[6].id == 201,
    "first name click sorts alphabetically inside each group and leaves empty slots last")
sortButtons.name.callback(panel, sortButtons.name)
assert(panel.lines[2].id == 102 and panel.lines[3].id == 101 and panel.lines[4].id == 103,
    "a second click reverses plan name sorting")
sortButtons.calories.callback(panel, sortButtons.calories)
assert(panel.lines[2].id == 102 and panel.lines[3].id == 101,
    "first calorie click shows the largest contribution first")
assert(panel.rowWidgets["Stew:102"].data.id == 102 and panel.rowWidgets["Stew:102"].removeButton.rowId == 102,
    "sorting does not change the row targeted by ingredient actions")
sortButtons.calories.callback(panel, sortButtons.calories)
assert(panel.lines[2].id == 101 and panel.lines[3].id == 102,
    "a second calorie click shows the smallest contribution first")
sortButtons.hunger.callback(panel, sortButtons.hunger)
assert(panel.lines[2].id == 102 and panel.lines[3].id == 101,
    "hunger sort uses the contribution rather than whole-item calories")
plan.rows = originalRows
panel.ingredientSort = { key = "hunger", descending = true }
settings.ingredientSortKey, settings.ingredientSortDescending = nil, nil
panel:refreshIngredients()
foodRow:setWidth(savedRowWidth)
foodRow:prerender()
assert(foodRow.removeButton.x + foodRow.removeButton.width <= foodRow.width,
    "actions stay inside a compact row")
foodRow:setWidth(480)
foodRow:prerender()
local actionLeft = foodRow.replaceButton.x
local compactLines = {}
foodRow.drawText = function(_, value, x, y)
    assert(x + #value * 6 < actionLeft, "compact row text stays clear of its actions")
    compactLines[y] = true
end
local savedDetailsWidth = panel.details.width
panel.details:setWidth(480 + 28)
panel.details:prerender()
foodRow:prerender()
local lineCount = 0
for _ in pairs(compactLines) do lineCount = lineCount + 1 end
assert(foodRow.height >= fontHeight * 3 + 14 and lineCount >= 3,
    "compact rows make room for name, calories and hunger without hiding a metric")
foodRow.drawText = nil
panel.details:setWidth(savedDetailsWidth)
panel.details:prerender()
foodRow:setWidth(savedRowWidth)
local ingredientHeadingDrawn = false
local originalDrawText = panel.drawText
panel.drawText = function(self, value, x, y, ...)
    if value == "UI_CookItForMe_PlanIngredients" then ingredientHeadingDrawn = true end
    return originalDrawText(self, value, x, y, ...)
end
fontHeight = 36
panel:prerender()
assert(not ingredientHeadingDrawn, "the table needs no redundant Ingredients heading")
local plainHeaderY = panel.tableHeader.y
panel.notice = { text = "temporary notice" }
panel:prerender()
assert(panel.tableHeader.y == plainHeaderY,
    "showing a notice does not move the table")
panel.notice = nil
panel:prerender()
assert(panel.tableHeader.y == plainHeaderY,
    "hiding a notice does not move the table")
panel.details:prerender()
foodRow:prerender()
assert(foodRow.height >= fontHeight + 10 and foodRow.replaceButton.height >= fontHeight + 6,
    "rows and actions grow with the current game font")
fontHeight = 18
panel.drawText = originalDrawText
local originalGetText = getText
getText = function(key, ...)
    if key == "UI_CookItForMe_Unavailable" then return "unavailable" end
    return originalGetText(key, ...)
end
e.food.frozen = true
panel:refreshIngredients()
foodRow:setWidth(2200)
local states = {}
foodRow.drawText = function(_, value) states[#states + 1] = value end
local originalGetTexture = getTexture
getTexture = function(path)
    if path == "media/ui/icon_frozen.png" then return "frozen texture" end
    return originalGetTexture and originalGetTexture(path) or nil
end
local snowflakes = {}
foodRow.drawTextureScaled = function(_, texture, x, y, width, height, alpha, red, green, blue)
    if texture == "frozen texture" then snowflakes[#snowflakes + 1] = { x, y, width, height, red, green, blue } end
end
panel.rowStatus = { [plan.rows[1].id] = true }
foodRow:prerender()
assert(#snowflakes == 1 and snowflakes[1][1] > 0 and snowflakes[1][5] < snowflakes[1][7],
    "frozen food has a blue snowflake beside its name")
assert(not table.concat(states, " "):find("available", 1, true),
    "available food has no redundant status label")
assert(foodRow.nameButton.tooltip:find("UI_CookItForMe_Frozen", 1, true),
    "the snowflake meaning is available in the name tooltip")
local previousDrawText, previousDrawTexture = foodRow.drawText, foodRow.drawTextureScaled
local iconPositions, nameY = {}, nil
foodRow.data.tex = "item texture"
foodRow.drawText = function(_, value, x, y)
    if value == foodRow.data.name then nameY = y end
end
foodRow.drawTextureScaled = function(_, texture, x, y, width, height)
    iconPositions[texture] = y + height / 2
end
fontHeight = 36
panel.details:prerender()
foodRow:setWidth(2200)
foodRow:prerender()
local nameCenter = nameY and nameY + fontHeight / 2
assert(nameCenter and math.abs(iconPositions["item texture"] - nameCenter) <= 1
    and math.abs(iconPositions["frozen texture"] - nameCenter) <= 1,
    "item icon, snowflake and ingredient name share one vertical centre")
assert(math.abs(foodRow.replaceButton.y + foodRow.replaceButton.height / 2 - foodRow.height / 2) <= 1
    and math.abs(foodRow.removeButton.y + foodRow.removeButton.height / 2 - foodRow.height / 2) <= 1,
    "both ingredient actions remain vertically centred as row height changes")
fontHeight = 18
foodRow.data.tex = nil
foodRow.drawText, foodRow.drawTextureScaled = previousDrawText, previousDrawTexture
panel.details:prerender()
states = {}
panel.rowStatus[plan.rows[1].id] = false
foodRow:prerender()
assert(table.concat(states, " "):find("unavailable", 1, true),
    "a planned item that disappears still has a visible warning")
e.food.frozen = false
snowflakes = {}
foodRow:prerender()
assert(#snowflakes == 0, "the snowflake disappears when the item thaws without rebuilding the plan")
getTexture = originalGetTexture
getText = originalGetText
panel:refreshIngredients()
panel.details:prerender()
foodRow:prerender()
panel:onReplaceIngredient(foodRow.replaceButton)
assert(panel.pickerVisible and panel.pickerEmpty and panel.pickerRowId == plan.rows[1].id,
    "replacement picker explains that no alternatives exist")
assert(panel.picker.width == 860 and panel.picker.height == 560
    and settings.pickerW == nil and settings.pickerH == nil,
    "the first picker opens larger without treating its default as a saved user size")
panel:closePicker()
assert(settings.pickerW == nil and settings.pickerH == nil,
    "closing an untouched picker does not mark the default size as a user preference")
panel:onReplaceIngredient(foodRow.replaceButton)
assert(panel.pickerSearch.height == 24 and panel.pickerCancel.height == 24,
    "search and Close use compact single-line heights: " .. tostring(panel.pickerSearch.height)
        .. "/" .. tostring(panel.pickerCancel.height) .. " font=" .. tostring(fontHeight))
assert(panel.picker.resizable and panel.picker.minimumWidth and panel.picker.minimumHeight,
    "the replacement picker can be resized with a bounded minimum size")
panel.picker:setWidth(panel.picker.width + 180)
panel.picker:setHeight(panel.picker.height + 120)
panel.picker:prerender()
assert(panel.pickerSearch.width == panel.pickerScroll.width
    and panel.pickerScroll.width == panel.picker.width - panel.pickerScroll.x * 2
    and panel.pickerCancel.y + panel.pickerCancel.height < panel.picker.height,
    "resizing keeps search, results, and Close inside the picker")
assert(panel.pickerCancel.x + panel.pickerCancel.width == panel.picker.width - panel.pickerScroll.x
    and panel.pickerCancel.width >= getTextManager():MeasureStringX(UIFont.Small, panel.pickerCancel.fullTitle) + fontHeight,
    "Close is wide enough for its label and stays aligned to the picker right edge")
assert(panel.pickerHeader and panel.pickerFooter
    and panel.pickerScroll.y >= panel.pickerHeader.y + panel.pickerHeader.height
    and panel.pickerScroll.y + panel.pickerScroll.height < panel.pickerFooter.y
    and panel.pickerCancel.y >= panel.pickerFooter.y,
    "picker table scrolls between a fixed header and a separate Close footer")
assert(panel.pickerCancel.title == "" and panel.pickerCancel.fullTitle == "UI_CookItForMe_SettingsClose",
    "Close text is drawn once by the themed button")
panel.picker:setWidth(panel.picker.minimumWidth)
panel.picker:setHeight(panel.picker.minimumHeight)
panel.picker:prerender()
assert(panel.pickerScroll.height > 0
    and panel.pickerScroll.y + panel.pickerScroll.height < panel.pickerFooter.y,
    "the scrollable table does not cover Close at the minimum window size")
panel.picker:setWidth(760)
panel.picker:setHeight(520)
panel.picker:prerender()
panel:closePicker()
assert(settings.pickerW == 760 and settings.pickerH == 520,
    "closing a manually resized picker saves its last dimensions")
panel:onRemoveIngredient(foodRow.removeButton)
assert(#plan.picked.items == 0 and panel.notice and panel.notice.removal.item == e.food,
    "remove action targets the displayed physical item")
assert(plan.rows[1].item == nil and panel.rowWidgets["Stew:1"].data.empty,
    "removing a visible item leaves a clickable slot at the same row ID")
panel:prerender()
assert(panel.resetButton.title == "" and panel.noticeButton.title == ""
    and panel.cookButton.title == "" and panel.closeButton.title == "",
    "themed buttons suppress the vanilla title so labels are drawn only once")
assert(foodRow.removeButton.title == "", "the remove action suppresses the vanilla x glyph")
assert(panel.cookButton.enable == false and panel.cookButton.tooltip == "UI_CookItForMe_NotEnough",
    "empty edited plan disables Cook with a reason")
panel:onUndoIngredient()
assert(#plan.picked.items == 1 and not panel.notice, "undo restores the selected row")
panel:prerender()
assert(panel.resetButton.visible == false, "Reset edits disappears after undo restores the automatic plan")
local alternative = e.source:AddItem(Env.item("Base.Carrot", 20))
alternative.getDisplayName = function() return string.char(0xD0,0x9C,0xD0,0x9E,0xD0,0xA0,0xD0,0x9A,0xD0,0x9E,0xD0,0x92,0xD0,0xAC) end
e.collected.foods[#e.collected.foods + 1] = alternative
local apple = e.source:AddItem(Env.item("Base.Carrot", 5))
apple.hunger = -0.2
apple.getDisplayName = function() return "Apple" end
e.collected.foods[#e.collected.foods + 1] = apple
local banana = e.source:AddItem(Env.item("Base.Carrot", 80))
banana.hunger = -0.05
banana.getDisplayName = function() return "Banana" end
e.collected.foods[#e.collected.foods + 1] = banana
panel:onReplaceIngredient(foodRow.replaceButton)
assert(panel.picker.width == 760 and panel.picker.height == 520,
    "the next picker restores the last user-sized dimensions")
assert(panel.pickerButtons[1].item == apple,
    "an untouched replacement table shows the strongest hunger relief first")
local pickerSort = panel.picker.sortButtons
assert(pickerSort and pickerSort.name and pickerSort.calories and pickerSort.hunger,
    "all three alternative table headings are clickable")
panel.pickerHeader:prerender()
assert(pickerSort.name.width > 0 and pickerSort.calories.x >= pickerSort.name.width
    and pickerSort.hunger.x >= pickerSort.calories.x + pickerSort.calories.width,
    "picker sort hit areas follow their visible header columns")
pickerSort.name.callback(panel, pickerSort.name)
assert(panel.pickerButtons[1].item == apple, "first name click sorts alternatives alphabetically")
pickerSort.name.callback(panel, pickerSort.name)
assert(panel.pickerButtons[1].item ~= apple, "second name click reverses alphabetical sorting")
pickerSort.calories.callback(panel, pickerSort.calories)
assert(panel.pickerButtons[1].item == banana, "alternatives sort by calorie contribution")
pickerSort.calories.callback(panel, pickerSort.calories)
assert(panel.pickerButtons[1].item == apple, "a second calorie click reverses alternative ordering")
pickerSort.hunger.callback(panel, pickerSort.hunger)
assert(settings.pickerSortKey == "hunger" and settings.pickerSortDescending,
    "replacement sorting is saved separately from plan sorting")
assert(panel.pickerButtons[1].item == apple, "alternatives sort by hunger contribution")
panel:closePicker()
panel:onReplaceIngredient(foodRow.replaceButton)
assert(panel.pickerSort.key == "hunger" and panel.pickerSort.descending
    and panel.pickerButtons[1].item == apple,
    "reopened replacement table keeps the chosen sorting")
panel.pickerSearch:setText(string.char(0xD0,0xBC,0xD0,0xBE,0xD1,0x80,0xD0,0xBA,0xD0,0xBE,0xD0,0xB2,0xD1,0x8C))
panel.pickerSearch.onTextChange()
assert(not panel.pickerEmpty and panel.pickerButtons[1].item == alternative,
    "search matches Cyrillic names without case sensitivity")
assert(panel.pickerButtons[1].parent == panel.pickerList and panel.pickerButtons[1].visible,
    "available alternatives are visible buttons inside the picker list")
local option = panel.pickerButtons[1]
assert(option.calories ~= nil and option.hunger ~= nil,
    "picker calculates each alternative's calorie and hunger contribution")
local rightText = {}
local nameLeft
option.drawTextRight = function(_, value) rightText[#rightText + 1] = value end
option.drawTextCentre = function(_, value, x)
    if value == option.fullTitle then
        nameLeft = x - getTextManager():MeasureStringX(UIFont.Small, value) / 2
    end
end
option:prerender()
assert(#rightText == 2 and rightText[1] == tostring(option.calories)
    and rightText[2] == tostring(option.hunger),
    "picker renders separate right-aligned calorie and hunger cells")
assert(nameLeft == 8, "candidate names start at the left edge of the name column")
panel.pickerButtons[1].callback(panel, panel.pickerButtons[1])
assert(plan.rows[1].item == alternative and not panel.pickerVisible,
    "picker changes the displayed plan row")
e.collected.foods = { e.food, alternative }
panel:onRemoveIngredient(foodRow.removeButton)
panel:onResetIngredients()
assert(#plan.picked.items == 2 and not plan.edited, "reset restores automatic selection from current food")
panel:onRemoveIngredient(panel.rowWidgets["Stew:1"].removeButton)
local editedPlan = plan
panel:rebuild()
panel = CookItForMe.planWindow
assert(panel.entries[2].plan == editedPlan and editedPlan.edited and #editedPlan.picked.items == 1,
    "settings rebuild keeps the manually edited composition until the window closes")
e.recipe.getUntranslatedName = function() return "Stew" end
panel:onStrategyButton(panel.strategyButtons[2])
panel = CookItForMe.planWindow
local strategyPlan = assert(panel.entries[2].plan)
assert(strategyPlan ~= editedPlan and strategyPlan.direction == "min"
    and not strategyPlan.edited and #strategyPlan.picked.items == 2
    and strategyPlan.picked.items[1] == alternative,
    "changing strategy discards manual edits and rebuilds the whole ingredient plan")
panel:prerender()
assert(panel.resetButton.visible == false,
    "a fresh strategy plan does not offer Reset edits")
panel.ingredientSortButtons.calories.callback(panel, panel.ingredientSortButtons.calories)
assert(settings.ingredientSortKey == "calories" and settings.ingredientSortDescending,
    "plan calorie order is saved before reopening")
panel:rebuild()
panel = CookItForMe.planWindow
assert(panel.ingredientSort.key == "calories" and panel.ingredientSort.descending
    and panel.pickerSort.key == "hunger" and panel.pickerSort.descending,
    "both saved table sorts survive reopening the plan window")
local failedWindow = panel
local failedPlan = panel.entries[panel.activeIndex].plan
local originalStart = CookItForMe.Cook.start
CookItForMe.Cook.start = function() return false, "ActionFailed" end
panel:onCook()
CookItForMe.Cook.start = originalStart
panel = CookItForMe.planWindow
assert(panel and panel ~= failedWindow and panel.entries[panel.activeIndex].plan ~= failedPlan,
    "failed start rebuilds a fresh plan so the player can cook again")
local canceledCooking = false
local originalCancel = CookItForMe.Cook.cancel
CookItForMe.Cook.cancel = function() canceledCooking = true end
panel:close()
CookItForMe.Cook.cancel = originalCancel
assert(CookItForMe.planWindow == nil and not canceledCooking,
    "closing the plan clears the window without cancelling an active cooking session")
local staleWindow = setmetatable({ isCollapsed = false }, CookItForMePlanUI)
assert(pcall(function() staleWindow:prerender() end), "hot-reloaded renderer must tolerate an old open window")
local six = {
    { key = "Soup", failKey = "NoStove" }, { key = "Stew", failKey = "NoStove" },
    { key = "Stir fry", failKey = "NoStove" }, { key = "Roasted Vegetables", failKey = "NoStove" },
    { key = "Salad", failKey = "ActionFailed" }, { key = "Fruit Salad", failKey = "ActionFailed" },
}
local saladPanel = CookItForMePlanUI:new(0, six, 5)
assert(saladPanel.lines[1].text == "UI_CookItForMe_ActionFailed" and saladPanel.lines[2] == nil,
    "unrelated planning failures must not suggest moving toward the stove")
local recipePanel = CookItForMePlanUI:new(0, { { key = "Omelette", failKey = "RecipeUnavailable" } }, 1)
assert(recipePanel.lines[1].text == "UI_CookItForMe_RecipeUnavailable" and recipePanel.lines[2] == nil,
    "missing preparation recipe has its own message without an unrelated stove hint")
local prepEgg = Env.item("Base.Egg")
prepEgg.getTexture = function() return "egg texture" end
local prepFork = Env.item("Base.Fork")
prepFork.nonFood = true
prepFork.isFrozen = nil
prepFork.getTexture = function() return "fork texture" end
local prepPan = Env.item("Base.Pan")
recipePanel.entries[1].plan = {
    prep = { items = { prepFork, prepEgg }, count = 2 },
    rows = { { id = 98, kind = "prep", prepIndex = 1, item = prepFork },
        { id = 99, kind = "prep", prepIndex = 2, item = prepEgg } },
    picked = { items = {}, spices = {} }, dishKey = "Omelette", dish = Catalog.DISHES.Omelette,
    cookware = prepPan, predictedCalories = 191, predictedHunger = 28,
}
recipePanel:refreshIngredients()
assert(recipePanel.lines[1].kind == "prepGroup" and recipePanel.lines[2].tex == "fork texture"
    and recipePanel.lines[3].tex == "egg texture" and recipePanel.lines[4].kind == "prepEnd",
    "preparation inputs render as a separate card with item icons")
assert(pcall(function() recipePanel.rowWidgets["Omelette:98"]:prerender() end),
    "non-food preparation tools render without a Food.isFrozen method")
local prepWidget = assert(recipePanel.rowWidgets["Omelette:99"])
assert(prepWidget.replaceButton.visible and prepWidget.removeButton.visible,
    "preparation inputs expose the same replacement and removal actions as additions")
local previousText = getText
getText = function(key, value)
    if key == "UI_CookItForMe_PlanCaloriesTotal" or key == "UI_CookItForMe_PlanHunger" then
        return key .. ": ~" .. tostring(value)
    end
    return previousText(key, value)
end
local summaryText = {}
recipePanel.summaryCard.drawText = function(_, value) summaryText[#summaryText + 1] = value end
local previousTexture = getTexture
getTexture = function() return nil end
recipePanel.summaryCard:prerender()
assert(not table.concat(summaryText, " "):find("~~", 1, true), "metric cards show one approximation mark")
getText = previousText
assert(summaryText[2]:find("UI_CookItForMe_CookwareLabel", 1, true)
    and not table.concat(summaryText, " "):find("UI_CookItForMe_PlanWaterNeeded", 1, true),
    "recipes without water show the cookware selector label without a water notice")
local soupPot = Env.item("Base.Pot")
recipePanel.entries[1].plan.dishKey = "Soup"
recipePanel.entries[1].plan.dish = Catalog.DISHES.Soup
recipePanel.entries[1].plan.cookware = soupPot
recipePanel.summaryCard:setWidth(1600)
recipePanel.compactHero = false
summaryText = {}
recipePanel.summaryCard:prerender()
assert(summaryText[2]:find("UI_CookItForMe_CookwareLabel", 1, true)
    and summaryText[3]:find("UI_CookItForMe_PlanWater", 1, true),
    "recipes requiring water retain the water source notice beside the selector")
recipePanel.entries[1].plan.dishKey = "Salad"
recipePanel.entries[1].plan.dish = Catalog.DISHES.Salad
recipePanel.entries[1].plan.cookware = Env.item("Base.Bowl")
summaryText = {}
recipePanel.summaryCard:prerender()
assert(summaryText[2]:find("UI_CookItForMe_CookwareLabel", 1, true)
    and not table.concat(summaryText, " "):find("UI_CookItForMe_PlanWaterNeeded", 1, true),
    "salad summary omits water information")
recipePanel.entries[1].plan.dishKey = "Omelette"
recipePanel.entries[1].plan.dish = Catalog.DISHES.Omelette
recipePanel.entries[1].plan.cookware = prepPan
getTexture = previousTexture
recipePanel:close()
saladPanel.width, saladPanel.height = 560, 460
saladPanel:prerender()
assert(saladPanel.finishCookingButton.visible == false and settings.finishCooking == false,
    "salad hides finish toggle without modifying saved choice")
for _, tab in ipairs(saladPanel.tabButtons) do
    assert(tab.y + tab.height < saladPanel.cookButton.y, "all six dish cards fit above footer")
end
saladPanel.activeIndex = 1
saladPanel:prerender()
assert(saladPanel.finishCookingButton.visible == true, "hot dish shows finish toggle again")
local previousGetItem, previousGetTexture = getItem, getTexture
local requestedIcons = {}
getItem = function(fullType)
    return { getIcon = function() return fullType end }
end
getTexture = function(path) return path end
local iconPanel = CookItForMePlanUI:new(0, {
    { key = "Soup", failKey = "NoStove" }, { key = "Stew", failKey = "NoStove" },
    { key = "Pasta", failKey = "NoStove" }, { key = "Rice", failKey = "NoStove" },
}, 1)
for _, button in ipairs(iconPanel.tabButtons) do
    button.drawTextureScaled = function(_, texture) requestedIcons[button.entry.key] = texture end
    button:prerender()
end
for _, key in ipairs({ "Soup", "Stew", "Pasta", "Rice" }) do
    assert(requestedIcons[key] == "Item_Base.Pot", key .. " uses the same pot icon as soup and stew")
end
getItem, getTexture = previousGetItem, previousGetTexture
iconPanel:close()
local secondPot = e.source:AddItem(Env.item("Base.PotForged"))
secondPot.nonFood = true
e.collected.cookware[#e.collected.cookware + 1] = secondPot
local cookwarePlan = assert(CookItForMe.Cook.plan(e.player, "Stew"))
local scanner = require "CookItForMe_Scanner"
local originalScan = scanner.scanAround
local openingRescans = 0
scanner.scanAround = function(...)
    openingRescans = openingRescans + 1
    return originalScan(...)
end
local cookwarePanel = CookItForMePlanUI:new(0, { { key = "Stew", plan = cookwarePlan } }, 1,
    e.scan, { regular = e.collected, cooked = e.collected })
cookwarePanel:setWidth(1600)
cookwarePanel:setHeight(900)
assert(cookwarePanel.cookwareButton and #cookwarePanel.cookwareOptions == 2,
    "a styled summary control offers both physical cooking vessels")
assert(cookwarePanel.cookwareButton.fullTitle:find(e.pot:getDisplayName(), 1, true),
    "the automatic vessel is shown when the window opens")
cookwarePanel:prerender()
scanner.scanAround = originalScan
assert(openingRescans == 0, "creating and first rendering the catalog reuse its opening scan")
local heroText = {}
cookwarePanel.summaryCard.drawText = function(_, value, x, y) heroText[value] = { x = x, y = y } end
local savedTexture = getTexture
getTexture = function() return nil end
cookwarePanel.summaryCard:prerender()
getTexture = savedTexture
local waterLine = heroText[getText("UI_CookItForMe_PlanWaterNeeded")]
local cookwareLine = heroText[getText("UI_CookItForMe_CookwareLabel")]
assert(waterLine and cookwareLine and waterLine.y == cookwareLine.y
    and waterLine.x >= cookwarePanel.cookwareButton.x + cookwarePanel.cookwareButton.width + 16,
    "water and cookware share one aligned row without overlapping")
assert(cookwarePanel.cookwareButton.x >= 14 + getTextManager():MeasureStringX(UIFont.Small,
    getText("UI_CookItForMe_CookwareLabel")) + 12,
    "the cookware control clears the localized label")
assert(math.abs(cookwarePanel.cookwarePicker.y - (cookwarePanel.summaryCard.y
    + cookwarePanel.cookwareButton.y + cookwarePanel.cookwareButton.height + 4)) <= 1,
    "the cookware choices open directly below the selector")
local originalChoose = CookItForMe.Cook.planEditor.chooseCookware
local originalOptions = CookItForMe.Cook.planEditor.cookwareOptions
CookItForMe.Cook.planEditor.chooseCookware = function()
    error("opening the cookware picker must not rebuild a plan")
end
CookItForMe.Cook.planEditor.cookwareOptions = function()
    error("opening the cookware picker must not scan the world again")
end
CookItForMePlanUI.onOpenCookwarePicker(cookwarePanel)
CookItForMe.Cook.planEditor.chooseCookware = originalChoose
CookItForMe.Cook.planEditor.cookwareOptions = originalOptions
assert(cookwarePanel.cookwarePicker and #cookwarePanel.cookwarePicker.buttons == 2,
    "the cookware choices open in their own styled list")
local pickerCaption
cookwarePanel.cookwarePicker.drawText = function(_, value) pickerCaption = value end
cookwarePanel.cookwarePicker:prerender()
assert(pickerCaption == nil and cookwarePanel.cookwareCloseButton == nil
    and cookwarePanel.cookwareScroll.y == 4,
    "the cookware choices start at the top without a heading or close button")
assert(cookwarePanel.cookwareList.height < cookwarePanel.cookwareScroll.height,
    "two cookware choices fit without a scrollbar")
assert(cookwarePanel.cookwarePickerVisible, "the cookware choices are open")
cookwarePanel.cookwarePicker.getMouseX = function() return 20 end
cookwarePanel.cookwarePicker.getMouseY = function() return 20 end
cookwarePanel.cookwarePicker:onMouseDownOutside(0, 0)
assert(cookwarePanel.cookwarePickerVisible,
    "mouse events dispatched to the popup while clicking a choice must not close it")
cookwarePanel.cookwareButton.isMouseOver = function() return true end
cookwarePanel.cookwarePicker:onMouseDownOutside(0, 0)
assert(cookwarePanel.cookwarePickerVisible,
    "the outside handler lets the selector's own click toggle the list")
cookwarePanel.cookwareButton.isMouseOver = nil
cookwarePanel.cookwarePicker.getMouseX = function() return -1 end
cookwarePanel.cookwarePicker.getMouseY = function() return -1 end
assert(cookwarePanel.cookwarePicker:onMouseDownOutside(0, 0) == false
    and not cookwarePanel.cookwarePickerVisible,
    "a click outside closes the list without consuming the click")
CookItForMePlanUI.onOpenCookwarePicker(cookwarePanel)
CookItForMePlanUI.onOpenCookwarePicker(cookwarePanel)
assert(not cookwarePanel.cookwarePickerVisible and not cookwarePanel.cookwarePicker.visible,
    "clicking the selector again dismisses the list without changing the plan")
CookItForMePlanUI.onOpenCookwarePicker(cookwarePanel)
cookwarePanel.cookwarePicker.getMouseX = function() return 20 end
cookwarePanel.cookwarePicker.getMouseY = function() return 52 end
cookwarePanel.cookwarePicker:onMouseDownOutside(0, 0)
assert(cookwarePanel.cookwarePickerVisible, "a click on a cookware row keeps it clickable")
local selectedRow = cookwarePanel.cookwarePicker.buttons[2]
selectedRow.callback(selectedRow.target, selectedRow)
assert(cookwarePanel.entries[1].plan.cookware == secondPot,
    "clicking a cookware row changes the exact plan used by Cook")
for _ = 1, 2 do
    local extra = e.source:AddItem(Env.item("Base.Pot"))
    extra.nonFood = true
    e.collected.cookware[#e.collected.cookware + 1] = extra
end
cookwarePanel:refreshCookwareOptions()
cookwarePanel:prerender()
CookItForMePlanUI.onOpenCookwarePicker(cookwarePanel)
assert(#cookwarePanel.cookwarePicker.buttons == 4
    and cookwarePanel.cookwareList.height < cookwarePanel.cookwareScroll.height,
    "four cookware choices fit without a scrollbar")
CookItForMePlanUI.onCloseCookwarePicker(cookwarePanel)
e.source:Remove(secondPot)
cookwarePanel:refreshCookwareOptions()
assert(cookwarePanel.cookwareButton.fullTitle:find(secondPot:getDisplayName(), 1, true),
    "a vanished selected vessel is still shown instead of silently selecting another")
cookwarePanel:close()
for _, name in ipairs({ "ISCollapsableWindow", "ISButton", "ISLabel", "ISComboBox", "ISSpinBox", "ISTickBox", "ISPanel", "ISTextEntryBox" }) do package.loaded["ISUI/" .. name] = nil end
print("UI STATE AND LAYOUT TESTS PASSED")
