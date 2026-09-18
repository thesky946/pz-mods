local Upgrade = require("ATABusUpgradeB42_Core")

local TICKS_BETWEEN_SCANS = 300
local ticks = TICKS_BETWEEN_SCANS

local function onTick()
    ticks = ticks + 1
    if ticks < TICKS_BETWEEN_SCANS then return end
    ticks = 0

    Upgrade.upgradeLoadedVehicles(getCell())
end

Events.OnTick.Add(onTick)
