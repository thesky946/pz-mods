-- Public SP entry points. Runtime state belongs to a single explicit session.
require "CookItForMe_Shared"
local Catalog = require "CookItForMe_Dishes"
local Planner = require "CookItForMe_Planner"
local Session = require "CookItForMe_Session"
local Executor = require "CookItForMe_Executor"

CookItForMe.Cook = CookItForMe.Cook or {}
local Cook = CookItForMe.Cook
Cook.ALL_DISHES = Catalog.ALL_DISHES
Cook.DISHES = Catalog.DISHES
Cook.availableDishes = Catalog.availableDishes
Cook.findCookware = Catalog.findCookware
Cook.plan = Planner.plan
Cook.planEditor = Planner
Cook.validatePlan = Planner.validate

function Cook.isMultiplayer()
    return (type(isClient) == "function" and isClient())
        or (type(isServer) == "function" and isServer())
end

function Cook.getSession()
    return Cook.session
end

function Cook.fail(player, key)
    if Cook.session and Cook.session.active and Cook.session.player == player then
        Cook.execution.fail(key)
    else
        local msg = getText("UI_CookItForMe_" .. key)
        CookItForMe.log("FAIL: " .. msg)
        if key ~= "ActionFailed" then player:Say(msg) end
    end
end

function Cook.start(player, dishKey, plan)
    if Cook.isMultiplayer() then
        CookItForMe.diagnostic("start rejected: multiplayer unsupported")
        return false, "MultiplayerUnsupported"
    end
    if Cook.session and Cook.session.active then
        player:Say(getText("UI_CookItForMe_Busy"))
        return false, "Busy"
    end
    CookItForMe.log(string.format("COOK START: dish=%s plan=%s", tostring(dishKey), tostring(plan ~= nil)))
    if not plan then
        local failKey
        plan, failKey = Cook.plan(player, dishKey)
        if not plan then
            Cook.fail(player, failKey)
            return
        end
    end
    local ok, valid, key, detail = pcall(Planner.validate, player, plan)
    if not ok or not valid then
        key = ok and key or "ActionFailed"
        CookItForMe.diagnostic("start rejected: " .. tostring(key) .. " " .. tostring(valid))
        if key ~= "ActionFailed" then
            player:Say(detail and getText("UI_CookItForMe_" .. key, detail)
                or getText("UI_CookItForMe_" .. key))
        end
        return false, key
    end
    Cook.session = Session.new(player, plan)
    Cook.execution = Executor.new(Cook.session)
    local started, err = pcall(Cook.execution.start)
    if not started then Cook.session.onError(err); return false, "ActionFailed" end
    return true
end

function Cook.cancel()
    if Cook.execution then Cook.execution.cancel() end
end

function Cook.tick()
    if Cook.execution then
        local ok, err = pcall(Cook.execution.tick)
        if not ok and Cook.session then Cook.session.onError(err) end
    end
    local session = Cook.session
    ---@diagnostic disable-next-line: unnecessary-if -- runtime session state can change after an action completes.
    if session and session.retryPending and not session.active then
        session.retryPending = nil
        local ok, err = pcall(function()
            local window = CookItForMe.planWindow
            ---@diagnostic disable-next-line: unnecessary-if -- client window is created after this shared module loads.
            if window then
                window:rebuild(false)
            elseif type(CookItForMe.openPlan) == "function" then
                CookItForMe.openPlan(session.player:getPlayerNum())
            end
        end)
        if not ok then CookItForMe.diagnostic("retry plan failed: " .. tostring(err)) end
    end
end

-- Keep one event handler; dispatch through the current facade on reload.
---@diagnostic disable-next-line: unnecessary-if -- registration survives Lua hot reload.
if not Cook.onTickRegistered then
    Cook.onTickRegistered = true
    Events.OnTick.Add(function() Cook.tick() end)
end

return Cook
