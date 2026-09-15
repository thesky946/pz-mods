package.path = "../42/media/lua/shared/?.lua;./?.lua;" .. package.path
local Env = require "support/cook_env"
local e = Env.new()
package.loaded.CookItForMe_Scanner = nil
local Scanner = require "CookItForMe_Scanner"
local squares = {}
for y = -3, 3 do
    for x = -3, 3 do
        local sq = { x = x, y = y, objects = {}, world = {} }
        function sq:getX() return self.x end
        function sq:getY() return self.y end
        function sq:isFree() return not self.wall end
        function sq:canReachTo(other) return not self.wall and not other.wall end
        function sq:getObjects() return Env.list(self.objects) end
        function sq:getStaticMovingObjects() return Env.list() end
        function sq:getWorldObjects() return Env.list(self.world) end
        squares[x .. "," .. y] = sq
    end
end
e.square = squares["0,0"]
getCell = function() return { getGridSquare = function(_, x, y) return squares[x .. "," .. y] end } end
instanceof = function(object, class) return object.class == class end
local function stove(x, broken)
    local square = squares[x .. ",0"]
    local container = Env.container("stove")
    local object = { class = "IsoStove", isMicrowave = function() return false end,
        isBroken = function() return broken end, getContainer = function() return container end }
    square.objects[#square.objects + 1] = object
    return object
end
stove(-1, true)
local good = stove(1, false)
assert(Scanner.scanAround(e.player, 0).stove == good, "radius zero includes adjacent usable stove")
local far = stove(2, false)
for y = -3, 3 do squares["1," .. y].wall = true end
assert(Scanner.scanAround(e.player, 3).stove == nil, "inaccessible stoves behind continuous wall excluded")
for y = -3, 3 do squares["1," .. y].wall = false end
assert(#Scanner.scanAround(e.player, 3).stoves == 2)
local bag = Env.item("Base.Bag")
bag.IsInventoryContainer = function() return true end
local inner = Env.container("bag")
bag.getInventory = function() return inner end
e.inv:AddItem(bag)
local pot = inner:AddItem(Env.item("Base.Pot"))
local result = Scanner.collectFood(e.player, { containers = { inner }, floorItems = {} })
assert(#result.cookware == 1 and result.cookware[1] == pot, "nested inventory is visited once")
getCell = nil
print("SCANNER TESTS PASSED")
