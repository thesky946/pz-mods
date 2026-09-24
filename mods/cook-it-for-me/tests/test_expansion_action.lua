package.path = "../42/media/lua/shared/?.lua;./?.lua;" .. package.path
local Env = require "support/cook_env"
local e = Env.new()
local Session = require "CookItForMe_Session"
local Actions = require "CookItForMe_Actions"
local pan = e.inv:AddItem(Env.item("Base.Pan"))
local egg1 = e.inv:AddItem(Env.item("Base.Egg"))
local egg2 = e.inv:AddItem(Env.item("Base.EggChicken"))
local whisk = e.inv:AddItem(Env.item("Base.Whisk"))
local craft = {
    getInputs = function() return Env.list({ {}, {}, {} }) end,
    requiresSpecificWorkstation = function() return false end,
}
local plan = { cookware = pan, settings = { frozenPenalty = 0 },
    prep = { recipe = craft, expected = "Base.OmeletteRecipe", items = { whisk, egg1, egg2 } } }
local session = Session.new(e.player, plan)
local failure, completed, crafts = nil, 0, 0
e.duplicateCallbacks = true
local actions = Actions.new(session, function(key) failure = key; session:finish("error") end)
HandcraftLogic = { new = function(_, _, surface)
    local logic = { selected = {}, surface = surface }
    function logic:setContainers(c) self.containers = c end
    function logic:setRecipe(r) self.recipe = r end
    function logic:setManualSelectInputs() end
    function logic:clearManualInputs() end
    function logic:setManualInputsFor(_, values) self.selected[#self.selected + 1] = values; return true end
    function logic:canPerformCurrentRecipe() return #self.selected == 3 and self.surface == nil end
    return logic
end }
ISHandcraftAction = { FromLogic = function()
    local action = { perform = function()
        crafts = crafts + 1
        e.inv:Remove(pan)
        e.inv:Remove(egg1)
        e.inv:Remove(egg2)
        e.inv:AddItem(Env.item("Base.OmeletteRecipe"))
    end }
    function action:setOnComplete(f) self.callback = f end
    function action:stop() end
    return action
end }
actions.prepare(e.player, plan.prep, function() completed = completed + 1 end)
local firstAction = assert(e.queue[1])
e:drain()
assert(not failure and completed == 1 and crafts == 1)
firstAction:perform()
assert(crafts == 1 and completed == 1, "repeated perform cannot repeat a consuming recipe")
assert(session.pot:getFullType() == "Base.OmeletteRecipe" and e.inv:contains(session.pot))
local pan2 = e.inv:AddItem(Env.item("Base.Pan"))
local egg3 = e.inv:AddItem(Env.item("Base.Egg"))
local egg4 = e.inv:AddItem(Env.item("Base.EggChicken"))
local prep2 = { recipe = craft, expected = "Base.OmeletteRecipe", items = { whisk, egg3, egg4 } }
local session2 = Session.new(e.player, { cookware = pan2, scan = plan.scan, prep = prep2, settings = plan.settings })
local failure2
local actions2 = Actions.new(session2, function(key) failure2 = key; session2:finish("error") end)
ISHandcraftAction.FromLogic = function()
    local action = { perform = function() crafts = crafts + 1; e.inv:Remove(pan2) end }
    function action:setOnComplete(f) self.callback = f end
    function action:stop() end
    return action
end
actions2.prepare(e.player, prep2, function() error("missing result continued") end)
e:drain()
assert(failure2 == "ActionFailed" and not session2.active and crafts == 2,
    "a callback without the new dish terminates without retrying craft")
local session3 = Session.new(e.player, { cookware = pan2, scan = plan.scan, prep = prep2, settings = plan.settings })
local failure3
local actions3 = Actions.new(session3, function(key) failure3 = key; session3:finish("error") end)
actions3.prepare(e.player, prep2, function() error("missing input continued") end)
assert(failure3 == "ItemMissing" and crafts == 2 and not session3.active)
local pan4 = e.inv:AddItem(Env.item("Base.Pan"))
local prep4 = { recipe = craft, expected = "Base.OmeletteRecipe", items = { whisk, egg3, egg4 } }
local session4 = Session.new(e.player, { cookware = pan4, scan = plan.scan, prep = prep4, settings = plan.settings })
local actions4 = Actions.new(session4, function() error("stale preparation failed") end)
actions4.prepare(e.player, prep4, function() error("stale preparation continued") end)
local stale = assert(e.queue[1])
session4:finish("cancelled")
stale:perform()
assert(crafts == 2 and e.inv:contains(pan4), "stale action cannot run the consuming recipe")
e.queue = {}
local pastaPot = e.inv:AddItem(Env.item("Base.Saucepan"))
local macaroni = e.inv:AddItem(Env.item("Base.Macaroni"))
local pastaInputs = { {}, {} } -- Fluid is part of the vessel input, not a third item input.
local pastaRecipe = { getInputs = function()
    return { size = function() return #pastaInputs end,
        get = function(_, index)
            assert(index >= 0 and index < #pastaInputs, "recipe input index out of bounds")
            return pastaInputs[index + 1]
        end }
end, requiresSpecificWorkstation = function() return false end }
local pastaPrep = { recipe = pastaRecipe, expected = "Base.WaterSaucepanPasta", items = { macaroni } }
local pastaSession = Session.new(e.player, { cookware = pastaPot, prep = pastaPrep, settings = plan.settings })
local pastaFailure, pastaCompleted = nil, 0
local pastaActions = Actions.new(pastaSession, function(key) pastaFailure = key; pastaSession:finish("error") end)
HandcraftLogic.new = function()
    local logic = { selected = {} }
    function logic:setContainers() end
    function logic:setRecipe() end
    function logic:setManualSelectInputs() end
    function logic:clearManualInputs() end
    function logic:setManualInputsFor(input, values)
        self.selected[#self.selected + 1] = { input = input, item = values:get(0) }
        return true
    end
    function logic:canPerformCurrentRecipe()
        return #self.selected == 2 and self.selected[1].input == pastaInputs[1]
            and self.selected[1].item == pastaPot and self.selected[2].input == pastaInputs[2]
            and self.selected[2].item == macaroni
    end
    return logic
end
ISHandcraftAction.FromLogic = function()
    local action = { perform = function()
        e.inv:Remove(pastaPot)
        e.inv:Remove(macaroni)
        e.inv:AddItem(Env.item("Base.WaterSaucepanPasta"))
    end }
    function action:setOnComplete(f) self.callback = f end
    function action:stop() end
    return action
end
pastaActions.prepare(e.player, pastaPrep, function() pastaCompleted = pastaCompleted + 1 end)
e:drain()
assert(not pastaFailure and pastaCompleted == 1 and pastaSession.pot:getFullType() == pastaPrep.expected,
    "pasta preparation uses two item inputs and produces the expected vessel")
local safePot = e.inv:AddItem(Env.item("Base.Saucepan"))
local safePasta = e.inv:AddItem(Env.item("Base.Macaroni"))
local latePrep = { recipe = pastaRecipe, expected = "Base.WaterSaucepanPasta", items = { safePasta } }
local lateSession = Session.new(e.player, { cookware = safePot, prep = latePrep, settings = plan.settings })
local lateFailure, lateCrafts = nil, 0
local lateActions = Actions.new(lateSession, function(key) lateFailure = key; lateSession:finish("error") end)
HandcraftLogic.new = function()
    return { setContainers = function() end, setRecipe = function() end,
        setManualSelectInputs = function() end, clearManualInputs = function() end,
        setManualInputsFor = function() return true end,
        canPerformCurrentRecipe = function() return true end }
end
ISHandcraftAction.FromLogic = function()
    local action = { perform = function() lateCrafts = lateCrafts + 1; e.inv:Remove(safePasta) end }
    function action:stop() end
    return action
end
lateActions.prepare(e.player, latePrep, function() error("poisoned prep continued") end)
assert(e.queue[1], "preparation action was queued before the item changed")
safePasta.poisonPower = 6
e:drain()
assert(lateFailure == "PlanChanged" and lateCrafts == 0 and e.inv:contains(safePasta),
    "newly poisoned preparation input cannot be consumed")
print("EXPANSION ACTION TESTS PASSED")
