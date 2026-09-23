local Adapter = {}
local OWNED_ID = "cook.stove.ownership.success"
local PREEXISTING_ID = "cook.stove.preexisting.success"
local EXPECTED_RESULT = "Base.PotOfSoupRecipe"

local function gameBuild() return tostring(getCore():getVersionNumber()) end

local function makeFinisher(context, finish)
    context.cleanup = context.cleanup or {}
    context.createdItemIds = context.createdItemIds or {}
    local finished = false
    return function(raw)
        if finished then return false end
        finished = true
        local cleanupFailures = {}
        for index = #context.cleanup, 1, -1 do
            local ok, err = pcall(context.cleanup[index])
            if not ok then cleanupFailures[#cleanupFailures + 1] = tostring(err) end
        end
        context.cleanup = {}
        raw = type(raw) == "table" and raw or {}
        raw.gameBuild = gameBuild()
        raw.cleanup = { status = #cleanupFailures == 0 and "pass" or "fail", failures = cleanupFailures }
        finish(raw)
        return true
    end
end

local function recordItem(context, item)
    context._createdItems = context._createdItems or {}
    if context._createdItems[item] then return end
    context._createdItems[item] = true
    context.createdItemIds[#context.createdItemIds + 1] = item:getID()
    context.cleanup[#context.cleanup + 1] = function()
        local container = item:getContainer()
        if container then container:Remove(item) end
        if item:getContainer() then error("run-owned item cleanup failed: " .. tostring(item:getID())) end
    end
end

local function snapshot(container)
    local result, items = {}, container:getItems()
    for index = 0, items:size() - 1 do result[#result + 1] = items:get(index) end
    return result
end

local function preserved(container, items)
    for _, item in ipairs(items) do
        if item:getContainer() ~= container or not container:contains(item) then return false end
    end
    return true
end

local function resolveRecipe(cookware, player, scan)
    local containers = ArrayList.new()
    for _, container in ipairs(scan.containers or {}) do containers:add(container) end
    local recipes = RecipeManager.getEvolvedRecipe(cookware, player, containers, false)
    local matches, discovered = {}, {}
    for index = 0, (recipes and recipes:size() or 0) - 1 do
        local recipe = recipes:get(index)
        local name = tostring(recipe:getUntranslatedName())
        local result = tostring(recipe:getFullResultItem())
        discovered[#discovered + 1] = name .. "->" .. result
        if name:sub(1, 4) == "Soup" and result == EXPECTED_RESULT then matches[#matches + 1] = recipe end
    end
    return matches, discovered
end

local function countEffect(item, fullType)
    local count, values = 0, item:getExtraItems()
    for index = 0, (values and values:size() or 0) - 1 do
        if values:get(index) == fullType then count = count + 1 end
    end
    return count
end

local function run(context, finish, expectInitiallyOn)
    local done = makeFinisher(context, finish)
    local Cook, session
    local startedByRun = false
    local function terminateRun()
        if startedByRun then
            if not session then return false end
            if session.active then
                local currentOk, current = pcall(Cook.getSession)
                if not currentOk or current ~= session then return false end
                local cancelOk = pcall(Cook.cancel)
                if not cancelOk or session.active then return false end
            end
            if session.active then return false end
        end
        return true
    end
    local function finishRun(raw)
        if not terminateRun() then return false end
        return done(raw)
    end
    local function failRun(message, observed)
        return finishRun({ status = "fail", failures = { message }, observed = observed or {} })
    end
    if not context.player then failRun("player fixture is missing"); return end

    local ok, err = pcall(function()
        Cook = require "CookItForMe_Cook"
        local Scanner = require "CookItForMe_Scanner"
        local player = context.player
        local inventory = player:getInventory()
        if not inventory:getItems():isEmpty() then
            failRun("stove fixture requires an empty player inventory")
            return
        end
        local settings = CookItForMe.getSettings(player)
        local scan = Scanner.scanAround(player, settings.radius)
        if #(scan.stoves or {}) ~= 1 then
            failRun("stove fixture requires exactly one valid stove; discovered=" .. tostring(#(scan.stoves or {})))
            return
        end
        if #(scan.sinks or {}) ~= 1 then
            failRun("water recipe fixture requires exactly one valid sink; discovered=" .. tostring(#(scan.sinks or {})))
            return
        end
        local stove, sink = scan.stoves[1], scan.sinks[1]
        if scan.stove ~= stove or scan.sink ~= sink then
            failRun("scanner primary stove/sink does not match the unique fixture")
            return
        end
        local initiallyOn = stove:Activated()
        if initiallyOn ~= expectInitiallyOn then
            failRun(expectInitiallyOn and "pre-existing stove fixture must start activated" or "owned stove fixture must start inactive")
            return
        end
        local priorStoveItems = snapshot(stove:getContainer())
        context.cleanup[#context.cleanup + 1] = function()
            if stove:Activated() ~= initiallyOn then stove:Toggle() end
            if stove:Activated() ~= initiallyOn then error("stove fixture state restoration failed") end
        end
        local previousDebugFast, previousCompletionSound = settings.debugFast, settings.completionSound
        context.cleanup[#context.cleanup + 1] = function()
            settings.debugFast, settings.completionSound = previousDebugFast, previousCompletionSound
        end
        settings.debugFast, settings.completionSound = true, false

        local pot = inventory:AddItem("Base.Pot")
        if not pot then failRun("failed to create Base.Pot"); return end
        recordItem(context, pot)
        local ingredient = inventory:AddItem("Base.Tomato")
        if not ingredient then failRun("failed to create Base.Tomato"); return end
        recordItem(context, ingredient)

        local matches, discovered = resolveRecipe(pot, player, scan)
        if #matches ~= 1 then
            failRun("soup recipe fixture is ambiguous or unavailable; candidates=" .. table.concat(discovered, ","))
            return
        end
        local recipe = matches[1]
        local entry = recipe:getItemsList():get(ingredient:getType())
        if not entry or entry:getUse() < 0 or entry:getFullType() ~= ingredient:getFullType() then
            failRun("Base.Tomato is not compatible with the resolved Soup recipe")
            return
        end
        local plan, planError = Cook.plan(player, "Soup")
        if not plan then failRun("Cook plan failed: " .. tostring(planError)); return end
        if plan.cookware ~= pot or plan.recipe ~= recipe or plan.scan.stove ~= stove or plan.scan.sink ~= sink
            or #plan.picked.items ~= 1 or plan.picked.items[1] ~= ingredient then
            failRun("Cook plan did not preserve the exact stove fixture objects")
            return
        end
        local started, startError = Cook.start(player, "Soup", plan)
        if started == false then failRun("Cook start failed: " .. tostring(startError)); return end
        startedByRun = true
        session = Cook.getSession()
        if not session or not session.active or session.pot ~= pot then
            failRun("Cook session did not start with exact cookware")
            return
        end

        local startedAt = getTimestampMs()
        local progressObserved = false
        local trackedPot = pot
        local lastCookingTime, lastHeat = pot:getCookingTime(), pot:getHeat()
        local onTick
        onTick = function()
            local callbackOk, callbackError = pcall(function()
                local current = Cook.getSession()
                if current ~= session then failRun("Cook session identity changed"); return end
                local result = session.pot
                if result ~= trackedPot then
                    trackedPot = result
                    recordItem(context, result)
                    lastCookingTime, lastHeat = result:getCookingTime(), result:getHeat()
                end
                local cookingTime, heat = result:getCookingTime(), result:getHeat()
                if session.cooking and (cookingTime > lastCookingTime or heat > lastHeat or result:isCooked()) then
                    progressObserved = true
                end
                lastCookingTime, lastHeat = cookingTime, heat

                if not session.active then
                    local destinationContains = result:getContainer() == inventory and inventory:contains(result)
                    local observed = {
                        initialStoveActive = initiallyOn,
                        stoveActive = stove:Activated(),
                        activationOwned = session.weTurnedStoveOn == true,
                        progressObserved = progressObserved,
                        sessionTerminal = true,
                        sessionReason = session.reason,
                        resultItemId = result:getID(),
                        fullType = result:getFullType(),
                        destinationContains = destinationContains,
                        effectCount = countEffect(result, ingredient:getFullType()),
                        unrelatedPreserved = preserved(stove:getContainer(), priorStoveItems),
                    }
                    local expectedFinalActive = expectInitiallyOn
                    local valid = session.reason == "success" and result ~= pot
                        and result:getFullType() == EXPECTED_RESULT and destinationContains
                        and observed.effectCount == 1 and progressObserved
                        and observed.activationOwned == (not expectInitiallyOn)
                        and observed.stoveActive == expectedFinalActive
                        and observed.unrelatedPreserved
                    if valid then finishRun({ status = "pass", failures = {}, observed = observed })
                    else failRun("stove scenario postconditions failed", observed) end
                    return
                end
                if getTimestampMs() - startedAt >= 120000 then
                    failRun("stove scenario timed out")
                end
            end)
            if not callbackOk then failRun("stove observation failed: " .. tostring(callbackError)) end
        end
        Events.OnTick.Add(onTick)
        context.cleanup[#context.cleanup + 1] = function() Events.OnTick.Remove(onTick) end
    end)
    if not ok then failRun("stove setup failed: " .. tostring(err)) end
end

function Adapter.register(registry)
    if registry[OWNED_ID] == nil then
        registry[OWNED_ID] = function(context, finish) run(context, finish, false) end
    end
    if registry[PREEXISTING_ID] == nil then
        registry[PREEXISTING_ID] = function(context, finish) run(context, finish, true) end
    end
end

return Adapter
