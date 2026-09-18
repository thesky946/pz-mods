package.path = "../42/media/lua/shared/?.lua;" .. package.path

ATA_BUS_UPGRADE_TEST = true

local Upgrade = require("ATABusUpgradeB42_Core")

local passed = 0

local function equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
    passed = passed + 1
end

local function makeVehicle(scriptName, power, maxSpeed)
    local vehicle = {
        power = power,
        maxSpeed = maxSpeed,
        engineUpdates = 0,
        speedUpdates = 0,
        transmissions = 0,
    }

    function vehicle:getScriptName() return scriptName end
    function vehicle:getEnginePower() return self.power end
    function vehicle:getEngineQuality() return 73 end
    function vehicle:getEngineLoudness() return 110 end
    function vehicle:getMaxSpeed() return self.maxSpeed end
    function vehicle:setEngineFeature(quality, loudness, newPower)
        equal(quality, 73, "engine quality must be preserved")
        equal(loudness, 110, "engine loudness must be preserved")
        self.power = newPower
        self.engineUpdates = self.engineUpdates + 1
    end
    function vehicle:setMaxSpeed(newSpeed)
        self.maxSpeed = newSpeed
        self.speedUpdates = self.speedUpdates + 1
    end
    function vehicle:transmitEngine()
        self.transmissions = self.transmissions + 1
    end

    return vehicle
end

equal(Upgrade.isTargetBus("Base.ATAArmyBus"), true, "army bus must match")
equal(Upgrade.isTargetBus("Base.ATAPrisonBus"), true, "prison bus must match")
equal(Upgrade.isTargetBus("Base.ATASchoolBus"), true, "school bus must match")
equal(Upgrade.isTargetBus("Base.ATAArmyBusBurnt"), false, "other scripts must not match")

local bus = makeVehicle("Base.ATAArmyBus", 3500, 60)
equal(Upgrade.upgradeVehicle(bus), true, "an outdated bus must be upgraded")
equal(bus.power, 5000, "engine must be 500 hp")
equal(bus.maxSpeed, 100, "top speed must be 100 mph")
equal(bus.engineUpdates, 1, "engine must be updated once")
equal(bus.speedUpdates, 1, "speed must be updated once")
equal(bus.transmissions, 1, "engine update must be transmitted")

equal(Upgrade.upgradeVehicle(bus), false, "repeat callback must be idempotent")
equal(bus.engineUpdates, 1, "repeat callback must not rewrite engine")
equal(bus.speedUpdates, 1, "repeat callback must not rewrite speed")

local other = makeVehicle("Base.CarNormal", 3500, 60)
equal(Upgrade.upgradeVehicle(other), false, "unrelated vehicles must be ignored")
equal(other.engineUpdates, 0, "unrelated engine must stay untouched")
equal(Upgrade.upgradeVehicle(nil), false, "missing vehicle must be safe")

local list = { bus, makeVehicle("Base.ATASchoolBus", 3200, 50), other }
local vehicles = {}
function vehicles:size() return #list end
function vehicles:get(index) return list[index + 1] end
local cell = {}
function cell:getVehicles() return vehicles end

equal(Upgrade.upgradeLoadedVehicles(cell), 1, "only outdated target buses must count")

local iteratorBus = makeVehicle("Base.ATAPrisonBus", 3100, 55)
local iteratorItems = { iteratorBus, other }
local iteratorIndex = 0
local iterator = {}
function iterator:hasNext() return iteratorIndex < #iteratorItems end
function iterator:next()
    iteratorIndex = iteratorIndex + 1
    return iteratorItems[iteratorIndex]
end
local iteratorOnlyVehicles = {}
function iteratorOnlyVehicles:size() return #iteratorItems end
function iteratorOnlyVehicles:iterator() return iterator end
local iteratorCell = {}
function iteratorCell:getVehicles() return iteratorOnlyVehicles end

equal(Upgrade.upgradeLoadedVehicles(iteratorCell), 1, "B42 iterator-only vehicle collections must work")
equal(iteratorBus.power, 5000, "iterator-only collection must upgrade engine")
equal(iteratorBus.maxSpeed, 100, "iterator-only collection must upgrade speed")

local scriptPath = "../42/media/scripts/vehicles/ata_bus_upgrade_b42.txt"
local file = assert(io.open(scriptPath, "rb"))
local script = file:read("*a")
file:close()

for _, name in ipairs({ "ATAArmyBus", "ATAPrisonBus", "ATASchoolBus" }) do
    local block = script:match("vehicle%s+" .. name .. "%s*(%b{})")
    equal(block ~= nil, true, name .. " script override must exist")
    equal(block:match("engineForce%s*=%s*5000%s*,") ~= nil, true, name .. " force must be 5000")
    equal(block:match("maxSpeed%s*=%s*100f%s*,") ~= nil, true, name .. " max speed must be 100")
    equal(block:match("offRoadEfficiency%s*=%s*1%.1%s*,") ~= nil, true, name .. " off-road efficiency must match the original")
    equal(block:match("engineQuality%s*=%s*80%s*,") ~= nil, true, name .. " engine quality must match the original")
    equal(block:match("rollInfluence%s*=%s*0%.8f%s*,") ~= nil, true, name .. " roll influence must match the original")
    equal(block:match("steeringIncrement%s*=%s*0%.04%s*,") ~= nil, true, name .. " steering must match the original")
    equal(block:match("steeringClamp%s*=%s*0%.3%s*,") ~= nil, true, name .. " steering clamp must match the original")
    equal(block:match("suspensionStiffness%s*=%s*35%s*,") ~= nil, true, name .. " suspension stiffness must match the original")
    equal(block:match("suspensionCompression%s*=%s*3%.83%s*,") ~= nil, true, name .. " suspension compression must match the original")
    equal(block:match("suspensionDamping%s*=%s*2%.88%s*,") ~= nil, true, name .. " suspension damping must match the original")
    equal(block:match("maxSuspensionTravelCm%s*=%s*10%s*,") ~= nil, true, name .. " suspension travel must match the original")
    equal(block:match("wheelFriction%s*=%s*1%.5f%s*,") ~= nil, true, name .. " wheel friction must match the original")
end

local info = assert(io.open("../42/mod.info", "rb"))
local modInfo = info:read("*a")
info:close()
equal(modInfo:match("require=ATA_Bus") ~= nil, true, "ATA_Bus must be a hard dependency")

print("ATABusUpgrade tests passed: " .. passed)
