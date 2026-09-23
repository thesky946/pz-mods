-- Cook It For Me: shared code (singleplayer, B42)

CookItForMe = CookItForMe or {}

-- Единственное место в Lua, где задан идентификатор мода. Отсюда берутся тег логов, ключ
-- ModData игрока и корень опции песочницы. Строкой его приходится дублировать только там,
-- где иначе нельзя: media/sandbox-options.txt, ключи переводов (статические файлы)
-- и id= в mod.info (его читает игра, а не Lua).
CookItForMe.ID = "CookItForMe"

-- Пункт ПКМ показывается только рядом с доступной плитой. Меняй это значение для тестов в игре.
CookItForMe.CONTEXT_MENU_STOVE_RADIUS = 4

local LOG_TAG = "[" .. CookItForMe.ID .. "]"

CookItForMe.DEFAULTS = {
    strategy = "max",     -- "max" | "min" | "hunger"
    completionSound = true,
    finishCooking = true,  -- нагревать блюдо после добавления ингредиентов
    radius = 1,           -- радиус поиска в тайлах; 0 = как proximity inventory (3x3)
    frozenPenalty = 0.5,  -- максимальный штраф при полностью замороженном составе
    debugFast = false,    -- скрытая опция: форсировать готовность через 5 секунд нагрева
}

-- Настройки лежат в ModData игрока (переживают перезагрузку)
function CookItForMe.getSettings(player)
    local md = player:getModData()
    if not md[CookItForMe.ID] then
        md[CookItForMe.ID] = {}
    end
    local s = md[CookItForMe.ID]
    for k, v in pairs(CookItForMe.DEFAULTS) do
        if s[k] == nil then s[k] = v end
    end
    if s.strategy ~= "max" and s.strategy ~= "min" and s.strategy ~= "hunger" then s.strategy = "max" end
    local radius = tonumber(s.radius)
    s.radius = radius and radius == radius and math.floor(math.max(0, math.min(30, radius))) or 1
    s.completionSound = s.completionSound ~= false
    s.finishCooking = s.finishCooking ~= false
    s.frozenPenalty = math.max(0, math.min(2, tonumber(s.frozenPenalty) or 0.5))
    return s
end

-- Always retain the last transitions/errors; normal detailed logs remain optional.
function CookItForMe.diagnostic(message)
    CookItForMe.history = CookItForMe.history or {}
    local history = CookItForMe.history
    history[#history + 1] = tostring(message)
    if #history > 40 then table.remove(history, 1) end
    print(LOG_TAG .. " " .. tostring(message))
end

function CookItForMe.withFrozenRecipe(recipe, callback)
    local previous = recipe:isAllowFrozenItem()
    local ok, value = pcall(function()
        recipe:setAllowFrozenItem(true)
        return callback()
    end)
    recipe:setAllowFrozenItem(previous)
    if not ok then error(value) end
    return value
end

function CookItForMe.saveSettings(player, settings)
    local md = player:getModData()
    if not md[CookItForMe.ID] then
        md[CookItForMe.ID] = {}
    end
    for k, v in pairs(settings) do
        md[CookItForMe.ID][k] = v
    end
end

-- Дебаг-логи. Источник истины — опция песочницы <ID>.Debug (media/sandbox-options.txt),
-- по умолчанию false. Дополнительно логи включаются в режиме отладки самого движка
-- (getCore():getDebug()), чтобы не пересоздавать мир ради отладки.
-- Значение читается на каждый вызов: опция может стать доступной позже загрузки SandboxVars,
-- а кэш сломался бы при загрузке сохранения с модом, добавленным в середине игры.
function CookItForMe.isDebug()
    local ok, on = pcall(function()
        if SandboxVars then
            local ns = SandboxVars[CookItForMe.ID]
            if ns ~= nil and ns.Debug ~= nil then return ns.Debug == true end
            -- фолбэк на плоское имя, если модовые опции попадут в aMods без вложенной таблицы
            local flat = SandboxVars[CookItForMe.ID .. "_Debug"]
            if flat ~= nil then return flat == true end
        end
        return getCore():getDebug()
    end)
    return ok and on == true
end

-- Тег подставляется здесь, а не в тексте сообщений: имя мода не размазано по 60 строкам
-- и меняется одной правкой CookItForMe.ID выше.
function CookItForMe.log(msg, ...)
    if not CookItForMe.isDebug() then return end
    print(LOG_TAG .. " " .. tostring(msg), ...)
end

-- Маркер загрузки + самопроверка локализации (кусок 1)
function CookItForMe.onGameBoot()
    CookItForMe.log("boot OK")
    CookItForMe.log("loc test: " .. tostring(getText("UI_CookItForMe_ContextMenu")))
end

if not CookItForMe.bootRegistered then
    CookItForMe.bootRegistered = true
    Events.OnGameBoot.Add(function() CookItForMe.onGameBoot() end)
end

return CookItForMe
