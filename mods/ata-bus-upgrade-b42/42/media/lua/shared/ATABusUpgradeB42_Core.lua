local Upgrade = {}

Upgrade.ENGINE_POWER = 5000
Upgrade.MAX_SPEED = 100

local TARGETS = {
    ["Base.ATAArmyBus"] = true,
    ["Base.ATAPrisonBus"] = true,
    ["Base.ATASchoolBus"] = true,
}

function Upgrade.isTargetBus(scriptName)
    return TARGETS[scriptName] == true
end

local function getScriptName(vehicle)
    if not vehicle then return nil end

    if vehicle.getScriptName then
        local name = vehicle:getScriptName()
        if name and name ~= "" then return name end
    end

    if vehicle.getScript then
        local script = vehicle:getScript()
        if script then
            if script.getFullName then return script:getFullName() end
            if script.getFullType then return script:getFullType() end
        end
    end

    return nil
end

function Upgrade.upgradeVehicle(vehicle)
    if not Upgrade.isTargetBus(getScriptName(vehicle)) then return false end

    local changed = false
    local engineChanged = false

    if vehicle.getEnginePower and vehicle.setEngineFeature
            and vehicle:getEnginePower() ~= Upgrade.ENGINE_POWER then
        vehicle:setEngineFeature(
            vehicle:getEngineQuality(),
            vehicle:getEngineLoudness(),
            Upgrade.ENGINE_POWER
        )
        changed = true
        engineChanged = true
    end

    if vehicle.getMaxSpeed and vehicle.setMaxSpeed
            and vehicle:getMaxSpeed() ~= Upgrade.MAX_SPEED then
        vehicle:setMaxSpeed(Upgrade.MAX_SPEED)
        changed = true
    end

    if engineChanged and vehicle.transmitEngine then
        vehicle:transmitEngine()
    end

    return changed
end

function Upgrade.upgradeLoadedVehicles(cell)
    if not cell or not cell.getVehicles then return 0 end

    local vehicles = cell:getVehicles()
    if not vehicles then return 0 end

    local changed = 0
    if type(vehicles.iterator) == "function" then
        local iterator = vehicles:iterator()
        while iterator:hasNext() do
            if Upgrade.upgradeVehicle(iterator:next()) then
                changed = changed + 1
            end
        end
        return changed
    end

    if type(vehicles.size) ~= "function" or type(vehicles.get) ~= "function" then
        return 0
    end

    for index = 0, vehicles:size() - 1 do
        if Upgrade.upgradeVehicle(vehicles:get(index)) then
            changed = changed + 1
        end
    end
    return changed
end

return Upgrade
