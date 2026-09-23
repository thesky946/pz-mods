-- Run from tests/. Each file resets the PZ doubles it needs.
local tests = {
    "test_action_simulator.lua",
    "test_simulated_scenarios.lua",
    "test_scenario_registry.lua",
    "test_forecast.lua",
    "test_foodlogic.lua",
    "test_cook.lua",
    "test_lifecycle.lua",
    "test_session.lua",
    "test_catalog.lua",
    "test_speed.lua",
    "test_notification.lua",
    "test_reliability.lua",
    "test_scanner.lua",
    "test_multiplayer.lua",
    "test_ui.lua",
}
for _, file in ipairs(tests) do
    io.write(file .. ": ")
    dofile(file)
end
print("ALL SUITES PASSED")
