-- Cook It For Me: панель «План готовки» (client, B42)
-- Окно ресайзится игроком, размер и позиция сохраняются.

require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISComboBox"
require "ISUI/ISSpinBox"
require "ISUI/ISTickBox"
require "ISUI/ISPanel"
require "ISUI/ISModalDialog"
-- NeatUI is a hard dependency.  Keep these requires explicit: the framework's
-- widgets are not guaranteed to be loaded just because another Neat mod is.
require "neatui_framework/scrollview/niscrollbar"
local NIScrollView = require "neatui_framework/scrollview/niscrollview"
require "neatui_framework/neattool/neattool_truncatetext"
require "CookItForMe_Shared"
local Catalog = require "CookItForMe_Dishes"
require "CookItForMe_Cook"

-- Все логи — под дебаг-флагом (CookItForMe.Debug в настройках песочницы)
local log = CookItForMe.log

CookItForMePlanUI = ISCollapsableWindow:derive("CookItForMePlanUI")

local COL1 = 16
local COL2 = 320
local BASE_FONT_HEIGHT = 18
local UI_SCALE = setmetatable({}, { __mode = "k" })
local KEY_CAPTURE_PANEL

local function uiPixel(panel, value)
    return math.floor(value * (UI_SCALE[panel] or 1) + 0.5)
end

local function setUiScale(panel, scale)
    UI_SCALE[panel] = scale
end

local function rgb(hex)
    return { r = math.floor(hex / 65536) / 255, g = math.floor(hex / 256) % 256 / 255, b = hex % 256 / 255 }
end

-- Single palette for NeatUI surfaces, custom controls, and the frozen-item marker.
local THEME = {
    background = rgb(0x141618), panel = rgb(0x1C1F22), hover = rgb(0x25292D), border = rgb(0x34393E),
    text = rgb(0xF0ECE4), secondary = rgb(0xA7A29A), accent = rgb(0xD39A4A),
    success = rgb(0x6FA36F), warning = rgb(0xC8A24D), error = rgb(0xB85C55), frozen = rgb(0x7098B8),
}
local RECIPE_HERO_ART

local function truncateText(text, width, font)
    if NeatTool and NeatTool.truncateText then
        return NeatTool.truncateText(text or "", math.max(0, width), font)
    end
    return text or ""
end

local function drawNeatSurface(panel, path, x, y, w, h, alpha, r, g, b)
    local texture = NinePatchTexture and NinePatchTexture.getSharedTexture
        and NinePatchTexture.getSharedTexture(path)
    if texture then
        texture:render(panel:getAbsoluteX() + x, panel:getAbsoluteY() + y, w, h, r, g, b, alpha)
    else
        panel:drawRect(x, y, w, h, alpha, r, g, b)
        panel:drawRectBorder(x, y, w, h, math.min(1, alpha + .25), THEME.border.r, THEME.border.g, THEME.border.b)
    end
end

local function styleButton(button, color, primary)
    button:setDisplayBackground(false)
    button.prerender = function(b)
        local c = color or THEME.border
        local hot = b:isMouseOver()
        local fill = primary and (b.enable == false and THEME.error or THEME.success)
            or (hot and THEME.hover or THEME.panel)
        local ink = primary and (b.enable == false and THEME.text or THEME.background)
            or (c == THEME.border and THEME.text or c)
        if primary then c = fill end
        if b.enable == false and not primary then fill, ink, c = THEME.panel, THEME.secondary, THEME.border end
        -- Background.png is a square NeatUI asset.  Stretching it into a
        -- long action button creates a pill that covers neighbouring labels.
        -- Use the framework's panel nine-patch and a precise colour fill.
        drawNeatSurface(b, "media/ui/NeatUI/DefaultPanel/ContentPanel_BG.png", 0, 0, b.width, b.height,
            .92, THEME.panel.r, THEME.panel.g, THEME.panel.b)
        b:drawRect(1, 1, b.width - 2, b.height - 2, b.enable == false and not primary and .7 or 1, fill.r, fill.g, fill.b)
        b:drawRectBorder(0, 0, b.width, b.height, 1, c.r, c.g, c.b)
        if hot and b.enable ~= false then
            b:drawRectBorder(1, 1, b.width - 2, b.height - 2, .55, THEME.accent.r, THEME.accent.g, THEME.accent.b)
        end
        if b.radiusGlyph then
            -- PZ's small UI font can drop a plus glyph on certain font scales.
            -- Draw the two primitives instead; it remains legible at every scale.
            local cx, cy = math.floor(b.width / 2), math.floor(b.height / 2)
            b:drawRect(cx - uiPixel(b.target, 5), cy - uiPixel(b.target, 1), uiPixel(b.target, 10), uiPixel(b.target, 2), 1, ink.r, ink.g, ink.b)
            if b.radiusGlyph == "+" then
                b:drawRect(cx - uiPixel(b.target, 1), cy - uiPixel(b.target, 5), uiPixel(b.target, 2), uiPixel(b.target, 10), 1, ink.r, ink.g, ink.b)
            end
        else
            local title = truncateText(b.renderTitle or b.fullTitle or b.title or "", b.width - uiPixel(b.target, 18), UIFont.Small)
            b:drawTextCentre(title, b.width / 2, math.floor((b.height - getTextManager():getFontHeight(UIFont.Small)) / 2),
                ink.r, ink.g, ink.b, b.enable == false and not primary and .8 or 1, UIFont.Small)
        end
        b:updateTooltip()
    end
end

local function dishIcon(entry)
    local dish = entry and Catalog.DISHES[entry.key]
    local base = dish and dish.bases and dish.bases[1]
    local script = base and getItem and getItem(base)
    return script and script:getIcon() and getTexture("Item_" .. script:getIcon()) or nil
end

local function drawRecipeHeroArt(panel, owner)
    if not RECIPE_HERO_ART then RECIPE_HERO_ART = getTexture("media/ui/CookItForMe/recipe_hero_v1.png") end
    if RECIPE_HERO_ART then
        -- The art deliberately sits under the metric cards: it adds an
        -- authored cooking mood without competing with actionable text.
        local h = panel.height + uiPixel(owner, 28)
        local w = math.floor(h * 1.5)
        panel:drawTextureScaled(RECIPE_HERO_ART, panel.width - w - uiPixel(owner, 2), -uiPixel(owner, 14), w, h, .48, 1, 1, 1)
    end
end

local function styleDishButton(button)
    button:setDisplayBackground(false)
    button.prerender = function(b)
        local selected = b.internal == b.target.activeIndex
        local ready = b.entry and b.entry.plan ~= nil
        local hot = b:isMouseOver()
        local color = selected and THEME.accent or THEME.border
        local fill = selected and THEME.hover or (hot and THEME.hover or THEME.panel)
        drawNeatSurface(b, "media/ui/NeatUI/DefaultPanel/ContentPanel_BG.png", 0, 0, b.width, b.height,
            1, fill.r, fill.g, fill.b)
        b:drawRectBorder(0, 0, b.width, b.height, selected and 1 or (hot and .78 or .42), color.r, color.g, color.b)
        local tex = dishIcon(b.entry)
        if tex then b:drawTextureScaled(tex, uiPixel(b.target, 9), uiPixel(b.target, 10), uiPixel(b.target, 32), uiPixel(b.target, 32), ready and 1 or .35, 1, 1, 1) end
        local title = truncateText(b.fullTitle or b.title, b.width - uiPixel(b.target, 60), UIFont.Small)
        local ink = ready and THEME.text or THEME.secondary
        b:drawTextCentre(title, b.width * .66, uiPixel(b.target, 18), ink.r, ink.g, ink.b, ready and 1 or .8, UIFont.Small)
        -- A status stripe communicates availability without overflowing in
        -- translated builds or competing with the dish title.
        b:drawRect(b.width - uiPixel(b.target, 7), uiPixel(b.target, 8), uiPixel(b.target, 3), b.height - uiPixel(b.target, 16), .95, color.r, color.g, color.b)
        b:updateTooltip()
    end
end

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
            frozen = a.frozen,
            text = string.format("%s x%d - %.0f %s%s", a.name, a.count, a.cal, getText("UI_CookItForMe_PlanCal"), tag),
        })
    end

    if #picked.spices > 0 then
        local spiceParts = {}
        for _, s in ipairs(picked.spices) do
            table.insert(spiceParts, s:getDisplayName())
        end
        table.insert(lines, {
            kind = "spice",
            tex = picked.spices[1]:getTexture(),
            text = getText("UI_CookItForMe_PlanSpices") .. " " .. table.concat(spiceParts, ", "),
        })
    end

    return lines
end

function CookItForMePlanUI:close()
    if KEY_CAPTURE_PANEL == self then KEY_CAPTURE_PANEL = nil end
    if self.keyConflictDialog then
        self.keyConflictDialog:destroy()
        self.keyConflictDialog = nil
    end
    if self.keyConflictCover then
        self.keyConflictCover:setVisible(false)
        self.keyConflictCover = nil
    end
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

function CookItForMePlanUI:persistGeometry()
    local p = getSpecificPlayer(self.player)
    if not p then return end
    local w, h = math.floor(self.width), math.floor(self.height)
    local x, y = math.floor(self.x), math.floor(self.y)
    if self.savedPanelW == w and self.savedPanelH == h and self.savedPanelX == x and self.savedPanelY == y then return end
    self.savedPanelW, self.savedPanelH, self.savedPanelX, self.savedPanelY = w, h, x, y
    CookItForMe.saveSettings(p, { panelW = w, panelH = h, panelX = x, panelY = y })
end

function CookItForMePlanUI:onStrategyButton(button)
    local p = getSpecificPlayer(self.player)
    local s = CookItForMe.getSettings(p)
    if s.strategy == button.internal then return end
    s.strategy = button.internal
    CookItForMe.saveSettings(p, s)
    self:rebuild()
end

function CookItForMePlanUI:onRadiusButton(button)
    local p = getSpecificPlayer(self.player)
    local s = CookItForMe.getSettings(p)
    s.radius = math.max(0, math.min(30, (tonumber(s.radius) or 0) + (button.internal or 0)))
    CookItForMe.saveSettings(p, s)
    self:rebuild()
end

function CookItForMePlanUI:onCompletionSoundButton()
    local p = getSpecificPlayer(self.player)
    local s = CookItForMe.getSettings(p)
    s.completionSound = not s.completionSound
    CookItForMe.saveSettings(p, s)
    self:rebuild()
end

function CookItForMePlanUI:onFinishCookingButton()
    local p = getSpecificPlayer(self.player)
    local s = CookItForMe.getSettings(p)
    s.finishCooking = not s.finishCooking
    CookItForMe.saveSettings(p, s)
    self:rebuild()
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

local function addKeyConflict(conflicts, seen, name)
    if name and name ~= "" and not seen[name] then
        seen[name] = true
        conflicts[#conflicts + 1] = name
    end
end

local function getPlanKeyConflicts(key)
    local conflicts, seen = {}, {}

    -- Core:getKeyBinding() returns Java KeyBinding userdata whose methods are
    -- not exposed to Kahlua in Build 42.20.4. MainOptions holds the Lua rows.
    if MainOptions and MainOptions.keyText and #MainOptions.keyText > 0 then
        for _, binding in ipairs(MainOptions.keyText) do
            if not binding.isModBind and tonumber(binding.keyCode) == key
                and not binding.shift and not binding.ctrl and not binding.alt
                and binding.txt and binding.txt.getName then
                addKeyConflict(conflicts, seen, binding.txt:getName())
            end
        end
    elseif MainOptions and MainOptions.keys then
        for _, binding in ipairs(MainOptions.keys) do
            if tonumber(binding.key) == key and not binding.shift and not binding.ctrl and not binding.alt then
                addKeyConflict(conflicts, seen, getText("UI_optionscreen_binding_" .. binding.value))
            end
        end
    end

    for _, options in ipairs(PZAPI.ModOptions.Data) do
        for _, option in ipairs(options.data) do
            if option.type == "keybind" and option ~= CookItForMe.planKeyOption
                and tonumber(option:getValue()) == key then
                addKeyConflict(conflicts, seen, getText(option.name))
            end
        end
    end

    return conflicts
end

local function updatePlanKeyButton(panel)
    if not panel.keybindButton then return end
    panel.keybindButton.fullTitle = panel.keyCaptureActive and "..." or getKeyName(CookItForMe.getOpenPlanKey())
    panel.keybindButton.title = ""
    panel.keybindButton.tooltip = getText(panel.keyCaptureActive
        and "UI_CookItForMe_KeybindCapture" or "UI_CookItForMe_KeybindTooltip")
end

local function finishPlanKeyCapture(panel)
    if KEY_CAPTURE_PANEL == panel then KEY_CAPTURE_PANEL = nil end
    panel.keyCaptureActive = false
    updatePlanKeyButton(panel)
end

local function onPlanKeyConflictChoice(panel, button, key)
    if button.internal == "YES" and CookItForMe.planWindow == panel then
        CookItForMe.setOpenPlanKey(key)
    end
    panel.keyConflictDialog = nil
    if panel.keyConflictCover then
        panel.keyConflictCover:setVisible(false)
        panel.keyConflictCover = nil
    end
    updatePlanKeyButton(panel)
end

local function showPlanKeyConflict(panel, key, conflicts)
    local message = getText("UI_CookItForMe_KeybindConflict", getKeyName(key), table.concat(conflicts, ", "))
    local width, height = ISModalDialog.CalcSize(480, 140, message)
    local cover = ISPanel:new(0, 0, panel.width, panel.height)
    cover.anchorRight = true
    cover.anchorBottom = true
    cover.backgroundColor.a = 0
    cover.borderColor.a = 0
    cover:initialise(); cover:instantiate()
    cover.javaObject:setConsumeMouseEvents(true)
    panel:addChild(cover)
    panel.keyConflictCover = cover
    local modal = ISModalDialog:new((getCore():getScreenWidth() - width) / 2,
        (getCore():getScreenHeight() - height) / 2, width, height, message, true, panel,
        onPlanKeyConflictChoice, nil, key)
    modal:initialise()
    modal.yes:setTitle(getText("UI_CookItForMe_KeybindKeepBoth"))
    modal.no:setTitle(getText("UI_Cancel"))
    modal:addToUIManager()
    modal:setAlwaysOnTop(true)
    panel.keyConflictDialog = modal
end

function CookItForMePlanUI.isCapturingPlanKey()
    return KEY_CAPTURE_PANEL ~= nil
end

function CookItForMePlanUI.onPlanKeyButton(panel)
    if KEY_CAPTURE_PANEL then return end
    KEY_CAPTURE_PANEL = panel
    panel.keyCaptureActive = true
    updatePlanKeyButton(panel)
end

function CookItForMePlanUI.onPlanKeyCapturePressed(key)
    local panel = KEY_CAPTURE_PANEL
    if not panel then return false end

    if key == Keyboard.KEY_ESCAPE then
        finishPlanKeyCapture(panel)
        return true
    end

    if key == Keyboard.KEY_LSHIFT or key == Keyboard.KEY_RSHIFT
        or key == Keyboard.KEY_LCONTROL or key == Keyboard.KEY_RCONTROL
        or key == Keyboard.KEY_LMENU or key == Keyboard.KEY_RMENU then
        return true
    end

    finishPlanKeyCapture(panel)
    local conflicts = getPlanKeyConflicts(key)
    if #conflicts > 0 then
        showPlanKeyConflict(panel, key, conflicts)
    else
        CookItForMe.setOpenPlanKey(key)
        updatePlanKeyButton(panel)
    end
    return true
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

    local px = function(value) return uiPixel(self, value) end
    local settings = CookItForMe.getSettings(getSpecificPlayer(self.player))
    local y, x = self:titleBarHeight() + px(10), px(COL1)
    self.tabButtons = {}
    for i, entry in ipairs(self.entries) do
        local label = getText(Catalog.DISHES[entry.key].label)
        local width = getTextManager():MeasureStringX(UIFont.Small, label) + px(20)
        if x + width > self.width - px(16) then x = px(COL1); y = y + px(30) end
        local button = ISButton:new(x, y, width, px(24), label, self, CookItForMePlanUI.onSwitchDish)
        button.internal = i
        button:initialise(); button:instantiate()
        button.fullTitle = label
        button.tooltip = entry.plan and label or (label .. "\n" .. failText(entry.failKey))
        -- ISButton renders title again after prerender().  The dish card owns
        -- its text rendering, so leave the vanilla title empty to prevent the
        -- grey duplicate shown under every card label.
        button.title = ""
        button.entry = entry
        styleDishButton(button)
        self:addChild(button); self.tabButtons[i] = button
        x = x + width + px(6)
    end
    y = y + px(34)
    self.controlsTop = y
    local strategyLabel = getText("UI_CookItForMe_SettingsStrategy")
    self.strategyLabel = ISLabel:new(px(COL1), y + px(4), px(18), strategyLabel, THEME.secondary.r, THEME.secondary.g, THEME.secondary.b, 1, UIFont.Small, true)
    self.strategyLabel:initialise(); self:addChild(self.strategyLabel); self.strategyLabel:setVisible(false)
    local labelWidth = getTextManager():MeasureStringX(UIFont.Small, strategyLabel) + px(12)
    self.strategyCombo = ISComboBox:new(px(COL1) + labelWidth, y, math.max(px(140), self.width - labelWidth - px(36)), px(24), self, CookItForMePlanUI.onStrategyChange)
    self.strategyCombo:addOptionWithData(getText("UI_CookItForMe_StrategyMax"), "max")
    self.strategyCombo:addOptionWithData(getText("UI_CookItForMe_StrategyMin"), "min")
    self.strategyCombo:addOptionWithData(getText("UI_CookItForMe_StrategyHunger"), "hunger")
    for i, option in ipairs(self.strategyCombo.options) do
        if option.data == settings.strategy then self.strategyCombo:setSelected(i); break end
    end
    self:addChild(self.strategyCombo)
    self.strategyCombo:setVisible(false)
    self.strategyButtons = {}
    for i, option in ipairs(self.strategyCombo.options) do
        local b = ISButton:new(0, 0, 1, px(24), option.text, self, CookItForMePlanUI.onStrategyButton)
        b.internal = option.data
        b.fullTitle = option.text
        b.title = ""
        b:initialise(); b:instantiate()
        styleButton(b, option.data == settings.strategy and THEME.accent or THEME.border)
        self:addChild(b)
        self.strategyButtons[i] = b
    end
    y = y + px(30)
    local radiusLabel = getText("UI_CookItForMe_SettingsRadius")
    self.radiusLabel = ISLabel:new(px(COL1), y + px(4), px(18), radiusLabel, THEME.secondary.r, THEME.secondary.g, THEME.secondary.b, 1, UIFont.Small, true)
    self.radiusLabel:initialise(); self:addChild(self.radiusLabel); self.radiusLabel:setVisible(false)
    local radiusX = px(COL1) + getTextManager():MeasureStringX(UIFont.Small, radiusLabel) + px(12)
    self.radiusSpin = ISSpinBox:new(radiusX, y, px(56), px(24), self, CookItForMePlanUI.onRadiusChange)
    for i = 0, 30 do self.radiusSpin:addOption(tostring(i)) end
    self.radiusSpin:setSelectedOption(tostring(settings.radius))
    self:addChild(self.radiusSpin)
    self.radiusSpin:setVisible(false)
    self.radiusButtons = {}
    for i, spec in ipairs({ { text = "-", delta = -1 }, { text = tostring(settings.radius), delta = 0 }, { text = "+", delta = 1 } }) do
        local b = ISButton:new(0, 0, 1, px(24), spec.text, self, CookItForMePlanUI.onRadiusButton)
        b.internal = spec.delta
        b.fullTitle = spec.text
        b.renderTitle = spec.text
        if spec.delta ~= 0 then b.radiusGlyph = spec.text end
        b.title = ""
        b:initialise(); b:instantiate()
        styleButton(b, THEME.border)
        self:addChild(b)
        self.radiusButtons[i] = b
    end
    self.radiusHint = ISLabel:new(radiusX + px(68), y + px(4), px(18), getText("UI_CookItForMe_SettingsRadiusHintShort"), THEME.secondary.r, THEME.secondary.g, THEME.secondary.b, 1, UIFont.Small, true)
    self.radiusHint:initialise(); self:addChild(self.radiusHint); self.radiusHint:setVisible(false)
    y = y + px(30)
    self.completionSoundTick = ISTickBox:new(px(COL1), y, self.width - px(32), px(24), "", self, CookItForMePlanUI.onCompletionSoundChange)
    self.completionSoundTick:initialise()
    self.completionSoundTick:addOption(getText("UI_CookItForMe_SettingsCompletionSound"))
    self.completionSoundTick:setSelected(1, settings.completionSound)
    self:addChild(self.completionSoundTick)
    self.completionSoundTick:setVisible(false)
    self.soundButton = ISButton:new(0, 0, 1, px(24), getText("UI_CookItForMe_SettingsCompletionSound"), self,
        CookItForMePlanUI.onCompletionSoundButton)
    self.soundButton.fullTitle = getText("UI_CookItForMe_SettingsCompletionSound")
    self.soundButton.title = ""
    self.soundButton:initialise(); self.soundButton:instantiate()
    styleButton(self.soundButton, settings.completionSound and THEME.success or THEME.border)
    self:addChild(self.soundButton)
    self.finishCookingButton = ISButton:new(0, 0, 1, px(24), getText("UI_CookItForMe_SettingsFinishCooking"), self,
        CookItForMePlanUI.onFinishCookingButton)
    self.finishCookingButton.fullTitle = getText("UI_CookItForMe_SettingsFinishCooking")
    self.finishCookingButton.title = ""
    self.finishCookingButton.tooltip = getText("UI_CookItForMe_SettingsFinishCookingTooltip")
    self.finishCookingButton:initialise(); self.finishCookingButton:instantiate()
    styleButton(self.finishCookingButton, settings.finishCooking and THEME.success or THEME.border)
    self:addChild(self.finishCookingButton)
    self.keybindButton = ISButton:new(0, 0, px(120), px(24), "", self, CookItForMePlanUI.onPlanKeyButton)
    self.keybindButton.fullTitle = getKeyName(CookItForMe.getOpenPlanKey())
    self.keybindButton.title = ""
    self.keybindButton.tooltip = getText("UI_CookItForMe_KeybindTooltip")
    self.keybindButton:initialise(); self.keybindButton:instantiate()
    styleButton(self.keybindButton, THEME.border)
    self:addChild(self.keybindButton)
    y = y + px(32)
    -- The preview is a NeatUI smooth scroll view.  The old ISPanel scrollbar
    -- made the plan feel like a debug dump and fought the mouse wheel.
    self.dishRail = ISPanel:new(px(8), self:titleBarHeight() + px(6), self.width - px(16), math.max(px(28), y - self:titleBarHeight() - px(12)))
    self.dishRail:initialise(); self.dishRail:instantiate()
    self.dishRail.prerender = function(panel)
        drawNeatSurface(panel, "media/ui/NeatUI/DefaultPanel/CategoryBG.png", 0, 0, panel.width, panel.height, 1, THEME.panel.r, THEME.panel.g, THEME.panel.b)
        panel:drawText(truncateText(getText("UI_CookItForMe_PlanTitle"), panel.width - px(20), UIFont.Small), px(10), px(5),
            THEME.text.r, THEME.text.g, THEME.text.b, 1, UIFont.Small)
    end
    self:addChild(self.dishRail)
    -- The panel itself renders the rail below the tab controls.  Keeping this
    -- child hidden avoids stealing clicks from the dish buttons on B42 builds
    -- where child z-order also controls mouse capture.
    self.dishRail:setVisible(false)

    self.summaryCard = ISPanel:new(px(8), y - px(4), self.width - px(16), px(58))
    self.summaryCard:initialise(); self.summaryCard:instantiate()
    self.summaryCard.prerender = function(panel)
        drawNeatSurface(panel, "media/ui/NeatUI/DefaultPanel/ContentPanel_BG.png", 0, 0, panel.width, panel.height, 1, THEME.panel.r, THEME.panel.g, THEME.panel.b)
        drawRecipeHeroArt(panel, self)
        local entry = self.entries[self.activeIndex]
        local spine = entry and entry.plan and THEME.accent or THEME.error
        panel:drawRect(0, 0, px(4), panel.height, .95, spine.r, spine.g, spine.b)
        if entry and entry.plan then
            local plan = entry.plan
            local contentX = px(14)
            local detailWidth = panel.width - contentX - px(14)
            panel:drawText(truncateText(getText(Catalog.DISHES[plan.dishKey].label), detailWidth, UIFont.Medium), contentX, px(20),
                THEME.text.r, THEME.text.g, THEME.text.b, 1, UIFont.Medium)
            local water = plan.dish.needsWater and getText("UI_CookItForMe_PlanWaterNeeded") or getText("UI_CookItForMe_PlanWaterNone")
            local equipment = plan.cookware:getDisplayName() .. "  /  " .. water
            equipment = truncateText(equipment, detailWidth, UIFont.Small)
            panel:drawText(equipment, contentX, px(46), THEME.secondary.r, THEME.secondary.g, THEME.secondary.b, 1, UIFont.Small)
            local statsH = px(38)
            local statsY = panel.height - statsH - px(8)
            local statW = math.max(px(76), math.floor((panel.width - px(42)) / 2))
            local statRightX = px(20) + statW
            -- Metrics are cards, not progress bars: saturated full-width
            -- fills made the centre of the UI visually heavy.
            panel:drawRect(px(14), statsY, statW, statsH, 1, THEME.panel.r, THEME.panel.g, THEME.panel.b)
            panel:drawRect(statRightX, statsY, statW, statsH, 1, THEME.panel.r, THEME.panel.g, THEME.panel.b)
            panel:drawRect(px(14), statsY, statW, px(3), 1, THEME.border.r, THEME.border.g, THEME.border.b)
            panel:drawRect(statRightX, statsY, statW, px(3), 1, THEME.border.r, THEME.border.g, THEME.border.b)
            panel:drawRectBorder(px(14), statsY, statW, statsH, 1, THEME.border.r, THEME.border.g, THEME.border.b)
            panel:drawRectBorder(statRightX, statsY, statW, statsH, 1, THEME.border.r, THEME.border.g, THEME.border.b)
            local calories = getText("UI_CookItForMe_PlanCaloriesTotal", tostring(plan.predictedCalories or "?"))
            local hunger = getText("UI_CookItForMe_PlanHunger", tostring(plan.predictedHunger or "?"))
            panel:drawText(truncateText(calories, statW - px(12), UIFont.Small), px(20), statsY - px(4), THEME.text.r, THEME.text.g, THEME.text.b, 1, UIFont.Small)
            panel:drawText(truncateText(hunger, statW - px(12), UIFont.Small), statRightX + px(6), statsY - px(4), THEME.text.r, THEME.text.g, THEME.text.b, 1, UIFont.Small)
        else
            panel:drawText(getText("UI_CookItForMe_PlanTitle"), px(14), px(12), THEME.text.r, THEME.text.g, THEME.text.b, 1, UIFont.Small)
            panel:drawText(failText(entry and entry.failKey), px(14), px(34), THEME.text.r, THEME.text.g, THEME.text.b, 1, UIFont.Small)
        end
    end
    self:addChild(self.summaryCard)

    self.content = NIScrollView:new(px(8), y + px(60), self.width - px(16), self.height - y - px(118))
    self.content.anchorRight = true; self.content.anchorBottom = true
    self.content:initialise(); self.content:instantiate()
    self.content:setAutoHideScrollbar(true)
    self.content.isNeatScrollView = true
    self.details = ISPanel:new(0, 0, self.content.width, 1)
    self.details:initialise(); self.details:instantiate()
    self.details.prerender = function(panel)
        panel:setStencilRect(0, 0, panel.width - px(14), panel.height)
        local top = px(10)
        local fontH = getTextManager():getFontHeight(UIFont.Small)
        local lineH = math.max(px(24), fontH + px(4))
        for _, line in ipairs(self.lines) do
            local words, row, rows = {}, "", {}
            local left = line.tex and px(40) or px(8)
            for word in line.text:gmatch("%S+") do words[#words + 1] = word end
            local function addRow(text)
                if text ~= "" then rows[#rows + 1] = text end
            end
            for _, word in ipairs(words) do
                local candidate = row == "" and word or row .. " " .. word
                if row ~= "" and getTextManager():MeasureStringX(UIFont.Small, candidate) > panel.width - left - px(28) then
                    addRow(row); row = word
                else row = candidate end
                if getTextManager():MeasureStringX(UIFont.Small, row) > panel.width - left - px(28) then
                    local chunk = ""
                    for char in row:gmatch("[^\128-\191][\128-\191]*") do
                        if chunk ~= "" and getTextManager():MeasureStringX(UIFont.Small, chunk .. char) > panel.width - left - px(28) then
                            addRow(chunk); chunk = char
                        else chunk = chunk .. char end
                    end
                    row = chunk
                end
            end
            addRow(row)
            if #rows == 0 then rows[1] = "" end
            local rowH = math.max(lineH + px(8), #rows * lineH + px(8))
            if line.kind == "header" then
                panel:drawRect(px(6), top - px(4), panel.width - px(24), rowH, 1, THEME.panel.r, THEME.panel.g, THEME.panel.b)
                panel:drawRect(px(6), top - px(4), px(4), rowH, 1, THEME.border.r, THEME.border.g, THEME.border.b)
            elseif line.kind == "item" then
                panel:drawRect(px(4), top - px(4), panel.width - px(22), rowH, 1, THEME.panel.r, THEME.panel.g, THEME.panel.b)
                panel:drawRect(px(4), top - px(4), px(2), rowH, 1, THEME.border.r, THEME.border.g, THEME.border.b)
                if line.frozen then panel:drawRect(px(4), top - px(4), px(3), rowH, 1, THEME.frozen.r, THEME.frozen.g, THEME.frozen.b) end
            elseif line.kind == "spice" then
                panel:drawRect(px(4), top - px(4), panel.width - px(22), rowH, 1, THEME.panel.r, THEME.panel.g, THEME.panel.b)
                panel:drawRect(px(4), top - px(4), px(3), rowH, 1, THEME.border.r, THEME.border.g, THEME.border.b)
            end
            if line.tex then
                panel:drawTextureScaled(line.tex, px(8), top + math.floor((rowH - px(24)) / 2) - px(4), px(24), px(24), 1, 1, 1, 1)
            end
            for i, text in ipairs(rows) do
                local textY = top - 5 + (i - 1) * lineH
                if line.kind == "header" then
                    panel:drawText(text, left, textY, THEME.text.r, THEME.text.g, THEME.text.b, 1, UIFont.Small)
                else
                    panel:drawText(text, left, textY, THEME.text.r, THEME.text.g, THEME.text.b, 1, UIFont.Small)
                end
            end
            top = top + rowH + px(4)
        end
        panel:setHeight(top + px(10))
        self.content:setScrollHeight(top + px(10))
        panel:clearStencilRect()
    end
    self.content:addScrollChild(self.details)
    self.content.prerender = function(panel)
        NIScrollView.prerender(panel)
        self.details:prerender()
    end
    self:addChild(self.content)
    local btnY = self.height - self:resizeWidgetHeight() - px(44)
    local function button(xPos, width, title, callback)
        local b = ISButton:new(xPos, btnY, width, px(30), getText(title), self, callback)
        b.anchorTop = false; b.anchorBottom = true
        b:initialise(); b:instantiate()
        self:addChild(b); return b
    end
    self.cookButton = button(px(COL1), px(160), "UI_CookItForMe_PlanCook", CookItForMePlanUI.onCook)
    styleButton(self.cookButton, nil, true)
    self.closeButton = button(px(COL1 + 174), px(110), "UI_CookItForMe_SettingsClose", CookItForMePlanUI.close)
    styleButton(self.closeButton, THEME.border)
end

function CookItForMePlanUI:prerender()
    ISCollapsableWindow.prerender(self)
    if self.isCollapsed then return end
    -- A Lua reload replaces this method but cannot add children to an already
    -- open legacy window.  Let it finish its frame quietly; reopening creates
    -- the new dashboard instead of producing an error every frame.
    if not self.strategyButtons or not self.radiusButtons or not self.soundButton or not self.keybindButton then return end
    local px = function(value) return uiPixel(self, value) end
    drawNeatSurface(self, "media/ui/NeatUI/DefaultPanel/MainPanelBG_FlatTop.png", 0, self:titleBarHeight(), self.width,
        self.height - self:titleBarHeight(), 1, THEME.background.r, THEME.background.g, THEME.background.b)
    local titleH = self:titleBarHeight()
    local pad, railW, gap = px(12), px(188), px(12)
    local railX, railY = pad, titleH + pad
    local mainX = railX + railW + gap
    local mainW = math.max(px(220), self.width - mainX - pad)
    local btnY = self.height - self:resizeWidgetHeight() - px(44)

    -- Left navigation is deliberately fixed and scannable: the player sees
    -- every possible dish and its availability before reading a single line.
    local railH = math.min(math.max(px(80), btnY - railY - px(8)), px(62) + #self.tabButtons * px(54))
    drawNeatSurface(self, "media/ui/NeatUI/DefaultPanel/CategoryBG.png", railX, railY, railW, railH,
        1, THEME.panel.r, THEME.panel.g, THEME.panel.b)
    local railTitle = getText("UI_CookItForMe_PlanDish", ""):gsub(":%s*$", "")
    railTitle = truncateText(railTitle, railW - px(24), UIFont.Small)
    self:drawText(railTitle, railX + px(12), railY + px(10), THEME.text.r, THEME.text.g, THEME.text.b, 1, UIFont.Small)
    for i, button in ipairs(self.tabButtons) do
        button:setX(railX + px(8))
        -- The game font's visual descender extends below its draw origin.
        -- Reserve a whole header row before the first navigation card.
        button:setY(railY + px(50) + (i - 1) * px(54))
        button:setWidth(railW - px(16))
        button:setHeight(px(48))
    end

    self:persistGeometry()
    local compactHeight = self.height < px(500)
    -- The result card no longer has the old status chip and cookware icon,
    -- so reserve that space for the ingredient viewport instead.
    local heroY, heroH = railY, compactHeight and px(120) or px(132)
    self.summaryCard:setX(mainX); self.summaryCard:setY(heroY)
    self.summaryCard:setWidth(mainW); self.summaryCard:setHeight(heroH)

    local settingsY = heroY + heroH + px(10)
    local compactSettings = mainW < px(520)
    local settingsH = compactHeight and px(148) or px(160)
    drawNeatSurface(self, "media/ui/NeatUI/DefaultPanel/ContentPanel_BG.png", mainX, settingsY, mainW, settingsH,
        1, THEME.panel.r, THEME.panel.g, THEME.panel.b)
    local keybindWidth = px(120)
    self.keybindButton:setX(mainX + mainW - keybindWidth - px(12))
    self.keybindButton:setY(settingsY + px(4))
    self.keybindButton:setWidth(keybindWidth)
    self.keybindButton:setHeight(px(24))
    if not self.keyCaptureActive and not self.keyConflictDialog then updatePlanKeyButton(self) end
    self:drawText(truncateText(getText("UI_CookItForMe_Settings"), math.max(px(20), mainW - keybindWidth - px(40)), UIFont.Small), mainX + px(12), settingsY + px(8),
        THEME.secondary.r, THEME.secondary.g, THEME.secondary.b, 1, UIFont.Small)
    self.strategyCombo:setVisible(false)
    -- A label needs more than the nominal font height in PZ: its shadow and
    -- descenders otherwise paint into the controls below it.
    local choiceX, choiceY = mainX + px(12), settingsY + (compactHeight and px(44) or px(48))
    local choiceW = math.floor((mainW - px(32)) / #self.strategyButtons)
    for i, b in ipairs(self.strategyButtons) do
        b:setX(choiceX + (i - 1) * (choiceW + px(4))); b:setY(choiceY)
        b:setWidth(choiceW); b:setHeight(px(28))
    end
    self.radiusSpin:setVisible(false); self.completionSoundTick:setVisible(false)
    local radiusLabel = getText("UI_CookItForMe_SettingsRadius")
    local radiusX = mainX + math.max(px(100), getTextManager():MeasureStringX(UIFont.Small, radiusLabel) + px(24))
    for i, b in ipairs(self.radiusButtons) do
        b:setX(radiusX); b:setY(settingsY + (compactHeight and px(80) or px(86)))
        b:setWidth(i == 2 and px(42) or px(26)); b:setHeight(px(26))
        radiusX = radiusX + b.width + px(3)
    end
    local settingButtonX = mainX + px(12)
    local settingButtonY = settingsY + (compactHeight and px(80) or px(86))
    local settingButtonGap = px(8)
    local settingButtonW
    if compactSettings then
        settingButtonX = mainX + px(12)
        settingButtonY = settingsY + (compactHeight and px(116) or px(122))
        settingButtonW = math.floor((mainW - px(32)) / 2)
    else
        settingButtonX = math.floor(radiusX + px(5))
        local availableRight = mainX + mainW - px(12)
        settingButtonW = math.floor((availableRight - settingButtonX - settingButtonGap) / 2)
    end
    self.soundButton:setX(settingButtonX); self.soundButton:setY(settingButtonY)
    self.soundButton:setWidth(settingButtonW)
    self.finishCookingButton:setX(settingButtonX + settingButtonW + settingButtonGap)
    self.finishCookingButton:setY(settingButtonY)
    self.finishCookingButton:setWidth(settingButtonW)
    self.soundButton:setHeight(px(26))
    self.finishCookingButton:setHeight(px(26))
    self:drawText(truncateText(radiusLabel, math.max(px(20), self.radiusButtons[1].x - mainX - px(20)), UIFont.Small), mainX + px(12),
        settingsY + (compactHeight and px(72) or px(76)), THEME.secondary.r, THEME.secondary.g, THEME.secondary.b, 1, UIFont.Small)
    self.radiusSpin:setWidth(px(62))
    self.strategyLabel:setVisible(false); self.radiusLabel:setVisible(false); self.radiusHint:setVisible(false)

    self.content:setX(mainX); self.content:setY(settingsY + settingsH + px(10))
    self.content:setWidth(mainW)
    self.content:setHeight(math.max(px(32), btnY - self.content.y - px(10)))
    self.details:setWidth(self.content.width)
    drawNeatSurface(self, "media/ui/NeatUI/DefaultPanel/ContentPanel_BG.png", self.content.x, self.content.y,
        self.content.width, self.content.height, 1, THEME.panel.r, THEME.panel.g, THEME.panel.b)

    self.cookButton:setX(mainX); self.cookButton:setWidth(math.max(px(120), mainW * .62)); self.cookButton:setY(btnY)
    self.closeButton:setX(mainX + self.cookButton.width + px(8)); self.closeButton:setWidth(math.max(px(88), mainW - self.cookButton.width - px(8))); self.closeButton:setY(btnY)
    local session = CookItForMe.Cook.getSession()
    local busy = session and session.active
    local entry = self.entries[self.activeIndex]
    self.cookButton:setEnable(not busy and entry ~= nil and entry.plan ~= nil)
    self.title = getText(busy and "UI_CookItForMe_Busy" or "UI_CookItForMe_PlanTitle")
    local tab = self.tabButtons[self.activeIndex]
    if tab then
        self:drawRectBorder(tab.x - 2, tab.y - 2, tab.width + 4, tab.height + 4, 1,
            THEME.accent.r, THEME.accent.g, THEME.accent.b)
    end
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
    local savedW, savedH = tonumber(settings.panelW), tonumber(settings.panelH)
    local hasSavedSize = savedW ~= nil or savedH ~= nil
    local fontHeight = tonumber(getTextManager():getFontHeight(UIFont.Small)) or BASE_FONT_HEIGHT
    local fontScale = math.max(1, fontHeight / BASE_FONT_HEIGHT)
    local layoutScale = hasSavedSize and 1 or fontScale
    local w, h
    if hasSavedSize then
        w = math.min(sw, math.max(math.min(sw, 560), savedW or 1040))
        h = math.min(sh, math.max(math.min(sh, 460), savedH or 640))
    else
        -- Scale the whole first-run layout with the active PZ font. Keep a
        -- margin on both axes so high-font settings remain usable at 1080p.
        local maxW = math.min(sw, math.max(math.min(sw, 560), sw * 0.9))
        local maxH = math.min(sh, math.max(math.min(sh, 460), sh * 0.9))
        local windowScale = math.min(fontScale, maxW / 1040, maxH / 640)
        layoutScale = math.min(fontScale, math.max(1, windowScale))
        w = math.floor(1040 * windowScale + 0.5)
        h = math.floor(640 * windowScale + 0.5)
    end
    local x = hasSavedSize and settings.panelX or nil
    local y = hasSavedSize and settings.panelY or nil
    x = x or ((sw - w) / 2)
    y = y or ((sh - h) / 2)
    x, y = math.max(0, math.min(sw - w, tonumber(x) or 0)), math.max(0, math.min(sh - h, tonumber(y) or 0))
    local o = ISCollapsableWindow.new(self, x, y, w, h)
    setUiScale(o, layoutScale)
    o.minimumWidth = math.min(sw, uiPixel(o, 560))
    o.minimumHeight = math.min(sh, uiPixel(o, 460))
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
