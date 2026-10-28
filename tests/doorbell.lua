-- Run from the repository root: lua tests/doorbell.lua
local function boot(url, onvif)
    local h = { time = 1000, requests = {}, commands = {}, shared = {}, watchers = {}, files = {}, rings = 0 }
    local json = {}
    local function encode(value)
        local key = "json:" .. tostring(#json + 1)
        json[#json + 1] = value
        json[key] = value
        return key
    end
    local function decode(value) return type(value) == "table" and value or json[value] end
    if url then h.files["/data/doorbell.json"] = { url = url } end
    local function set(key, value)
        h.shared[key] = value
        if key == "command" and value and value.action == "ring" then h.rings = h.rings + 1 end
        if h.watchers[key] then h.watchers[key](value) end
    end
    local api = {
        pluginDataDir = function() return "/data" end,
        nowMs = function() return h.time end,
        readFile = function(path)
            if path == "/proc/sys/kernel/random/uuid" then
                h.nonceReads = (h.nonceReads or 0) + 1
                if h.badNonce then return nil end
                return "12345678-1234-4234-8234-123456789abc\n"
            end
            return h.files[path]
        end,
        readFileAsync = function(_, cb) h.asyncReads = (h.asyncReads or 0) + 1; cb("12345678-1234-4234-8234-123456789abc\n", nil); return true end,
        writeFile = function(path, value) h.files[path] = value; return not h.writeFail end,
        renameFile = function(from, to) h.files[to] = h.files[from]; h.files[from] = nil; return true end,
        removeFile = function(path) h.files[path] = nil end,
        commandExists = function() return not h.noKeyring end,
        runAsync = function(argv, cb) h.commands[#h.commands + 1] = { argv = argv, cb = cb }; return not h.rejectLookup end,
        http = function(request, cb)
            if h.rejectHttp then return false end
            h.requests[#h.requests + 1] = { request = request, cb = cb }
            return true
        end,
        setUpdateInterval = function(ms) h.interval = ms end,
        notifyError = function(_, body) h.notification = body end,
        log = function(message) h.logs = h.logs or {}; h.logs[#h.logs + 1] = message end,
        tr = function(key) return key end,
        json = { encode = encode, decode = decode },
        string = {
            trim = function(s) return s:match("^%s*(.-)%s*$") end,
            urlEncode = function(s) return (s:gsub("([^%w%-_%.~])", function(c) return string.format("%%%02X", c:byte()) end)) end,
        },
        state = { get = function(key) return h.shared[key] end, set = set,
            watch = function(key, cb) h.watchers[key] = cb end },
    }
    h.api = api
    h.env = setmetatable({ noctalia = api, os = setmetatable({ time = function(value)
        if h.badClock then return nil end
        return os.time(value)
    end }, { __index = os }), require = function(path)
        if path == "./WsSecurity.luau" then return { usernameToken = function() return "<wsse:Security>PasswordDigest</wsse:Security>" end } end
        return assert(loadfile(path))()
    end }, { __index = _G })
    assert(loadfile(os.getenv("DOORBELL_TEST_FILE") or "Doorbell.luau", "t", h.env))()
    function h:command(action, value) set("doorbellCommand", { action = action, value = value }) end
    function h:tick(ms) self.time = self.time + (ms or 2000); self.env.update() end
    function h:credentials()
        local n = #self.commands
        assert(n >= 2)
        self.commands[n - 1].cb({ exitCode = 0, stdout = "bell-user\n" })
        self.commands[n].cb({ exitCode = 0, stdout = 'bell-secret $() "\n' })
        self:tick(0)
        if not onvif and self.requests[#self.requests] and self.requests[#self.requests].request.url:find("/onvif/device_service", 1, true) then
            local request = table.remove(self.requests)
            request.cb({ body = "unavailable", status = 404, ok = true })
            self:tick(0)
        end
    end
    function h:reply(value, status, ok, i)
        self.requests[i or #self.requests].cb({ body = value, status = status or 200, ok = ok ~= false })
    end
    function h:login()
        self:reply({ { cmd = "Login", code = 0, value = { Token = { name = "test token", leaseTime = 3600 } } } })
        self:tick(1000)
    end
    function h:event(active)
        self:reply({ { cmd = "GetEvents", code = 0, value = {
            channel = 0, md = { support = 1, alarm_state = 1 },
            ai = { people = { support = 1, alarm_state = 1 } },
            visitor = { support = 1, alarm_state = active },
        } } })
    end
    return h
end

local count = 0
local function test(name, fn) fn(); count = count + 1; print("ok " .. count .. " - " .. name) end
local function connected()
    local h = boot("http://doorbell.example.com")
    h:credentials()
    h:login()
    return h
end

test("ONVIF discovery begins with authenticated native SOAP", function()
    local h = boot("http://doorbell.example.com", true)
    h:credentials()
    local r = h.requests[1].request
    assert(r.url == "http://doorbell.example.com/onvif/device_service")
    assert(r.method == "POST" and r.body:find("GetCapabilities", 1, true))
    assert(r.body:find("PasswordDigest", 1, true) and not r.body:find("bell%-secret"))
    assert(h.nonceReads == 1 and not h.asyncReads, "kernel UUID uses bounded synchronous reading")
end)

test("ONVIF falls back if the secure nonce cannot be read", function()
    local h = boot("http://doorbell.example.com", true)
    h.badNonce = true
    h:credentials()
    assert(#h.requests == 0 and h.shared.doorbell.status == "doorbellFallback")
end)

local function envelope(body)
    return '<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" '
        .. 'xmlns:tds="http://www.onvif.org/ver10/device/wsdl" '
        .. 'xmlns:tev="http://www.onvif.org/ver10/events/wsdl" '
        .. 'xmlns:tt="http://www.onvif.org/ver10/schema" '
        .. 'xmlns:wsa="http://www.w3.org/2005/08/addressing" '
        .. 'xmlns:wsnt="http://docs.oasis-open.org/wsn/b-2" '
        .. 'xmlns:tns1="http://www.onvif.org/ver10/topics"><s:Body>' .. body .. '</s:Body></s:Envelope>'
end

local times = '<wsnt:CurrentTime>2026-10-28T12:00:00Z</wsnt:CurrentTime>'
    .. '<wsnt:TerminationTime>2026-10-28T12:01:00Z</wsnt:TerminationTime>'

local function subscribed(h)
    h:credentials()
    h:reply(envelope('<tds:GetCapabilitiesResponse><tds:Capabilities><tt:Events>'
        .. '<tt:XAddr>http://doorbell.example.com:8000/onvif/events</tt:XAddr>'
        .. '</tt:Events></tds:Capabilities></tds:GetCapabilitiesResponse>'))
    assert(h.requests[#h.requests].request.body:find('CreatePullPointSubscription', 1, true))
    h:reply(envelope('<tev:CreatePullPointSubscriptionResponse><tev:SubscriptionReference>'
        .. '<wsa:Address>http://doorbell.example.com:8000/onvif/sub?idx=1</wsa:Address>'
        .. '</tev:SubscriptionReference>' .. times .. '</tev:CreatePullPointSubscriptionResponse>'))
    assert(h.requests[#h.requests].request.body:find('PullMessages', 1, true))
    local parser = assert(loadfile('./OnvifXml.luau'))()
    for _, request in ipairs(h.requests) do
        assert(parser.parse(request.request.body), 'outbound SOAP must be valid XML')
        assert(request.request.body:find('<wsa:Action>', 1, true) and request.request.body:find('<wsa:To>', 1, true))
    end
end

local function eventMessage(operation, active, topic)
    return '<wsnt:NotificationMessage><wsnt:Topic>tns1:RuleEngine/MyRuleDetector/' .. (topic or 'Visitor')
        .. '</wsnt:Topic><wsnt:Message><tt:Message PropertyOperation="' .. operation
        .. '"><tt:Data><tt:SimpleItem Name="State" Value="' .. active
        .. '"/></tt:Data></tt:Message></wsnt:Message></wsnt:NotificationMessage>'
end

test("ONVIF event stream only rings for a changed visitor edge and continues immediately", function()
    local h = boot("http://doorbell.example.com", true)
    subscribed(h)
    h:reply(envelope('<tev:PullMessagesResponse>' .. times .. eventMessage('Initialized', 'false')
        .. eventMessage('Changed', 'true', 'Motion') .. '</tev:PullMessagesResponse>'))
    assert(h.rings == 0 and #h.requests == 4)
    h:reply(envelope('<tev:PullMessagesResponse>' .. times .. eventMessage('Changed', 'true')
        .. eventMessage('Changed', 'true') .. '</tev:PullMessagesResponse>'))
    assert(h.rings == 1 and #h.requests == 5)
    h:reply(envelope('<tev:PullMessagesResponse>' .. times .. eventMessage('Changed', 'false')
        .. eventMessage('Changed', 'true') .. '</tev:PullMessagesResponse>'))
    assert(h.rings == 2 and h.shared.doorbell.status == 'doorbellListening')
end)

test("ONVIF accepts whitespace around a visitor topic", function()
    local h = boot('http://doorbell.example.com', true)
    subscribed(h)
    local message = eventMessage('Changed', 'true'):gsub('<wsnt:Topic>', '<wsnt:Topic>\n  ')
        :gsub('</wsnt:Topic>', '  \n</wsnt:Topic>')
    h:reply(envelope('<tev:PullMessagesResponse>' .. times .. message .. '</tev:PullMessagesResponse>'))
    assert(h.rings == 1)
end)

test("ONVIF handles fractional timestamps and timezone offsets", function()
    local h = boot('http://doorbell.example.com', true)
    h:credentials()
    h:reply(envelope('<tds:GetCapabilitiesResponse><tds:Capabilities><tt:Events>'
        .. '<tt:XAddr>http://doorbell.example.com:8000/onvif/events</tt:XAddr>'
        .. '</tt:Events></tds:Capabilities></tds:GetCapabilitiesResponse>'))
    local mixed = '<wsnt:CurrentTime>2026-10-28T12:00:00.500Z</wsnt:CurrentTime>'
        .. '<wsnt:TerminationTime>2026-10-28T15:01:00.500+03:00</wsnt:TerminationTime>'
    h:reply(envelope('<tev:CreatePullPointSubscriptionResponse><tev:SubscriptionReference>'
        .. '<wsa:Address>http://doorbell.example.com:8000/onvif/sub</wsa:Address>'
        .. '</tev:SubscriptionReference>' .. mixed .. '</tev:CreatePullPointSubscriptionResponse>'))
    assert(h.shared.doorbell.status == 'doorbellListening')
    assert(h.requests[#h.requests].request.body:find('<tev:PullMessages>', 1, true))
end)

test("ONVIF accepts whitespace surrounding timestamps", function()
    local h = boot('http://doorbell.example.com', true)
    h:credentials()
    h:reply(envelope('<tds:GetCapabilitiesResponse><tds:Capabilities><tt:Events>'
        .. '<tt:XAddr>http://doorbell.example.com:8000/onvif/events</tt:XAddr>'
        .. '</tt:Events></tds:Capabilities></tds:GetCapabilitiesResponse>'))
    local padded = times:gsub('2026%-10%-28T12:00:00Z', '  2026-10-28T12:00:00Z\n')
        :gsub('2026%-10%-28T12:01:00Z', '\n2026-10-28T12:01:00Z  ')
    h:reply(envelope('<tev:CreatePullPointSubscriptionResponse><tev:SubscriptionReference>'
        .. '<wsa:Address>http://doorbell.example.com:8000/onvif/sub</wsa:Address>'
        .. '</tev:SubscriptionReference>' .. padded .. '</tev:CreatePullPointSubscriptionResponse>'))
    assert(h.shared.doorbell.status == 'doorbellListening')
end)

test("ONVIF handles a timestamp outside the host clock range", function()
    local h = boot('http://doorbell.example.com', true)
    h:credentials()
    h:reply(envelope('<tds:GetCapabilitiesResponse><tds:Capabilities><tt:Events>'
        .. '<tt:XAddr>http://doorbell.example.com:8000/onvif/events</tt:XAddr>'
        .. '</tt:Events></tds:Capabilities></tds:GetCapabilitiesResponse>'))
    h.badClock = true
    h:reply(envelope('<tev:CreatePullPointSubscriptionResponse><tev:SubscriptionReference>'
        .. '<wsa:Address>http://doorbell.example.com:8000/onvif/sub</wsa:Address>'
        .. '</tev:SubscriptionReference>' .. times .. '</tev:CreatePullPointSubscriptionResponse>'))
    assert(h.shared.doorbell.status == 'doorbellFallback')
end)

test("ONVIF accepts whitespace around advertised endpoint addresses", function()
    local h = boot('http://doorbell.example.com', true)
    h:credentials()
    h:reply(envelope('<tds:GetCapabilitiesResponse><tds:Capabilities><tt:Events>'
        .. '<tt:XAddr> \nhttp://doorbell.example.com:8000/onvif/events \n</tt:XAddr>'
        .. '</tt:Events></tds:Capabilities></tds:GetCapabilitiesResponse>'))
    assert(h.requests[#h.requests].request.body:find('CreatePullPointSubscription', 1, true))
    h:reply(envelope('<tev:CreatePullPointSubscriptionResponse><tev:SubscriptionReference>'
        .. '<wsa:Address> \nhttp://doorbell.example.com:8000/onvif/sub \n</wsa:Address>'
        .. '</tev:SubscriptionReference>' .. times .. '</tev:CreatePullPointSubscriptionResponse>'))
    assert(h.shared.doorbell.status == 'doorbellListening')
end)

test("first changed active event rings even before an initial state", function()
    local h = boot('http://doorbell.example.com', true)
    subscribed(h)
    h:reply(envelope('<tev:PullMessagesResponse>' .. times .. eventMessage('Changed', 'true') .. '</tev:PullMessagesResponse>'))
    assert(h.rings == 1)
    h:reply(envelope('<tev:PullMessagesResponse>' .. times .. eventMessage('Initialized', 'false')
        .. eventMessage('Changed', 'true') .. '</tev:PullMessagesResponse>'))
    assert(h.rings == 1)
end)

test("ONVIF renews before expiry even when repeated pull responses arrive", function()
    local h = boot('http://doorbell.example.com', true)
    subscribed(h)
    h:tick(45000)
    h:reply(envelope('<tev:PullMessagesResponse>' .. times .. '</tev:PullMessagesResponse>'))
    assert(h.requests[#h.requests].request.body:find('<wsnt:Renew>', 1, true))
    assert(h.requests[#h.requests].request.body:find('wsn/bw%-2/SubscriptionManager/RenewRequest'))
    h:reply(envelope('<wsnt:RenewResponse>' .. times .. '</wsnt:RenewResponse>'))
    assert(h.requests[#h.requests].request.body:find('<tev:PullMessages>', 1, true))
end)

test("long polling leaves time to renew before the subscription deadline", function()
    local h = boot('http://doorbell.example.com', true)
    subscribed(h)
    assert(h.requests[#h.requests].request.body:find('<tev:Timeout>PT20S</tev:Timeout>', 1, true))
    h:tick(20000)
    h:reply(envelope('<tev:PullMessagesResponse>' .. times .. '</tev:PullMessagesResponse>'))
    assert(h.requests[#h.requests].request.body:find('<tev:Timeout>PT17S</tev:Timeout>', 1, true))
    h:tick(17000)
    h:reply(envelope('<tev:PullMessagesResponse>' .. times .. '</tev:PullMessagesResponse>'))
    assert(h.requests[#h.requests].request.body:find('<wsnt:Renew>', 1, true))
end)

test("a CGI authentication failure does not prevent the next ONVIF attempt", function()
    local h = boot('http://doorbell.example.com')
    h:credentials()
    h:reply({ { cmd = 'Login', code = 1 } })
    assert(h.shared.doorbell.status == 'doorbellAuthFailed')
    h:tick(60000)
    assert(h.requests[#h.requests].request.url:find('/onvif/device_service', 1, true))
end)

test("old ONVIF callbacks cannot release the current request", function()
    local h = boot('http://doorbell.example.com', true)
    subscribed(h)
    local old = #h.requests
    h:reply(envelope('<tev:PullMessagesResponse>' .. times .. '</tev:PullMessagesResponse>'))
    local current = #h.requests
    h:reply(envelope('<tev:PullMessagesResponse>' .. times .. '</tev:PullMessagesResponse>'), 200, true, old)
    h:tick(1000)
    assert(#h.requests == current)
end)

test("ONVIF rejects an endpoint on another host or downgraded TLS", function()
    for _, endpoint in ipairs({ 'http://evil.example.com/events', 'http://doorbell.example.com/events' }) do
        local h = boot('https://doorbell.example.com', true)
        h:credentials()
        h:reply(envelope('<tds:GetCapabilitiesResponse><tds:Capabilities><tt:Events><tt:XAddr>'
            .. endpoint .. '</tt:XAddr></tt:Events></tds:Capabilities></tds:GetCapabilitiesResponse>'))
        assert(h.shared.doorbell.status == 'doorbellFallback' and #h.requests == 1)
    end
end)

test("ONVIF ignores old events after disabling and falls back after failure", function()
    local h = boot('http://doorbell.example.com', true)
    subscribed(h)
    local old = #h.requests
    h:command('url', ''); h:tick(1000)
    h:reply(envelope('<tev:PullMessagesResponse>' .. times .. eventMessage('Changed', 'true')
        .. '</tev:PullMessagesResponse>'), 200, true, old)
    assert(h.rings == 0 and h.shared.doorbell.status == 'doorbellDisabled')
    local other = boot('http://doorbell.example.com', true)
    subscribed(other)
    other:reply('unavailable', 500)
    assert(other.shared.doorbell.status == 'doorbellFallback')
end)

test("unconfigured doorbell does no network or keyring work", function()
    local h = boot()
    h:tick(30000)
    assert(#h.requests == 0 and #h.commands == 0 and h.shared.doorbell.status == "doorbellDisabled")
end)

test("native Login keeps credentials out of URLs, state and saved settings", function()
    local h = boot("http://doorbell.example.com/")
    h:credentials()
    local r = h.requests[1].request
    assert(r.url == "http://doorbell.example.com/cgi-bin/api.cgi?cmd=Login&token=null")
    assert(r.method == "POST" and r.follow_redirects == false and not r.allow_insecure_tls)
    local body = h.api.json.decode(r.body)
    assert(body[1].param.User.userName == "bell-user" and body[1].param.User.password == 'bell-secret $() "')
    assert(h.commands[1].argv[4] == "noctalia-frigate-doorbell")
    assert(h.shared.doorbell.password == nil and h.shared.doorbell.username == nil and h.shared.doorbell.token == nil)
    assert(h.files["/data/doorbell.json"].password == nil)
end)

test("only button edges ring; initial active state and motion do not open the viewer", function()
    local h = connected()
    assert(h.requests[2].request.url:find("token=test%20token", 1, true))
    assert(h.api.json.decode(h.requests[2].request.body)[1].param.channel == 0)
    h:event(1)
    assert(h.rings == 0)
    h:tick(); h:event(0)
    assert(h.rings == 0 and h.shared.doorbell.status == "doorbellFallback")
    h:tick(); h:event(1)
    assert(h.rings == 1)
    h:tick(); h:event(1)
    assert(h.rings == 1)
    h:tick(); h:event(0)
    h:tick(); h:event(1)
    assert(h.rings == 2)
end)

test("background polling stays single-flight and recovers with bounded backoff", function()
    local h = connected()
    h:tick(30000)
    assert(#h.requests == 2)
    h:reply("offline", 0, false)
    h:tick(1000)
    assert(#h.requests == 2 and h.shared.doorbell.status == "doorbellUnavailable")
    h:tick(4000)
    assert(#h.requests == 3)
    h:event(0)
    h:tick(); h:event(1)
    assert(h.rings == 1)
end)

test("token expiry reauthenticates without repeating the same press", function()
    local h = connected()
    h:event(0); h:tick(); h:event(1)
    h:tick()
    h:reply({ { cmd = "GetEvents", code = 1, error = { rspCode = -6 } } })
    h:tick(5000)
    assert(h.requests[#h.requests].request.url:find("cmd=Login", 1, true))
    h:login(); h:event(1)
    assert(h.rings == 1)
end)

test("retries reuse a valid session when keyring credentials have not changed", function()
    local h = connected()
    h:event(0)
    h:command("retry")
    local stale = h.commands[#h.commands - 1]
    h:command("retry")
    stale.cb({ exitCode = 0, stdout = "stale-user\n" })
    h:credentials()
    assert(h.requests[#h.requests].request.url:find("cmd=GetEvents", 1, true))
    h:event(1)
    assert(h.rings == 1)
end)

test("bad credentials and unsupported visitor do not spin or ring", function()
    local h = boot("http://doorbell.example.com")
    h:credentials()
    h:reply({ { cmd = "Login", code = 1, error = { rspCode = -6 } } })
    h:tick(59000)
    assert(#h.requests == 1 and h.shared.doorbell.status == "doorbellAuthFailed")
    h:command("retry"); h:credentials(); h:login()
    h:reply({ { cmd = "GetEvents", code = 0, value = { channel = 0, visitor = { support = 0, alarm_state = 1 } } } })
    local n = #h.requests
    h:tick(58000)
    assert(#h.requests == n and h.rings == 0 and h.shared.doorbell.status == "doorbellUnsupported")
end)

test("malformed responses and other channels never become button events", function()
    for _, response in ipairs({ "html", {}, { { cmd = "GetEvents", code = 0, value = {
        channel = 1, visitor = { support = 1, alarm_state = 1 },
    } } }, { { cmd = "GetEvents", code = 0, value = {
        channel = 0, visitor = { support = 1, alarm_state = "yes" },
    } } } }) do
        local h = connected()
        h:event(0); h:tick(); h:reply(response)
        assert(h.rings == 0 and h.shared.doorbell.status == "doorbellInvalidResponse")
    end
end)

test("clearing the URL stops polling and ignores late responses", function()
    local h = connected()
    h:event(0); h:tick()
    local old = #h.requests
    h:command("url", ""); h:tick(1000)
    h:event(1)
    h:tick(60000)
    assert(#h.requests == old and h.rings == 0 and h.shared.doorbell.status == "doorbellDisabled")
    assert(h.api.json.decode(h.files["/data/doorbell.json"]).url == "")
end)

test("unsafe URL drafts never reach network or disk", function()
    for _, url in ipairs({ "http://user:secret@host", "file:///tmp/camera", "http://", "http://host/?password=secret", "http://host\\@other" }) do
        local h = boot()
        h:command("url", url); h:tick(1000)
        assert(#h.requests == 0 and #h.commands == 0 and not h.files["/data/doorbell.json"])
        assert(h.shared.doorbell.status == "invalidUrl")
    end
end)

test("clearing an invalid draft also clears the previously saved address", function()
    local h = boot("http://doorbell.example.com")
    h:command("url", "http://user:secret@host"); h:tick(1000)
    assert(h.files["/data/doorbell.json"].url == "http://doorbell.example.com")
    h:command("url", ""); h:tick(1000)
    assert(h.api.json.decode(h.files["/data/doorbell.json"]).url == "")
    assert(h.shared.doorbell.status == "doorbellDisabled" and h.interval == 30000)
end)

test("keyring failure prevents login and retry discards old lookups", function()
    local h = boot("http://doorbell.example.com")
    local old = h.commands[1]
    h.commands[1].cb({ exitCode = 2, stdout = "" })
    h.commands[2].cb({ exitCode = 1, stdout = "" })
    h:tick()
    assert(#h.requests == 0 and h.shared.doorbell.status == "keyringFailed")
    h:command("retry")
    old.cb({ exitCode = 0, stdout = "stale-user\n" })
    h:credentials()
    assert(h.api.json.decode(h.requests[1].request.body)[1].param.User.userName == "bell-user")
end)

test("HTTP start rejection backs off; unload ignores late button callbacks", function()
    local h = boot("http://doorbell.example.com")
    h.rejectHttp = true
    h:credentials()
    h:tick(0)
    assert(h.shared.doorbell.status == "doorbellUnavailable")
    h.rejectHttp = false
    h:tick(1000)
    assert(#h.requests == 0)
    h:tick(4000); h:login(); h:event(0); h:tick()
    h.env.onExit()
    h:event(1)
    assert(h.rings == 0)
end)

print(count .. " doorbell checks passed")
