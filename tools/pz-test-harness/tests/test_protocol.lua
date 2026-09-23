package.path = "../PzModsTestHarness/42/media/lua/shared/?.lua;../PzModsTestHarness/42/media/lua/client/?.lua;" .. package.path

local Protocol = require "PzTestHarness_Protocol"

local scenario = "cook.transfer.container.success"
local run001 = "00000000000000000000000000000001"
local run002 = "00000000000000000000000000000002"
local run003 = "00000000000000000000000000000003"
local run004 = "00000000000000000000000000000004"

local request, requestError = Protocol.parseRequest(run001 .. "\t" .. scenario .. "\n")
assert(request and not requestError, "allowlisted request must parse")
assert(request.runId == run001 and request.scenario == scenario, "parsed request fields")

for _, malformed in ipairs({
    "",
    run001 .. "\tunknown.scenario\n",
    "../" .. run001 .. "\t" .. scenario .. "\n",
    "ABCDEFABCDEFABCDEFABCDEFABCDEF12\t" .. scenario .. "\n",
    run001 .. "\t" .. scenario .. "\textra\n",
}) do
    local parsed = Protocol.parseRequest(malformed)
    assert(parsed == nil, "malformed or unknown request must be rejected: " .. malformed)
end

local accepted = {}
local first, firstError = Protocol.acceptRequest(run002 .. "\t" .. scenario .. "\n", accepted)
assert(first and not firstError, "first run ID must be accepted")
local duplicate, duplicateError = Protocol.acceptRequest(run002 .. "\t" .. scenario .. "\n", accepted)
assert(duplicate == nil and duplicateError == "duplicate-run-id", "duplicate run ID must not dispatch twice")

local consumedRequest, claimMarker = Protocol.claimRequest(run003 .. "\t" .. scenario .. "\n", nil, nil)
assert(consumedRequest and consumedRequest.runId == run003, "pending request must be claimable")
assert(claimMarker == Protocol.claimMarkerText(run003), "claim marker must be persisted before dispatch")
local replayed, replayError = Protocol.claimRequest(run003 .. "\t" .. scenario .. "\n", claimMarker, nil)
assert(replayed == nil and replayError == "duplicate-run-id", "persistent dedupe must survive a client restart")
assert(Protocol.claimRequest(run003 .. "\t" .. scenario .. "\n", "partial", nil) == nil, "partial claim marker must block replay after a crash")
assert(Protocol.parseRequest(Protocol.revokedRequestText(run003)) == nil, "revoked request must never dispatch")

local previousHarness = PzTestHarness
local previousEvents = Events
local previousReader = getFileReader
local previousWriter = getFileWriter
local allowedFileExtensions = { ini = true, cfg = true, txt = true, log = true, json = true }
local writtenPaths = {}
local function assertAllowedGameFilePath(path)
    local extension = path:match("%.([^%.]+)$")
    assert(extension and allowedFileExtensions[extension], "PZ file API does not allow this extension: " .. path)
end
local requestPath = "pzmodtests/request.txt"
local resultPath = "pzmodtests/result.txt"
local claimPath = "pzmodtests/state/" .. run004 .. ".claimed.txt"
local grantPath = "pzmodtests/state/" .. run004 .. ".granted.txt"
local cancelPath = "pzmodtests/state/" .. run004 .. ".cancelled.txt"
local startedPath = "pzmodtests/state/" .. run004 .. ".started.txt"
for _, path in ipairs({ requestPath, resultPath, claimPath, grantPath, cancelPath, startedPath }) do
    assertAllowedGameFilePath(path)
end
local mailbox = {
    [requestPath] = run004 .. "\t" .. scenario .. "\n",
    [cancelPath] = "cancelled\n",
}
local ticks = {}
PzTestHarness = { scenarios = { [scenario] = function() error("cancelled request must not run") end } }
Events = {
    OnTick = { Add = function(callback) ticks.tick = callback end },
    OnRenderTick = { Add = function(callback) ticks.render = callback end },
}
getFileReader = function(path)
    local text = mailbox[path]
    if not text then return nil end
    local index = 1
    return {
        readLine = function()
            local newline = text:find("\n", index, true)
            if not newline then return nil end
            local line = text:sub(index, newline - 1)
            index = newline + 1
            return line
        end,
        close = function() end,
    }
end
getFileWriter = function(path)
    local extension = path:match("%.([^%.]+)$")
    if not (extension and allowedFileExtensions[extension]) then return nil end
    writtenPaths[#writtenPaths + 1] = path
    local chunks = {}
    return {
        write = function(_, value) chunks[#chunks + 1] = value end,
        close = function() mailbox[path] = table.concat(chunks) end,
    }
end
dofile("../PzModsTestHarness/42/media/lua/client/PzTestHarness_Client.lua")
for _, scenarioId in ipairs({
    "cook.transfer.container.success",
    "cook.recipe.replacement.success",
    "cook.stove.ownership.success",
    "cook.stove.preexisting.success",
}) do
    assert(type(PzTestHarness.scenarios[scenarioId]) == "function", "Cook adapter must be registered: " .. scenarioId)
end
for _ = 1, 15 do ticks.tick() end
assert(mailbox[claimPath] ~= nil, "client must persist a per-run claim")

PzTestHarness = { scenarios = { [scenario] = function() error("restart must not replay consumed run") end } }
mailbox[requestPath] = run004 .. "\t" .. scenario .. "\n"
dofile("../PzModsTestHarness/42/media/lua/client/PzTestHarness_Client.lua")
for _ = 1, 15 do ticks.tick() end
assert(mailbox[requestPath] == run004 .. "\t" .. scenario .. "\n", "client must continue reading the .txt request after restart")

local dispatches = 0
mailbox[cancelPath] = nil
mailbox[claimPath] = "partial"
mailbox[grantPath] = Protocol.grantMarkerText(run004)
PzTestHarness = { scenarios = { [scenario] = function() dispatches = dispatches + 1 end } }
dofile("../PzModsTestHarness/42/media/lua/client/PzTestHarness_Client.lua")
for _ = 1, 15 do ticks.tick() end
assert(dispatches == 0, "partial claim marker must block a crash-restarted client from dispatching")

mailbox[claimPath] = Protocol.claimMarkerText(run004)
PzTestHarness = { scenarios = { [scenario] = function(_, finish)
    dispatches = dispatches + 1
    finish({ status = "pass" })
end } }
dofile("../PzModsTestHarness/42/media/lua/client/PzTestHarness_Client.lua")
for _ = 1, 15 do ticks.tick() end
assert(dispatches == 1, "exact grant must dispatch exactly once")
assert(mailbox[startedPath] == Protocol.consumedMarkerText(run004), "started marker must precede dispatch")
assert(mailbox[resultPath] ~= nil, "client must write the matching result to the .txt mailbox")

PzTestHarness = { scenarios = { [scenario] = function() error("started run must not replay") end } }
dofile("../PzModsTestHarness/42/media/lua/client/PzTestHarness_Client.lua")
for _ = 1, 15 do ticks.tick() end
assert(dispatches == 1, "started marker must survive a crash/restart without a second dispatch")
local writtenPathSet = {}
for _, path in ipairs(writtenPaths) do
    assertAllowedGameFilePath(path)
    writtenPathSet[path] = true
end
assert(writtenPathSet[claimPath], "client must persist the claim using an allowed extension")
assert(writtenPathSet[startedPath], "client must persist the started marker using an allowed extension")
assert(writtenPathSet[resultPath], "client must persist results using an allowed extension")
PzTestHarness = previousHarness
Events = previousEvents
getFileReader = previousReader
getFileWriter = previousWriter

local matchingResult = Protocol.acceptResult({ runId = run001 }, run001)
assert(matchingResult, "matching result ID must be accepted")
local staleResult, staleError = Protocol.acceptResult({ runId = run002 }, run001)
assert(staleResult == nil and staleError == "stale-result", "stale result ID must be rejected")

local encoded = Protocol.encodeResult(Protocol.buildResult(run001, scenario, {
    status = "pass",
    observed = { quote = "say \"hello\"", control = "line1\nline2\\tail" },
    failures = {},
    cleanup = { status = "pass", failures = {} },
}))
assert(encoded:find('"runId":"' .. run001 .. '"', 1, true), "result must include run ID")
assert(encoded:find('say \\\"hello\\\"', 1, true), "quotes must be JSON escaped")
assert(encoded:find('line1\\nline2\\\\tail', 1, true), "controls and backslashes must be JSON escaped")
assert(not encoded:find("\n", 1, true), "result must remain one JSON line")

local emptyObserved = Protocol.encodeResult(Protocol.buildResult(run002, scenario, { status = "pass" }))
assert(emptyObserved:find('"observed":{}', 1, true), "observed must remain a JSON object when empty")
assert(emptyObserved:find('"gameBuild":null', 1, true), "result must include an explicit null gameBuild field")

local normalized = Protocol.buildResult(run003, scenario, {
    status = "fail",
    failures = { "original failure" },
    cleanup = { status = "fail", failures = { "cleanup failure" } },
})
assert(normalized.status == "fail", "cleanup failure must not become a pass")
assert(normalized.failures[1] == "original failure", "original failure must be preserved")
assert(normalized.cleanup.status == "fail", "cleanup failure must remain separate")
assert(normalized.cleanup.failures[1] == "cleanup failure", "cleanup failure detail must be preserved")
assert(not pcall(Protocol.buildResult, "ABCDEFABCDEFABCDEFABCDEFABCDEF12", scenario, {}), "result run IDs must reject uppercase values")
assert(not pcall(Protocol.buildResult, "../" .. run004, scenario, {}), "result run IDs must reject traversal")

local completions = 0
local finish = Protocol.once(function() completions = completions + 1 end)
assert(finish() == true, "first completion must execute")
assert(finish() == false, "second completion must be rejected")
assert(completions == 1, "scenario completion must be at most once")

print("PZ TEST HARNESS PROTOCOL TESTS PASSED")
