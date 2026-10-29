--!nonstrict
local state = noctalia.state
local dataDir = noctalia.pluginDataDir()
local savedPath = dataDir and dataDir .. "/audio.json"
local infoPath = nil
local saved = savedPath and noctalia.readFile(savedPath)
saved = saved and noctalia.json.decode(saved) or {}
if type(saved) ~= "table" then saved = {} end
local url = type(saved.url) == "string" and saved.url or ""
local stream = type(saved.stream) == "string" and saved.stream or ""
local file = type(saved.file) == "string" and saved.file or ""
local peer = type(saved.peer) == "string" and saved.peer or ""
local status, busy, requested, alive = "audioIdle", false, false, true
local serverDone, httpDone = false, false
local serial, startedAt = 0, 0

local function publish()
    state.set("audio", { url = url, stream = stream, file = file, peer = peer, status = status, busy = busy })
end

local function persist()
    local text = noctalia.json.encode({ url = url, stream = stream, file = file, peer = peer })
    local temp = savedPath and savedPath .. ".tmp"
    if not text or not temp or not noctalia.writeFile(temp, text) or not noctalia.renameFile(temp, savedPath) then
        if temp then noctalia.removeFile(temp) end
        noctalia.notifyError(noctalia.tr("title"), noctalia.tr("saveFailed"))
    end
end

local function validUrl(value)
    local authority = value:match("^https?://([%w%.%-]+:?%d*)$")
    if not authority then return false end
    local port = authority:match(":(%d+)$")
    return not port or (tonumber(port) >= 1 and tonumber(port) <= 65535)
end

local function play()
    if busy then return end
    local info = file:sub(1, 1) == "/" and noctalia.fileInfo(file)
    local sshPeer = peer:match("^ssh:[%w%.%-_]+:/[%w%._%-%/]+$")
    if not validUrl(url) or stream == "" or (peer ~= "" and not peer:match("^[%w%.%-]+$") and not sshPeer) then status = "audioConfigInvalid"
    elseif not info or info.isDir or not info.size or info.size <= 0 or info.size > 10485760 then status = "audioFileInvalid"
    elseif not dataDir or not noctalia.pluginDir() or not noctalia.commandExists("python3") then status = "audioUnavailable"
    else
        serial = serial + 1
        local current = serial
        busy, requested, status, startedAt = true, false, "audioStarting", noctalia.nowMs()
        serverDone, httpDone = false, false
        infoPath = dataDir .. "/audio-server-" .. tostring(startedAt) .. "-" .. tostring(current) .. ".json"
        local ownInfoPath = infoPath
        local accepted = noctalia.runAsync({ "python3", noctalia.pluginDir() .. "/AudioServer.py", url, file, ownInfoPath, peer }, function(result)
            if not alive or current ~= serial then return end
            serverDone = true
            busy = false
            if result.exitCode ~= 0 or result.timedOut then status = "audioFailed" end
            if requested and not httpDone then status = "audioFailed" end
            noctalia.log(result.exitCode == 0 and not result.timedOut and "audio: file delivered" or "audio: file delivery failed")
            noctalia.removeFile(ownInfoPath)
            publish()
        end, 45000)
        if not accepted then busy, status = false, "audioFailed" end
    end
    publish()
end

function update()
    if not alive or not busy or requested then return end
    local text = noctalia.readFile(infoPath)
    local info = text and noctalia.json.decode(text)
    local source = type(info) == "table" and ((type(info.url) == "string" and info.url:match("^http://[%d%.]+:%d+/clip$") and info.url)
        or (type(info.file) == "string" and info.file:match("^/config/noctalia%-audio%-[%w%-]+%.ogg$") and info.file))
    if source then
        requested = true
        local current = serial
        local src = "ffmpeg:" .. source .. "#audio=pcmu#input=file"
        local endpoint = url .. "/api/streams?dst=" .. noctalia.string.urlEncode(stream) .. "&src=" .. noctalia.string.urlEncode(src)
        local accepted = noctalia.http({ url = endpoint, method = "POST", follow_redirects = false }, function(response)
            if not alive or current ~= serial then return end
            if status ~= "audioFailed" then
                status = response.ok and response.status >= 200 and response.status < 300 and "audioSent" or "audioFailed"
            end
            noctalia.log(status == "audioSent" and "audio: playback requested" or ("audio: playback failed (HTTP " .. tostring(response.status) .. ")"))
            httpDone = true
            if peer:match("^ssh:") then noctalia.writeFile(infoPath .. ".done", "done") end
            if serverDone then busy = false end
            publish()
        end)
        if not accepted then
            httpDone, status = true, "audioFailed"
            if peer:match("^ssh:") then noctalia.writeFile(infoPath .. ".done", "done") end
            if serverDone then busy = false end
            publish()
        end
    elseif noctalia.nowMs() - startedAt > 20000 then
        requested, httpDone, status = true, true, "audioFailed"
        publish()
    end
end

state.watch("audioCommand", function(command)
    if type(command) ~= "table" then return end
    state.set("audioCommand", nil)
    if command.action == "play" then play(); return end
    if busy or type(command.value) ~= "string" then return end
    local value = noctalia.string.trim(command.value)
    if command.action == "url" then url = value:gsub("/+$", "")
    elseif command.action == "stream" then stream = value
    elseif command.action == "file" then file = value
    elseif command.action == "peer" then peer = value
    else return end
    status = "audioIdle"
    persist(); publish()
end)

state.watch("command", function(command)
    if type(command) == "table" and command.action == "ring" then
        noctalia.log("audio: doorbell event received")
        play()
    end
end)

function onIpc(event)
    if event == "play" then play() end
    if event == "test-ring" then state.set("command", { action = "ring" }) end
end

function onExit()
    alive = false
    serial = serial + 1
end

noctalia.setUpdateInterval(250)
publish()
