-- Cook It For Me: панель «План готовки» (client, B42)
-- Окно ресайзится игроком, размер и позиция сохраняются.
-- PZ UI widgets receive their fields dynamically from Lua/Java constructors.
---@diagnostic disable: undefined-field, inject-field

require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISComboBox"
require "ISUI/ISSpinBox"
require "ISUI/ISTickBox"
require "ISUI/ISPanel"
require "ISUI/ISTextEntryBox"
require "ISUI/ISModalDialog"
-- NeatUI is a hard dependency.  Keep these requires explicit: the framework's
-- widgets are not guaranteed to be loaded just because another Neat mod is.
require "neatui_framework/scrollview/niscrollbar"
local NIScrollView = require "neatui_framework/scrollview/niscrollview"
require "neatui_framework/neattool/neattool_truncatetext"
require "CookItForMe_Shared"
local Catalog = require "CookItForMe_Dishes"
local Forecast = require "CookItForMe_Forecast"
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
local FROZEN_ICON

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
    button.fullTitle = button.fullTitle or button.title or ""
    button.title = "" -- ISButton:render draws title again after our custom prerender.
    button:setDisplayBackground(false)
    button.prerender = function(b)
        local c = color or THEME.border
        local hot = b:isMouseOver()
        local fill = primary and (b.enable == false and THEME.error or THEME.success)
            or (hot and THEME.hover or THEME.panel)
        local ink = primary and THEME.text
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
            local icon = b.pickerItem and b.pickerItem:getTexture() or nil
            local iconSize = icon and math.min(uiPixel(b.target, 24), b.height - uiPixel(b.target, 8)) or 0
            if icon then b:drawTextureScaled(icon, uiPixel(b.target, 8), math.floor((b.height - iconSize) / 2),
                iconSize, iconSize, 1, 1, 1, 1) end
            local title = truncateText(b.renderTitle or b.fullTitle or b.title or "",
                b.width - iconSize - uiPixel(b.target, 26), UIFont.Small)
            b:drawTextCentre(title, (b.width + iconSize) / 2, math.floor((b.height - getTextManager():getFontHeight(UIFont.Small)) / 2),
                ink.r, ink.g, ink.b, b.enable == false and not primary and .8 or 1, UIFont.Small)
        end
        b:updateTooltip()
    end
end

local function styleIngredientAction(button, remove)
    button.title = "" -- The action glyph is painted by this custom renderer.
    button:setDisplayBackground(false)
    button.prerender = function(b)
        local px = function(v) return uiPixel(b.target, v) end
        local hot = b.enable ~= false and b:isMouseOver()
        local fill = hot and THEME.hover or THEME.panel
        local edge = hot and (remove and THEME.error or THEME.accent) or THEME.border
        local ink = b.enable == false and THEME.secondary
            or (remove and (hot and THEME.error or THEME.secondary) or (hot and THEME.accent or THEME.text))
        drawNeatSurface(b, "media/ui/NeatUI/DefaultPanel/ContentPanel_BG.png", 0, 0, b.width, b.height,
            1, THEME.panel.r, THEME.panel.g, THEME.panel.b)
        b:drawRect(1, 1, b.width - 2, b.height - 2, 1, fill.r, fill.g, fill.b)
        b:drawRectBorder(0, 0, b.width, b.height, hot and 1 or .7, edge.r, edge.g, edge.b)
        b:drawRect(px(3), px(2), b.width - px(6), 1, hot and .24 or .12,
            THEME.text.r, THEME.text.g, THEME.text.b)
        if remove then
            b:drawTextCentre("x", b.width / 2, math.floor((b.height - getTextManager():getFontHeight(UIFont.Small)) / 2),
                ink.r, ink.g, ink.b, b.enable == false and .7 or 1, UIFont.Small)
        else
            -- Use filled pixels: ISUIElement:drawLine2 can disappear on buttons in-game.
            local cx, cy = math.floor(b.width / 2), math.floor(b.height / 2)
            local alpha = b.enable == false and .7 or 1
            local function pixel(x, y, w, h)
                b:drawRect(x, y, w, h, alpha, ink.r, ink.g, ink.b)
            end
            pixel(cx - px(9), cy - px(5), px(16), px(2))
            pixel(cx + px(5), cy - px(8), px(2), px(2))
            pixel(cx + px(7), cy - px(6), px(3), px(4))
            pixel(cx + px(5), cy - px(2), px(2), px(2))
            pixel(cx - px(7), cy + px(4), px(16), px(2))
            pixel(cx - px(7), cy + px(2), px(2), px(2))
            pixel(cx - px(10), cy + px(3), px(3), px(4))
            pixel(cx - px(7), cy + px(7), px(2), px(2))
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

local function searchFold(value)
    local bytes, out = { (value or ""):lower():byte(1, #(value or "")) }, {}
    local i = 1
    while i <= #bytes do
        local first, second = bytes[i], bytes[i + 1]
        if first == 0xD0 and second and second >= 0x90 and second <= 0x9F then
            out[#out + 1] = string.char(0xD0, second + 0x20); i = i + 2
        elseif first == 0xD0 and second and second >= 0xA0 and second <= 0xAF then
            ---@diagnostic disable-next-line: param-type-mismatch
            out[#out + 1] = string.char(0xD1, second - 0x20); i = i + 2
        elseif first == 0xD0 and second == 0x81 then
            out[#out + 1] = string.char(0xD1, 0x91); i = i + 2
        elseif first == 0xC3 and second and second >= 0x80 and second <= 0x9E and second ~= 0x97 then
            out[#out + 1] = string.char(0xC3, second + 0x20); i = i + 2
        else
            out[#out + 1] = string.char(first); i = i + 1
        end
    end
    return table.concat(out)
end

local function sortName(name)
    local folded = searchFold(name or "")
    return (folded:gsub(string.char(0xD1, 0x91), string.char(0xD0, 0xB5) .. "~"))
end

local function sortedEntries(entries, sort)
    if not sort then return entries end
    table.sort(entries, function(a, b)
        if a.empty ~= b.empty then return not a.empty end
        local av = sort.key == "name" and sortName(a.name) or a[sort.key]
        local bv = sort.key == "name" and sortName(b.name) or b[sort.key]
        if av == nil or bv == nil then
            if av ~= bv then return av ~= nil end
        elseif av ~= bv then
            if sort.descending then return av > bv end
            return av < bv
        end
        local an, bn = sortName(a.name), sortName(b.name)
        if an ~= bn then return an < bn end
        return (a.id or 0) < (b.id or 0)
    end)
    return entries
end

local function nextSort(current, key)
    if current and current.key == key then return { key = key, descending = not current.descending } end
    return { key = key, descending = key ~= "name" }
end

local function savedSort(settings, prefix)
    local key = settings[prefix .. "Key"]
    if key ~= "name" and key ~= "calories" and key ~= "hunger" then
        return { key = "hunger", descending = true }
    end
    return { key = key, descending = settings[prefix .. "Descending"] == true }
end

local function drawSortArrow(panel, zone, descending, px)
    local x = zone[1] + zone[2] - px(17)
    local y = math.floor((panel.height - px(12)) / 2)
    local ink = THEME.accent
    local function bar(dx, dy, w, h)
        panel:drawRect(x + px(dx), y + px(dy), px(w), px(h), 1, ink.r, ink.g, ink.b)
    end
    if descending then
        bar(4, 0, 2, 7)
        bar(0, 6, 10, 2)
        bar(2, 8, 6, 2)
        bar(4, 10, 2, 2)
    else
        bar(4, 0, 2, 2)
        bar(2, 2, 6, 2)
        bar(0, 4, 10, 2)
        bar(4, 6, 2, 6)
    end
end

-- Рендер-строки: {kind="text", text} | {kind="header", text} | {kind="item", tex, text}
local function buildRenderLines(entries, activeIndex, sort)
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

    for _, group in ipairs({ { kind = "food", count = #picked.items, label = "UI_CookItForMe_GroupFoods" },
        { kind = "spice", count = #picked.spices, label = "UI_CookItForMe_GroupSpices" } }) do
        table.insert(lines, { kind = "group", text = getText(group.label, tostring(group.count)) })
        local groupLines = {}
        for _, row in ipairs(plan.rows or {}) do
            if row.kind == group.kind then
                local item = row.item
                if item then
                    local calories = nil
                    local ok, value = pcall(Forecast.contribution, plan.player, plan.recipe, item, "max")
                    if ok then calories = math.floor(value + 0.5) end
                    local hunger = nil
                    ok, value = pcall(Forecast.contribution, plan.player, plan.recipe, item, "hunger")
                    if ok and value ~= nil then hunger = math.floor(value + 0.5) end
                    table.insert(groupLines, { kind = "ingredient", id = row.id, name = item:getDisplayName(),
                        item = item, tex = item:getTexture(), calories = calories, hunger = hunger })
                else
                    local label = getText(row.kind == "food" and "UI_CookItForMe_AddFood" or "UI_CookItForMe_AddSpice")
                    table.insert(groupLines, { kind = "ingredient", id = row.id, empty = true, name = label })
                end
            end
        end
        for _, line in ipairs(sortedEntries(groupLines, sort)) do table.insert(lines, line) end
    end

    return lines
end

local IngredientPicker = ISCollapsableWindow:derive("CookItForMeIngredientPicker")

local function pickerColumns(panel, width)
    local px = function(v) return uiPixel(panel, v) end
    local measure = function(key) return getTextManager():MeasureStringX(UIFont.Small, getText(key)) end
    local calW = math.ceil(measure("UI_CookItForMe_CalInDish") + px(30))
    local hungerW = math.ceil(measure("UI_CookItForMe_HungerInDish") + px(30))
    local nameW = width - calW - hungerW
    return { nameW = nameW, calW = calW, hungerW = hungerW, compact = nameW < px(150) }
end

local function stylePickerRow(button)
    button:setDisplayBackground(false)
    button.prerender = function(b)
        local px = function(v) return uiPixel(b.target, v) end
        local cols = pickerColumns(b.target.picker, b.width)
        local fill = b:isMouseOver() and THEME.hover or THEME.panel
        b:drawRect(0, 0, b.width, b.height, 1, fill.r, fill.g, fill.b)
        b:drawRect(0, b.height - 1, b.width, 1, .7, THEME.border.r, THEME.border.g, THEME.border.b)
        local fontH = getTextManager():getFontHeight(UIFont.Small)
        local textY = cols.compact and px(5) or math.floor((b.height - fontH) / 2)
        local icon = b.pickerItem and b.pickerItem:getTexture() or nil
        local iconSize = math.min(px(24), b.height - px(8))
        if icon then b:drawTextureScaled(icon, px(6), math.floor((b.height - iconSize) / 2),
            iconSize, iconSize, 1, 1, 1, 1) end
        local nameX = icon and px(36) or px(8)
        local nameRight = cols.compact and b.width - px(8) or cols.nameW - px(8)
        local name = truncateText(b.fullTitle, nameRight - nameX, UIFont.Small)
        local nameCenter = nameX + getTextManager():MeasureStringX(UIFont.Small, name) / 2
        b:drawTextCentre(name, nameCenter, textY,
            THEME.text.r, THEME.text.g, THEME.text.b, 1, UIFont.Small)
        local cal, hunger = b.calories and tostring(b.calories) or "?", b.hunger and tostring(b.hunger) or "?"
        if cols.compact then
            local summary = getText("UI_CookItForMe_CompactRow", cal) .. " / "
                .. getText("UI_CookItForMe_HungerInDish") .. ": " .. hunger
            summary = truncateText(summary, b.width - px(16), UIFont.Small)
            b:drawTextCentre(summary, px(8) + getTextManager():MeasureStringX(UIFont.Small, summary) / 2, textY + fontH,
                THEME.secondary.r, THEME.secondary.g, THEME.secondary.b, 1, UIFont.Small)
        else
            b:drawTextRight(cal, cols.nameW + cols.calW - px(8), textY,
                THEME.text.r, THEME.text.g, THEME.text.b, 1, UIFont.Small)
            b:drawTextRight(hunger, b.width - px(8), textY,
                THEME.text.r, THEME.text.g, THEME.text.b, 1, UIFont.Small)
        end
        b:updateTooltip()
    end
end

function IngredientPicker:close()
    self.owner:closePicker()
end

function IngredientPicker:createChildren()
    ISCollapsableWindow.createChildren(self)
    if self.collapseButton then self.collapseButton:setVisible(false) end
    local px = function(value) return uiPixel(self, value) end
    local inset = px(12)
    local fontH = getTextManager():getFontHeight(UIFont.Small)
    local searchH = math.max(px(24), fontH + px(2))
    local buttonH = math.max(px(24), fontH + px(2))
    local searchY = self:titleBarHeight() + px(12)
    local headerY = searchY + searchH + px(8)
    local headerH = fontH + px(12)
    local listY = headerY + headerH + px(2)
    local footerH = buttonH + px(14)
    local footerY = self.height - self:resizeWidgetHeight() - footerH
    local cancelY = footerY + px(5)

    self.search = ISTextEntryBox:new("", inset, searchY, self.width - inset * 2, searchH)
    self.search:initialise(); self.search:instantiate()
    self.search.onTextChange = function() self.owner:refreshPicker() end
    self:addChild(self.search)

    self.header = ISPanel:new(inset, headerY, self.width - inset * 2, headerH)
    self.header:initialise(); self.header:instantiate()
    self.header.background = false
    self.header.prerender = function(panel)
        local cols = pickerColumns(self, panel.width - px(12))
        panel:drawRect(0, 0, panel.width, panel.height, 1, THEME.panel.r, THEME.panel.g, THEME.panel.b)
        panel:drawRect(0, panel.height - 1, panel.width, 1, 1, THEME.border.r, THEME.border.g, THEME.border.b)
        local zones
        if cols.compact then
            local third = math.floor(panel.width / 3)
            zones = { name = { 0, third }, calories = { third, third },
                hunger = { third * 2, panel.width - third * 2 } }
        else
            zones = { name = { 0, cols.nameW }, calories = { cols.nameW, cols.calW },
                hunger = { cols.nameW + cols.calW, cols.hungerW } }
        end
        for key, zone in pairs(zones) do
            local button = self.sortButtons[key]
            button:setX(zone[1]); button:setY(0); button:setWidth(zone[2]); button:setHeight(panel.height)
            if button:isMouseOver() then
                panel:drawRect(zone[1], 0, zone[2], panel.height, .55, THEME.hover.r, THEME.hover.g, THEME.hover.b)
            end
            if self.owner.pickerSort.key == key then
                panel:drawRect(zone[1] + px(4), panel.height - px(3), math.max(1, zone[2] - px(8)), px(2), 1,
                    THEME.accent.r, THEME.accent.g, THEME.accent.b)
                drawSortArrow(panel, zone, self.owner.pickerSort.descending, px)
            end
        end
        local ingredient = getText("UI_CookItForMe_Ingredient")
        panel:drawText(truncateText(ingredient, zones.name[2] - px(self.owner.pickerSort.key == "name" and 28 or 12), UIFont.Small), px(8), px(5),
            THEME.secondary.r, THEME.secondary.g, THEME.secondary.b, 1, UIFont.Small)
        if not cols.compact then
            panel:drawTextRight(getText("UI_CookItForMe_CalInDish"), cols.nameW + cols.calW - px(self.owner.pickerSort.key == "calories" and 24 or 8), px(5),
                THEME.secondary.r, THEME.secondary.g, THEME.secondary.b, 1, UIFont.Small)
            panel:drawTextRight(getText("UI_CookItForMe_HungerInDish"), panel.width - px(self.owner.pickerSort.key == "hunger" and 36 or 20), px(5),
                THEME.secondary.r, THEME.secondary.g, THEME.secondary.b, 1, UIFont.Small)
        else
            for _, key in ipairs({ "calories", "hunger" }) do
                local zone = zones[key]
                local labelKey = key == "calories" and "UI_CookItForMe_CalInDish" or "UI_CookItForMe_HungerInDish"
                local label = getText(labelKey)
                panel:drawText(truncateText(label, zone[2] - px(self.owner.pickerSort.key == key and 24 or 8), UIFont.Small), zone[1] + px(4), px(5),
                    THEME.secondary.r, THEME.secondary.g, THEME.secondary.b, 1, UIFont.Small)
            end
        end
    end
    self:addChild(self.header)
    self.sortButtons = {}
    for _, spec in ipairs({ { key = "name", label = "UI_CookItForMe_Ingredient" },
        { key = "calories", label = "UI_CookItForMe_CalInDish" },
        { key = "hunger", label = "UI_CookItForMe_HungerInDish" } }) do
        local button = ISButton:new(0, 0, 1, headerH, "", self.owner, CookItForMePlanUI.onSortPicker)
        button.sortKey = spec.key
        button.tooltip = getText(spec.label)
        button:initialise(); button:instantiate(); button:setDisplayBackground(false)
        self.header:addChild(button)
        self.sortButtons[spec.key] = button
    end

    self.scroll = NIScrollView:new(inset, listY, self.width - inset * 2, footerY - listY - px(8))
    self.scroll:initialise(); self.scroll:instantiate()
    self.scroll:setAutoHideScrollbar(true)
    self.list = ISPanel:new(0, 0, self.scroll.width, 1)
    self.list:initialise(); self.list:instantiate()
    self.list.prerender = function(list)
        if self.owner.pickerEmpty then
            local message = getText(self.owner.pickerEmptyText or "UI_CookItForMe_NoAlternatives")
            list:drawText(truncateText(message, list.width - px(20), UIFont.Small), px(8), px(8),
                THEME.secondary.r, THEME.secondary.g, THEME.secondary.b, 1, UIFont.Small)
        end
    end
    self.scroll:addScrollChild(self.list)
    self:addChild(self.scroll)

    self.footer = ISPanel:new(0, footerY, self.width, footerH)
    self.footer:initialise(); self.footer:instantiate()
    self.footer.background = false
    self.footer.prerender = function(panel)
        panel:drawRect(0, 0, panel.width, panel.height, 1, THEME.panel.r, THEME.panel.g, THEME.panel.b)
        panel:drawRect(0, 0, panel.width, 1, 1, THEME.border.r, THEME.border.g, THEME.border.b)
    end
    self:addChild(self.footer)

    local closeText = getText("UI_CookItForMe_SettingsClose")
    local closeW = math.max(px(190), getTextManager():MeasureStringX(UIFont.Small, closeText) + px(40))
    self.cancel = ISButton:new(self.width - inset - closeW, cancelY, closeW, buttonH,
        "", self.owner, CookItForMePlanUI.closePicker)
    self.cancel.fullTitle = closeText
    self.cancel:initialise(); self.cancel:instantiate(); styleButton(self.cancel, THEME.border)
    self:addChild(self.cancel)

    self.owner.pickerSearch = self.search
    self.owner.pickerHeader = self.header
    self.owner.pickerScroll = self.scroll
    self.owner.pickerList = self.list
    self.owner.pickerFooter = self.footer
    self.owner.pickerCancel = self.cancel
end

function IngredientPicker:prerender()
    ISCollapsableWindow.prerender(self)
    if self.isCollapsed then return end
    if self.width ~= self.initialWidth or self.height ~= self.initialHeight then self.userResized = true end
    local inset = uiPixel(self, 12)
    local width = self.width - inset * 2
    self.search:setWidth(width)
    self.header:setWidth(width)
    self.footer:setY(self.height - self:resizeWidgetHeight() - self.footer.height)
    self.footer:setWidth(self.width)
    self.scroll:setWidth(width)
    self.scroll:setHeight(self.footer.y - self.scroll.y - uiPixel(self, 8))
    self.list:setWidth(width)
    self.cancel:setX(self.width - inset - self.cancel.width)
    self.cancel:setY(self.footer.y + uiPixel(self, 5))
    for _, button in ipairs(self.owner.pickerButtons or {}) do
        button:setWidth(width - uiPixel(self, 12))
    end
    self.title = truncateText(self.fullTitle, self.width - uiPixel(self, 70), UIFont.Small)
    local th = self:titleBarHeight()
    drawNeatSurface(self, "media/ui/NeatUI/DefaultPanel/ContentPanel_BG.png", 0, th, self.width,
        self.height - th, 1, THEME.panel.r, THEME.panel.g, THEME.panel.b)
end

local function createIngredientPicker(owner, title)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local settings = CookItForMe.getSettings(getSpecificPlayer(owner.player))
    local maxW, maxH = math.max(1, sw - uiPixel(owner, 24)), math.max(1, sh - uiPixel(owner, 24))
    local minW, minH = math.min(maxW, uiPixel(owner, 580)), math.min(maxH, uiPixel(owner, 220))
    local w = math.min(maxW, math.max(minW, tonumber(settings.pickerW) or uiPixel(owner, 860)))
    local h = math.min(maxH, math.max(minH, tonumber(settings.pickerH) or uiPixel(owner, 560)))
    local x = math.max(0, math.min(sw - w, math.floor(owner.x + (owner.width - w) / 2)))
    local y = math.max(0, math.min(sh - h, math.floor(owner.y + (owner.height - h) / 2)))
    local picker = ISCollapsableWindow.new(IngredientPicker, x, y, w, h)
    setUiScale(picker, UI_SCALE[owner] or 1)
    picker.owner = owner
    picker.title = truncateText(title, w - uiPixel(owner, 70), UIFont.Small)
    picker.fullTitle = title
    picker.initialWidth, picker.initialHeight = w, h
    picker.moveWithMouse = true
    picker.keepOnScreen = true
    picker.minimumWidth, picker.minimumHeight = minW, minH
    picker:setResizable(true)
    picker:initialise()
    picker:addToUIManager()
    picker:setAlwaysOnTop(true)
    picker:bringToTop()
    return picker
end

function CookItForMePlanUI:close()
    if self.picker then self:closePicker() end
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
function CookItForMePlanUI:rebuild(preserveEdits)
    local p = getSpecificPlayer(self.player)
    local entries = {}
    for _, key in ipairs(CookItForMe.Cook.ALL_DISHES) do
        local plan, failKey = CookItForMe.Cook.plan(p, key)
        if preserveEdits ~= false then
            for _, old in ipairs(self.entries) do
                if old.key == key and old.plan and old.plan.edited then
                    -- Retain manual composition when changing settings other than strategy.
                    -- Its old items are checked against the current scan before cooking.
                    old.plan.settings = CookItForMe.getSettings(p)
                    if plan then old.plan.scan = plan.scan end
                    plan, failKey = old.plan, nil
                    break
                end
            end
        end
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
    panel:rebuild(false)
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
    self:rebuild(false)
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
    if ok then self:close() else self.lastValidationAt = nil end
end

function CookItForMePlanUI:onSwitchDish(button)
    local i = button.internal
    if i == self.activeIndex then return end
    if self.pickerVisible then self:closePicker() end
    -- просто переключаем вкладку и перерисовываем содержимое (не пересоздаём окно)
    self.activeIndex = i
    self.lines = buildRenderLines(self.entries, i, self.ingredientSort)
    self.notice = nil
    self.lastValidationAt = nil
    self:syncRows()
    self.content:setYScroll(0)
end

function CookItForMePlanUI:refreshIngredients()
    self.lines = buildRenderLines(self.entries, self.activeIndex, self.ingredientSort)
    self.lastValidationAt = nil
    self:syncRows()
end

function CookItForMePlanUI:onSortIngredients(button)
    self.ingredientSort = nextSort(self.ingredientSort, button.sortKey)
    CookItForMe.saveSettings(getSpecificPlayer(self.player), {
        ingredientSortKey = self.ingredientSort.key,
        ingredientSortDescending = self.ingredientSort.descending,
    })
    self:refreshIngredients()
end

function CookItForMePlanUI:onRemoveIngredient(button)
    local entry = self.entries[self.activeIndex]
    ---@diagnostic disable-next-line: unnecessary-if
    if not entry or not entry.plan or (CookItForMe.Cook.getSession() or {}).active then return end
    local removal = CookItForMe.Cook.planEditor.remove(entry.plan, button.rowId)
    if not removal then return end
    self.notice = { removal = removal, plan = entry.plan,
        text = getText("UI_CookItForMe_RowRemoved", removal.item:getDisplayName()) }
    self:refreshIngredients()
end

function CookItForMePlanUI:onUndoIngredient()
    ---@diagnostic disable-next-line: unnecessary-if
    if (CookItForMe.Cook.getSession() or {}).active then return end
    local notice = self.notice
    if not notice or not notice.removal then return end
    if notice.plan == self.entries[self.activeIndex].plan then
        CookItForMe.Cook.planEditor.undo(notice.plan, notice.removal)
    end
    self.notice = nil
    self:refreshIngredients()
end

function CookItForMePlanUI:onResetIngredients()
    local entry = self.entries[self.activeIndex]
    if not entry or not entry.plan or (CookItForMe.Cook.getSession() or {}).active then return end
    local ok, key = CookItForMe.Cook.planEditor.reset(getSpecificPlayer(self.player), entry.plan)
    if not ok then self.notice = { text = failText(key) } else self.notice = nil end
    self:refreshIngredients()
end

local function layoutColumns(panel, width)
    local px = function(v) return uiPixel(panel, v) end
    local measure = function(key) return getTextManager():MeasureStringX(UIFont.Small, getText(key)) end
    local replaceW = math.max(px(34), getTextManager():getFontHeight(UIFont.Small) + px(8))
    local removeW = replaceW
    local actionW = math.max(replaceW + removeW + px(12), math.ceil(measure("UI_CookItForMe_Actions") + px(12)))
    local calW = math.ceil(measure("UI_CookItForMe_CalInDish") + px(30))
    local hungerW = math.ceil(measure("UI_CookItForMe_HungerInDish") + px(30))
    local nameW = width - actionW - calW - hungerW - px(12)
    local minNameW = math.max(px(126), measure("UI_CookItForMe_Unavailable") + px(100))
    return { compact = nameW < minNameW, nameW = nameW, calW = calW, hungerW = hungerW,
        actionW = actionW, replaceW = replaceW, removeW = removeW, width = width }
end

function CookItForMePlanUI:syncRows()
    if not self.details then return end
    self.rowWidgets = self.rowWidgets or {}
    for _, widget in pairs(self.rowWidgets) do widget:setVisible(false) end
    local entry = self.entries[self.activeIndex]
    if not entry or not entry.plan then return end
    for _, line in ipairs(self.lines) do
        if line.kind == "ingredient" then
            local key = entry.key .. ":" .. line.id
            local row = self.rowWidgets[key]
            if not row then
                row = ISPanel:new(0, 0, self.details.width, 1)
                row:initialise(); row:instantiate()
                row.owner = self
                row.nameButton = ISButton:new(0, 0, 1, 1, "", self, function(owner, button)
                    if button.emptySlot then owner:onReplaceIngredient(button) end
                end)
                row.nameButton.rowId = line.id
                row.nameButton:initialise(); row.nameButton:instantiate()
                row.nameButton:setDisplayBackground(false)
                row.nameButton.prerender = function(b) b:updateTooltip() end
                row:addChild(row.nameButton)
                row.replaceButton = ISButton:new(0, 0, 1, 1, "", self, CookItForMePlanUI.onReplaceIngredient)
                row.replaceButton.rowId = line.id
                row.replaceButton:initialise(); row.replaceButton:instantiate()
                styleIngredientAction(row.replaceButton, false)
                row:addChild(row.replaceButton)
                row.removeButton = ISButton:new(0, 0, 1, 1, "x", self, CookItForMePlanUI.onRemoveIngredient)
                row.removeButton.rowId = line.id
                row.removeButton.tooltip = getText("UI_CookItForMe_RemoveFromPlan")
                row.removeButton:initialise(); row.removeButton:instantiate()
                styleIngredientAction(row.removeButton, true)
                row:addChild(row.removeButton)
                ---@diagnostic disable-next-line: redundant-parameter
                row.prerender = function(widget)
                    local owner, data = widget.owner, widget.data
                    local px = function(v) return uiPixel(owner, v) end
                    local cols = layoutColumns(owner, widget.width)
                    local fontH = getTextManager():getFontHeight(UIFont.Small)
                    local nameY = cols.compact and px(7) or math.floor((widget.height - fontH) / 2)
                    local hot = widget:isMouseOver() or (data.empty and widget.nameButton:isMouseOver())
                    if hot then widget:drawRect(0, 0, widget.width, widget.height, .65, THEME.hover.r, THEME.hover.g, THEME.hover.b) end
                    widget:drawRect(0, widget.height - 1, widget.width, 1, .7, THEME.border.r, THEME.border.g, THEME.border.b)
                    if data.empty then
                        local iconX, iconY = px(14), nameY + math.floor(fontH / 2)
                        widget:drawRect(iconX - px(5), iconY - px(1), px(10), px(2), 1,
                            THEME.secondary.r, THEME.secondary.g, THEME.secondary.b)
                        widget:drawRect(iconX - px(1), iconY - px(5), px(2), px(10), 1,
                            THEME.secondary.r, THEME.secondary.g, THEME.secondary.b)
                        widget:drawText(truncateText(data.name, widget.width - px(48), UIFont.Small), px(34), nameY,
                            THEME.secondary.r, THEME.secondary.g, THEME.secondary.b, 1, UIFont.Small)
                        widget.nameButton:setX(0); widget.nameButton:setY(0)
                        widget.nameButton:setWidth(widget.width); widget.nameButton:setHeight(widget.height)
                        widget.nameButton:setEnable(not owner.busy)
                        return
                    end
                    if data.tex then widget:drawTextureScaled(data.tex, px(5), nameY + math.floor((fontH - px(24)) / 2),
                        px(24), px(24), 1, 1, 1, 1) end
                    local frozen = data.item:isFrozen()
                    local unavailable = owner.rowStatus and owner.rowStatus[data.id] == false
                    local nameX = frozen and px(54) or px(34)
                    if frozen then
                        if not FROZEN_ICON then FROZEN_ICON = getTexture("media/ui/icon_frozen.png") end
                        if FROZEN_ICON then widget:drawTextureScaled(FROZEN_ICON, px(34), nameY + math.floor((fontH - px(16)) / 2), px(16), px(16),
                            1, THEME.frozen.r, THEME.frozen.g, THEME.frozen.b) end
                    end
                    local actionsX = widget.width - cols.actionW
                    local badge = unavailable and getText("UI_CookItForMe_Unavailable") or nil
                    local badgeX = badge and cols.nameW - getTextManager():MeasureStringX(UIFont.Small, badge) - px(6) or nil
                    local nameRight = cols.compact and actionsX - px(8) or (badgeX and badgeX - px(8) or cols.nameW - px(8))
                    widget:drawText(truncateText(data.name, nameRight - nameX, UIFont.Small), nameX, nameY,
                        THEME.text.r, THEME.text.g, THEME.text.b, 1, UIFont.Small)
                    if cols.compact then
                        local sub = getText("UI_CookItForMe_CompactRow", data.calories and tostring(data.calories) or "?")
                        widget:drawText(truncateText(sub, actionsX - px(42), UIFont.Small), px(34), nameY + fontH,
                            THEME.secondary.r, THEME.secondary.g, THEME.secondary.b, 1, UIFont.Small)
                        local hunger = getText("UI_CookItForMe_HungerInDish") .. ": " .. (data.hunger and tostring(data.hunger) or "?")
                        widget:drawText(truncateText(hunger, actionsX - px(42), UIFont.Small), px(34), nameY + fontH * 2,
                            THEME.secondary.r, THEME.secondary.g, THEME.secondary.b, 1, UIFont.Small)
                        if badge then widget:drawText(truncateText(badge, actionsX - px(42), UIFont.Small),
                            px(34), nameY + fontH * 3,
                            THEME.error.r, THEME.error.g, THEME.error.b, 1, UIFont.Small) end
                    else
                        if badge then widget:drawText(badge, badgeX, nameY,
                            THEME.error.r, THEME.error.g, THEME.error.b, 1, UIFont.Small) end
                        widget:drawTextRight(data.calories and tostring(data.calories) or "?", cols.nameW + cols.calW - px(9), nameY,
                            THEME.text.r, THEME.text.g, THEME.text.b, 1, UIFont.Small)
                        widget:drawTextRight(data.hunger and tostring(data.hunger) or "?", cols.nameW + cols.calW + cols.hungerW - px(9), nameY,
                            THEME.text.r, THEME.text.g, THEME.text.b, 1, UIFont.Small)
                    end
                    widget.nameButton.tooltip = data.name .. (frozen and " (" .. getText("UI_CookItForMe_Frozen") .. ")" or "")
                    widget.nameButton:setX(0); widget.nameButton:setY(0)
                    widget.nameButton:setWidth(cols.compact and actionsX or cols.nameW)
                    widget.nameButton:setHeight(widget.height)
                    local buttonH = math.max(px(26), getTextManager():getFontHeight(UIFont.Small) + px(8))
                    local buttonY = math.floor((widget.height - buttonH) / 2)
                    local buttonsX = widget.width - cols.replaceW - cols.removeW - px(9)
                    widget.replaceButton:setX(buttonsX); widget.replaceButton:setY(buttonY)
                    widget.replaceButton:setWidth(cols.replaceW); widget.replaceButton:setHeight(buttonH)
                    widget.removeButton:setX(buttonsX + cols.replaceW + px(6)); widget.removeButton:setY(buttonY)
                    widget.removeButton:setWidth(cols.removeW); widget.removeButton:setHeight(buttonH)
                    widget.replaceButton:setEnable(not owner.busy)
                    widget.removeButton:setEnable(not owner.busy)
                end
                self.details:addChild(row)
                self.rowWidgets[key] = row
            end
            row.data = line
            row.nameButton.emptySlot = line.empty == true
            row.nameButton.tooltip = line.name
            row.replaceButton:setVisible(not line.empty)
            row.removeButton:setVisible(not line.empty)
            if not line.empty then
                row.replaceButton.tooltip = getText("UI_CookItForMe_ReplaceTitle", line.name)
            end
            row:setVisible(true)
        end
    end
end

function CookItForMePlanUI:onReplaceIngredient(button)
    local entry = self.entries[self.activeIndex]
    ---@diagnostic disable-next-line: unnecessary-if
    if not entry or not entry.plan or (CookItForMe.Cook.getSession() or {}).active then return end
    local target
    for _, row in ipairs(entry.plan.rows) do if row.id == button.rowId then target = row break end end
    if not target then return end
    self.pickerTitle = target.item and getText("UI_CookItForMe_ReplaceTitle", target.item:getDisplayName())
        or getText(target.kind == "food" and "UI_CookItForMe_AddFoodTitle" or "UI_CookItForMe_AddSpiceTitle")
    if self.picker then self:closePicker() end
    self.pickerRowId = target.id
    self.pickerAdding = target.item == nil
    self.picker = createIngredientPicker(self, self.pickerTitle)
    self.pickerButtons = {}
    self.pickerSearch:setText("")
    self.pickerVisible = true
    self:refreshPicker()
end

function CookItForMePlanUI:closePicker()
    if self.picker then
        if self.picker.userResized or self.picker.width ~= self.picker.initialWidth
            or self.picker.height ~= self.picker.initialHeight then
            CookItForMe.saveSettings(getSpecificPlayer(self.player), {
                pickerW = math.floor(self.picker.width), pickerH = math.floor(self.picker.height) })
        end
        self.picker:setVisible(false)
        self.picker:removeFromUIManager()
    end
    self.picker = nil
    self.pickerVisible = false
    self.pickerRowId = nil
    self.pickerAdding = nil
    self.pickerSearch, self.pickerHeader, self.pickerScroll, self.pickerList = nil, nil, nil, nil
    self.pickerFooter, self.pickerCancel, self.pickerButtons = nil, nil, nil
end

function CookItForMePlanUI:onPickIngredient(button)
    ---@diagnostic disable-next-line: unnecessary-if
    if (CookItForMe.Cook.getSession() or {}).active then return end
    local entry = self.entries[self.activeIndex]
    if not entry or not entry.plan or not self.pickerRowId then return end
    if CookItForMe.Cook.planEditor.replace(getSpecificPlayer(self.player), entry.plan, self.pickerRowId, button.item) then
        self.notice = nil
        self:closePicker()
        self:refreshIngredients()
    else
        self:refreshPicker()
    end
end

function CookItForMePlanUI:onSortPicker(button)
    self.pickerSort = nextSort(self.pickerSort, button.sortKey)
    CookItForMe.saveSettings(getSpecificPlayer(self.player), {
        pickerSortKey = self.pickerSort.key,
        pickerSortDescending = self.pickerSort.descending,
    })
    self:refreshPicker()
end

function CookItForMePlanUI:refreshPicker()
    if not self.pickerRowId then return end
    self.pickerItems = CookItForMe.Cook.planEditor.alternatives(getSpecificPlayer(self.player),
        self.entries[self.activeIndex].plan, self.pickerRowId)
    local candidates = {}
    local player = getSpecificPlayer(self.player)
    local recipe = self.entries[self.activeIndex].plan.recipe
    for index, item in ipairs(self.pickerItems) do
        local ok, value = pcall(Forecast.contribution, player, recipe, item, "max")
        local calories = ok and value and math.floor(value + 0.5) or nil
        ok, value = pcall(Forecast.contribution, player, recipe, item, "hunger")
        local hunger = ok and value and math.floor(value + 0.5) or nil
        candidates[#candidates + 1] = { id = index, item = item, name = item:getDisplayName(),
            calories = calories, hunger = hunger }
    end
    sortedEntries(candidates, self.pickerSort)
    local query = searchFold(self.pickerSearch:getText())
    local y = 0
    self.pickerButtons = self.pickerButtons or {}
    for _, b in ipairs(self.pickerButtons) do b:setVisible(false) end
    local shown = 0
    for _, candidate in ipairs(candidates) do
        local item = candidate.item
        if query == "" or searchFold(candidate.name):find(query, 1, true) then
            shown = shown + 1
            local b = self.pickerButtons[shown]
            if not b then
                local created = ISButton:new(0, 0, 1, 1, "", self, CookItForMePlanUI.onPickIngredient)
                created:initialise(); created:instantiate(); stylePickerRow(created)
                self.pickerList:addChild(created)
                self.pickerButtons[shown] = created
                b = created
            end
            b.item = item
            b.pickerItem = item
            b.fullTitle = candidate.name
            b.tooltip = b.fullTitle
            b.calories, b.hunger = candidate.calories, candidate.hunger
            b:setX(0); b:setY(y); b:setWidth(self.pickerScroll.width - uiPixel(self, 12))
            local itemH = math.max(uiPixel(self, 34), getTextManager():getFontHeight(UIFont.Small) + uiPixel(self, 10))
            if pickerColumns(self.picker, b.width).compact then itemH = itemH + getTextManager():getFontHeight(UIFont.Small) end
            b:setHeight(itemH); b:setVisible(true)
            y = y + itemH + uiPixel(self, 2)
        end
    end
    self.pickerEmpty = shown == 0
    self.pickerEmptyText = #self.pickerItems == 0
        and (self.pickerAdding and "UI_CookItForMe_NoAdditions" or "UI_CookItForMe_NoAlternatives")
        or "UI_CookItForMe_NoMatches"
    self.pickerList:setHeight(math.max(y, uiPixel(self, 36)))
    self.pickerScroll:setScrollHeight(self.pickerList.height)
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
        local top = px(6)
        local fontH = getTextManager():getFontHeight(UIFont.Small)
        local groupH = math.max(px(32), fontH + px(14))
        local buttonH = math.max(px(26), fontH + px(8))
        local rowH = math.max(px(33), fontH + px(12), buttonH + px(6))
        local entry = self.entries[self.activeIndex]
        local key = entry and entry.key or ""
        local cols = layoutColumns(self, panel.width - px(14))
        for _, line in ipairs(self.lines) do
            if line.kind == "group" then
                panel:drawRect(px(4), top, panel.width - px(20), groupH - px(4), 1, THEME.panel.r, THEME.panel.g, THEME.panel.b)
                panel:drawText(truncateText(line.text, panel.width - px(32), UIFont.Small), px(10), top + px(5),
                    THEME.text.r, THEME.text.g, THEME.text.b, 1, UIFont.Small)
                top = top + groupH
            elseif line.kind == "ingredient" then
                local widget = self.rowWidgets and self.rowWidgets[key .. ":" .. line.id]
                ---@diagnostic disable-next-line: unnecessary-if
                if widget then
                    widget:setX(px(4)); widget:setY(top); widget:setWidth(panel.width - px(14))
                    local compactLines = self.rowStatus and self.rowStatus[line.id] == false and 4 or 3
                    widget:setHeight(cols.compact and math.max(px(40), fontH * compactLines + px(14), buttonH + px(6)) or rowH)
                    top = top + widget.height + px(2)
                end
            else
                local text = truncateText(line.text or "", panel.width - px(30), UIFont.Small)
                panel:drawText(text, px(10), top, THEME.text.r, THEME.text.g, THEME.text.b, 1, UIFont.Small)
                top = top + math.max(px(28), fontH + px(10))
            end
        end
        panel:setHeight(top + px(8))
        self.content:setScrollHeight(panel.height)
    end
    self:syncRows()
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

    self.tableHeader = ISPanel:new(0, 0, self.content.width, px(28))
    self.tableHeader:initialise(); self.tableHeader:instantiate(); self:addChild(self.tableHeader)
    self.tableHeader.prerender = function(panel)
        local cols = layoutColumns(self, panel.width - px(14))
        panel:drawRect(0, 0, panel.width, panel.height, 1, THEME.panel.r, THEME.panel.g, THEME.panel.b)
        panel:drawRect(0, panel.height - 1, panel.width, 1, 1, THEME.border.r, THEME.border.g, THEME.border.b)
        local zones
        if cols.compact then
            local sortableW = math.floor(math.max(1, cols.width - cols.actionW))
            local nameW = math.floor(sortableW * .44)
            local calW = math.floor((sortableW - nameW) / 2)
            zones = { name = { 0, nameW }, calories = { nameW, calW },
                hunger = { nameW + calW, sortableW - nameW - calW } }
        else
            zones = { name = { 0, cols.nameW }, calories = { cols.nameW, cols.calW },
                hunger = { cols.nameW + cols.calW, cols.hungerW } }
        end
        for key, zone in pairs(zones) do
            local sortControl = self.ingredientSortButtons[key]
            sortControl:setX(zone[1]); sortControl:setY(0); sortControl:setWidth(zone[2]); sortControl:setHeight(panel.height)
            if sortControl:isMouseOver() then
                panel:drawRect(zone[1], 0, zone[2], panel.height, .55, THEME.hover.r, THEME.hover.g, THEME.hover.b)
            end
            if self.ingredientSort.key == key then
                panel:drawRect(zone[1] + px(4), panel.height - px(3), math.max(1, zone[2] - px(8)), px(2), 1,
                    THEME.accent.r, THEME.accent.g, THEME.accent.b)
                drawSortArrow(panel, zone, self.ingredientSort.descending, px)
            end
        end
        local ingredient = getText("UI_CookItForMe_Ingredient")
        panel:drawText(truncateText(ingredient, zones.name[2] - px(self.ingredientSort.key == "name" and 30 or 14), UIFont.Small), px(10), px(5),
            THEME.secondary.r, THEME.secondary.g, THEME.secondary.b, 1, UIFont.Small)
        if not cols.compact then
            panel:drawTextRight(getText("UI_CookItForMe_CalInDish"), cols.nameW + cols.calW - px(self.ingredientSort.key == "calories" and 25 or 9), px(5),
                THEME.secondary.r, THEME.secondary.g, THEME.secondary.b, 1, UIFont.Small)
            panel:drawTextRight(getText("UI_CookItForMe_HungerInDish"), cols.nameW + cols.calW + cols.hungerW - px(self.ingredientSort.key == "hunger" and 25 or 9), px(5),
                THEME.secondary.r, THEME.secondary.g, THEME.secondary.b, 1, UIFont.Small)
        else
            for _, key in ipairs({ "calories", "hunger" }) do
                local zone = zones[key]
                local labelKey = key == "calories" and "UI_CookItForMe_CalInDish" or "UI_CookItForMe_HungerInDish"
                local label = getText(labelKey)
                panel:drawText(truncateText(label, zone[2] - px(self.ingredientSort.key == key and 24 or 8), UIFont.Small), zone[1] + px(4), px(5),
                    THEME.secondary.r, THEME.secondary.g, THEME.secondary.b, 1, UIFont.Small)
            end
        end
        panel:drawText(getText("UI_CookItForMe_Actions"), cols.width - cols.actionW, px(5),
            THEME.secondary.r, THEME.secondary.g, THEME.secondary.b, 1, UIFont.Small)
    end
    self.ingredientSortButtons = {}
    for _, spec in ipairs({ { key = "name", label = "UI_CookItForMe_Ingredient" },
        { key = "calories", label = "UI_CookItForMe_CalInDish" },
        { key = "hunger", label = "UI_CookItForMe_HungerInDish" } }) do
        local sortControl = ISButton:new(0, 0, 1, self.tableHeader.height, "", self, CookItForMePlanUI.onSortIngredients)
        sortControl.sortKey = spec.key
        sortControl.tooltip = getText(spec.label)
        sortControl:initialise(); sortControl:instantiate(); sortControl:setDisplayBackground(false)
        self.tableHeader:addChild(sortControl)
        self.ingredientSortButtons[spec.key] = sortControl
    end
    self.resetButton = ISButton:new(0, 0, 1, px(24), getText("UI_CookItForMe_ResetEdits"), self, CookItForMePlanUI.onResetIngredients)
    self.resetButton:initialise(); self.resetButton:instantiate(); styleButton(self.resetButton, THEME.border); self:addChild(self.resetButton)
    self.noticeButton = ISButton:new(0, 0, 1, px(24), getText("UI_CookItForMe_Undo"), self, CookItForMePlanUI.onUndoIngredient)
    self.noticeButton:initialise(); self.noticeButton:instantiate(); styleButton(self.noticeButton, THEME.border); self:addChild(self.noticeButton)

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

    local tableTop = settingsY + settingsH + px(10)
    local fontH = getTextManager():getFontHeight(UIFont.Small)
    local session = CookItForMe.Cook.getSession()
    local busy = session and session.active
    self.busy = busy
    if busy and self.pickerVisible then self:closePicker() end
    local entry = self.entries[self.activeIndex]
    local toolbarH = math.max(px(28), fontH + px(12))
    local headerH = math.max(px(28), fontH + px(12))
    self.tableHeader:setX(mainX); self.tableHeader:setY(tableTop + toolbarH)
    self.tableHeader:setWidth(mainW); self.tableHeader:setHeight(headerH)
    self.content:setX(mainX); self.content:setY(self.tableHeader.y + headerH)
    self.content:setWidth(mainW)
    self.content:setHeight(math.max(px(18), btnY - self.content.y - px(10)))
    self.details:setWidth(self.content.width)
    drawNeatSurface(self, "media/ui/NeatUI/DefaultPanel/ContentPanel_BG.png", self.content.x, self.content.y,
        self.content.width, self.content.height, 1, THEME.panel.r, THEME.panel.g, THEME.panel.b)

    self.cookButton:setX(mainX); self.cookButton:setWidth(math.max(px(120), mainW * .62)); self.cookButton:setY(btnY)
    self.closeButton:setX(mainX + self.cookButton.width + px(8)); self.closeButton:setWidth(math.max(px(88), mainW - self.cookButton.width - px(8))); self.closeButton:setY(btnY)
    local now = getTimestampMs()
    if entry and entry.plan and (not self.lastValidationAt or now - self.lastValidationAt > 500) then
        self.lastValidationAt = now
        self.rowStatus = CookItForMe.Cook.planEditor.rowAvailability(getSpecificPlayer(self.player), entry.plan)
        local ok, key, detail = CookItForMe.Cook.validatePlan(getSpecificPlayer(self.player), entry.plan, self.rowStatus)
        self.planValid = ok
        self.planFail = not ok and (detail and getText("UI_CookItForMe_" .. key, detail)
            or getText("UI_CookItForMe_" .. key)) or nil
    elseif not entry or not entry.plan then
        self.planValid, self.planFail = false, failText(entry and entry.failKey)
    end
    self.cookButton:setEnable(not busy and self.planValid == true)
    self.cookButton.tooltip = busy and getText("UI_CookItForMe_Busy") or self.planFail
    local resetW = math.ceil(getTextManager():MeasureStringX(UIFont.Small, getText("UI_CookItForMe_ResetEdits")) + px(40))
    local undoW = math.ceil(getTextManager():MeasureStringX(UIFont.Small, getText("UI_CookItForMe_Undo")) + px(40))
    local showReset = entry and entry.plan and entry.plan.edited and not busy or false
    local showUndo = self.notice and self.notice.removal and not busy or false
    self.resetButton:setVisible(showReset)
    local toolbarButtonH = math.max(px(24), fontH + px(6))
    self.resetButton:setX(mainX + mainW - resetW); self.resetButton:setY(tableTop + px(2))
    self.resetButton:setWidth(resetW); self.resetButton:setHeight(toolbarButtonH)
    self.noticeButton:setVisible(showUndo)
    self.noticeButton:setX(mainX + mainW - resetW - undoW - px(6)); self.noticeButton:setY(tableTop + px(2))
    self.noticeButton:setWidth(undoW); self.noticeButton:setHeight(toolbarButtonH)
    local toolbarText = self.notice and self.notice.text or ""
    local reserved = (showReset and resetW or 0) + (showUndo and undoW + px(6) or 0)
    self:drawText(truncateText(toolbarText, mainW - reserved - px(20), UIFont.Small), mainX + px(8), tableTop + px(5),
        THEME.text.r, THEME.text.g, THEME.text.b, 1, UIFont.Small)
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
    local settings = CookItForMe.getSettings(getSpecificPlayer(player))
    local ingredientSort = savedSort(settings, "ingredientSort")
    local pickerSort = savedSort(settings, "pickerSort")
    local lines = buildRenderLines(entries, activeIndex, ingredientSort)
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
    o.ingredientSort = ingredientSort
    o.pickerSort = pickerSort
    o.title = getText("UI_CookItForMe_PlanTitle")
    o:setResizable(true)
    o.moveWithMouse = true
    o:initialise()
    o:addToUIManager()
    o:setVisible(true)
    CookItForMe.planWindow = o
    return o
end
