--!nonstrict
local state = noctalia.state
local ws = require("./WsSecurity.luau")
local xml = require("./OnvifXml.luau")
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
local flight = 0
local previous = nil
local mode, eventsUrl, subscriptionUrl = "discover", "", ""
local renewAt, retryOnvifAt = 0, 0
local haveChanged = false

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
    mode, eventsUrl, subscriptionUrl, renewAt, retryOnvifAt = "discover", "", "", 0, 0
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

local soap = "http://www.w3.org/2003/05/soap-envelope"
local schema = "http://www.onvif.org/ver10/schema"
local events = "http://www.onvif.org/ver10/events/wsdl"
local notification = "http://docs.oasis-open.org/wsn/b-2"
local addressing = "http://www.w3.org/2005/08/addressing"

local function child(node, namespace, name)
    if type(node) ~= "table" then return nil end
    for _, value in ipairs(node.children) do
        if value.namespace == namespace and value.localName == name then return value end
    end
end

local function sameHost(value)
    if type(value) ~= "string" or value:find("[%s%c#@\\]") then return false end
    local function parts(address)
        local scheme, authority = address:match("^(https?)://([^/?]+)")
        if not scheme then return nil end
        local host, port = authority:match("^(%[[%x:%.]+%]):?(%d*)$")
        if not host then host, port = authority:match("^([%w%.%-]+):?(%d*)$") end
        if not host or (port ~= "" and (tonumber(port) < 1 or tonumber(port) > 65535)) then return nil end
        return scheme, host:lower()
    end
    local scheme, host = parts(value)
    local originalScheme, originalHost = parts(url)
    return scheme and originalScheme and host == originalHost
        and (originalScheme ~= "https" or scheme == "https")
end

local function fallback()
    mode, eventsUrl, subscriptionUrl = "fallback", "", ""
    retryOnvifAt, nextPollAt = noctalia.nowMs() + 60000, 0
    status = "doorbellFallback"
    noctalia.log("doorbell: ONVIF unavailable; using polling")
    publish()
end

local function responseBody(body, expected)
    if type(body) ~= "string" or #body > 262144 then return nil end
    local root = xml.parse(body)
    if not root or root.namespace ~= soap or root.localName ~= "Envelope" then return nil end
    return child(child(root, soap, "Body"), events, expected)
end

local function timestamp(text)
    if type(text) ~= "string" then return nil end
    text = noctalia.string.trim(text)
    local y, m, d, h, min, sec, zone = text:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)(.*)$")
    if not y then return nil end
    y, m, d, h, min, sec = tonumber(y), tonumber(m), tonumber(d), tonumber(h), tonumber(min), tonumber(sec)
    local leap = y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0)
    local days = { 31, leap and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if y == 0 or m < 1 or m > 12 or d < 1 or d > days[m] or h > 23 or min > 59 or sec > 59 then return nil end
    local fraction = 0
    if zone:sub(1, 1) == "." then
        local digits, suffix = zone:match("^%.(%d+)(.*)$")
        if not digits then return nil end
        fraction, zone = tonumber("0." .. digits:sub(1, 9)), suffix
    end
    local offset = 0
    if zone ~= "Z" then
        local sign, hours, minutes = zone:match("^([+-])(%d%d):(%d%d)$")
        if not sign then return nil end
        hours, minutes = tonumber(hours), tonumber(minutes)
        if hours > 14 or minutes > 59 or (hours == 14 and minutes ~= 0) then return nil end
        offset = (hours * 60 + minutes) * 60 * (sign == "+" and 1 or -1)
    end
    local ok, result = pcall(os.time, { year = y, month = m, day = d, hour = h, min = min, sec = sec })
    if not ok or type(result) ~= "number" then return nil end
    return result + fraction - offset
end

local function expiry(node)
    local current = child(node, notification, "CurrentTime") or child(node, events, "CurrentTime")
    local termination = child(node, notification, "TerminationTime") or child(node, events, "TerminationTime")
    local now, untilTime = timestamp(current and current.text), timestamp(termination and termination.text)
    if not now or not untilTime or untilTime - now < 10 then return false end
    local nextRenew = noctalia.nowMs() + math.max(1000, math.min(60000, (untilTime - now) * 1000) * 0.7)
    renewAt = renewAt == 0 and nextRenew or math.min(renewAt, nextRenew)
    return true
end

local function eventMessages(node)
    for _, item in ipairs(node.children) do
        if item.namespace == notification and item.localName == "NotificationMessage" then
            local topic = child(item, notification, "Topic")
            local prefix, path
            if topic then prefix, path = noctalia.string.trim(topic.text):match("^([^:]+):(.+)$") end
            local message = child(child(item, notification, "Message"), schema, "Message")
            local data = child(message, schema, "Data")
            if topic and prefix and topic.namespaces[prefix] == "http://www.onvif.org/ver10/topics"
                and path == "RuleEngine/MyRuleDetector/Visitor" and message and data then
                local pressed
                for _, value in ipairs(data.children) do
                    if value.namespace == schema and value.localName == "SimpleItem" and value.attrs.Name == "State" then
                        if value.attrs.Value == "true" or value.attrs.Value == "1" then pressed = true
                        elseif value.attrs.Value == "false" or value.attrs.Value == "0" then pressed = false end
                    end
                end
                if pressed ~= nil then
                    local ring = message.attrs.PropertyOperation == "Changed" and previous ~= true and pressed
                    if message.attrs.PropertyOperation == "Changed" or (message.attrs.PropertyOperation == "Initialized" and not haveChanged) then
                        if message.attrs.PropertyOperation == "Changed" then haveChanged = true end
                        previous = pressed
                        if ring then noctalia.log("doorbell: visitor event detected"); state.set("command", { action = "ring" }) end
                    end
                end
            end
        end
    end
end

local function onvif()
    if not ready or inFlight then return end
    local current = generation
    local action, target, operation, expected
    if mode == "discover" then
        action, target, operation, expected = "GetCapabilities", url .. "/onvif/device_service",
            '<tds:GetCapabilities><tds:Category>Events</tds:Category></tds:GetCapabilities>', "GetCapabilitiesResponse"
    elseif mode == "subscribe" then
        action, target, operation, expected = "CreatePullPointSubscription", eventsUrl,
            '<tev:CreatePullPointSubscription><tev:InitialTerminationTime>PT60S</tev:InitialTerminationTime></tev:CreatePullPointSubscription>', "CreatePullPointSubscriptionResponse"
    elseif mode == "listen" then
        local remaining = math.floor((renewAt - noctalia.nowMs()) / 1000)
        if remaining <= 5 then
            action, target, operation, expected = "Renew", subscriptionUrl,
                '<wsnt:Renew><wsnt:TerminationTime>PT60S</wsnt:TerminationTime></wsnt:Renew>', "RenewResponse"
        else
            action, target, operation, expected = "PullMessages", subscriptionUrl,
                '<tev:PullMessages><tev:Timeout>PT' .. tostring(math.min(20, remaining - 5)) .. 'S</tev:Timeout><tev:MessageLimit>32</tev:MessageLimit></tev:PullMessages>', "PullMessagesResponse"
        end
    else return end
    if not sameHost(target) then fallback(); return end
    inFlight = true
    flight = flight + 1
    local ownFlight = flight
    local raw = noctalia.readFile("/proc/sys/kernel/random/uuid")
    local nonce = type(raw) == "string" and noctalia.string.trim(raw) or ""
    if not nonce:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") then
        noctalia.log("doorbell: ONVIF nonce unavailable (type " .. type(raw) .. ", length " .. tostring(#nonce) .. ")")
        inFlight = false; fallback(); return
    end
    local security = ws.usernameToken(username, password, nonce, os.date("!%Y-%m-%dT%H:%M:%SZ"))
    if not security then noctalia.log("doorbell: ONVIF authentication preparation failed"); inFlight = false; fallback(); return end
    local actionUri = action == "GetCapabilities" and "http://www.onvif.org/ver10/device/wsdl/GetCapabilities"
        or action == "CreatePullPointSubscription" and events .. "/EventPortType/CreatePullPointSubscriptionRequest"
        or action == "PullMessages" and events .. "/PullPointSubscription/PullMessagesRequest"
        or "http://docs.oasis-open.org/wsn/bw-2/SubscriptionManager/RenewRequest"
    local safeTarget = target:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
    local body = '<s:Envelope xmlns:s="' .. soap .. '" xmlns:tds="http://www.onvif.org/ver10/device/wsdl" xmlns:tev="' .. events
        .. '" xmlns:wsnt="' .. notification .. '" xmlns:wsa="' .. addressing
        .. '" xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd"'
        .. ' xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">'
        .. '<s:Header><wsa:Action>' .. actionUri .. '</wsa:Action><wsa:To>' .. safeTarget .. '</wsa:To>'
        .. security .. '</s:Header><s:Body>' .. operation .. '</s:Body></s:Envelope>'
    local started = noctalia.http({ url = target, method = "POST", headers = { "Content-Type: application/soap+xml; charset=utf-8" },
        body = body, follow_redirects = false }, function(response)
        if ownFlight ~= flight then return end
        inFlight = false
        if not alive or current ~= generation then return end
        if not response.ok or response.status < 200 or response.status >= 300 then
            noctalia.log("doorbell: ONVIF " .. action .. " failed (HTTP " .. tostring(response.status) .. ")")
            fallback(); return
        end
        local root
        if action == "GetCapabilities" then
            local envelope = xml.parse(response.body)
            local bodyNode = envelope and envelope.namespace == soap and child(envelope, soap, "Body")
            root = child(bodyNode, "http://www.onvif.org/ver10/device/wsdl", expected)
            local caps = child(root, "http://www.onvif.org/ver10/device/wsdl", "Capabilities")
            local event = child(caps, schema, "Events")
            local address = child(event, schema, "XAddr")
            local endpoint = address and noctalia.string.trim(address.text)
            if not endpoint or not sameHost(endpoint) then noctalia.log("doorbell: ONVIF discovery response invalid"); fallback(); return end
            eventsUrl, mode = endpoint, "subscribe"
        elseif action == "CreatePullPointSubscription" then
            root = responseBody(response.body, expected)
            local ref = child(root, events, "SubscriptionReference")
            local address = child(ref, addressing, "Address")
            local endpoint = address and noctalia.string.trim(address.text)
            if not endpoint or not sameHost(endpoint) or not expiry(root) then noctalia.log("doorbell: ONVIF subscription response invalid"); fallback(); return end
            subscriptionUrl, mode, haveChanged = endpoint, "listen", false
            status = "doorbellListening"; noctalia.log("doorbell: ONVIF event subscription active"); publish()
        elseif action == "PullMessages" then
            root = responseBody(response.body, expected)
            if not root or not expiry(root) then noctalia.log("doorbell: ONVIF event response invalid"); fallback(); return end
            eventMessages(root)
            status = "doorbellListening"; publish()
        else
            local envelope = xml.parse(response.body)
            local bodyNode = envelope and envelope.namespace == soap and child(envelope, soap, "Body")
            root = child(bodyNode, notification, expected)
            renewAt = 0
            if not root or not expiry(root) then noctalia.log("doorbell: ONVIF renewal response invalid"); fallback(); return end
        end
        onvif()
    end)
    if not started then noctalia.log("doorbell: ONVIF HTTP request not started"); inFlight = false; fallback() end
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
    flight = flight + 1
    local ownFlight = flight
    local accepted = noctalia.http({
        url = url .. "/cgi-bin/api.cgi?cmd=" .. cmd .. "&token=" .. (login and "null" or noctalia.string.urlEncode(token)),
        method = "POST", headers = { "Content-Type: application/json" }, body = body,
        follow_redirects = false,
    }, function(response)
        if ownFlight ~= flight then return end
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
        status = "doorbellFallback"
        nextPollAt = noctalia.nowMs() + 2000
        publish()
        if ring then noctalia.log("doorbell: visitor event detected by polling"); state.set("command", { action = "ring" }) end
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
    if mode == "fallback" and noctalia.nowMs() >= retryOnvifAt and not inFlight then
        mode = "discover"
        ready = username ~= "" and password ~= ""
    end
    if mode == "fallback" then poll() else onvif() end
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
