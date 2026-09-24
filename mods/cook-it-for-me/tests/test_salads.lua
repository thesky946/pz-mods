package.path = "../42/media/lua/shared/?.lua;./?.lua;" .. package.path
local Env = require "support/cook_env"

local function ready(dish)
    local e = Env.new(dish)
    e.scan.stove, e.scan.sink = nil, nil
    e.stove.isBroken = function() error("salad must not inspect stove") end
    e.stove.getContainer = function() error("salad must not inspect stove") end
    e.stove.Activated = function() error("salad must not inspect stove") end
    e.stove.Toggle = function() error("salad must not toggle stove") end
    e.sink.hasFluid = function() error("salad must not inspect sink") end
    return e
end

for _, case in ipairs({
    { "Salad", "Base.Bowl", "Base.Salad" },
    { "Salad", "Base.ClayBowl", "Base.SaladClay" },
    { "Fruit Salad", "Base.Bowl", "Base.FruitSalad" },
    { "Fruit Salad", "Base.ClayBowl", "Base.FruitSaladClay" },
}) do
    local dish, bowlType, resultType = case[1], case[2], case[3]
    local e = ready(dish)
    if e.pot:getFullType() ~= bowlType then
        e.source:Remove(e.pot)
        e.pot = e.source:AddItem(Env.item(bowlType))
        e.pot.nonFood = true
        e.collected.cookware = { e.pot }
    end
    local plan, key = e.cook.plan(e.player, dish)
    assert(plan, dish .. " must plan without heat/water: " .. tostring(key))
    assert(plan.needsHeat == false and plan.dish.needsWater == false)
    assert(e.cook.start(e.player, dish, plan))
    e:drain()
    local result = e.cook.getSession().pot
    assert(result ~= plan.cookware, "first ingredient replaces the bowl")
    assert(result:getFullType() == resultType)
    assert(result:getContainer() == e.inv and e.inv:contains(result), "tracked salad is in player inventory")
    assert(e:state().active == false and e:state().reason == "success")
    assert(#e.uiSounds == 1 and e.on == false)
end

local wrongResult = ready("Salad")
wrongResult.recipe.getFullResultItem = function() return "Base.SaladClay" end
local wrongPlan, wrongKey = wrongResult.cook.plan(wrongResult.player, "Salad")
assert(wrongPlan == nil and wrongKey == "NoCookware",
    "same-name recipe with a result for the other bowl must be rejected")

local wet = ready("Salad")
wet.pot.water = 1
local dry = wet.source:AddItem(Env.item("Base.ClayBowl"))
dry.nonFood = true
wet.collected.cookware[#wet.collected.cookware + 1] = dry
local dryPlan = assert(wet.cook.plan(wet.player, "Salad"))
assert(dryPlan.cookware == dry, "dry bowl chosen before a filled bowl")
wet.collected.cookware = { wet.pot }
local noPlan, noKey = wet.cook.plan(wet.player, "Salad")
assert(noPlan == nil and noKey == "NoEmptyBowl", "filled bowl is not a salad base")
assert(wet.pot.water == 1 and wet.source:contains(wet.pot), "failed plan preserves liquid and bowl")

local cooked = ready("Salad")
local potato = cooked.source:AddItem(Env.item("Base.Potato", 60))
potato.cooked = true
cooked.collected.foods[#cooked.collected.foods + 1] = potato
local cookedPlan = assert(cooked.cook.plan(cooked.player, "Salad"))
assert(cookedPlan.predictedCalories ~= nil and cookedPlan.predictedHunger ~= nil,
    "accepted cooked salad ingredients keep a useful nutrition preview")
local sawPotato = false
for _, item in ipairs(cookedPlan.picked.items) do if item == potato then sawPotato = true end end
assert(sawPotato, "cooked |Cooked ingredient is in the plan")
local cookedPlain = ready("Salad")
cookedPlain.food.cooked = true
local cookedPlainPlan = assert(cookedPlain.cook.plan(cookedPlain.player, "Salad"))
assert(cookedPlainPlan.picked.items[1] == cookedPlain.food,
    "installed vanilla recipe accepts cooked food without |Cooked")
assert(cookedPlain.cook.start(cookedPlain.player, "Salad", cookedPlainPlan))
cookedPlain:drain()
assert(cookedPlain:state().reason == "success")
potato.cooked = false
local rawStart, rawKey = cooked.cook.start(cooked.player, "Salad", cookedPlan)
assert(rawStart == false and rawKey == "SelectedUnavailable" and #cooked.queue == 0,
    "ingredient becoming raw before start is rejected without actions")

local rawOnly = ready("Salad")
local rawPotato = rawOnly.source:AddItem(Env.item("Base.Potato", 60))
rawOnly.collected.foods = { rawPotato }
local rawPlan = assert(rawOnly.cook.plan(rawOnly.player, "Salad"))
assert(#rawPlan.picked.items == 0, "raw |Cooked ingredient is not auto-selected")
for _, option in ipairs(rawOnly.cook.planEditor.alternatives(rawOnly.player, rawPlan, rawPlan.rows[1].id)) do
    assert(option ~= rawPotato, "raw |Cooked ingredient is not offered in editor")
end

local frozen = ready("Salad")
frozen.food.frozen = true
local frozenPlan = assert(frozen.cook.plan(frozen.player, "Salad"))
assert(frozen.cook.start(frozen.player, "Salad", frozenPlan))
frozen:drain()
assert(frozen:state().reason == "success" and frozen.allowFrozen == false,
    "frozen salad is allowed and shared recipe policy restored")

local changedBowl = ready("Salad")
local changedPlan = assert(changedBowl.cook.plan(changedBowl.player, "Salad"))
changedBowl.pot.water = 1
local started, failure = changedBowl.cook.start(changedBowl.player, "Salad", changedPlan)
assert(started == false and failure == "NoEmptyBowl" and #changedBowl.queue == 0)
assert(changedBowl.pot.water == 1 and changedBowl.source:contains(changedBowl.pot))

local wetAfterStart = ready("Salad")
local wetPlan = assert(wetAfterStart.cook.plan(wetAfterStart.player, "Salad"))
assert(wetAfterStart.cook.start(wetAfterStart.player, "Salad", wetPlan))
wetAfterStart.pot.water = 1
wetAfterStart:drain()
assert(not wetAfterStart:state().active and wetAfterStart:state().reason == "error")
assert(wetAfterStart.pot.water == 1 and #wetAfterStart.pot.extra == 0,
    "changed bowl is not consumed during execution")

local ignoredAdd = ready("Salad")
ignoredAdd.recipe.addItem = function(_, bowl) return bowl end
assert(ignoredAdd.cook.start(ignoredAdd.player, "Salad", assert(ignoredAdd.cook.plan(ignoredAdd.player, "Salad"))))
ignoredAdd:drain()
assert(not ignoredAdd:state().active and ignoredAdd:state().reason == "error"
    and #ignoredAdd.uiSounds == 0, "no-op ingredient cannot complete a salad")

local ignoredSecond = ready("Salad")
local secondCarrot = ignoredSecond.source:AddItem(Env.item("Base.Carrot", 35))
ignoredSecond.collected.foods[#ignoredSecond.collected.foods + 1] = secondCarrot
local realAdd = ignoredSecond.recipe.addItem
ignoredSecond.recipe.addItem = function(recipe, bowl, ingredient, player)
    if ingredient == secondCarrot then return bowl end
    return realAdd(recipe, bowl, ingredient, player)
end
assert(ignoredSecond.cook.start(ignoredSecond.player, "Salad",
    assert(ignoredSecond.cook.plan(ignoredSecond.player, "Salad"))))
ignoredSecond:drain()
assert(ignoredSecond:state().reason == "error" and #ignoredSecond.uiSounds == 0,
    "a later food add must change the tracked salad before success")

local stale = ready("Salad")
local stalePlan = assert(stale.cook.plan(stale.player, "Salad"))
assert(stale.cook.start(stale.player, "Salad", stalePlan))
local staleCallback = stale.queue[1].callback
stale.cook.cancel()
assert(stale.cook.start(stale.player, "Salad", stalePlan))
local queued = #stale.queue
staleCallback()
assert(#stale.queue == queued, "callback from cancelled salad cannot advance new session")
stale.duplicateCallbacks = true
stale:drain()
assert(stale:state().reason == "success" and #stale.uiSounds == 1)

local occupiedStove = ready("Salad")
local otherFood = occupiedStove.stoveInv:AddItem(Env.item("Base.OtherDish"))
occupiedStove.on = true
assert(occupiedStove.cook.start(occupiedStove.player, "Salad", assert(occupiedStove.cook.plan(occupiedStove.player, "Salad"))))
occupiedStove:drain()
assert(occupiedStove.on and occupiedStove.stoveInv:contains(otherFood)
    and occupiedStove:state().reason == "success", "salad leaves preexisting stove and food alone")

local noRoom = ready("Salad")
local noRoomPlan = assert(noRoom.cook.plan(noRoom.player, "Salad"))
noRoom.inv.full = true
assert(noRoom.cook.start(noRoom.player, "Salad", noRoomPlan))
noRoom:drain()
assert(noRoom:state().reason == "error" and noRoom.source:contains(noRoom.pot)
    and #noRoom.uiSounds == 0, "failed transfer cannot create salad")

local lostBowl = ready("Salad")
local lostPlan = assert(lostBowl.cook.plan(lostBowl.player, "Salad"))
local addCalls = 0
local originalAdd = lostBowl.recipe.addItem
lostBowl.recipe.addItem = function(...)
    addCalls = addCalls + 1
    return originalAdd(...)
end
local createMove = ISInventoryTransferAction.new
ISInventoryTransferAction.new = function(...)
    local action = createMove(...)
    if action.item == lostBowl.food then
        local perform = action.perform
        action.perform = function(self)
            perform(self)
            lostBowl.inv:Remove(lostBowl.pot)
        end
    end
    return action
end
assert(lostBowl.cook.start(lostBowl.player, "Salad", lostPlan))
lostBowl:drain()
assert(lostBowl:state().reason == "error" and addCalls == 0 and lostBowl.inv:contains(lostBowl.food),
    "missing bowl must stop before consuming the ingredient")

local rawDuringTransfer = ready("Salad")
local hotPotato = rawDuringTransfer.source:AddItem(Env.item("Base.Potato", 60))
hotPotato.cooked = true
rawDuringTransfer.collected.foods = { hotPotato }
local transferPlan = assert(rawDuringTransfer.cook.plan(rawDuringTransfer.player, "Salad"))
local createTransfer = ISInventoryTransferAction.new
ISInventoryTransferAction.new = function(...)
    local action = createTransfer(...)
    if action.item == hotPotato then
        local perform = action.perform
        action.perform = function(self) perform(self); hotPotato.cooked = false end
    end
    return action
end
assert(rawDuringTransfer.cook.start(rawDuringTransfer.player, "Salad", transferPlan))
rawDuringTransfer:drain()
assert(rawDuringTransfer:state().reason == "error" and #rawDuringTransfer.pot.extra == 0,
    "ingredient made raw during transfer is rejected before addItem")

local vanished = ready("Fruit Salad")
local vanishedPlan = assert(vanished.cook.plan(vanished.player, "Fruit Salad"))
vanished.source:Remove(vanished.food)
local missingStart, missingKey = vanished.cook.start(vanished.player, "Fruit Salad", vanishedPlan)
assert(missingStart == false and missingKey == "SelectedUnavailable" and #vanished.queue == 0)

local interrupted = ready("Salad")
assert(interrupted.cook.start(interrupted.player, "Salad", assert(interrupted.cook.plan(interrupted.player, "Salad"))))
interrupted.cook.cancel()
assert(interrupted:state().reason == "cancelled" and not interrupted:state().active
    and #interrupted.pot.extra == 0 and not interrupted.on)

local noFood = ready("Salad")
noFood.collected.foods = {}
local emptyPlan = assert(noFood.cook.plan(noFood.player, "Salad"))
local emptyStart, emptyKey = noFood.cook.start(noFood.player, "Salad", emptyPlan)
assert(emptyStart == false and emptyKey == "NotEnough" and #noFood.queue == 0)

local frozenError = ready("Salad")
frozenError.food.frozen = true
frozenError.addError = frozenError.food
assert(frozenError.cook.start(frozenError.player, "Salad",
    assert(frozenError.cook.plan(frozenError.player, "Salad"))))
frozenError:drain()
assert(frozenError:state().reason == "error" and frozenError.allowFrozen == false,
    "frozen override is restored after addItem throws")

print("SALAD TESTS PASSED")
