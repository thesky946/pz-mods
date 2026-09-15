-- Cook It For Me: панель «План готовки» (client, B42)
-- Окно ресайзится игроком, размер и позиция сохраняются.

require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISComboBox"
require "ISUI/ISSpinBox"
require "ISUI/ISTickBox"
require "ISUI/ISPanel"
require "CookItForMe_Shared"
local Catalog = require "CookItForMe_Dishes"
require "CookItForMe_Cook"

-- Все логи — под дебаг-флагом (CookItForMe.Debug в настройках песочницы)
local log = CookItForMe.log

CookItForMePlanUI = ISCollapsableWindow:derive("CookItForMePlanUI")

local COL1 = 16
local COL2 = 320

local DIRECTION_LABELS = {
    max = "UI_CookItForMe_DirectionMax",
    min = "UI_CookItForMe_DirectionMin",
    hunger = "UI_CookItForMe_DirectionHunger",
}

local function failText(failKey)
    return getText("UI_CookItForMe_" .. (failKey or "NotEnough"))
end

-- Рендер-строки: {kind="text", text} | {kind="header", text} | {kind="item", tex, text}
local function buildRenderLines(entries, activeIndex)
    local entry = entries[activeIndex]
    if not entry or not entry.plan then
        local lines = {
            { kind = "text", text = failText(entry and entry.failKey) },
            { kind = "text", text = getText("UI_CookItForMe_HintCheckRadius") },
        }
        -- если не хватает посуды — показываем иконки нужной посуды
        if entry and entry.failKey == "NoCookware" then
            local dish = CookItForMe.Cook.DISHES and CookItForMe.Cook.DISHES[entry.key]
            if dish and dish.bases then
                table.insert(lines, { kind = "text", text = getText("UI_CookItForMe_PlanCookwareNeeded") })
                for _, ft in ipairs(dish.bases) do
                    local tex = nil
                    local si = getItem(ft)
                    if si and si:getIcon() then
                        tex = getTexture("Item_" .. si:getIcon())
                    end
                    table.insert(lines, { kind = "item", tex = tex, text = getItemNameFromFullType(ft) })
                end
            end
        end
        return lines
    end
    local plan = entry.plan
    local lines = {}
    local picked = plan.picked

    local waterText = plan.dish.needsWater
        and getText("UI_CookItForMe_PlanWaterNeeded")
        or getText("UI_CookItForMe_PlanWaterNone")
    table.insert(lines, { kind = "text", text = getText("UI_CookItForMe_PlanDish", getText(Catalog.DISHES[plan.dishKey].label))
        .. "   |   " .. getText("UI_CookItForMe_PlanCookware", plan.cookware:getDisplayName())
        .. "   |   " .. waterText })

    table.insert(lines, { kind = "text", text = getText(DIRECTION_LABELS[plan.direction] or DIRECTION_LABELS.max) })

    table.insert(lines, { kind = "header", text = getText("UI_CookItForMe_PlanIngredients") })
    local agg, order, seen = {}, {}, {}
    for _, f in ipairs(picked.items) do
        local ft = f:getFullType()
        if not agg[ft] then
            agg[ft] = { name = f:getDisplayName(), count = 0, cal = 0, frozen = false, tex = f:getTexture() }
        end
        agg[ft].count = agg[ft].count + 1
        agg[ft].cal = agg[ft].cal + f:getCalories()
        agg[ft].frozen = agg[ft].frozen or f:isFrozen()
        if not seen[ft] then
            seen[ft] = true
            table.insert(order, ft)
        end
    end
    for _, ft in ipairs(order) do
        local a = agg[ft]
        local tag = a.frozen and (" " .. getText("UI_CookItForMe_PlanFrozenTag")) or ""
        table.insert(lines, {
            kind = "item",
            tex = a.tex,
            text = string.format("%s x%d - %.0f %s%s", a.name, a.count, a.cal, getText("UI_CookItForMe_PlanCal"), tag),
        })
    end

    if #picked.spices > 0 then
        local spiceParts = {}
        for _, s in ipairs(picked.spices) do
            table.insert(spiceParts, s:getDisplayName())
        end
        table.insert(lines, {
            kind = "item",
            tex = picked.spices[1]:getTexture(),
            text = getText("UI_CookItForMe_PlanSpices") .. " " .. table.concat(spiceParts, ", "),
        })
    end

    local hungerPts = plan.predictedHunger or "?"
    local calPts = plan.predictedCalories or "?"
    table.insert(lines, { kind = "text", text = getText("UI_CookItForMe_PlanCaloriesTotal", tostring(calPts))
        .. "   |   " .. getText("UI_CookItForMe_PlanHunger", tostring(hungerPts)) })

    return lines
end

function CookItForMePlanUI:close()
    if CookItForMe.planWindow == self then CookItForMe.planWindow = nil end
    local p = getSpecificPlayer(self.player)
    if p then
        local s = CookItForMe.getSettings(p)
        s.panelW = self.width
        s.panelH = self.height
        s.panelX = self.x
        s.panelY = self.y
        CookItForMe.saveSettings(p, s)
    end
    self:setVisible(false)
    self:removeFromUIManager()
end

-- Пересборка всех блюд с текущими настройками
function CookItForMePlanUI:rebuild()
    local p = getSpecificPlayer(self.player)
    local entries = {}
    for _, key in ipairs(CookItForMe.Cook.ALL_DISHES) do
        local plan, failKey = CookItForMe.Cook.plan(p, key)
        table.insert(entries, { key = key, plan = plan, failKey = failKey })
    end
    local activeKey = self.entries[self.activeIndex] and self.entries[self.activeIndex].key
    local newActive = 1
    for i, e in ipairs(entries) do
        if e.key == activeKey then newActive = i break end
    end
    self:close()
    CookItForMePlanUI:new(self.player, entries, newActive)
end

-- Ваниль вызывает onChange/onButton(target, widget, ...) без self-подстановки — функции с точкой
function CookItForMePlanUI.onStrategyChange(panel, combo)
    local p = getSpecificPlayer(panel.player)
    local s = CookItForMe.getSettings(p)
    s.strategy = combo.options[combo.selected].data
    CookItForMe.saveSettings(p, s)
    panel:rebuild()
end

function CookItForMePlanUI.onRadiusChange(panel, spinbox)
    local p = getSpecificPlayer(panel.player)
    local s = CookItForMe.getSettings(p)
    s.radius = tonumber(spinbox.options[spinbox.selected])
    CookItForMe.saveSettings(p, s)
    panel:rebuild()
end

function CookItForMePlanUI.onCompletionSoundChange(panel, index, selected)
    CookItForMe.saveSettings(getSpecificPlayer(panel.player), { completionSound = selected })
end

function CookItForMePlanUI:onCook()
    local entry = self.entries[self.activeIndex]
    if not entry or not entry.plan then return end
    log("PLAN COOK CLICKED: " .. tostring(entry.key))
    local ok = CookItForMe.Cook.start(getSpecificPlayer(self.player), entry.key, entry.plan)
    if ok then self:close() else self:rebuild() end
end

function CookItForMePlanUI:onSwitchDish(button)
    local i = button.internal
    if i == self.activeIndex then return end
    -- просто переключаем вкладку и перерисовываем содержимое (не пересоздаём окно)
    self.activeIndex = i
    self.lines = buildRenderLines(self.entries, i)
    self.content:setYScroll(0)
end

function CookItForMePlanUI:createChildren()
    ISCollapsableWindow.createChildren(self)

    local settings = CookItForMe.getSettings(getSpecificPlayer(self.player))
    local y, x = self:titleBarHeight() + 10, COL1
    self.tabButtons = {}
    for i, entry in ipairs(self.entries) do
        local label = getText(Catalog.DISHES[entry.key].label)
        local width = getTextManager():MeasureStringX(UIFont.Small, label) + 20
        if x + width > self.width - 16 then x = COL1; y = y + 30 end
        local button = ISButton:new(x, y, width, 24, label, self, CookItForMePlanUI.onSwitchDish)
        button.internal = i
        button:initialise(); button:instantiate()
        if entry.plan then button:enableAcceptColor() else button:enableCancelColor() end
        self:addChild(button); self.tabButtons[i] = button
        x = x + width + 6
    end
    y = y + 34
    self.controlsTop = y
    local strategyLabel = getText("UI_CookItForMe_SettingsStrategy")
    self:addChild(ISLabel:new(COL1, y + 4, 18, strategyLabel, .75, .75, .75, 1, UIFont.Small, true))
    local labelWidth = getTextManager():MeasureStringX(UIFont.Small, strategyLabel) + 12
    self.strategyCombo = ISComboBox:new(COL1 + labelWidth, y, math.max(140, self.width - labelWidth - 36), 24, self, CookItForMePlanUI.onStrategyChange)
    self.strategyCombo:addOptionWithData(getText("UI_CookItForMe_StrategyMax"), "max")
    self.strategyCombo:addOptionWithData(getText("UI_CookItForMe_StrategyMin"), "min")
    self.strategyCombo:addOptionWithData(getText("UI_CookItForMe_StrategyHunger"), "hunger")
    for i, option in ipairs(self.strategyCombo.options) do
        if option.data == settings.strategy then self.strategyCombo:setSelected(i); break end
    end
    self:addChild(self.strategyCombo)
    y = y + 30
    local radiusLabel = getText("UI_CookItForMe_SettingsRadius")
    self:addChild(ISLabel:new(COL1, y + 4, 18, radiusLabel, .75, .75, .75, 1, UIFont.Small, true))
    local radiusX = COL1 + getTextManager():MeasureStringX(UIFont.Small, radiusLabel) + 12
    self.radiusSpin = ISSpinBox:new(radiusX, y, 56, 24, self, CookItForMePlanUI.onRadiusChange)
    for i = 0, 30 do self.radiusSpin:addOption(tostring(i)) end
    self.radiusSpin:setSelectedOption(tostring(settings.radius))
    self:addChild(self.radiusSpin)
    self:addChild(ISLabel:new(radiusX + 68, y + 4, 18, getText("UI_CookItForMe_SettingsRadiusHintShort"), .55, .55, .55, 1, UIFont.Small, true))
    y = y + 30
    self.completionSoundTick = ISTickBox:new(COL1, y, self.width - 32, 24, "", self, CookItForMePlanUI.onCompletionSoundChange)
    self.completionSoundTick:initialise()
    self.completionSoundTick:addOption(getText("UI_CookItForMe_SettingsCompletionSound"))
    self.completionSoundTick:setSelected(1, settings.completionSound)
    self:addChild(self.completionSoundTick)
    y = y + 32
    self.content = ISPanel:new(8, y, self.width - 16, self.height - y - 58)
    self.content.anchorRight = true; self.content.anchorBottom = true
    self.content:initialise(); self.content:instantiate()
    self.content:addScrollBars()
    self.content.onMouseWheel = function(panel, delta)
        panel:setYScroll(math.min(0, math.max(math.min(0, panel.height - panel:getScrollHeight()), panel:getYScroll() - delta * 30)))
        return true
    end
    self.content.prerender = function(panel)
        panel:setStencilRect(0, 0, panel.width - 14, panel.height)
        local top = 0
        for _, line in ipairs(self.lines) do
            local words, row = {}, ""
            local left = line.tex and 40 or 8
            if line.tex then panel:drawTextureScaled(line.tex, 8, top, 24, 24, 1, 1, 1, 1) end
            for word in line.text:gmatch("%S+") do words[#words + 1] = word end
            local function draw(text)
                panel:drawText(text, left, top, 0.92, 0.92, line.kind == "header" and 0.6 or 0.92, 1, UIFont.Small)
                top = top + math.max(24, getTextManager():getFontHeight(UIFont.Small) + 4)
            end
            for _, word in ipairs(words) do
                local candidate = row == "" and word or row .. " " .. word
                if row ~= "" and getTextManager():MeasureStringX(UIFont.Small, candidate) > panel.width - left - 28 then
                    draw(row); row = word
                else row = candidate end
                if getTextManager():MeasureStringX(UIFont.Small, row) > panel.width - left - 28 then
                    local chunk = ""
                    for char in row:gmatch("[^\128-\191][\128-\191]*") do
                        if chunk ~= "" and getTextManager():MeasureStringX(UIFont.Small, chunk .. char) > panel.width - left - 28 then
                            draw(chunk); chunk = char
                        else chunk = chunk .. char end
                    end
                    row = chunk
                end
            end
            draw(row)
        end
        panel:setScrollHeight(top)
        panel:clearStencilRect()
    end
    self:addChild(self.content)
    local btnY = self.height - self:resizeWidgetHeight() - 44
    local function button(xPos, width, title, callback)
        local b = ISButton:new(xPos, btnY, width, 30, getText(title), self, callback)
        b.anchorTop = false; b.anchorBottom = true
        b:initialise(); b:instantiate()
        self:addChild(b); return b
    end
    self.cookButton = button(COL1, 160, "UI_CookItForMe_PlanCook", CookItForMePlanUI.onCook)
    self.cookButton:enableAcceptColor()
    self.closeButton = button(COL1 + 174, 110, "UI_CookItForMe_SettingsClose", CookItForMePlanUI.close)
    self.closeButton:enableCancelColor()
end

function CookItForMePlanUI:prerender()
    ISCollapsableWindow.prerender(self)
    if self.isCollapsed then return end
    local x, y = COL1, self:titleBarHeight() + 10
    local tabs = {}
    for _, button in ipairs(self.tabButtons) do
        tabs[button] = true
        if x + button.width > self.width - 16 then x = COL1; y = y + 30 end
        button:setX(x); button:setY(y); x = x + button.width + 6
    end
    local controlsTop = y + 34
    local shift = controlsTop - self.controlsTop
    if shift ~= 0 then
        for _, child in pairs(self.children) do
            if not tabs[child] and child.anchorTop ~= false and child.y >= self.controlsTop then child:setY(child.y + shift) end
        end
        self.controlsTop = controlsTop
    end
    self.strategyCombo:setWidth(math.max(140, self.width - self.strategyCombo.x - 20))
    local btnY = self.height - self:resizeWidgetHeight() - 44
    self.cookButton:setY(btnY)
    self.closeButton:setY(btnY)
    self.content:setWidth(self.width - 16)
    self.content:setHeight(math.max(32, btnY - self.content.y - 6))
    local session = CookItForMe.Cook.getSession()
    local busy = session and session.active
    local entry = self.entries[self.activeIndex]
    self.cookButton:setEnable(not busy and entry ~= nil and entry.plan ~= nil)
    self.title = getText(busy and "UI_CookItForMe_Busy" or "UI_CookItForMe_PlanTitle")
    local tab = self.tabButtons[self.activeIndex]
    if tab then self:drawRectBorder(tab.x - 2, tab.y - 2, tab.width + 4, tab.height + 4, 1, 1, .9, .5) end
end

function CookItForMePlanUI:new(player, entries, activeIndex)
    -- активный таб по умолчанию — первый доступный
    if not activeIndex or not entries[activeIndex] then
        activeIndex = 1
        for i, e in ipairs(entries) do
            if e.plan then activeIndex = i break end
        end
    end
    local lines = buildRenderLines(entries, activeIndex)
    local settings = CookItForMe.getSettings(getSpecificPlayer(player))
    if CookItForMe.planWindow then CookItForMe.planWindow:close() end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local w = math.min(sw, math.max(560, tonumber(settings.panelW) or 560))
    local h = math.min(sh, math.max(420, tonumber(settings.panelH) or 560))
    local x = settings.panelX or ((getCore():getScreenWidth() - w) / 2)
    local y = settings.panelY or ((getCore():getScreenHeight() - h) / 2)
    x, y = math.max(0, math.min(sw - w, tonumber(x) or 0)), math.max(0, math.min(sh - h, tonumber(y) or 0))
    local o = ISCollapsableWindow.new(self, x, y, w, h)
    o.minimumWidth = math.min(sw, 560)
    o.minimumHeight = math.min(sh, 420)
    o.player = player
    o.entries = entries
    o.activeIndex = activeIndex
    o.lines = lines
    o.title = getText("UI_CookItForMe_PlanTitle")
    o:setResizable(true)
    o.moveWithMouse = true
    o:initialise()
    o:addToUIManager()
    o:setVisible(true)
    CookItForMe.planWindow = o
    return o
end
