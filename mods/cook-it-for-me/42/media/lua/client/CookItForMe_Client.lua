-- Cook It For Me: client side (контекстное меню, настройки, UI)

require "CookItForMe_Shared"
local FoodLogic = require "CookItForMe_FoodLogic"
local Scanner = require "CookItForMe_Scanner"
require "CookItForMe_Cook"
require "CookItForMe_PlanUI"
require "ISUI/ISLabel"
require "ISUI/ISButton"

local KEY_OPTIONS_ID = "CookItForMe"
local PLAN_KEY_ID = "OpenPlan"
local PLAN_KEY_NAME = "UI_CookItForMe_KeybindName"

local function registerPlanKeybind()
    local options = PZAPI.ModOptions:getOptions(KEY_OPTIONS_ID)
    if not options then
        options = PZAPI.ModOptions:create(KEY_OPTIONS_ID, "UI_CookItForMe_ModOptions")
    end
    local option = options:getOption(PLAN_KEY_ID)
    if not option then
        option = options:addKeyBind(PLAN_KEY_ID, PLAN_KEY_NAME, Keyboard.KEY_F8)
    end
    CookItForMe.planKeyOption = option
end

registerPlanKeybind()

local controlsKeyScreen, controlsKeyPanel, controlsKeyRow

local function keepControlsBindUnmodified()
    if not MainOptions or not MainOptions.keyPressHandler
        or MainOptions.keyPressHandler == CookItForMe.planKeyPressWrapper then return end
    local vanillaKeyPress = MainOptions.keyPressHandler
    local wrapper = function(key, shift, ctrl, alt)
        local dialog = MainOptions.setKeybindDialog
        if dialog and dialog.keybindName == getText(PLAN_KEY_NAME) then
            return vanillaKeyPress(key, false, false, false)
        end
        return vanillaKeyPress(key, shift, ctrl, alt)
    end
    MainOptions.keyPressHandler = wrapper
    CookItForMe.planKeyPressWrapper = wrapper
end

function CookItForMe.syncControlsKeybind()
    local screen = MainOptions and MainOptions.instance
    if not screen or not screen.tabs or not MainOptions.keyText then return end
    local controls = screen.tabs:getView(getText("UI_optionscreen_keybinding"))
    if not controls then return end
    keepControlsBindUnmodified()

    local row = controlsKeyRow
    if row and controlsKeyScreen == screen and controlsKeyPanel == controls then
        local displayName = getText(PLAN_KEY_NAME)
        if row.txt:getName() ~= displayName then
            row.txt:setNameWithoutMoving(displayName)
            row.txt:setTranslation(displayName)
            row.txt:setX(row.btn.x - 10 - row.txt:getWidth())
            row.btn.internal = displayName
        end
        local title = getKeyName(row.keyCode)
        if row.btn.title ~= title then row.btn:setTitle(title) end
        return
    end

    -- Vanilla puts Mod Options keybinds on the Mods page. Move this one into
    -- Controls while retaining its single Mod Options value and stock dialog.
    local oldRow = CookItForMe.planKeyOption.element
    if oldRow and oldRow.txt and oldRow.btn then
        for i = #MainOptions.keyText, 1, -1 do
            if MainOptions.keyText[i] == oldRow then table.remove(MainOptions.keyText, i) end
        end
        oldRow.txt:setVisible(false)
        oldRow.btn:setVisible(false)
    end

    local height = getTextManager():getFontHeight(UIFont.Small) + 2
    local buttonWidth = screen.keyButtonWidth
    local buttonX, lastBindingBottom
    for _, binding in ipairs(MainOptions.keyText) do
        if not binding.isModBind and binding.btn then
            if binding.left and not buttonX then buttonX = binding.btn.x end
            local bottom = binding.btn.y + binding.btn.height
            if not lastBindingBottom or bottom > lastBindingBottom then lastBindingBottom = bottom end
        end
    end
    buttonX = buttonX or screen.width / 2 + 10
    local y = lastBindingBottom and lastBindingBottom + 12 or controls:getScrollHeight() + 6
    local displayName = getText(PLAN_KEY_NAME)
    local label = ISLabel:new(0, y, height, displayName,
        1, 1, 1, 1, UIFont.Small)
    label:initialise()
    label:setAnchorLeft(false)
    label:setAnchorRight(true)
    label:setTranslation(displayName)
    label:setX(buttonX - 10 - label:getWidth())
    controls:addChild(label)

    local button = ISButton:new(buttonX, y, buttonWidth, height,
        getKeyName(CookItForMe.getOpenPlanKey()), screen, MainOptions.onKeyBindingBtnPress)
    button.internal = displayName
    button.isModBind = true
    button:initialise()
    button:instantiate()
    controls:addChild(button)

    row = { txt = label, btn = button, keyCode = CookItForMe.getOpenPlanKey(),
        defaultKeyCode = Keyboard.KEY_F8, altCode = 0,
        shift = false, ctrl = false, alt = false, isModBind = true }
    table.insert(MainOptions.keyText, row)
    CookItForMe.planKeyOption.element = row
    controlsKeyRow = row
    controlsKeyScreen = screen
    controlsKeyPanel = controls
    controls:setScrollHeight(math.max(controls:getScrollHeight(), y + height + 20))
end

function CookItForMe.getOpenPlanKey()
    local key = tonumber(CookItForMe.planKeyOption:getValue())
    if not key then return Keyboard.KEY_F8 end
    return key
end

function CookItForMe.setOpenPlanKey(key)
    key = tonumber(key)
    if not key or key <= 0 or key % 1 ~= 0 then return false end
    CookItForMe.planKeyOption:setValue(key)
    PZAPI.ModOptions:save()
    return true
end

-- Все логи — под дебаг-флагом (CookItForMe.Debug в настройках песочницы)
local log = CookItForMe.log

-- Debug-превью без реальной готовки (кнопка в настройках)
function CookItForMe.debugPreview(player)
    local settings = CookItForMe.getSettings(player)
    local scan = Scanner.scanAround(player, settings.radius)
    log(string.format("SCAN: stove=%s sink=%s containers=%d floorItems=%d",
        scan.stove and 1 or 0, scan.sink and 1 or 0, #scan.containers, #scan.floorItems))

    local collected = Scanner.collectFood(player, scan)
    log(string.format("FOOD: foods=%d spices=%d cookware=%d",
        #collected.foods, #collected.spices, #collected.cookware))
    for _, c in ipairs(collected.cookware) do
        log("  cookware: " .. tostring(c:getDisplayName()) .. " (" .. tostring(c:getFullType()) .. ")")
    end

    local nutrition = player:getNutrition()
    local direction = FoodLogic.decideDirection(nutrition, settings)
    log(string.format("DIRECTION: %s (weight=%.1f, mode=%s)", direction, nutrition:getWeight(), settings.mode))

    local picked = FoodLogic.pickIngredients(collected.foods, collected.spices, direction, 6)
    log(string.format("PICK: %d items, frozenCount=%d", #picked.items, picked.frozenCount))
    for _, f in ipairs(picked.items) do
        local tag = f:isFrozen() and " [frozen]" or ""
        log(string.format("  - %s (%.0f cal)%s", f:getDisplayName(), f:getCalories(), tag))
    end
    local spiceNames = {}
    for _, s in ipairs(picked.spices) do table.insert(spiceNames, s:getDisplayName()) end
    log("SPICES: " .. #spiceNames .. " -> " .. table.concat(spiceNames, ", "))

    local penaltyTime = FoodLogic.frozenPenaltyTime(100, settings.frozenPenalty, picked.frozenCount, #picked.items)
    log(string.format("FROZEN TIME: base=100 -> %.0f (penalty=%.1f, frozen=%d)",
        penaltyTime, settings.frozenPenalty, picked.frozenCount))
end

function CookItForMe.openPlan(player)
    if CookItForMe.Cook.isMultiplayer() or CookItForMe.planWindow then return false end
    local p = getSpecificPlayer(player)
    if not p then return false end

    -- табы всех блюд; недоступные помечаем failKey (показываются красными)
    local entries = {}
    for _, key in ipairs(CookItForMe.Cook.ALL_DISHES) do
        local plan, failKey = CookItForMe.Cook.plan(p, key)
        table.insert(entries, { key = key, plan = plan, failKey = failKey })
    end

    return CookItForMePlanUI:new(player, entries)
end

function CookItForMe.onFillWorldObjectContextMenu(player, context, worldobjects, test)
    if CookItForMe.Cook.isMultiplayer() then return end

    local playerObj = getSpecificPlayer(player)
    if not playerObj then return end
    if playerObj:getVehicle() then return end
    if not Scanner.scanAround(playerObj, CookItForMe.CONTEXT_MENU_STOVE_RADIUS).stove then return end
    if test and ISWorldObjectContextMenu.Test then return true end

    -- пункт без подменю — кликается напрямую, открывает план со всеми настройками
    context:addOption(getText("UI_CookItForMe_ContextMenu"), worldobjects, function()
        CookItForMe.openPlan(player)
    end)
end

local function hasKeyModifierDown()
    return Keyboard.isKeyDown(Keyboard.KEY_LSHIFT) or Keyboard.isKeyDown(Keyboard.KEY_RSHIFT)
        or Keyboard.isKeyDown(Keyboard.KEY_LCONTROL) or Keyboard.isKeyDown(Keyboard.KEY_RCONTROL)
        or Keyboard.isKeyDown(Keyboard.KEY_LMENU) or Keyboard.isKeyDown(Keyboard.KEY_RMENU)
end

function CookItForMe.onPlanKeyPressed(key)
    local onCaptureKey = CookItForMePlanUI and CookItForMePlanUI.onPlanKeyCapturePressed
    if onCaptureKey and onCaptureKey(key) then return end
    if key ~= CookItForMe.getOpenPlanKey() or hasKeyModifierDown() then return end
    if CookItForMe.Cook.isMultiplayer() then return end
    if not getSpecificPlayer(0) then return end
    local window = CookItForMe.planWindow
    if window then
        if window.keyCaptureActive or window.keyConflictDialog then return end
        window:close()
        return
    end
    CookItForMe.openPlan(0)
end

-- Регистрация один раз: reloadLua() не должен плодить пункты меню
if not CookItForMe.clientEventsRegistered then
    CookItForMe.clientEventsRegistered = true
    Events.OnFillWorldObjectContextMenu.Add(function(...) return CookItForMe.onFillWorldObjectContextMenu(...) end)
end

if not CookItForMe.planKeyEventRegistered then
    CookItForMe.planKeyEventRegistered = true
    Events.OnKeyPressed.Add(function(key) return CookItForMe.onPlanKeyPressed(key) end)
end

if not CookItForMe.controlsKeyEventRegistered then
    CookItForMe.controlsKeyEventRegistered = true
    Events.OnRenderTick.Add(function() CookItForMe.syncControlsKeybind() end)
end
CookItForMe.syncControlsKeybind()
