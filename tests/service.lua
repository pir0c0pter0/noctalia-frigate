-- Run from the repository root: lua tests/service.lua
local function boot(options)
    options = options or {}
    local h = { time = 1000, requests = {}, files = {}, state = {}, watchers = {}, commands = {}, removed = {} }
    h.files = options.files or { ["/data/viewer.json"] = { frigateUrl = "https://frigate.example.com" } }
    local json = {}
    local function encode(value)
        local token = "json:" .. tostring(#json + 1)
        json[#json + 1] = value
        json[token] = value
        return token
    end
    local function decode(value)
        return type(value) == "table" and value or json[value]
    end
    local function set(key, value)
        h.state[key] = value
        for _, callback in ipairs(h.watchers[key] or {}) do callback(value) end
    end
    h.api = {
        nowMs = function() return h.time end,
        getConfig = function(key) error("plugin has no native settings: " .. key) end,
        getenv = function(key)
            return ({ XDG_RUNTIME_DIR = "/run/user/1000", XDG_CONFIG_HOME = "/config" })[key]
        end,
        expandPath = function(path) return path end,
        pluginDataDir = function() return "/data" end,
        readFile = function(path) return h.files[path] end,
        fileExists = function(path) return h.files[path] ~= nil end,
        writeFile = function(path, value) h.files[path] = value; return not h.writeFail end,
        renameFile = function(from, to) h.files[to] = h.files[from]; h.files[from] = nil; return true end,
        removeFile = function(path) h.files[path] = nil; h.removed[#h.removed + 1] = path; return true end,
        mkdirAll = function() return true end,
        setUpdateInterval = function(ms) h.interval = ms end,
        togglePanel = function(id) h.openedPanel = id; h.panelOpens = (h.panelOpens or 0) + 1 end,
        commandExists = function() return options.keyring == true end,
        runAsync = function(argv, callback)
            h.commands[#h.commands + 1] = { argv = argv, callback = callback }
            return true
        end,
        http = function(request, callback)
            if h.rejectHttp then return false end
            h.requests[#h.requests + 1] = { request = request, callback = callback }
            return true
        end,
        tr = function(key) return key end,
        log = function() end,
        notifyError = function(_, body) h.notification = body end,
        json = { encode = encode, decode = decode },
        string = {
            trim = function(s) return s:match("^%s*(.-)%s*$") end,
            urlEncode = function(s) return (s:gsub("([^%w%-_%.~])", function(c)
                return string.format("%%%02X", string.byte(c))
            end)) end,
        },
        state = {
            set = function(key, value)
                if options.noSelfWatch and key == "command" then h.state[key] = value else set(key, value) end
            end,
            get = function(key) return h.state[key] end,
            watch = function(key, callback)
                h.watchers[key] = h.watchers[key] or {}
                table.insert(h.watchers[key], callback)
            end,
        },
    }
    h.env = setmetatable({ noctalia = h.api }, { __index = _G })
    local chunk, err = loadfile("Main.luau", "t", h.env)
    assert(chunk, "Noctalia 5 service must exist and compile: " .. tostring(err))
    chunk()
    function h:command(action, value) set("command", { action = action, value = value }) end
    function h:reply(index, body, status, ok)
        self.requests[index].callback({ body = body, status = status or 200, ok = ok ~= false })
    end
    function h:setUrl(url)
        set("command", { action = "url", value = url })
        self.time = self.time + 800
        self.env.update()
    end
    function h:find(suffix)
        for i = #self.requests, 1, -1 do
            if self.requests[i].request.url:find(suffix, 1, true) then return i end
        end
        error("request missing: " .. suffix)
    end
    return h
end

local count = 0
local function test(name, check)
    check()
    count = count + 1
    print("ok " .. count .. " - " .. name)
end

local function selectedBoot(options)
    options = options or {}
    options.files = options.files or { ["/data/viewer.json"] = {
        frigateUrl = "https://frigate.example.com", defaultCamera = options.defaultCamera, selectedCameras = { "front", "side" },
    } }
    return boot(options)
end

test("doorbell opens the panel; an already open viewer returns to the main camera", function()
    local h = selectedBoot({ defaultCamera = "side", noSelfWatch = true })
    h:command("ring")
    assert(h.openedPanel == "pir0c0pter0/frigate:viewer" and h.state.panelPage == "viewer")
    h:command("open")
    h:command("next")
    h:command("preview", false)
    h:command("ring")
    assert(h.panelOpens == 1 and h.state.viewer.camera == "side" and h.state.viewer.opened)
    assert(h.state.panelPage == "viewer")
end)

test("without selected cameras only health runs", function()
    local h = boot()
    assert(#h.requests == 1 and h.requests[1].request.url:match("/api/version$"))
    assert(h.interval >= 1000)
end)

test("main camera stays warm while closed and opens without discarding its frame", function()
    local h = selectedBoot({ defaultCamera = "side" })
    local first = h:find("/api/side/latest.jpg")
    h:reply(first, "\255\216\255warm\255\217")
    local frame = h.state.viewer.frame
    assert(frame ~= "" and h.files[frame])
    h:command("open")
    assert(h.state.viewer.frame == frame)
    h:command("close")
    assert(h.state.viewer.frame == frame and h.files[frame])
    h.time = h.time + 200
    h.env.update()
    local second = h:find("/api/side/latest.jpg")
    assert(second ~= first)
    h:reply(second, "\255\216\255fresh\255\217")
    h:command("open")
    assert(h.files[h.state.viewer.frame] == "\255\216\255fresh\255\217")
end)

test("preview cadence includes request latency instead of adding an idle second", function()
    local h = selectedBoot()
    h:command("open")
    for _ = 1, 5 do
        local i = h:find("latest.jpg")
        h.time = h.time + 150
        h:reply(i, "\255\216\255ok\255\217")
        h.time = h.time + 50
        h.env.update()
        assert(h:find("latest.jpg") ~= i, "next frame must start within 200 ms of the previous start")
    end
end)

test("main camera keeps updating while another camera is visible", function()
    local h = selectedBoot()
    h:reply(h:find("/api/front/latest.jpg"), "\255\216\255main\255\217")
    h:command("open")
    h:command("next")
    local side = h:find("/api/side/latest.jpg")
    h:reply(side, "\255\216\255side\255\217")
    local visible = h.state.viewer.frame
    local main = h:find("/api/front/latest.jpg")
    h.time = h.time + 200
    h.env.update()
    if h:find("/api/front/latest.jpg") == main then
        h:reply(h:find("/api/side/latest.jpg"), "\255\216\255side\255\217")
    end
    main = h:find("/api/front/latest.jpg")
    assert(main > side)
    h:reply(main, "\255\216\255main-fresh\255\217")
    assert(h.state.viewer.camera == "side" and h.files[h.state.viewer.frame]:find("side"))
    h:command("close")
    assert(h.state.viewer.camera == "front" and h.files[h.state.viewer.frame]:find("main%-fresh"))
    assert(not h.files[visible])
end)

test("slow preview responses never build a queue and resume immediately when overdue", function()
    local h = selectedBoot()
    local first = h:find("latest.jpg")
    local before = #h.requests
    for _ = 1, 10 do
        h.time = h.time + 100
        h.env.update()
        assert(#h.requests == before)
    end
    h:reply(first, "\255\216\255slow\255\217")
    assert(h:find("latest.jpg") ~= first and #h.requests == before + 1)
    h.env.update()
    assert(#h.requests == before + 1)
end)

test("changing the main camera while closed drops its old pending response", function()
    local h = selectedBoot()
    local old = h:find("/api/front/latest.jpg")
    h:command("default", "side")
    h:reply(old, "\255\216\255old\255\217")
    local current = h:find("/api/side/latest.jpg")
    assert(current > old)
    h:reply(current, "\255\216\255new\255\217")
    h:command("open")
    assert(h.state.viewer.camera == "side" and h.files[h.state.viewer.frame] == "\255\216\255new\255\217")
end)

test("a previous visible camera cannot publish after navigating again", function()
    local h = selectedBoot({ files = { ["/data/viewer.json"] = {
        frigateUrl = "https://frigate.example.com", selectedCameras = { "front", "side", "back" },
    } } })
    h:reply(h:find("latest.jpg"), "\255\216\255main\255\217")
    h:command("open")
    h:command("next")
    local side = h:find("/api/side/latest.jpg")
    h:command("next")
    h:reply(side, "bad", 401)
    assert(h.state.viewer.camera == "back" and h.state.viewer.problem == "" and h.state.viewer.frame == "")
    h:reply(h:find("/api/back/latest.jpg"), "\255\216\255back\255\217")
    assert(h.files[h.state.viewer.frame] == "\255\216\255back\255\217")
end)

test("two preview caches stay bounded and unloading ignores the pending response", function()
    local h = selectedBoot()
    h:command("open")
    h:command("next")
    local replied = 0
    for _ = 1, 30 do
        h.time = h.time + 100
        h.env.update()
        local i = h:find("latest.jpg")
        if i ~= replied then
            h:reply(i, "\255\216\255ok\255\217")
            replied = i
        end
        local files = 0
        for path in pairs(h.files) do if path:match("%.jpg$") then files = files + 1 end end
        assert(files <= 4)
    end
    h.time = h.time + 200
    h.env.update()
    local pending = h:find("latest.jpg")
    assert(pending ~= replied)
    h.env.onExit()
    local before = #h.requests
    h:reply(pending, "\255\216\255late\255\217")
    assert(#h.requests == before)
    for path in pairs(h.files) do assert(not path:match("%.jpg$")) end
end)

test("a main camera error backs off independently of the visible camera", function()
    local h = selectedBoot()
    local main = h:find("/api/front/latest.jpg")
    h:command("open")
    h:command("next")
    h:reply(main, "bad", 500)
    h:reply(h:find("/api/side/latest.jpg"), "\255\216\255side\255\217")
    for _ = 1, 4 do
        h.time = h.time + 200
        h.env.update()
        h:reply(h:find("/api/side/latest.jpg"), "\255\216\255side\255\217")
    end
    assert(h:find("/api/front/latest.jpg") == main)
    assert(h.state.viewer.message == "" and h.files[h.state.viewer.frame] == "\255\216\255side\255\217")
end)

test("opening resets default; navigation wraps in both directions", function()
    local h = selectedBoot({ defaultCamera = "side" })
    h:command("open")
    assert(h.state.viewer.camera == "side")
    h:command("next")
    assert(h.state.viewer.camera == "front")
    h:command("previous")
    assert(h.state.viewer.camera == "side")
    h:command("close")
    h:command("open")
    assert(h.state.viewer.camera == "side")
end)

test("snapshot uses native HTTP, encoded camera and bounded resolution", function()
    local h = selectedBoot({ files = { ["/data/viewer.json"] = { frigateUrl = "frigate.example.com", selectedCameras = { "front / 1" } } } })
    h:command("open")
    local req = h.requests[h:find("latest.jpg")].request
    assert(req.url:find("front%20%2F%201/latest.jpg", 1, true))
    assert(req.url:find("height=640", 1, true) and req.url:find("quality=90", 1, true))
    assert(req.follow_redirects == false)
end)

test("preview asks for the camera's detect height, capped at 720", function()
    local h = selectedBoot()
    h:command("discover")
    h:reply(h:find("/api/config"), { cameras = { front = { detect = { height = 288 } }, side = { detect = { height = 2160 } } } })
    h:reply(h:find("latest.jpg"), "\255\216\255initial\255\217")
    h.time = h.time + 200
    h.env.update()
    h:command("open")
    assert(h.requests[h:find("latest.jpg")].request.url:find("height=288&", 1, true))
    h:command("next")
    h:reply(h:find("latest.jpg"), "\255\216\255jpeg\255\217")
    assert(h.requests[h:find("latest.jpg")].request.url:find("height=720&", 1, true))
end)

test("one preview in flight; closing discards the other camera's late result", function()
    local h = selectedBoot()
    h:command("open")
    local i = h:find("latest.jpg")
    local before = #h.requests
    h.time = h.time + 100
    h.env.update()
    assert(#h.requests == before)
    h:reply(i, "\255\216\255jpeg\255\217")
    assert(h.state.viewer.frame ~= "" and h.files[h.state.viewer.frame])
    h:command("next")
    i = h:find("/api/side/latest.jpg")
    before = #h.requests
    h:command("close")
    assert(#h.requests == before)
    h:reply(i, "\255\216\255late\255\217")
    assert(h.state.viewer.camera == "front" and h.files[h.state.viewer.frame] == "\255\216\255jpeg\255\217")
    h.env.onExit()
    for path in pairs(h.files) do assert(not path:match("%.jpg$")) end
end)

test("a main camera response cannot replace another camera's visible frame", function()
    local h = selectedBoot()
    h:command("open")
    local old = h:find("latest.jpg")
    h:command("next")
    assert(h:find("latest.jpg") == old)
    h:reply(old, "\255\216\255old\255\217")
    local current = h:find("latest.jpg")
    assert(current ~= old and h.state.viewer.frame == "")
    h:reply(current, "\255\216\255new\255\217")
    assert(h.state.viewer.camera == "side" and h.files[h.state.viewer.frame]:find("new"))
end)

test("snapshot failure backs off; success resets retry delay", function()
    local h = selectedBoot()
    h:command("open")
    h:reply(h:find("latest.jpg"), "bad", 500)
    local before = #h.requests
    h.time = h.time + 1000
    h.env.update()
    assert(#h.requests == before)
    h.time = h.time + 1000
    h.env.update()
    assert(#h.requests == before + 1)
    h:reply(h:find("latest.jpg"), "\255\216\255ok\255\217")
    h.time = h.time + 1000
    h.env.update()
    assert(#h.requests == before + 2)
end)

test("malformed image never replaces last valid frame", function()
    local h = selectedBoot()
    h:command("open")
    h:reply(h:find("latest.jpg"), "\255\216\255ok\255\217")
    local frame = h.state.viewer.frame
    h.time = h.time + 1000
    h.env.update()
    h:reply(h:find("latest.jpg"), "<html>login</html>")
    assert(h.state.viewer.frame == frame and h.state.viewer.message == "streamError")
end)

test("discovery validates shape, filters birdseye, preserves selection on error", function()
    local h = selectedBoot()
    h:command("discover")
    h:reply(h:find("/api/config"), { cameras = { front = {}, side = {}, birdseye = {} } })
    assert(#h.state.viewer.cameras == 2 and h.state.viewer.cameras[1] == "front")
    h:command("discover")
    h:reply(h:find("/api/config"), { cameras = "invalid" })
    assert(h.state.viewer.problem == "invalidResponse" and #h.state.viewer.selected == 2)
end)

test("selection persists atomically and removing current camera remains valid", function()
    local h = selectedBoot()
    h:command("discover")
    h:reply(h:find("/api/config"), { cameras = { front = {}, side = {} } })
    h:command("toggle", "front")
    assert(h.state.viewer.camera == "side" and #h.state.viewer.selected == 1)
    local saved = h.api.json.decode(h.files["/data/viewer.json"])
    assert(saved.selectedCameras[1] == "side")
    h:command("toggle", "side")
    h:command("next")
    assert(h.state.viewer.camera == "" and #h.state.viewer.selected == 0)
end)

test("keyring credentials stay out of URLs, state and subprocess argv", function()
    local h = selectedBoot({ keyring = true })
    assert(#h.requests == 0 and #h.commands == 2)
    h.commands[1].callback({ exitCode = 0, stdout = "user\n" })
    h.commands[2].callback({ exitCode = 0, stdout = " séc\"ret \n" })
    local req = h.requests[1].request
    assert(req.basic_username == "user" and req.basic_password == " séc\"ret ")
    assert(not req.url:find("user", 1, true))
    assert(h.state.viewer.password == nil and h.state.viewer.username == nil)
    assert(h.state.command == nil)
end)

test("legacy URL, default and selection migrate; secrets are never copied", function()
    local old = { frigateUrl = "legacy.example.com/", defaultCamera = "side",
        selectedCameras = { "front", "side", "side", 42 }, password = "do-not-copy" }
    local h = boot({ files = {
        ["/config/noctalia/plugins/noctalia-frigate/settings.json"] = old,
    } })
    assert(h.requests[1].request.url == "https://legacy.example.com/api/version")
    assert(h.state.viewer.camera == "side" and #h.state.viewer.selected == 2)
    local saved = h.api.json.decode(h.files["/data/viewer.json"])
    assert(saved.password == nil and saved.frigateUrl == "legacy.example.com/" and saved.defaultCamera == "side")
    assert(old.password == "do-not-copy")
end)

test("fresh install waits for a URL without network access", function()
    local h = boot({ files = {} })
    assert(#h.requests == 0 and h.state.viewer.problem == "noUrlConfigured")
    local saved = h.api.json.decode(h.files["/data/viewer.json"])
    assert(saved.frigateUrl == "" and saved.selectedCameras == nil)
end)

test("rejects embedded credentials and unsafe URL schemes before network access", function()
    for _, url in ipairs({ "https://user:pass@example.com", "file:///etc/passwd", "http://", "https://host/#fragment" }) do
        local h = boot({ files = { ["/data/viewer.json"] = { frigateUrl = url } } })
        assert(#h.requests == 0 and h.state.viewer.problem == "invalidUrl", url)
    end
end)

test("URL change is debounced, persisted and invalidates old callbacks", function()
    local h = selectedBoot()
    h:command("open")
    local oldFrame, oldHealth = h:find("latest.jpg"), 1
    local before = #h.requests
    h:command("url", "https://n")
    h:command("url", "https://new.example.com")
    assert(#h.requests == before)
    h.time = h.time + 800
    h.env.update()
    assert(h.api.json.decode(h.files["/data/viewer.json"]).frigateUrl == "https://new.example.com")
    assert(h.state.viewer.url == "https://new.example.com")
    h:reply(oldHealth, "old", 401)
    h:reply(oldFrame, "\255\216\255old\255\217")
    assert(h.state.viewer.frame == "")
    assert(h.requests[h:find("latest.jpg")].request.url:find("new.example.com", 1, true))
end)

test("temporary files remain bounded across many frames", function()
    local h = selectedBoot()
    h:command("open")
    for _ = 1, 12 do
        h:reply(h:find("latest.jpg"), "\255\216\255ok\255\217")
        h.time = h.time + 1000
        h.env.update()
    end
    local files = 0
    for path in pairs(h.files) do if path:match("%.jpg$") then files = files + 1 end end
    assert(files <= 2)
    h.env.onExit()
    for path in pairs(h.files) do assert(not path:match("%.jpg$")) end
end)

test("connecting auto-discovers cameras, shows all on first run and reports version", function()
    local h = boot()
    h:reply(1, "0.16.0")
    assert(h.state.viewer.connected and h.state.viewer.version == "0.16.0")
    h:reply(h:find("/api/config"), { cameras = { side = {}, front = {}, birdseye = {} } })
    assert(#h.state.viewer.selected == 2 and h.state.viewer.selected[1] == "front")
    local saved = h.api.json.decode(h.files["/data/viewer.json"])
    assert(#saved.selectedCameras == 2)
end)

test("an explicitly empty selection is not auto-filled again", function()
    local h = boot({ files = { ["/data/viewer.json"] = { frigateUrl = "https://f.example.com", selectedCameras = {} } } })
    h:reply(1, "0.16.0")
    h:reply(h:find("/api/config"), { cameras = { front = {} } })
    assert(#h.state.viewer.selected == 0)
end)

test("main camera choice persists and opens first", function()
    local h = selectedBoot()
    h:command("default", "side")
    assert(h.api.json.decode(h.files["/data/viewer.json"]).defaultCamera == "side")
    h:command("open")
    assert(h.state.viewer.camera == "side" and h.state.viewer.defaultCamera == "side")
end)

test("health failures surface as problems and retry quickly", function()
    local h = boot()
    h:reply(1, "", 401)
    assert(h.state.viewer.problem == "authFailed" and not h.state.viewer.connected)
    h.time = h.time + 5000
    h.env.update()
    h:reply(h:find("/api/version"), "0.16.0")
    assert(h.state.viewer.problem == "" and h.state.viewer.connected)
end)

test("changing servers drops old discovery and rediscovers once connected", function()
    local h = boot()
    h:command("discover")
    h:reply(h:find("/api/config"), { cameras = { old = {} } })
    h:setUrl("https://new.example.com")
    assert(#h.state.viewer.cameras == 0)
    h:reply(h:find("/api/version"), "0.16.0")
    assert(h.requests[h:find("/api/config")].request.url:find("new.example.com", 1, true))
end)

test("settings keeps only the main camera running and returning reuses its frame", function()
    local h = selectedBoot()
    h:command("open")
    h:reply(h:find("/api/front/latest.jpg"), "\255\216\255main\255\217")
    h:command("next")
    local side = h:find("/api/side/latest.jpg")
    h:command("preview", false)
    h:reply(side, "\255\216\255old\255\217")
    h.time = h.time + 200
    h.env.update()
    local i = h:find("latest.jpg")
    assert(h.requests[i].request.url:find("/api/front/latest.jpg", 1, true))
    h:reply(i, "\255\216\255warm\255\217")
    assert(h.state.viewer.frame == "")
    h:command("preview", true)
    h:reply(h:find("/api/side/latest.jpg"), "\255\216\255side\255\217")
    h:command("previous")
    assert(h.files[h.state.viewer.frame] == "\255\216\255warm\255\217")
end)

test("keyring lookup failures do not issue unauthenticated requests", function()
    local h = boot({ keyring = true })
    h.commands[1].callback({ exitCode = 2, stdout = "", timedOut = true })
    h.commands[2].callback({ exitCode = 1, stdout = "" })
    h.time = h.time + 30000
    h.env.update()
    assert(#h.requests == 0 and h.state.viewer.problem == "keyringFailed")
end)

test("rejected HTTP starts back off instead of spinning", function()
    local h = selectedBoot()
    h:reply(h:find("latest.jpg"), "\255\216\255ok\255\217")
    h.time = h.time + 200
    h.rejectHttp = true
    h.env.update()
    assert(h.state.viewer.problem == "cannotReachServer")
    h.rejectHttp = false
    local before = #h.requests
    h.time = h.time + 1000
    h.env.update()
    assert(#h.requests == before)
    h.time = h.time + 1000
    h.env.update()
    assert(#h.requests == before + 1)
end)

test("startup preserves an unreadable selection file instead of overwriting it", function()
    local h = boot({ files = { ["/data/viewer.json"] = "broken-json" } })
    assert(h.files["/data/viewer.json"] == "broken-json")
end)

test("failed selection persistence preserves the last save and notifies", function()
    local h = selectedBoot()
    local original = h.files["/data/viewer.json"]
    h:command("discover")
    h:reply(h:find("/api/config"), { cameras = { front = {}, side = {} } })
    h.writeFail = true
    h:command("toggle", "front")
    assert(h.files["/data/viewer.json"] == original)
    assert(h.notification == "saveFailed")
end)

test("clearing the URL stops future requests and discards pending frames", function()
    local h = selectedBoot()
    h:command("open")
    local oldFrame = h:find("latest.jpg")
    h:setUrl("")
    local before = #h.requests
    h:reply(oldFrame, "\255\216\255old\255\217")
    h.time = h.time + 60000
    h.env.update()
    assert(#h.requests == before and h.state.viewer.frame == "" and h.state.viewer.problem == "noUrlConfigured")
end)

test("retry reloads keyring credentials after a failed lookup", function()
    local h = boot({ keyring = true })
    h.commands[1].callback({ exitCode = 2, stdout = "" })
    h.commands[2].callback({ exitCode = 1, stdout = "" })
    assert(h.state.viewer.problem == "keyringFailed" and #h.requests == 0)
    h:command("retry")
    h.commands[3].callback({ exitCode = 1, stdout = "" })
    h.commands[4].callback({ exitCode = 1, stdout = "" })
    h:reply(h:find("/api/version"), "0.16.0")
    assert(h.state.viewer.problem == "" and h.state.viewer.credentialsReady)
end)

test("snapshot saves a full-resolution recording frame into the localized pictures dir", function()
    local h = selectedBoot({ files = {
        ["/data/viewer.json"] = { frigateUrl = "https://frigate.example.com", selectedCameras = { "front door" } },
        ["/config/user-dirs.dirs"] = '# comment\nXDG_PICTURES_DIR="$HOME/Imagens"\n',
    } })
    h.api.expandPath = function(path) return (path:gsub("^~", "/home/u")) end
    h:command("open")
    h:command("snapshot")
    local i = h:find("/snapshot.jpg")
    assert(h.requests[i].request.url:find("/api/front%%20door/recordings/%d+/snapshot%.jpg$") and h.state.viewer.savingSnapshot)
    -- No recording yet: fall back to the live detect frame; a bad body there is reported.
    h:reply(i, '{"detail":"Not Found"}', 404)
    h:reply(h:find("/latest.jpg?quality=95"), "<html>login</html>")
    assert(h.notification == "snapshotSaveFailed" and h.state.viewer.savedSnapshot == "")
    h:command("snapshot")
    h:reply(h:find("/snapshot.jpg"), "\255\216\255full\255\217")
    local saved = h.state.viewer.savedSnapshot
    assert(saved:match("^/home/u/Imagens/cameras/front_door%-%d+%-%d+%-%d+_%d+%-%d+%-%d+%.jpg$"), saved)
    assert(h.files[saved] == "\255\216\255full\255\217" and not h.state.viewer.savingSnapshot)
    h:command("next")
    assert(h.state.viewer.savedSnapshot == "")
end)

print(count .. " service checks passed")
