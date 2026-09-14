-- Cook It For Me: панель «План готовки» (client, B42)
-- Окно ресайзится игроком, размер и позиция сохраняются.

require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISComboBox"
require "ISUI/ISSpinBox"
require "CookItForMe_Shared"
local Scanner = require "CookItForMe_Scanner"
require "CookItForMe_Cook"

-- Все логи — под дебаг-флагом (CookItForMe.Debug в настройках песочницы)
local log = CookItForMe.log

CookItForMePlanUI = ISCollapsableWindow:derive("CookItForMePlanUI")

local DISH_LABELS = {
    Soup = "UI_CookItForMe_DishSoup",
    Stew = "UI_CookItForMe_DishStew",
    ["Stir fry"] = "UI_CookItForMe_DishStirFry",
    ["Roasted Vegetables"] = "UI_CookItForMe_DishRoast",
}

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
    table.insert(lines, { kind = "text", text = getText("UI_CookItForMe_PlanDish", getText(DISH_LABELS[plan.dishKey]))
        .. "   |   " .. getText("UI_CookItForMe_PlanCookware", plan.cookware:getDisplayName())
        .. "   |   " .. waterText })

    table.insert(lines, { kind = "text", text = getText(DIRECTION_LABELS[plan.direction] or DIRECTION_LABELS.max) })

    table.insert(lines, { kind = "header", text = getText("UI_CookItForMe_PlanIngredients") })
    local totalCal = 0
    local totalHunger = 0
    local agg, order, seen = {}, {}, {}
    for _, f in ipairs(picked.items) do
        local ft = f:getFullType()
        if not agg[ft] then
            agg[ft] = { name = f:getDisplayName(), count = 0, cal = 0, frozen = false, tex = f:getTexture() }
        end
        agg[ft].count = agg[ft].count + 1
        agg[ft].cal = agg[ft].cal + f:getCalories()
        agg[ft].frozen = agg[ft].frozen or f:isFrozen()
        totalCal = totalCal + f:getCalories()
        totalHunger = totalHunger + f:getBaseHunger()
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

    local hungerPts = plan.predictedHunger or math.floor(-totalHunger * 100 * 0.5 + 0.5)
    local calPts = plan.predictedCalories or math.floor(totalCal + 0.5)
    table.insert(lines, { kind = "text", text = getText("UI_CookItForMe_PlanCaloriesTotal", tostring(calPts))
        .. "   |   " .. getText("UI_CookItForMe_PlanHunger", tostring(hungerPts)) })

    return lines
end

function CookItForMePlanUI:close()
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
    local settings = CookItForMe.getSettings(p)
    local scan = Scanner.scanAround(p, settings.radius)
    local collected = Scanner.collectFood(p, scan)
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

function CookItForMePlanUI:onCook()
    local entry = self.entries[self.activeIndex]
    if not entry or not entry.plan then return end
    log("PLAN COOK CLICKED: " .. tostring(entry.key))
    self:close()
    CookItForMe.Cook.start(getSpecificPlayer(self.player), entry.key, entry.plan)
end

function CookItForMePlanUI:onSwitchDish(button)
    local i = button.internal
    if i == self.activeIndex then return end
    -- просто переключаем вкладку и перерисовываем содержимое (не пересоздаём окно)
    self.activeIndex = i
    self.lines = buildRenderLines(self.entries, i)
end

function CookItForMePlanUI:createChildren()
    ISCollapsableWindow.createChildren(self)

    local settings = CookItForMe.getSettings(getSpecificPlayer(self.player))
    local th = self:titleBarHeight()
    local y = th + 10

    -- Табы всех блюд (недоступные — красные)
    self.tabButtons = {}
    local x = COL1
    for i, e in ipairs(self.entries) do
        local label = getText(DISH_LABELS[e.key])
        local w = getTextManager():MeasureStringX(UIFont.Small, label) + 20
        local btn = ISButton:new(x, y, w, 24, label, self, CookItForMePlanUI.onSwitchDish)
        btn.internal = i
        btn:initialise()
        btn:instantiate()
        if e.plan then
            btn:enableAcceptColor()
        else
            btn:enableCancelColor()
        end
        self:addChild(btn)
        self.tabButtons[i] = btn
        x = x + w + 6
    end
    y = y + 30

    -- Стратегия | Радиус
    x = COL1
    self:addChild(ISLabel:new(x, y + 4, 18, getText("UI_CookItForMe_SettingsStrategy"), 0.75, 0.75, 0.75, 1, UIFont.Small, true))
    self.strategyCombo = ISComboBox:new(x + 110, y, 220, 24, nil, nil)
    self.strategyCombo:setOnChange(self, CookItForMePlanUI.onStrategyChange)
    self.strategyCombo:addOptionWithData(getText("UI_CookItForMe_StrategyMax"), "max")
    self.strategyCombo:addOptionWithData(getText("UI_CookItForMe_StrategyMin"), "min")
    self.strategyCombo:addOptionWithData(getText("UI_CookItForMe_StrategyHunger"), "hunger")
    for i, opt in ipairs(self.strategyCombo.options) do
        if opt.data == settings.strategy then self.strategyCombo:setSelected(i) break end
    end
    self:addChild(self.strategyCombo)

    x = COL2 + 50
    self:addChild(ISLabel:new(x, y + 4, 18, getText("UI_CookItForMe_SettingsRadius"), 0.75, 0.75, 0.75, 1, UIFont.Small, true))
    self.radiusSpin = ISSpinBox:new(x + 80, y, 56, 24, nil, nil)
    for i = 0, 30 do self.radiusSpin:addOption(tostring(i)) end
    self.radiusSpin:setSelectedOption(tostring(settings.radius))
    self.radiusSpin.target = self
    self.radiusSpin.targetFunc = CookItForMePlanUI.onRadiusChange
    self:addChild(self.radiusSpin)
    self:addChild(ISLabel:new(x + 142, y + 4, 18, getText("UI_CookItForMe_SettingsRadiusHintShort"), 0.55, 0.55, 0.55, 1, UIFont.Small, true))

    -- кнопки
    local rh = self:resizeWidgetHeight()
    local btnY = self.height - rh - 44
    local btn = ISButton:new(COL1, btnY, 160, 30, getText("UI_CookItForMe_PlanCook"), self, CookItForMePlanUI.onCook)
    btn:initialise()
    btn:instantiate()
    btn:enableAcceptColor()
    btn.anchorTop = false
    btn.anchorBottom = true
    self:addChild(btn)

    btn = ISButton:new(COL1 + 174, btnY, 100, 30, getText("UI_CookItForMe_SettingsClose"), self, CookItForMePlanUI.close)
    btn:initialise()
    btn:instantiate()
    btn:enableCancelColor()
    btn.anchorTop = false
    btn.anchorBottom = true
    self:addChild(btn)
end

function CookItForMePlanUI:prerender()
    ISCollapsableWindow.prerender(self)
    if self.isCollapsed then return end

    local activeTab = self.tabButtons and self.tabButtons[self.activeIndex]
    if activeTab then
        self:drawRectBorder(activeTab.x - 2, activeTab.y - 2, activeTab.width + 4, activeTab.height + 4, 1, 1, 0.9, 0.5)
    end

    local th = self:titleBarHeight()
    local y = th + 10 + 30 + 34 + 8
    for _, line in ipairs(self.lines) do
        if line.kind == "header" then
            self:drawText(line.text, COL1 + 2, y + 3, 1, 0.9, 0.7, 1, UIFont.Small)
            y = y + 26
        elseif line.kind == "item" and line.tex then
            self:drawTextureScaled(line.tex, COL1 + 14, y, 24, 24, 1, 1, 1, 1)
            self:drawText(line.text, COL1 + 46, y + 3, 0.92, 0.92, 0.92, 1, UIFont.Small)
            y = y + 26
        else
            self:drawText(line.text, COL1 + 14, y + 3, 0.92, 0.92, 0.92, 1, UIFont.Small)
            y = y + 22
        end
    end
end

function CookItForMePlanUI:new(player, entries, activeIndex)
    -- активный таб по умолчанию — первый доступный
    if not activeIndex or not entries[activeIndex] or not entries[activeIndex].plan then
        activeIndex = 1
        for i, e in ipairs(entries) do
            if e.plan then activeIndex = i break end
        end
    end
    local lines = buildRenderLines(entries, activeIndex)
    local settings = CookItForMe.getSettings(getSpecificPlayer(player))
    local w = settings.panelW or 560
    local h = settings.panelH or 560
    local x = settings.panelX or ((getCore():getScreenWidth() - w) / 2)
    local y = settings.panelY or ((getCore():getScreenHeight() - h) / 2)
    local o = ISCollapsableWindow.new(self, x, y, w, h)
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
    return o
end
