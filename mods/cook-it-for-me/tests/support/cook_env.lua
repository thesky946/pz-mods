-- Minimal PZ boundary doubles. This is not a simulation of the game engine.
local Simulator = require "support/action_simulator"
local Env = {}

function Env.list(values)
    values = values or {}
    return {
        size = function() return #values end,
        get = function(_, i) return values[i + 1] end,
        add = function(_, v) values[#values + 1] = v end,
    }
end

function Env.container(kind)
    local c = { items = {}, kind = kind }
    function c:getItems() return Env.list(self.items) end
    function c:contains(item) for _, v in ipairs(self.items) do if v == item then return true end end return false end
    function c:hasRoomFor() return not self.full end
    function c:isPowered() return self.powered ~= false end
    function c:isExistYet() return true end
    function c:getType() return self.kind end
    function c:getSourceGrid() return nil end
    function c:Remove(item)
        for i, v in ipairs(self.items) do
            if v == item then table.remove(self.items, i) break end
        end
        if item.container == self then item.container = nil end
    end
    function c:AddItem(item)
        self.items[#self.items + 1] = item
        item.container = self
        return item
    end
    return c
end

function Env.item(fullType, calories)
    local item = { fullType = fullType, calories = calories or 0, hunger = -0.1, extra = {}, minutes = 100 }
    function item:getFullType() return self.fullType end
    function item:getType() return self.fullType:match("%.(.+)") end
    function item:getDisplayName() return self.fullType end
    function item:getTexture() return nil end
    function item:getName() return self.fullType end
    function item:getCalories() return self.calories end
    function item:getBaseHunger() return self.hunger end
    function item:getHungerChange() return self.hunger end
    function item:getHungChange() return self.hunger end
    function item:isRotten() return self.rotten or false end
    function item:getPoisonPower() return self.poisonPower or 0 end
    function item:isSpice() return self.spice or false end
    function item:isFrozen() return self.frozen or false end
    function item:isCooked() return self.cooked or false end
    function item:isBurnt() return self.burnt or false end
    function item:isBroken() return self.broken or false end
    function item:setCooked(v) self.cooked = v end
    function item:getContainer() return self.container end
    function item:getSquare() return nil end
    function item:getWorldItem() return self.world end
    function item:getMinutesToBurn() return self.burnMinutes or 200 end
    function item:setMinutesToBurn(value) self.burnMinutes = value end
    function item:getCookingTime() return self.cookingTime or 0 end
    function item:getHeat() return self.heat or 1 end
    function item:getFreezingTime() return self.freezingTime or 0 end
    function item:getID() return self end
    function item:haveExtraItems() return #self.extra > 0 end
    function item:getExtraItems() return Env.list(self.extra) end
    function item:getMinutesToCook() return self.minutes end
    function item:getSpices() return Env.list(self.spices) end
    function item:setMinutesToCook(v) self.minutes = v end
    function item:getFluidContainer()
        return { getCapacity = function() return 2 end, getAmount = function() return item.water or 0 end,
            isEmpty = function() return (item.water or 0) == 0 end, adjustSpecificFluidAmount = function() end }
    end
    function item:createCloneItem()
        local clone = Env.item(self.fullType, self.calories)
        clone.hunger, clone.clone = self.hunger, true
        return clone
    end
    return item
end

function Env.new(dishKey)
    for name in pairs(package.loaded) do
        if name:match("^CookItForMe_") then package.loaded[name] = nil end
    end
    CookItForMe = nil
    local e = {
        on = false,
        allowFrozen = false,
        queue = {},
        callbackEvents = {},
        trace = {},
        uiSounds = {},
        now = 0,
        zombies = {},
        messages = {},
    }
    local function record(s) e.trace[#e.trace + 1] = s end
    e.inv, e.source, e.stoveInv = Env.container("inventory"), Env.container("cupboard"), Env.container("stove")
    e.square = { getX = function() return 0 end, getY = function() return 0 end }
    e.player = {
        getInventory = function() return e.inv end,
        getCurrentSquare = function() return e.square end,
        getNutrition = function() return { getWeight = function() return 80 end } end,
        getPerkLevel = function() return 3 end,
        getX = function() return 0 end, getY = function() return 0 end, getZ = function() return 0 end,
        getCell = function() return { getZombieList = function() return Env.list(e.zombies) end } end,
        getEmitter = function() return { playSoundImpl = function() record("sound") end } end,
        Say = function(_, s) e.messages[#e.messages + 1] = s end,
    }
    e.modData = {}
    e.player.getModData = function() return e.modData end
    e.stove = {
        getContainer = function() return e.stoveInv end,
        getSquare = function() return e.square end,
        isBroken = function() return e.broken or false end,
        Activated = function() return e.on or false end,
        Toggle = function() e.on = not e.on record(e.on and "on" or "off") end,
    }
    e.sink = {
        hasFluid = function() return not e.dry end,
        getSquare = function() return e.square end,
        isTaintedWater = function() return false end,
    }
    local bases = { Soup = "Base.Pot", Stew = "Base.Pot", ["Stir fry"] = "Base.Pan", ["Roasted Vegetables"] = "Base.RoastingPan",
        Salad = "Base.Bowl", ["Fruit Salad"] = "Base.ClayBowl" }
    dishKey = dishKey or "Soup"
    e.pot = e.source:AddItem(Env.item(bases[dishKey]))
    e.pot.nonFood = true
    e.food = e.source:AddItem(Env.item(dishKey == "Fruit Salad" and "Base.Apple" or "Base.Carrot", 40))
    e.spice = e.source:AddItem(Env.item("Base.Salt", 0))
    e.spice.spice = true
    e.spice.leftover = true
    e.collected = { cookware = { e.pot }, foods = { e.food }, spices = { e.spice } }
    e.scan = { stove = e.stove, sink = e.sink, containers = { e.source }, floorItems = {} }
    package.loaded.CookItForMe_Scanner = {
        scanAround = function() return e.scan end,
        collectFood = function() return e.collected end,
    }
    e.recipe = {
        getUntranslatedName = function()
            local name = dishKey == "Fruit Salad" and "FruitSalad" or dishKey
            return e.recipeBaseType == "Base.ClayBowl" and name .. "Clay" or name
        end,
        getMaxItems = function() return 6 end,
        getItemsList = function()
            if e.metadataError then error("recipe metadata unavailable") end
            return { get = function(_, name)
                if name == e.food:getType() or name == "Salt" or (dishKey == "Salad" and name == "Potato") then
                    return { getUse = function() return name == "Salt" and 1 or 10 end }
                end
            end }
        end,
        needToBeCooked = function(_, item)
            local required = item:getType() == "Potato"
            return not required or item:isCooked() or item:isBurnt()
        end,
        isCookable = function() return true end,
        isAllowFrozenItem = function() return e.allowFrozen or false end,
        setAllowFrozenItem = function(_, v) e.allowFrozen = v end,
        getPossibleItems = function() return Env.list(e.collected.foods) end,
        getItemsCanBeUse = function() return Env.list(e.collected.foods) end,
        getResultItem = function()
            return dishKey == "Salad" and (e.recipeBaseType == "Base.ClayBowl" and "SaladClay" or "Salad")
                or (dishKey == "Fruit Salad" and (e.recipeBaseType == "Base.ClayBowl" and "FruitSaladClay" or "FruitSalad") or "CookedDish")
        end,
        getFullResultItem = function() return "Base." .. e.recipe:getResultItem() end,
        getAddIngredientSound = function() return "AddItemInRecipe" end,
        isItemUsableInRecipe = function(_, _, _, item) return item ~= e.reject and (not item:isFrozen() or e.allowFrozen) end,
        addItem = function(_, pot, ingredient)
            if pot.clone then
                if not pot.container then e.inv:AddItem(pot) end
                if e.simError then error("simulation unavailable") end
            else
                record("add:" .. ingredient.fullType)
                if ingredient == e.addError then error("add unavailable") end
                if not ingredient.leftover and ingredient.container then ingredient.container:Remove(ingredient) end
            end
            if not pot.clone and pot.nonFood then
                local old = pot
                pot = Env.item(e.recipe:getFullResultItem(), 0)
                if old.container then old.container:Remove(old) end
                e.inv:AddItem(pot)
                e.pot = pot
            end
            if ingredient.spice then
                pot.spices = pot.spices or {}
                pot.spices[#pot.spices + 1] = ingredient.fullType
            else
                pot.extra[#pot.extra + 1] = ingredient.fullType
            end
            pot.calories = pot.calories + ingredient.calories
            return pot
        end,
    }
    RecipeManager = { getEvolvedRecipe = function(cookware)
        e.recipeBaseType = cookware:getFullType()
        return Env.list(e.noRecipe and {} or { e.recipe })
    end }
    ArrayList = { new = function() return Env.list() end }
    Fluid, Perks = { Water = 1 }, { Cooking = 1 }
    instanceof = function(item, class) return class == "Food" and not item.nonFood end
    ScriptManager = { instance = { getAllUniqueRecipes = function() if e.forecastError then error("forecast unavailable") end return Env.list() end } }
    SandboxVars = { CookItForMe = { Debug = false } }
    getText = function(key) return key end
    getTimestampMs = function() return e.now end
    getPlayer = function() return e.player end
    getSoundManager = function() return { playUISound = function(_, name) e.uiSounds[#e.uiSounds + 1] = name end } end
    Events = {
        OnGameBoot = { Add = function() end },
        OnTick = { Add = function(f) e.tick = f end },
    }
    AdjacentFreeTileFinder = { Find = function() return e.square end }
    local function action(kind, perform)
        local a = { kind = kind, perform = perform }
        function a:setOnComplete(f) self.callback = f end
        function a:isValidStart() return true end
        function a:waitToStart() return false end
        function a:start() end
        function a:update() end
        function a:complete() return true end
        function a:isValid() return true end
        function a:stop() e.queue = {} end
        function a:forceStop() self:stop() end
        function a:forceCancel() self:stop() end
        return a
    end
    e.player.getVehicle = function() return nil end
    getGameSpeed = function() return e.speed or 1 end
    setGameSpeed = function(value) e.speed = value end
    getGameTime = function() return {
        setMultiplier = function(_, value) e.multiplier = value end,
    } end
    ISWalkToTimedAction = { new = function(_, _, square)
        local a = action("walk", function() e.square = square end)
        a.isValid = function() return getGameSpeed() <= 2 and not e.noPath end
        return a
    end }
    ISInventoryTransferAction = { new = function(_, _, item, src, dest)
        local a = action("transfer", function()
            record("transfer:" .. item.fullType .. ":" .. dest.kind)
            if src then src:Remove(item) end
            dest:AddItem(item)
        end)
        a.item, a.srcContainer, a.destContainer = item, src, dest
        a.isValid = function() return src ~= nil and dest ~= nil and src:contains(item) and dest:hasRoomFor(e.player, item) end
        return a
    end }
    ISTakeWaterAction = { new = function(_, _, item)
        local a = action("water", function() record("water"); item.water = e.dry and 0 or 2 end)
        a.isValid = function() return not e.dry end
        return a
    end }
    ISGrabItemAction = { new = function(_, _, world)
        local item = world:getItem()
        local a = action("grab", function()
            if item.container then item.container:Remove(item) end
            item.world = nil; world.square = nil
            e.inv:AddItem(item)
        end)
        a.setOnComplete = nil -- vanilla grab/water do not expose the transfer callback API
        a.isValid = function() return world:getSquare() ~= nil and e.inv:hasRoomFor(e.player, item) end
        return a
    end }
    ItemContainer = { new = function(_, square)
        local floor = Env.container("floor")
        floor.getSourceGrid = function() return square end
        function floor:AddItem(item)
            local world = { square = square, getSquare = function(self) return self.square end, getItem = function() return item end }
            item.world = world; item.container = nil
        end
        return floor
    end }
    ISAddItemInRecipe = { checkName = function() end, checkTemperature = function() end }
    ISTimedActionQueue = {
        getTimedActionQueue = function() return { queue = e.queue } end,
        add = function(a) e.queue[#e.queue + 1] = a end,
        clear = function() e.queue = {} record("clear") end,
    }
    local function scheduleCallback(callback)
        e.callbackEvents[#e.callbackEvents + 1] = callback
    end
    local function runAction(a, faults, callbackScheduler)
        local sim = Simulator.new({ faults = faults or {} })
        local proxy = { effectKey = "action:" .. tostring(a) }
        if a.item and a.srcContainer and a.srcContainer:contains(a.item) then
            sim:place(a.item, a.srcContainer)
        end
        function proxy:isValidStart()
            if faults and faults.rejectBeforeStart then return false end
            return not a.isValidStart or a:isValidStart()
        end
        function proxy:waitToStart() return a.waitToStart and a:waitToStart() or false end
        function proxy:start()
            if a.start then a:start() end
            if faults and faults.itemDisappears then self.itemUnavailable = true end
            if faults and faults.destinationBecomesFull and a.destContainer then a.destContainer.full = true end
        end
        function proxy:update() if a.update then a:update() end end
        function proxy:isValid()
            if self.itemUnavailable then return false end
            return not a.isValid or a:isValid()
        end
        function proxy:complete()
            if not a.complete then return true end
            return a:complete() ~= false
        end
        function proxy:perform(runningSim)
            if a.perform then a:perform() end
            if a.item and a.item:getContainer() then runningSim:place(a.item, a.item:getContainer()) end
            if callbackScheduler and a.callback then callbackScheduler(a.callback, runningSim) end
        end
        function proxy:stop() if a.stop then a:stop() end end
        function proxy:forceCancel()
            if a.forceCancel then a:forceCancel()
            elseif a.forceStop then a:forceStop() end
        end
        sim:queue(proxy)
        sim:runUntilIdle()
        sim:assertInvariants()
        e.lastSimulator = sim
        return sim
    end
    function e:drain()
        for _ = 1, 100 do
            if self.callbackEvents[1] then
                table.remove(self.callbackEvents, 1)()
            elseif self.queue[1] then
                local a = table.remove(self.queue, 1)
                runAction(a, nil, function(callback)
                    scheduleCallback(callback)
                    if self.duplicateCallbacks then scheduleCallback(callback) end
                end)
            else
                self.now = self.now + 500
                self.tick()
                if #self.queue == 0 and not self:state().delayNext then return end
            end
        end
        error("queue did not settle")
    end
    function e:state()
        return self.cook.getSession and self.cook.getSession() or self.cook
    end
    function e:runScenario(id, faults)
        if id == "cook.recipe.replacement.success" then
            local old = self.pot
            local plan = assert(self.cook.plan(self.player, "Soup"))
            plan.picked.spices = {}
            local effects = 0
            local addItem = self.recipe.addItem
            self.recipe.addItem = function(recipe, pot, ingredient, player)
                effects = effects + 1
                return addItem(recipe, pot, ingredient, player)
            end
            self.cook.start(self.player, "Soup", plan)
            self:drain()
            self.pot.cooked = true
            self.tick()
            self:drain()
            local session = self:state()
            local result = self.pot
            local function present(container, item) return container:contains(item) end
            local oldPresent = present(self.source, old) or present(self.inv, old) or present(self.stoveInv, old)
            local resultLocations = (present(self.source, result) and 1 or 0)
                + (present(self.inv, result) and 1 or 0)
                + (present(self.stoveInv, result) and 1 or 0)
            local passed = not session.active and session.reason == "success" and not oldPresent
                and result.fullType == "Base.CookedDish" and effects == 1 and resultLocations == 1
                and present(self.inv, result) and not self.on
            local failureReason
            if not passed then failureReason = session.reason or session.stage end
            return {
                status = passed and "pass" or "fail",
                sessionActive = session.active,
                sourceContains = present(self.source, result),
                destinationContains = present(self.inv, result),
                effectCount = effects,
                stoveActive = self.on,
                failureReason = failureReason,
                oldObjectPresent = oldPresent,
                resultFullType = result.fullType,
                resultLocationCount = resultLocations,
            }
        end
        assert(id == "cook.transfer.container.success", "unknown scenario: " .. tostring(id))
        faults = faults or {}
        local item = self.pot
        local source, destination = self.source, self.inv
        local transfer = ISInventoryTransferAction:new(self.player, item, source, destination, nil)
        local effects = 0
        local perform = transfer.perform
        transfer.perform = function(self)
            perform(self)
            effects = effects + 1
        end
        local callbackCalled, callbackCount, callbackAttempts = false, 0, 0
        transfer:setOnComplete(function()
            callbackAttempts = callbackAttempts + 1
            if callbackCalled then return end
            callbackCalled = true
            callbackCount = callbackCount + 1
        end)
        local sim
        sim = runAction(transfer, faults, function(callback, runningSim)
            if faults.staleCallbackAfterSession then
                runningSim:schedule(1, callback)
            else
                scheduleCallback(callback)
                if faults.duplicateCallback then scheduleCallback(callback) end
            end
        end)
        while self.callbackEvents[1] do table.remove(self.callbackEvents, 1)() end
        sim:runUntilIdle()
        sim:assertInvariants()
        local sourceContains = source:contains(item)
        local destinationContains = destination:contains(item)
        local passed = sim.state.status == "PASS" and not sourceContains and destinationContains
            and effects == 1 and not self.on
        local failureReason
        if not passed then failureReason = sim.state.status end
        return {
            status = passed and "pass" or "fail",
            sessionActive = sim.state.active,
            sourceContains = sourceContains,
            destinationContains = destinationContains,
            effectCount = effects,
            callbackCount = callbackCount,
            callbackAttempts = callbackAttempts,
            rejectedCallbackCount = sim.state.rejectedCallbacks,
            stoveActive = self.on,
            failureReason = failureReason,
        }
    end
    e.cook = require "CookItForMe_Cook"
    return e
end

return Env
