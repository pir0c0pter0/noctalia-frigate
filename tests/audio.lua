local state, watchers, requests, files, commands = {}, {}, {}, {}, {}
local now = 1000
local json = {}
local api = {
    pluginDataDir = function() return "/data" end,
    pluginDir = function() return "/plugin" end,
    nowMs = function() return now end,
    setUpdateInterval = function() end,
    readFile = function(path) return files[path] end,
    writeFile = function(path, value) files[path] = value; return true end,
    renameFile = function(a, b) files[b] = files[a]; files[a] = nil; return true end,
    removeFile = function(path) files[path] = nil end,
    fileInfo = function(path) if path == "/clip.ogg" then return { size = 100, isDir = false } end end,
    commandExists = function() return true end,
    runAsync = function(argv, cb) commands[#commands + 1] = { argv = argv, cb = cb }; return true end,
    http = function(req, cb) requests[#requests + 1] = { req = req, cb = cb }; return true end,
    tr = function(k) return k end,
    log = function() end,
    notifyError = function(_, msg) state.notification = msg end,
    json = { encode = function(v) json.value = v; return "encoded" end,
        decode = function(v) if v == "encoded" then return json.value end; return v end },
    string = { trim = function(s) return s:match("^%s*(.-)%s*$") end,
        urlEncode = function(s) return (s:gsub("([^%w%-_%.~])", function(c) return string.format("%%%02X", c:byte()) end)) end },
    state = { get = function(k) return state[k] end, set = function(k, v) state[k] = v; if watchers[k] then watchers[k](v) end end,
        watch = function(k, cb) watchers[k] = cb end },
}
local env = setmetatable({ noctalia = api }, { __index = _G })
assert(loadfile("Audio.luau", "t", env))()
local function cmd(action, value) api.state.set("audioCommand", { action = action, value = value }) end
cmd("url", "http://go2rtc.local:1984")
cmd("stream", "door bell")
cmd("file", "/clip.ogg")
cmd("peer", "192.0.2.2")
cmd("play")
assert(#commands == 1 and state.audio.status == "audioStarting")
assert(commands[1].argv[6] == "192.0.2.2")
cmd("play")
assert(#commands == 1)
files[commands[1].argv[5]] = { url = "http://192.0.2.1:4444/clip" }
env.update()
assert(#requests == 1 and requests[1].req.method == "POST")
assert(requests[1].req.url:find("/api/streams?", 1, true))
assert(requests[1].req.url:find("dst=door%%20bell"))
assert(requests[1].req.url:find("ffmpeg%%3Ahttp%%3A", 1) and requests[1].req.url:find("%%23input%%3Dfile"))
assert(requests[1].req.url:find("%%23audio%%3Dpcmu"))
requests[1].cb({ ok = true, status = 200 })
assert(state.audio.status == "audioSent")
commands[1].cb({ exitCode = 0 })
api.state.set("command", { action = "ring" })
assert(#commands == 1, "doorbell audio waits for the camera's chime")
now = now + 3999
env.update()
assert(#commands == 1, "doorbell audio must not start before four seconds")
api.state.set("command", { action = "ring" })
now = now + 1
env.update()
assert(#commands == 2 and state.audio.status == "audioStarting", "duplicate rings do not postpone or duplicate playback")
commands[2].cb({ exitCode = 1 })
cmd("file", "/missing.ogg")
cmd("play")
assert(state.audio.status == "audioFileInvalid" and #commands == 2)
cmd("file", "/clip.ogg")
cmd("peer", "ssh:server:/srv/frigate/config")
cmd("play")
assert(#commands == 3)
files[commands[3].argv[5]] = { file = "/config/noctalia-audio-ab12.ogg" }
env.update()
assert(requests[2].req.url:find("%%2Fconfig%%2Fnoctalia%-audio%-ab12%.ogg"))
requests[2].cb({ ok = true, status = 200 })
assert(files[commands[3].argv[5] .. ".done"] == "done")
commands[3].cb({ exitCode = 0 })
env.onIpc("test-ring")
assert(#commands == 3, "ring IPC also waits for the chime")
now = now + 4000
env.update()
assert(#commands == 4, "ring IPC starts playback after the chime")
api.state.set("command", { action = "ring" })
commands[4].cb({ exitCode = 1 })
now = now + 4000
env.update()
assert(#commands == 4, "rings during playback do not queue another response")
api.state.set("command", { action = "ring" })
cmd("play")
assert(#commands == 5, "manual playback stays immediate")
commands[5].cb({ exitCode = 1 })
now = now + 4000
env.update()
assert(#commands == 5, "manual playback cancels the queued automatic response")
api.state.set("command", { action = "ring" })
env.onExit()
now = now + 4000
env.update()
assert(#commands == 5, "stopped services do not play queued responses")
print("audio checks passed")
