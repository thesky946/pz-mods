local Protocol = {
    schema = 1,
    allowedScenarios = {
        ["cook.transfer.container.success"] = true,
        ["cook.recipe.replacement.success"] = true,
        ["cook.stove.ownership.success"] = true,
        ["cook.stove.preexisting.success"] = true,
    },
}

local allowedStatuses = {
    pass = true,
    fail = true,
    ["not-run"] = true,
    ["not-applicable"] = true,
}

local function copyFailures(value)
    local copied = {}
    if type(value) ~= "table" then return copied end
    for _, failure in ipairs(value) do
        copied[#copied + 1] = tostring(failure)
    end
    return copied
end

local function normalizeCleanup(value)
    value = type(value) == "table" and value or {}
    local status = value.status
    if not allowedStatuses[status] then status = "not-applicable" end
    return {
        status = status,
        failures = copyFailures(value.failures),
    }
end

function Protocol.parseRequest(text)
    if type(text) ~= "string" then return nil, "malformed-request" end
    local runId, scenario = text:match("^([0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f])\t([a-z][a-z0-9_.-]+)\n?$")
    if not runId then return nil, "malformed-request" end
    if not Protocol.allowedScenarios[scenario] then return nil, "unknown-scenario" end
    return { runId = runId, scenario = scenario }
end

function Protocol.acceptRequest(text, seenRunIds)
    local request, err = Protocol.parseRequest(text)
    if not request then return nil, err end
    seenRunIds = seenRunIds or {}
    if seenRunIds[request.runId] then return nil, "duplicate-run-id" end
    seenRunIds[request.runId] = true
    return request
end

function Protocol.consumedRequestText(runId)
    assert(type(runId) == "string" and runId:match("^[0-9a-f]+$") == runId and #runId == 32, "invalid run ID")
    return runId .. "\t__consumed__\n"
end

function Protocol.revokedRequestText(runId)
    assert(type(runId) == "string" and runId:match("^[0-9a-f]+$") == runId and #runId == 32, "invalid run ID")
    return runId .. "\t__revoked__\n"
end

function Protocol.claimMarkerText(runId) return "claimed:" .. runId .. "\n" end
function Protocol.grantMarkerText(runId) return "granted:" .. runId .. "\n" end
function Protocol.consumedMarkerText(runId) return "started:" .. runId .. "\n" end

function Protocol.claimRequest(text, claimMarker, consumedMarker)
    local request, err = Protocol.parseRequest(text)
    if not request then return nil, err end
    if claimMarker ~= nil or consumedMarker ~= nil then return nil, "duplicate-run-id" end
    return request, Protocol.claimMarkerText(request.runId)
end

function Protocol.canDispatch(runId, claim, grant, cancelled, started)
    if claim ~= Protocol.claimMarkerText(runId) then return false end
    if started ~= nil or cancelled ~= nil then return false end
    return grant == Protocol.grantMarkerText(runId)
end

function Protocol.acceptResult(result, expectedRunId)
    if type(result) ~= "table" or type(result.runId) ~= "string" then
        return nil, "malformed-result"
    end
    if result.runId ~= expectedRunId then return nil, "stale-result" end
    return result
end

function Protocol.buildResult(runId, scenario, raw)
    assert(type(runId) == "string" and runId:match("^[0-9a-f]+$") == runId and #runId == 32, "invalid run ID")
    assert(Protocol.allowedScenarios[scenario], "unknown scenario")
    raw = type(raw) == "table" and raw or {}

    local status = raw.status
    local failures = copyFailures(raw.failures)
    if not allowedStatuses[status] then
        status = "fail"
        failures[#failures + 1] = "invalid scenario status"
    end

    local cleanup = normalizeCleanup(raw.cleanup)
    if cleanup.status == "fail" then status = "fail" end

    return {
        schema = Protocol.schema,
        runId = runId,
        scenario = scenario,
        status = status,
        gameBuild = raw.gameBuild,
        observed = type(raw.observed) == "table" and raw.observed or {},
        failures = failures,
        cleanup = cleanup,
    }
end

local function encodeString(value)
    return '"' .. value:gsub('[\\"%z\1-\31]', function(character)
        local escapes = { ["\\"] = "\\\\", ['"'] = '\\"', ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
        return escapes[character] or string.format("\\u%04x", string.byte(character))
    end) .. '"'
end

local function isArray(value)
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then return false end
        count = count + 1
    end
    return count == #value
end

local function encode(value, forceObject)
    local valueType = type(value)
    if value == nil then return "null" end
    if valueType == "boolean" then return value and "true" or "false" end
    if valueType == "number" then
        assert(value == value and value ~= math.huge and value ~= -math.huge, "invalid JSON number")
        return tostring(value)
    end
    if valueType == "string" then return encodeString(value) end
    assert(valueType == "table", "unsupported JSON value")

    if not forceObject and isArray(value) then
        local values = {}
        for index = 1, #value do values[index] = encode(value[index]) end
        return "[" .. table.concat(values, ",") .. "]"
    end

    local keys = {}
    for key in pairs(value) do
        assert(type(key) == "string", "JSON object keys must be strings")
        keys[#keys + 1] = key
    end
    table.sort(keys)
    local values = {}
    for _, key in ipairs(keys) do
        values[#values + 1] = encodeString(key) .. ":" .. encode(value[key])
    end
    return "{" .. table.concat(values, ",") .. "}"
end

function Protocol.encodeResult(result)
    assert(type(result) == "table", "result must be a table")
    local keys = { "cleanup", "failures", "gameBuild", "observed", "runId", "scenario", "schema", "status" }
    local values = {}
    for _, key in ipairs(keys) do
        values[#values + 1] = encodeString(key) .. ":" .. encode(result[key], key == "observed")
    end
    return "{" .. table.concat(values, ",") .. "}"
end

function Protocol.once(callback)
    local completed = false
    return function(...)
        if completed then return false end
        completed = true
        callback(...)
        return true
    end
end

return Protocol
