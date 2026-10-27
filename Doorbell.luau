--!nonstrict
local state = noctalia.state
local dataDir = noctalia.pluginDataDir()
local savedPath = dataDir and (dataDir .. "/doorbell.json")
local savedText = savedPath and noctalia.readFile(savedPath)
local saved = savedText and noctalia.json.decode(savedText)
local url = type(saved) == "table" and type(saved.url) == "string" and saved.url or ""
local status = "doorbellDisabled"
local draft, applyAt = nil, nil
local username, password, token = "", "", ""
local expiresAt, nextPollAt, failures, generation = 0, 0, 0, 0
local ready, inFlight, alive = false, false, true
local previous = nil

local function normalizeUrl(value)
    value = noctalia.string.trim(value)
    if value == "" then return "" end
    if not value:find("://", 1, true) then value = "https://" .. value end
    if value:find("[%s%c%?%#@\\]") or not value:match("^https?://[^/]+/*$") then return nil end
    return value:gsub("/+$", "")
end

local function publish()
    state.set("doorbell", { url = url, status = status })
end

local function fail(reason)
    failures = math.min(failures + 1, 4)
    nextPollAt = noctalia.nowMs() + math.min(30000, 5000 * 2 ^ (failures - 1))
    status = reason
    publish()
end

local function loadCredentials()
    generation = generation + 1
    local current = generation
    ready, failures, nextPollAt = false, 0, 0
    if url == "" then status = "doorbellDisabled"; publish(); return end
    status = "doorbellConnecting"
    publish()
    if not noctalia.commandExists("secret-tool") then status = "keyringFailed"; publish(); return end
    local remaining, failed = 2, false
    local loaded = {}
    for _, key in ipairs({ "username", "password" }) do
        local function done(result)
            if not alive or current ~= generation then return end
            if result.exitCode == 0 and type(result.stdout) == "string" and not result.stdoutTruncated and not result.timedOut then
                loaded[key] = result.stdout:gsub("\n$", "")
            elseif result.exitCode ~= 1 or result.timedOut or result.stdoutTruncated then
                failed = true
            end
            remaining = remaining - 1
            if remaining == 0 then
                if not failed then
                    -- Reolink limits active sessions; a retry with unchanged credentials reuses its token.
                    local nextUsername, nextPassword = loaded.username or "", loaded.password or ""
                    if username ~= nextUsername or password ~= nextPassword then token = "" end
                    username, password = nextUsername, nextPassword
                end
                ready = not failed and username ~= "" and password ~= ""
                status = failed and "keyringFailed" or (ready and "doorbellConnecting" or "doorbellCredentialsMissing")
                publish()
            end
        end
        if not noctalia.runAsync({ "secret-tool", "lookup", "service", "noctalia-frigate-doorbell", "key", key }, done, 5000) then
            done({ exitCode = -1 })
        end
    end
end

local function poll()
    if not ready or inFlight or noctalia.nowMs() < nextPollAt then return end
    local current = generation
    local login = token == "" or noctalia.nowMs() >= expiresAt
    local cmd = login and "Login" or "GetEvents"
    local param = login and { User = { userName = username, password = password } } or { channel = 0 }
    local body = noctalia.json.encode({ { cmd = cmd, action = 0, param = param } })
    if not body then ready = false; status = "doorbellInvalidResponse"; publish(); return end
    inFlight = true
    local accepted = noctalia.http({
        url = url .. "/cgi-bin/api.cgi?cmd=" .. cmd .. "&token=" .. (login and "null" or noctalia.string.urlEncode(token)),
        method = "POST", headers = { "Content-Type: application/json" }, body = body,
        follow_redirects = false,
    }, function(response)
        inFlight = false
        if not alive or current ~= generation then return end
        if response.status == 401 or response.status == 403 then
            token = ""
            if login then ready = false; status = "doorbellAuthFailed"; publish()
            else fail("doorbellUnavailable") end
            return
        end
        if not response.ok or response.status < 200 or response.status >= 300 then fail("doorbellUnavailable"); return end
        local decoded = noctalia.json.decode(response.body)
        local result = type(decoded) == "table" and decoded[1]
        if type(result) ~= "table" or result.cmd ~= cmd or type(result.code) ~= "number" then
            fail("doorbellInvalidResponse"); return
        end
        if result.code ~= 0 then
            local err = type(result.error) == "table" and result.error.rspCode
            if login then ready = false; status = "doorbellAuthFailed"; publish()
            elseif err == -6 then token = ""; fail("doorbellUnavailable")
            else ready = false; status = "doorbellUnsupported"; publish() end
            return
        end
        local value = result.value
        if login then
            local session = type(value) == "table" and value.Token
            local lease = type(session) == "table" and tonumber(session.leaseTime)
            if not lease or lease ~= lease or lease <= 0 or type(session.name) ~= "string" or session.name == "" then
                fail("doorbellInvalidResponse"); return
            end
            token = session.name
            expiresAt = noctalia.nowMs() + math.max(1, math.min(lease, 86400) - 30) * 1000
            nextPollAt = noctalia.nowMs()
            return
        end
        local visitor = type(value) == "table" and value.visitor
        if type(visitor) ~= "table" or value.channel ~= 0 or (visitor.alarm_state ~= 0 and visitor.alarm_state ~= 1) then
            fail("doorbellInvalidResponse"); return
        end
        if visitor.support ~= 1 then ready = false; status = "doorbellUnsupported"; publish(); return end
        local pressed = visitor.alarm_state == 1
        -- shortcut: rapid presses share one visitor alarm; use push events if each press must be distinct.
        -- Seed startup state; a held visitor alarm must not reopen after reload.
        local ring = previous == false and pressed
        previous = pressed
        failures = 0
        status = "doorbellListening"
        nextPollAt = noctalia.nowMs() + 2000
        publish()
        if ring then state.set("command", { action = "ring" }) end
    end)
    if not accepted then inFlight = false; fail("doorbellUnavailable") end
end

local function applyUrl()
    applyAt = nil
    local normalized = normalizeUrl(draft)
    draft = nil
    if normalized == url and normalized ~= "" then return end
    generation = generation + 1
    ready = false
    previous = nil
    username, password, token = "", "", ""
    url = normalized or ""
    noctalia.setUpdateInterval(url ~= "" and 1000 or 30000)
    if not normalized then status = "invalidUrl"; publish(); return end
    local text = noctalia.json.encode({ url = url })
    local temp = savedPath and (savedPath .. ".tmp")
    if not temp or not text or not noctalia.writeFile(temp, text) or not noctalia.renameFile(temp, savedPath) then
        if temp then noctalia.removeFile(temp) end
        noctalia.notifyError(noctalia.tr("title"), noctalia.tr("saveFailed"))
    end
    loadCredentials()
end

function update()
    if not alive then return end
    if applyAt and noctalia.nowMs() >= applyAt then applyUrl() end
    poll()
end

state.watch("doorbellCommand", function(command)
    if type(command) ~= "table" then return end
    state.set("doorbellCommand", nil)
    if command.action == "url" and type(command.value) == "string" then
        draft = command.value
        applyAt = noctalia.nowMs() + 800
        noctalia.setUpdateInterval(1000)
    elseif command.action == "retry" then
        loadCredentials()
    end
end)

function onIpc(event)
    if event == "refresh" then loadCredentials() end
end

function onExit()
    alive = false
    generation = generation + 1
    ready = false
    username, password, token = "", "", ""
end

local normalized = normalizeUrl(url)
url = normalized or ""
noctalia.setUpdateInterval(url ~= "" and 1000 or 30000)
if normalized then loadCredentials() else status = "invalidUrl"; publish() end
