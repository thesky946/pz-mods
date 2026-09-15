-- Cook It For Me: client side (контекстное меню, настройки, UI)

require "CookItForMe_Shared"
local FoodLogic = require "CookItForMe_FoodLogic"
local Scanner = require "CookItForMe_Scanner"
require "CookItForMe_Cook"
require "CookItForMe_PlanUI"

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

local function onCookingClick(player)
    local p = getSpecificPlayer(player)

    -- табы всех блюд; недоступные помечаем failKey (показываются красными)
    local entries = {}
    for _, key in ipairs(CookItForMe.Cook.ALL_DISHES) do
        local plan, failKey = CookItForMe.Cook.plan(p, key)
        table.insert(entries, { key = key, plan = plan, failKey = failKey })
    end

    CookItForMePlanUI:new(player, entries)
end

function CookItForMe.onFillWorldObjectContextMenu(player, context, worldobjects, test)
    if test and ISWorldObjectContextMenu.Test then return true end

    local playerObj = getSpecificPlayer(player)
    if playerObj:getVehicle() then return end

    -- пункт без подменю — кликается напрямую, открывает план со всеми настройками
    context:addOption(getText("UI_CookItForMe_ContextMenu"), worldobjects, function()
        onCookingClick(player)
    end)
end

-- Регистрация один раз: reloadLua() не должен плодить пункты меню
if not CookItForMe.clientEventsRegistered then
    CookItForMe.clientEventsRegistered = true
    Events.OnFillWorldObjectContextMenu.Add(function(...) return CookItForMe.onFillWorldObjectContextMenu(...) end)
end
