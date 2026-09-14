-- Cook It For Me: shared code (singleplayer, B42)

CookItForMe = CookItForMe or {}

-- Единственное место в Lua, где задан идентификатор мода. Отсюда берутся тег логов, ключ
-- ModData игрока и корень опции песочницы. Строкой его приходится дублировать только там,
-- где иначе нельзя: media/sandbox-options.txt, ключи переводов (статические файлы)
-- и id= в mod.info (его читает игра, а не Lua).
CookItForMe.ID = "CookItForMe"

local LOG_TAG = "[" .. CookItForMe.ID .. "]"

CookItForMe.DEFAULTS = {
    strategy = "max",     -- "max" | "min" | "hunger"
    radius = 1,           -- радиус поиска в тайлах; 0 = как proximity inventory (3x3)
    frozenPenalty = 0.5,  -- штраф времени готовки за каждый замороженный ингредиент
    debugFast = false,    -- скрытая опция: форсировать готовность через 5 секунд нагрева
    panelW = 560,         -- размер окна плана (сохраняется при закрытии)
    panelH = 560,
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
    return s
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
local function onGameBoot()
    CookItForMe.log("boot OK")
    CookItForMe.log("loc test: " .. tostring(getText("UI_CookItForMe_ContextMenu")))
end

Events.OnGameBoot.Add(onGameBoot)

return CookItForMe
