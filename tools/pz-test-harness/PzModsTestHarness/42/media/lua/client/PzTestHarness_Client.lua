PzTestHarness = PzTestHarness or {}
PzTestHarness.scenarios = PzTestHarness.scenarios or {}
PzTestHarness.seenRunIds = PzTestHarness.seenRunIds or {}
PzTestHarness.ticks = PzTestHarness.ticks or 0

local Protocol = require "PzTestHarness_Protocol"
require("scenarios/CookTransfer").register(PzTestHarness.scenarios)
require("scenarios/CookRecipe").register(PzTestHarness.scenarios)
require("scenarios/CookStove").register(PzTestHarness.scenarios)
local REQUEST = "pzmodtests/request.txt"
local RESULT = "pzmodtests/result.txt"
local CHECK_EVERY_TICKS = 15

local function readText(path)
    if not getFileReader then return nil end
    local reader = getFileReader(path, false)
    if not reader then return nil end
    local lines = {}
    local line = reader:readLine()
    while line do
        lines[#lines + 1] = line
        line = reader:readLine()
    end
    reader:close()
    if #lines == 0 then return "" end
    return table.concat(lines, "\n") .. "\n"
end

local function writeText(path, text)
    if not getFileWriter then return end
    local writer = getFileWriter(path, true, false)
    if not writer then return false end
    writer:write(text)
    writer:close()
    return true
end

local function writeResult(result)
    writeText(RESULT, Protocol.encodeResult(result))
end

local function statePath(runId, suffix) return "pzmodtests/state/" .. runId .. suffix end

local function dispatch(request)
    local runner = PzTestHarness.scenarios[request.scenario]
    if type(runner) ~= "function" then
        writeResult(Protocol.buildResult(request.runId, request.scenario, {
            status = "not-run",
            failures = { "scenario is not registered" },
        }))
        return
    end

    local context = {
        runId = request.runId,
        scenario = request.scenario,
        cleanup = {},
        createdItemIds = {},
        startTime = getTimestamp and getTimestamp() or nil,
        player = getSpecificPlayer and getSpecificPlayer(0) or nil,
    }
    local finish = Protocol.once(function(raw)
        writeResult(Protocol.buildResult(request.runId, request.scenario, raw))
    end)
    local ok, err = pcall(runner, context, finish)
    if not ok then
        finish({ status = "fail", failures = { tostring(err) } })
    end
end

local function poll()
    PzTestHarness.ticks = PzTestHarness.ticks + 1
    if PzTestHarness.ticks % CHECK_EVERY_TICKS ~= 0 then return end

    local text = readText(REQUEST)
    if not text then return end
    local request = Protocol.parseRequest(text)
    if not request then return end
    local claimPath = statePath(request.runId, ".claimed.txt")
    local grantPath = statePath(request.runId, ".granted.txt")
    local cancelPath = statePath(request.runId, ".cancelled.txt")
    local startedPath = statePath(request.runId, ".started.txt")
    local claim = readText(claimPath)
    local started = readText(startedPath)
    if started ~= nil then return end
    if claim == nil then
        if not writeText(claimPath, Protocol.claimMarkerText(request.runId)) then return end
        return
    end
    if not Protocol.canDispatch(request.runId, claim, readText(grantPath), readText(cancelPath), started) then return end
    if not writeText(startedPath, Protocol.consumedMarkerText(request.runId)) then return end
    PzTestHarness.seenRunIds[request.runId] = true
    PzTestHarness.lastRunId = request.runId
    dispatch(request)
end

Events.OnTick.Add(poll)
Events.OnRenderTick.Add(poll)
