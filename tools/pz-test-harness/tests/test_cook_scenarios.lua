package.path = "../PzModsTestHarness/42/media/lua/client/?.lua;" .. package.path

local currentEnv

local Cook = {}
function Cook.plan(player, dishKey) return currentEnv:plan(player, dishKey) end
function Cook.start(player, dishKey, plan) return currentEnv:startCook(player, dishKey, plan) end
function Cook.getSession() return currentEnv.session end
function Cook.cancel() return currentEnv:cancelCook() end

local Scanner = {}
function Scanner.scanAround() return currentEnv.scan end

package.preload["CookItForMe_Cook"] = function() return Cook end
package.preload["CookItForMe_Scanner"] = function() return Scanner end

local function list(values)
    return {
        size = function() return #values end,
        get = function(_, index) return values[index + 1] end,
        isEmpty = function() return #values == 0 end,
    }
end

local EventsState = { handlers = {} }
Events = {
    OnTick = {
        Add = function(handler) EventsState.handlers[#EventsState.handlers + 1] = handler end,
        Remove = function(handler)
            for index = #EventsState.handlers, 1, -1 do
                if EventsState.handlers[index] == handler then table.remove(EventsState.handlers, index) end
            end
        end,
    },
}

local function fireTick()
    local handlers = {}
    for index, handler in ipairs(EventsState.handlers) do handlers[index] = handler end
    for _, handler in ipairs(handlers) do handler() end
end

getCore = function() return { getVersionNumber = function() return "42.20.4" end } end
getTimestampMs = function() return currentEnv.now end

ArrayList = {
    new = function()
        local values = {}
        return {
            add = function(_, value) values[#values + 1] = value end,
            values = values,
        }
    end,
}

local Env = {}
Env.__index = Env

function Env:newContainer(kind)
    local container = { kind = kind, items = {}, env = self }
    function container:getType() return self.kind end
    function container:getItems() return list(self.items) end
    function container:contains(item)
        for _, value in ipairs(self.items) do if value == item then return true end end
        return false
    end
    function container:AddItem(value)
        local item = value
        if type(value) == "string" then item = self.env:newItem(value) end
        if item.container then item.container:Remove(item) end
        self.items[#self.items + 1] = item
        item.container = self
        return item
    end
    function container:Remove(item)
        for index, value in ipairs(self.items) do
            if value == item then
                table.remove(self.items, index)
                item.container = nil
                return item
            end
        end
        return nil
    end
    function container:hasRoomFor() return self.env.hasRoom end
    function container:isPowered() return self.env.powered end
    return container
end

function Env:newItem(fullType)
    self.nextId = self.nextId + 1
    local item = {
        id = self.nextId,
        fullType = fullType,
        cookingTime = 0,
        heat = 0,
        cooked = false,
        extra = {},
    }
    function item:getID() return self.id end
    function item:getFullType() return self.fullType end
    function item:getType() return self.fullType:match("%.(.+)$") end
    function item:getContainer() return self.container end
    function item:getInventory() return self.inner end
    function item:getExtraItems() return list(self.extra) end
    function item:getCookingTime() return self.cookingTime end
    function item:getHeat() return self.heat end
    function item:isCooked() return self.cooked end
    if fullType == "Base.Bag_NormalHikingBag" then item.inner = self:newContainer("bag") end
    self.allItems[#self.allItems + 1] = item
    return item
end

function Env:newRecipe(name, resultType)
    local recipe = { name = name, resultType = resultType }
    function recipe:getUntranslatedName() return self.name end
    function recipe:getFullResultItem() return self.resultType end
    function recipe:getItemsList()
        return {
            get = function(_, itemType)
                if itemType ~= "Tomato" then return nil end
                return {
                    getUse = function() return 12 end,
                    getFullType = function() return "Base.Tomato" end,
                }
            end,
        }
    end
    return recipe
end

function Env.new(options)
    options = options or {}
    local self = setmetatable({
        now = 1000,
        nextId = 100,
        allItems = {},
        hasRoom = options.hasRoom ~= false,
        powered = true,
        preservePreexisting = options.preservePreexisting ~= false,
        startPotMismatch = options.startPotMismatch == true,
        cancelLeavesActive = options.cancelLeavesActive == true,
        cancelCount = 0,
        queuedEffectCount = 0,
        settings = { radius = 1, debugFast = false, completionSound = true },
    }, Env)
    self.inventory = self:newContainer("inventory")
    self.stoveContainer = self:newContainer("stove")
    self.player = { inventory = self.inventory }
    function self.player:getInventory() return self.inventory end
    self.stove = { on = options.stoveOn == true, container = self.stoveContainer }
    function self.stove:Activated() return self.on end
    function self.stove:Toggle() self.on = not self.on end
    function self.stove:getContainer() return self.container end
    function self.stove:isBroken() return false end
    self.sink = { fluid = true }
    function self.sink:hasFluid() return self.fluid end
    self.scan = {
        stove = self.stove,
        sink = self.sink,
        stoves = options.stoves or { self.stove },
        sinks = options.sinks or { self.sink },
        containers = {},
        floorItems = {},
    }
    self.recipes = options.recipes or { self:newRecipe("Stir fry", "Base.PanFriedVegetables") }
    if options.preexistingSession then
        self.session = { active = true }
        self.startFailure = "Busy"
    end
    currentEnv = self
    return self
end

function Env:find(fullType)
    for _, item in ipairs(self.inventory.items) do
        if item.fullType == fullType then return item end
    end
    return nil
end

function Env:plan(player, dishKey)
    if self.planFailure then return nil, self.planFailure end
    local cookwareType = dishKey == "Soup" and "Base.Pot" or "Base.Pan"
    local resultType = dishKey == "Soup" and "Base.PotOfSoupRecipe" or "Base.PanFriedVegetables"
    local recipe
    for _, candidate in ipairs(self.recipes) do
        if candidate:getFullResultItem() == resultType then recipe = candidate end
    end
    local cookware, ingredient = self:find(cookwareType), self:find("Base.Tomato")
    return {
        player = player,
        dishKey = dishKey,
        dish = { needsWater = dishKey == "Soup" },
        cookware = cookware,
        recipe = recipe,
        picked = { items = { ingredient }, spices = {} },
        scan = self.scan,
        settings = self.settings,
    }
end

function Env:startCook(_, _, plan)
    if self.startFailure then return false, self.startFailure end
    local initiallyOn = self.stove.on
    self.session = {
        active = true,
        cooking = plan.dishKey == "Soup",
        pot = plan.cookware,
        stove = self.stove,
        plan = plan,
        reason = nil,
        weTurnedStoveOn = not initiallyOn,
    }
    if self.startPotMismatch then self.session.pot = plan.picked.items[1] end
    if not initiallyOn and plan.dishKey == "Soup" then self.stove:Toggle() end
    local captured = self.session
    self.queuedEffect = function()
        if captured.active then self.queuedEffectCount = self.queuedEffectCount + 1 end
    end
    return true
end

function Env:replaceCookware(resultType, effectCount)
    local session = assert(self.session)
    local old = session.pot
    if old.container then old.container:Remove(old) end
    local result = self.inventory:AddItem(resultType)
    for _ = 1, effectCount or 1 do result.extra[#result.extra + 1] = "Base.Tomato" end
    local ingredient = session.plan.picked.items[1]
    if ingredient and ingredient.container then ingredient.container:Remove(ingredient) end
    session.pot = result
    return result
end

function Env:cancelCook()
    if not self.session or not self.session.active then return end
    self.cancelCount = self.cancelCount + 1
    if self.cancelLeavesActive then return end
    self.session.active = false
    self.session.cooking = false
    self.session.reason = "cancelled"
    if self.session.weTurnedStoveOn and self.stove.on then self.stove:Toggle() end
end

function Env:runQueuedEffect()
    if self.queuedEffect then self.queuedEffect() end
end

function Env:finishCooking()
    local session = assert(self.session)
    local result = session.pot
    if result.container ~= self.inventory then self.inventory:AddItem(result) end
    result.cooked = true
    session.active = false
    session.cooking = false
    session.reason = "success"
    if session.weTurnedStoveOn then
        self.stove.on = false
    else
        self.stove.on = self.preservePreexisting
    end
end

RecipeManager = {
    getEvolvedRecipe = function()
        return list(currentEnv.recipes)
    end,
}

CookItForMe = {
    getSettings = function() return currentEnv.settings end,
}

ISInventoryTransferAction = {}
function ISInventoryTransferAction:new(player, item, source, destination)
    local action = { character = player, item = item, source = source, destination = destination }
    function action:setOnComplete(callback) self.onComplete = callback end
    function action:stop() self.stopped = true end
    function action:forceCancel() self.cancelled = true end
    return action
end

ISTimedActionQueue = {
    add = function(action)
        currentEnv.action = action
        return { queue = { action } }
    end,
}

local Transfer = require "scenarios/CookTransfer"
local Recipe = require "scenarios/CookRecipe"
local Stove = require "scenarios/CookStove"

local failures = {}
local function test(name, callback)
    local ok, err = pcall(callback)
    if not ok then failures[#failures + 1] = name .. ": " .. tostring(err) end
end

local function assertEqual(actual, expected, message)
    assert(actual == expected, (message or "values differ") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

local function capture(runner, context, env)
    local calls, result = 0, nil
    runner(context, function(value)
        if env then env.finishSessionActive = env.session and env.session.active or false end
        calls, result = calls + 1, value
    end)
    return function() return calls, result end
end

local function context(env)
    return { runId = "00000000000000000000000000000006", player = env.player, createdItemIds = {}, cleanup = {} }
end

local function assertRunOwnedRemoved(env, ctx)
    local owned = {}
    for _, id in ipairs(ctx.createdItemIds) do owned[id] = true end
    for _, item in ipairs(env.allItems) do
        if owned[item:getID()] then assert(item:getContainer() == nil, "run-owned item survived cleanup: " .. item:getID()) end
    end
end

local function assertOnlyKeys(registry, expected)
    local count = 0
    for key, value in pairs(registry) do
        count = count + 1
        assert(expected[key], "unexpected registered scenario: " .. tostring(key))
        assert(type(value) == "function", "scenario runner must be a function")
    end
    local expectedCount = 0
    for _ in pairs(expected) do expectedCount = expectedCount + 1 end
    assertEqual(count, expectedCount, "registered scenario count")
end

test("adapters register only documented scenario IDs", function()
    local registry = {}
    Transfer.register(registry)
    Recipe.register(registry)
    Stove.register(registry)
    assertOnlyKeys(registry, {
        ["cook.transfer.container.success"] = true,
        ["cook.recipe.replacement.success"] = true,
        ["cook.stove.ownership.success"] = true,
        ["cook.stove.preexisting.success"] = true,
    })
end)

test("all adapters refuse a missing player exactly once", function()
    local registry = {}
    Transfer.register(registry); Recipe.register(registry); Stove.register(registry)
    for id, runner in pairs(registry) do
        local calls, result = 0, nil
        runner({ runId = "00000000000000000000000000000006", cleanup = {}, createdItemIds = {} }, function(value)
            calls, result = calls + 1, value
        end)
        assertEqual(calls, 1, id .. " missing-player finish count")
        assertEqual(result.status, "fail", id .. " missing-player status")
        assert(result.failures[1]:find("player", 1, true), id .. " missing-player diagnostic")
    end
end)

local function runTransfer(options)
    local env = Env.new(options)
    local registry = {}; Transfer.register(registry)
    local ctx = context(env)
    local getResult = capture(registry["cook.transfer.container.success"], ctx)
    return env, ctx, getResult
end

test("transfer queues the exact nested object and cleans only run-owned objects", function()
    local env, ctx, getResult = runTransfer()
    local unrelated = env.inventory:AddItem("Base.Spoon")
    local moved = env.action.item
    assert(env.action.source:contains(moved), "test item must start in the created bag")
    env.action.source:Remove(moved)
    env.action.destination:AddItem(moved)
    env.action.onComplete(); env.action.onComplete()
    local calls, result = getResult()
    assertEqual(calls, 1, "duplicate callback finish count")
    assertEqual(result.status, "pass", "transfer status")
    assert(result.observed.destinationContains and not result.observed.sourceContains, "transfer postconditions")
    assertEqual(result.observed.itemId, moved:getID(), "exact transferred object ID")
    assertEqual(#ctx.createdItemIds, 2, "bag and nested item recorded before queue")
    assert(env.inventory:contains(unrelated), "cleanup must preserve unrelated same-type item")
end)

test("transfer rejects no-room before queueing and cleans created objects", function()
    local env, ctx, getResult = runTransfer({ hasRoom = false })
    local calls, result = getResult()
    assertEqual(calls, 1)
    assertEqual(result.status, "fail")
    assert(result.failures[1]:find("room", 1, true), "no-room diagnostic")
    assert(env.action == nil, "no-room must fail before action start")
    assertEqual(#ctx.createdItemIds, 2, "created objects still tracked for cleanup")
end)

test("transfer cancellation finishes once and ignores its stale completion", function()
    local env, _, getResult = runTransfer()
    env.action:stop()
    if env.action.onComplete then env.action.onComplete() end
    local calls, result = getResult()
    assertEqual(calls, 1)
    assertEqual(result.status, "fail")
    assert(result.failures[1]:find("cancel", 1, true), "cancel diagnostic")
end)

test("transfer reports cleanup failure separately", function()
    local env, _, getResult = runTransfer()
    local moved = env.action.item
    env.action.source:Remove(moved)
    env.action.destination:AddItem(moved)
    env.inventory.Remove = function() end
    env.action.onComplete()
    local calls, result = getResult()
    assertEqual(calls, 1)
    assertEqual(result.cleanup.status, "fail")
    assert(#result.cleanup.failures > 0, "cleanup failure details")
end)

test("transfer disappearance and same-type substitution fail exact identity", function()
    for _, mode in ipairs({ "vanished", "substituted" }) do
        local env, _, getResult = runTransfer()
        local expected = env.action.item
        env.action.source:Remove(expected)
        if mode == "substituted" then env.action.destination:AddItem("Base.Spoon") end
        env.action.onComplete()
        local calls, result = getResult()
        assertEqual(calls, 1)
        assertEqual(result.status, "fail")
        assertEqual(result.observed.destinationContains, false, mode .. " exact identity")
    end
end)

local function runRecipe(options)
    local env = Env.new(options)
    local registry = {}; Recipe.register(registry)
    local ctx = context(env)
    local getResult = capture(registry["cook.recipe.replacement.success"], ctx, env)
    return env, ctx, getResult
end

test("recipe records replacement, validates exact identity/type/location and consumes once", function()
    local env, ctx, getResult = runRecipe()
    local old = env.session.pot
    local resultItem = env:replaceCookware("Base.PanFriedVegetables", 1)
    fireTick(); fireTick()
    local calls, result = getResult()
    assertEqual(calls, 1, "recipe finish count")
    assertEqual(result.status, "pass", "recipe status")
    assert(result.observed.replaced and result.observed.destinationContains, "replacement postconditions")
    assertEqual(result.observed.oldItemId, old:getID())
    assertEqual(result.observed.resultItemId, resultItem:getID())
    assertEqual(result.observed.effectCount, 1)
    assertEqual(#ctx.createdItemIds, 3, "pan, ingredient and replacement recorded")
    assert(env.session.active == false, "recipe session must be terminal")
end)

test("recipe ambiguity fails diagnostically without silent substitution", function()
    local first = Env.new():newRecipe("Stir fry", "Base.PanFriedVegetables")
    local second = Env.new():newRecipe("Stir fry duplicate", "Base.PanFriedVegetables")
    local env, ctx, getResult = runRecipe({ recipes = { first, second } })
    local calls, result = getResult()
    assertEqual(calls, 1)
    assertEqual(result.status, "fail")
    local diagnostic = table.concat(result.failures, " ")
    assert(diagnostic:find("Stir fry", 1, true) and diagnostic:find("duplicate", 1, true), "candidate diagnostic")
    assertEqual(#ctx.createdItemIds, 2, "recipe lookup requires tracked cookware and ingredient")
    assert(env.session == nil, "ambiguous fixture must not start Cook")
end)

test("recipe wrong result type and duplicate tick cannot pass or finish twice", function()
    local env, ctx, getResult = runRecipe()
    env:replaceCookware("Base.WrongResult", 1)
    fireTick(); fireTick()
    local calls, result = getResult()
    assertEqual(calls, 1)
    assertEqual(result.status, "fail")
    assertEqual(result.observed.fullType, "Base.WrongResult")
    assertEqual(env.cancelCount, 1, "post-start verification failure must cancel captured session")
    assertEqual(env.session.active, false, "captured recipe session must be terminal before cleanup")
    assertEqual(env.finishSessionActive, false, "finish must observe a terminal captured session")
    assertRunOwnedRemoved(env, ctx)
    env:runQueuedEffect()
    assertEqual(env.queuedEffectCount, 0, "queued recipe effect must not continue after cleanup")
end)

test("recipe observer exception cancels captured session before finishing once", function()
    local env, ctx, getResult = runRecipe()
    local resultItem = env:replaceCookware("Base.PanFriedVegetables", 1)
    resultItem.getExtraItems = function() error("recipe probe failed") end
    fireTick(); fireTick()
    local calls, result = getResult()
    assertEqual(calls, 1)
    assertEqual(result.status, "fail")
    assertEqual(env.cancelCount, 1)
    assertEqual(env.session.active, false)
    assertEqual(env.finishSessionActive, false)
    assertRunOwnedRemoved(env, ctx)
    env:runQueuedEffect()
    assertEqual(env.queuedEffectCount, 0)
end)

test("recipe post-start cookware verification failure cancels before fixture cleanup", function()
    local env, ctx, getResult = runRecipe({ startPotMismatch = true })
    local calls, result = getResult()
    assertEqual(calls, 1)
    assertEqual(result.status, "fail")
    assertEqual(env.cancelCount, 1)
    assertEqual(env.session.active, false)
    assertEqual(env.finishSessionActive, false)
    assertRunOwnedRemoved(env, ctx)
    env:runQueuedEffect()
    assertEqual(env.queuedEffectCount, 0)
end)

test("recipe failure never cancels an unrelated current session", function()
    local env, _, getResult = runRecipe()
    local captured = env.session
    captured.active = false
    local unrelated = { active = true, pot = captured.pot }
    env.session = unrelated
    fireTick(); fireTick()
    local calls, result = getResult()
    assertEqual(calls, 1)
    assertEqual(result.status, "fail")
    assertEqual(env.cancelCount, 0)
    assert(unrelated.active, "unrelated current session must remain active")
end)

test("recipe rejected by a pre-existing session never cancels it", function()
    local env, _, getResult = runRecipe({ preexistingSession = true })
    local calls, result = getResult()
    assertEqual(calls, 1)
    assertEqual(result.status, "fail")
    assertEqual(env.cancelCount, 0)
    assert(env.session.active, "pre-existing session must remain active")
end)

test("recipe does not clean up or finish until captured cancellation is terminal", function()
    local env, ctx, getResult = runRecipe({ startPotMismatch = true, cancelLeavesActive = true })
    local calls = getResult()
    assertEqual(calls, 0, "non-terminal captured session must block finish")
    assertEqual(env.cancelCount, 1)
    assert(env.session.active, "failed cancellation must leave the captured session visible")
    local retained = 0
    local owned = {}
    for _, id in ipairs(ctx.createdItemIds) do owned[id] = true end
    for _, item in ipairs(env.allItems) do
        if owned[item:getID()] and item:getContainer() then retained = retained + 1 end
    end
    assertEqual(retained, #ctx.createdItemIds, "run-owned fixtures must survive until terminal cleanup")
end)

test("recipe cancellation before replacement fails terminally without retry", function()
    local env, _, getResult = runRecipe()
    env:cancelCook()
    fireTick(); fireTick()
    local calls, result = getResult()
    assertEqual(calls, 1)
    assertEqual(result.status, "fail")
    assert(table.concat(result.failures, " "):find("terminated", 1, true), "terminal cancellation diagnostic")
end)

local function runStove(id, options)
    local env = Env.new(options)
    env.recipes = { env:newRecipe("Soup", "Base.PotOfSoupRecipe") }
    if options and options.unrelatedStoveItem then
        env.unrelatedStoveItem = env.stoveContainer:AddItem("Base.OtherDish")
    end
    local registry = {}; Stove.register(registry)
    local ctx = context(env)
    local getResult = capture(registry[id], ctx, env)
    return env, ctx, getResult
end

local function completeStove(env)
    local resultItem = env:replaceCookware("Base.PotOfSoupRecipe", 1)
    fireTick()
    resultItem.cookingTime = 1
    resultItem.heat = 1
    fireTick()
    env:finishCooking()
    fireTick(); fireTick()
    return resultItem
end

test("owned stove observes progress, ends off, returns exact dish and preserves unrelated contents", function()
    local env, ctx, getResult = runStove("cook.stove.ownership.success", { stoveOn = false, unrelatedStoveItem = true })
    local unrelated = env.unrelatedStoveItem
    local resultItem = completeStove(env)
    local calls, result = getResult()
    assertEqual(calls, 1)
    assertEqual(result.status, "pass")
    assert(result.observed.progressObserved and result.observed.sessionTerminal, "progress and terminal state")
    assert(result.observed.activationOwned and not result.observed.stoveActive, "owned activation cleanup")
    assertEqual(result.observed.resultItemId, resultItem:getID(), "exact returned dish")
    assert(env.stoveContainer:contains(unrelated), "unrelated stove item preserved")
    assertEqual(#ctx.createdItemIds, 3, "pot, ingredient and replacement recorded")
end)

test("pre-existing stove remains on and is not claimed by the Cook session", function()
    local env, _, getResult = runStove("cook.stove.preexisting.success", { stoveOn = true, preservePreexisting = true })
    completeStove(env)
    local calls, result = getResult()
    assertEqual(calls, 1)
    assertEqual(result.status, "pass")
    assert(not result.observed.activationOwned and result.observed.stoveActive, "pre-existing activation preserved")
end)

test("pre-existing stove switched off is a diagnostic failure", function()
    local env, _, getResult = runStove("cook.stove.preexisting.success", { stoveOn = true, preservePreexisting = false })
    completeStove(env)
    local calls, result = getResult()
    assertEqual(calls, 1)
    assertEqual(result.status, "fail")
    assertEqual(result.observed.stoveActive, false)
end)

test("stove cancellation and missing final object cannot pass", function()
    local env, _, getResult = runStove("cook.stove.ownership.success", { stoveOn = false })
    env:cancelCook()
    fireTick(); fireTick()
    local calls, result = getResult()
    assertEqual(calls, 1)
    assertEqual(result.status, "fail")
    assertEqual(result.observed.sessionReason, "cancelled")

    env, _, getResult = runStove("cook.stove.ownership.success", { stoveOn = false })
    local resultItem = env:replaceCookware("Base.PotOfSoupRecipe", 1)
    resultItem.cookingTime = 1
    fireTick()
    env:finishCooking()
    env.inventory:Remove(resultItem)
    fireTick()
    calls, result = getResult()
    assertEqual(calls, 1)
    assertEqual(result.status, "fail")
    assertEqual(result.observed.destinationContains, false)
end)

test("stove observer exception cancels only captured run and restores activation ownership", function()
    for _, case in ipairs({
        { id = "cook.stove.ownership.success", stoveOn = false, expectedOn = false },
        { id = "cook.stove.preexisting.success", stoveOn = true, expectedOn = true },
    }) do
        local env, ctx, getResult = runStove(case.id, { stoveOn = case.stoveOn })
        env.session.pot.getCookingTime = function() error("stove probe failed") end
        fireTick(); fireTick()
        local calls, result = getResult()
        assertEqual(calls, 1, case.id .. " finish count")
        assertEqual(result.status, "fail", case.id .. " exception status")
        assertEqual(env.cancelCount, 1, case.id .. " captured cancel count")
        assertEqual(env.session.active, false, case.id .. " captured session terminal")
        assertEqual(env.finishSessionActive, false, case.id .. " finish must observe terminal session")
        assertRunOwnedRemoved(env, ctx)
        assertEqual(env.stove.on, case.expectedOn, case.id .. " activation ownership")
        env:runQueuedEffect()
        assertEqual(env.queuedEffectCount, 0, case.id .. " queued effect stopped")
    end
end)

test("stove post-start identity failure cancels before owned-state cleanup", function()
    for _, case in ipairs({
        { id = "cook.stove.ownership.success", stoveOn = false, expectedOn = false },
        { id = "cook.stove.preexisting.success", stoveOn = true, expectedOn = true },
    }) do
        local env, ctx, getResult = runStove(case.id, { stoveOn = case.stoveOn, startPotMismatch = true })
        local calls, result = getResult()
        assertEqual(calls, 1, case.id .. " finish count")
        assertEqual(result.status, "fail", case.id .. " identity status")
        assertEqual(env.cancelCount, 1, case.id .. " captured cancel count")
        assertEqual(env.session.active, false, case.id .. " captured session terminal")
        assertEqual(env.finishSessionActive, false, case.id .. " finish must observe terminal session")
        assertEqual(env.stove.on, case.expectedOn, case.id .. " activation ownership")
        assertRunOwnedRemoved(env, ctx)
        env:runQueuedEffect()
        assertEqual(env.queuedEffectCount, 0, case.id .. " queued effect stopped")
    end
end)

test("ambiguous stove and sink fixtures fail before creating or consuming items", function()
    local extraStove = {}
    local env, ctx, getResult = runStove("cook.stove.ownership.success", { stoves = { {}, extraStove } })
    local calls, result = getResult()
    assertEqual(calls, 1)
    assertEqual(result.status, "fail")
    assert(table.concat(result.failures, " "):find("stove", 1, true), "stove ambiguity diagnostic")
    assertEqual(#ctx.createdItemIds, 0)
    assert(env.session == nil)

    env, ctx, getResult = runStove("cook.stove.ownership.success", { sinks = { {}, {} } })
    calls, result = getResult()
    assertEqual(calls, 1)
    assertEqual(result.status, "fail")
    assert(table.concat(result.failures, " "):find("sink", 1, true), "sink ambiguity diagnostic")
    assertEqual(#ctx.createdItemIds, 0)
end)

if #failures > 0 then error(table.concat(failures, "\n")) end
print("cook scenario adapter tests passed")
