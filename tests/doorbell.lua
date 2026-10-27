-- Run from the repository root: lua tests/doorbell.lua
local function boot(url)
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
        readFile = function(path) return h.files[path] end,
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
    h.env = setmetatable({ noctalia = api }, { __index = _G })
    assert(loadfile("Doorbell.luau", "t", h.env))()
    function h:command(action, value) set("doorbellCommand", { action = action, value = value }) end
    function h:tick(ms) self.time = self.time + (ms or 2000); self.env.update() end
    function h:credentials()
        local n = #self.commands
        assert(n >= 2)
        self.commands[n - 1].cb({ exitCode = 0, stdout = "bell-user\n" })
        self.commands[n].cb({ exitCode = 0, stdout = 'bell-secret $() "\n' })
        self:tick(0)
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
    assert(h.rings == 0 and h.shared.doorbell.status == "doorbellListening")
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
    h:tick(60000)
    assert(#h.requests == 1 and h.shared.doorbell.status == "doorbellAuthFailed")
    h:command("retry"); h:credentials(); h:login()
    h:reply({ { cmd = "GetEvents", code = 0, value = { channel = 0, visitor = { support = 0, alarm_state = 1 } } } })
    local n = #h.requests
    h:tick(60000)
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
