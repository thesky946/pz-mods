package.path = "../42/media/lua/shared/?.lua;../42/media/lua/client/?.lua;./?.lua;" .. package.path
local Env = require "support/cook_env"
local e = Env.new()
local Base = {}
Base.__index = Base
function Base:derive() local c = {}; c.__index = c; return setmetatable(c, { __index = self }) end
function Base:new(x, y, w, h, text, target, callback)
    return setmetatable({ x = x, y = y, width = w, height = h, children = {}, options = {},
        text = text, target = target, callback = callback, anchorTop = true }, self)
end
for _, name in ipairs({ "initialise", "instantiate", "setResizable", "enableAcceptColor", "enableCancelColor",
    "setVisible", "removeFromUIManager", "addScrollBars", "setStencilRect", "clearStencilRect", "drawRect", "drawRectBorder", "drawTextureScaled", "prerender", "createChildren" }) do
    Base[name] = function() end
end
function Base:addChild(child) self.children[#self.children + 1] = child end
function Base:instantiate()
    self.engineAnchorTop, self.engineAnchorBottom = self.anchorTop, self.anchorBottom
end
function Base:addToUIManager() self:createChildren() end
function Base:titleBarHeight() return 20 end
function Base:resizeWidgetHeight() return 8 end
function Base:setX(value) self.x = value end
function Base:setY(value) self.y = value end
function Base:setWidth(value) self.width = value end
function Base:setHeight(value) self.height = value end
function Base:setYScroll(value) self.scroll = value end
function Base:getYScroll() return self.scroll or 0 end
function Base:setScrollHeight(value) self.scrollHeight = value end
function Base:getScrollHeight() return self.scrollHeight or 0 end
function Base:setEnable(value) assert(type(value) == "boolean"); self.enabled = value end
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
-- ISButton does not expose ISPanel:drawText in the game.  Custom button
-- renderers must use its supported centred text API.
ISButton.drawText = false
package.loaded["neatui_framework/scrollview/niscrollbar"] = true
package.loaded["neatui_framework/scrollview/niscrollview"] = Base:derive()
package.loaded["neatui_framework/neattool/neattool_truncatetext"] = true
UIFont = { Small = 1 }
getSpecificPlayer = function() return e.player end
getCore = function() return { getScreenWidth = function() return 900 end, getScreenHeight = function() return 700 end } end
getTextManager = function() return { MeasureStringX = function(_, _, text) return #text * 6 end, getFontHeight = function() return 18 end } end
local settings = CookItForMe.getSettings(e.player)
settings.panelX, settings.panelY, settings.panelW, settings.panelH = 3000, -30, 850, 600
require "CookItForMe_PlanUI"
local entries = { { key = "Soup", failKey = "NoStove" }, { key = "Stew", failKey = "NoStove" },
    { key = "Stir fry", failKey = "NoStove" }, { key = "Roasted Vegetables", failKey = "NoStove" } }
local panel = CookItForMePlanUI:new(0, entries, 2)
assert(panel.x >= 0 and panel.y >= 0 and panel.x + panel.width <= 900)
assert(panel.activeIndex == 2 and panel.completionSoundTick.checked)
assert(panel.dishRail and panel.summaryCard and panel.content.isNeatScrollView,
    "plan UI must expose the NeatUI dashboard layout")
panel.tabButtons[1]:prerender()
panel.radiusButtons[1]:prerender(); panel.radiusButtons[3]:prerender()
assert(panel.cookButton.engineAnchorTop == false and panel.cookButton.engineAnchorBottom == true,
    "footer anchors must reach the engine before resizing")
CookItForMePlanUI.onCompletionSoundChange(panel, 1, false)
panel:close()
panel = CookItForMePlanUI:new(0, entries, 2)
assert(not panel.completionSoundTick.checked, "checkbox survives reopening")
panel.width = 560; panel.height = 420; panel.content.width = 544
panel:prerender()
local persisted = CookItForMe.getSettings(e.player)
assert(persisted.panelW == 560 and persisted.panelH == 420, "resized panel dimensions persist before closing")
assert(panel.content.y > panel.completionSoundTick.y + 24 and panel.content.height > 0)
assert(panel.soundButton.y >= panel.radiusButtons[1].y + panel.radiusButtons[1].height + 8,
    "compact settings must put sound control on a separate row")
assert(panel.soundButton.x >= panel.content.x and panel.soundButton.x + panel.soundButton.width <= panel.content.x + panel.content.width,
    "compact sound control stays inside the content column")
assert(panel.tabButtons[1].y >= 20 + 12 + 50,
    "dish cards must leave a full line below the rail heading")
assert(panel.strategyButtons[1].y >= panel.summaryCard.y + panel.summaryCard.height + 10 + 44,
    "strategy controls must leave a full line below the settings heading")
for _, size in ipairs({ { 900, 700 }, { 560, 420 }, { 800, 600 }, { 560, 420 } }) do
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
assert(panel.cookButton.enabled == false and panel.cancelButton == nil)
local staleWindow = setmetatable({ isCollapsed = false }, CookItForMePlanUI)
assert(pcall(function() staleWindow:prerender() end), "hot-reloaded renderer must tolerate an old open window")
for _, name in ipairs({ "ISCollapsableWindow", "ISButton", "ISLabel", "ISComboBox", "ISSpinBox", "ISTickBox", "ISPanel" }) do package.loaded["ISUI/" .. name] = nil end
print("UI STATE AND LAYOUT TESTS PASSED")
