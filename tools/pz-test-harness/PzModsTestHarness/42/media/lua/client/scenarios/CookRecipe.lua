local Adapter = {}
local SCENARIO_ID = "cook.recipe.replacement.success"
local EXPECTED_RESULT = "Base.PanFriedVegetables"

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

local function recipeCandidates(cookware, player, scan)
    local containers = ArrayList.new()
    for _, container in ipairs(scan.containers or {}) do containers:add(container) end
    local recipes = RecipeManager.getEvolvedRecipe(cookware, player, containers, false)
    local matches, discovered = {}, {}
    for index = 0, (recipes and recipes:size() or 0) - 1 do
        local recipe = recipes:get(index)
        local name = tostring(recipe:getUntranslatedName())
        local result = tostring(recipe:getFullResultItem())
        discovered[#discovered + 1] = name .. "->" .. result
        if name:sub(1, 8) == "Stir fry" and result == EXPECTED_RESULT then matches[#matches + 1] = recipe end
    end
    return matches, discovered
end

local function countEffect(item, fullType)
    local count = 0
    local values = item:getExtraItems()
    for index = 0, (values and values:size() or 0) - 1 do
        if values:get(index) == fullType then count = count + 1 end
    end
    return count
end

local function run(context, finish)
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
            failRun("recipe fixture requires an empty player inventory")
            return
        end

        local scan = Scanner.scanAround(player, CookItForMe.getSettings(player).radius)
        if #(scan.stoves or {}) ~= 1 then
            failRun("recipe fixture requires exactly one valid stove; discovered=" .. tostring(#(scan.stoves or {})))
            return
        end

        local pan = inventory:AddItem("Base.Pan")
        if not pan then failRun("failed to create Base.Pan"); return end
        recordItem(context, pan)
        local ingredient = inventory:AddItem("Base.Tomato")
        if not ingredient then failRun("failed to create Base.Tomato"); return end
        recordItem(context, ingredient)

        local matches, discovered = recipeCandidates(pan, player, scan)
        if #matches ~= 1 then
            failRun("recipe fixture is ambiguous or unavailable; candidates=" .. table.concat(discovered, ","))
            return
        end
        local recipe = matches[1]
        local entry = recipe:getItemsList():get(ingredient:getType())
        if not entry or entry:getUse() < 0 or entry:getFullType() ~= ingredient:getFullType() then
            failRun("Base.Tomato is not compatible with the resolved Stir fry recipe")
            return
        end

        local plan, planError = Cook.plan(player, "Stir fry")
        if not plan then failRun("Cook plan failed: " .. tostring(planError)); return end
        if plan.cookware ~= pan or plan.recipe ~= recipe or #plan.picked.items ~= 1 or plan.picked.items[1] ~= ingredient then
            failRun("Cook plan did not preserve the exact recipe fixture objects")
            return
        end

        local started, startError = Cook.start(player, "Stir fry", plan)
        if started == false then failRun("Cook start failed: " .. tostring(startError)); return end
        startedByRun = true
        session = Cook.getSession()
        if not session or not session.active or session.pot ~= pan then
            failRun("Cook session did not start with the exact cookware object")
            return
        end

        local startedAt = getTimestampMs()
        local onTick
        onTick = function()
            local callbackOk, callbackError = pcall(function()
                local current = Cook.getSession()
                if current ~= session then failRun("Cook session identity changed"); return end
                local result = session.pot
                if result ~= pan then
                    recordItem(context, result)
                    if not terminateRun() then return end
                    local effectCount = countEffect(result, ingredient:getFullType())
                    local destinationContains = result:getContainer() == inventory and inventory:contains(result)
                    local oldAbsent = pan:getContainer() == nil and not inventory:contains(pan)
                    local observed = {
                        oldItemId = pan:getID(),
                        resultItemId = result:getID(),
                        fullType = result:getFullType(),
                        replaced = result ~= pan and oldAbsent,
                        destinationContains = destinationContains,
                        effectCount = effectCount,
                        ingredientPresent = ingredient:getContainer() ~= nil,
                        sessionTerminal = not session.active,
                    }
                    if result:getFullType() ~= EXPECTED_RESULT or not observed.replaced or not destinationContains
                        or effectCount ~= 1 or session.active then
                        failRun("recipe replacement postconditions failed", observed)
                    else
                        finishRun({ status = "pass", failures = {}, observed = observed })
                    end
                    return
                end
                if not session.active then failRun("Cook session terminated before recipe replacement"); return end
                if getTimestampMs() - startedAt >= 30000 then
                    failRun("recipe replacement timed out")
                end
            end)
            if not callbackOk then failRun("recipe observation failed: " .. tostring(callbackError)) end
        end
        Events.OnTick.Add(onTick)
        context.cleanup[#context.cleanup + 1] = function() Events.OnTick.Remove(onTick) end
    end)
    if not ok then failRun("recipe setup failed: " .. tostring(err)) end
end

function Adapter.register(registry)
    if registry[SCENARIO_ID] == nil then registry[SCENARIO_ID] = run end
end

return Adapter
