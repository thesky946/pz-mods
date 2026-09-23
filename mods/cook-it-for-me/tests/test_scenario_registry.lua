package.path = "./?.lua;" .. package.path

local registry = require "scenarios"

local expected = {
    ["cook.transfer.container.success"] = true,
    ["cook.recipe.replacement.success"] = true,
    ["cook.stove.ownership.success"] = true,
    ["cook.stove.preexisting.success"] = true,
}

local supportedModes = {
    offline = true,
    gameSp = true,
    gameMp = true,
    packaged = true,
    manual = true,
}

assert(registry.schema == 1, "scenario registry schema must be 1")

local found = {}
for _, scenario in ipairs(registry.scenarios) do
    assert(type(scenario.id) == "string" and scenario.id:match("^[a-z][a-z0-9_.-]+$") == scenario.id,
        "scenario ID must be lowercase dotted slug")
    assert(not found[scenario.id], "scenario IDs must be unique: " .. scenario.id)
    found[scenario.id] = true

    assert(type(scenario.modes) == "table", "scenario must declare supported modes: " .. scenario.id)
    local modeCount = 0
    for mode, enabled in pairs(scenario.modes) do
        assert(supportedModes[mode], "unsupported mode '" .. tostring(mode) .. "' for " .. scenario.id)
        assert(enabled == true, "declared mode must be true for " .. scenario.id)
        modeCount = modeCount + 1
    end
    assert(modeCount > 0, "scenario must support at least one mode: " .. scenario.id)
end

for id in pairs(expected) do
    assert(found[id], "missing expected scenario: " .. id)
end
for id in pairs(found) do
    assert(expected[id], "unexpected scenario: " .. id)
end

print("SCENARIO REGISTRY TESTS PASSED")
