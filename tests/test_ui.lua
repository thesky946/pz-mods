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
    "setVisible", "removeFromUIManager", "addScrollBars", "setStencilRect", "clearStencilRect", "drawRectBorder", "drawTextureScaled", "prerender", "createChildren" }) do
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
function Base:drawText(text, x) assert(x + #text * 6 <= self.width - 14, "wrapped content exceeds viewport") end
for _, name in ipairs({ "ISCollapsableWindow", "ISButton", "ISLabel", "ISComboBox", "ISSpinBox", "ISTickBox", "ISPanel" }) do
    _G[name] = Base:derive()
    package.loaded["ISUI/" .. name] = true
end
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
assert(panel.cookButton.engineAnchorTop == false and panel.cookButton.engineAnchorBottom == true,
    "footer anchors must reach the engine before resizing")
CookItForMePlanUI.onCompletionSoundChange(panel, 1, false)
panel:close()
panel = CookItForMePlanUI:new(0, entries, 2)
assert(not panel.completionSoundTick.checked, "checkbox survives reopening")
panel.width = 560; panel.height = 420; panel.content.width = 544
panel:prerender()
assert(panel.content.y > panel.completionSoundTick.y + 24 and panel.content.height > 0)
for _, size in ipairs({ { 900, 700 }, { 560, 420 }, { 800, 600 }, { 560, 420 } }) do
    panel.width, panel.height = size[1], size[2]
    panel:prerender()
    for _, b in ipairs({ panel.cookButton, panel.closeButton }) do
        assert(b.y + b.height < panel.height - panel:resizeWidgetHeight(), "footer stays inside window")
        assert(panel.content.y + panel.content.height < b.y, "content does not cover footer")
    end
    assert(panel.content.width == panel.width - 16)
end
for _, button in ipairs(panel.tabButtons) do assert(button.y + 24 < panel.controlsTop) end
panel.lines = { { kind = "text", text = string.rep("longword", 30) } }
panel.content:prerender()
assert(panel.content:getScrollHeight() > 24)
local previous = panel
panel = CookItForMePlanUI:new(0, entries, 2)
assert(CookItForMe.planWindow == panel and panel ~= previous)
panel:prerender()
assert(panel.cookButton.enabled == false and panel.cancelButton == nil)
for _, name in ipairs({ "ISCollapsableWindow", "ISButton", "ISLabel", "ISComboBox", "ISSpinBox", "ISTickBox", "ISPanel" }) do package.loaded["ISUI/" .. name] = nil end
print("UI STATE AND LAYOUT TESTS PASSED")
