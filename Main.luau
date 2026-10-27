--!nonstrict
local state = noctalia.state
local dataDir = noctalia.pluginDataDir()
local savedPath = dataDir and (dataDir .. "/viewer.json")
local function readObject(path)
    local text = path and noctalia.readFile(path)
    local value = text and noctalia.json.decode(text)
    return type(value) == "table" and value or nil
end
local savedFileExists = savedPath and noctalia.fileExists(savedPath)
local saved = readObject(savedPath)
if not saved then
    local configDir = noctalia.getenv("XDG_CONFIG_HOME") or noctalia.expandPath("~/.config")
    saved = readObject(configDir .. "/noctalia/plugins/noctalia-frigate/settings.json") or {}
end

-- Only whitelisted keys are copied; legacy files may hold secrets.
local serverUrl = type(saved.frigateUrl) == "string" and saved.frigateUrl or ""
local defaultCamera = type(saved.defaultCamera) == "string" and saved.defaultCamera or ""
-- Until the user picks cameras, every discovered camera is shown.
local autoSelect = type(saved.selectedCameras) ~= "table"
local selected = {}
local seen = {}
for _, name in ipairs(autoSelect and {} or saved.selectedCameras) do
    if type(name) == "string" and name ~= "" and name ~= "birdseye" and not seen[name] then
        table.insert(selected, name)
        seen[name] = true
    end
end
local cameras = {}
local detectHeights = {}
local index = 1
local opened = false
local previewVisible = true
local frame = ""
local files = {}
local frameSerial = 0
local epoch = 0
local frameEpoch = 0
local pending = {}
local frameInFlight = false
local nextFrameAt = 0
local nextHealthAt = 0
local failures = 0
local connected = false
local version = ""
-- problem: connection/setup error shown as the panel state; message: preview error caption.
local problem = ""
local problemParams = {}
local message = ""
local savedSnapshot = ""
local username, password = "", ""
local credentialsReady = false
local credentialGeneration = 0
local baseUrl = ""
local urlError = ""
local urlDraft = serverUrl
local urlApplyAt = nil
local runtimeDir = noctalia.getenv("XDG_RUNTIME_DIR")
local frameDir = runtimeDir and (runtimeDir .. "/noctalia-frigate-" .. tostring(noctalia.nowMs()))
if frameDir and not noctalia.mkdirAll(frameDir) then frameDir = nil end

local function currentCamera()
    return selected[index] or ""
end

local function resetCamera()
    index = 1
    for i, name in ipairs(selected) do
        if name == defaultCamera then index = i; break end
    end
end

local function publish()
    state.set("viewer", {
        camera = currentCamera(), index = index, cameras = cameras, selected = selected,
        connected = connected, version = version, frame = frame, message = message,
        problem = problem, problemParams = problemParams, opened = opened,
        url = serverUrl, defaultCamera = defaultCamera,
        credentialsReady = credentialsReady, hasCredentials = username ~= "",
        savedSnapshot = savedSnapshot, savingSnapshot = pending.snapshot ~= nil,
    })
end

local function persist()
    if not savedPath then
        message = "saveFailed"
        noctalia.notifyError(noctalia.tr("title"), noctalia.tr("saveFailed"))
        return
    end
    local text = noctalia.json.encode({
        frigateUrl = serverUrl,
        defaultCamera = defaultCamera,
        selectedCameras = not autoSelect and selected or nil,
    })
    local temp = savedPath .. ".tmp"
    if not text or not noctalia.writeFile(temp, text) or not noctalia.renameFile(temp, savedPath) then
        message = "saveFailed"
        noctalia.notifyError(noctalia.tr("title"), noctalia.tr("saveFailed"))
        noctalia.removeFile(temp)
    end
end

local function clearFrames()
    frameEpoch = frameEpoch + 1
    frame = ""
    savedSnapshot = ""
    failures = 0
    nextFrameAt = 0
    for _, path in ipairs(files) do noctalia.removeFile(path) end
    files = {}
end

local function configureUrl()
    local value = noctalia.string.trim(serverUrl)
    urlError = ""
    if value == "" then baseUrl = ""; urlError = "noUrlConfigured"; return end
    if not value:find("://", 1, true) then value = "https://" .. value end
    local authority = value:match("^https?://([^/%?#]+)")
    if not authority or authority:find("@", 1, true) or value:find("[%s%?#%c]") then
        baseUrl = ""
        urlError = "invalidUrl"
        return
    end
    baseUrl = value:gsub("/+$", "")
end

local function request(path, operation, callback)
    if baseUrl == "" or not credentialsReady or pending[operation] then return false end
    local token = {}
    local generation = epoch
    pending[operation] = token
    local accepted = noctalia.http({
        url = baseUrl .. path,
        basic_username = username ~= "" and username or nil,
        basic_password = username ~= "" and password or nil,
        follow_redirects = false,
    }, function(response)
        if generation ~= epoch or pending[operation] ~= token then return end
        pending[operation] = nil
        callback(response)
    end)
    if not accepted then
        pending[operation] = nil
        callback({ ok = false, status = 0, body = "" })
    end
    return accepted
end

local function responseError(response)
    if response.status == 401 or response.status == 403 then return "authFailed" end
    if not response.ok or response.status == 0 then return "cannotReachServer" end
    if response.status < 200 or response.status >= 300 then return "httpError" end
    return nil
end

local function fail(err, response)
    connected = false
    problem = err
    problemParams = { status = response and response.status or 0 }
end

local requestFrame

local function discover()
    request("/api/config", "cameras", function(response)
        local err = responseError(response)
        local value = not err and noctalia.json.decode(response.body)
        if err then
            fail(err, response)
        elseif type(value) ~= "table" or type(value.cameras) ~= "table" then
            fail("invalidResponse", response)
        else
            local discovered = {}
            detectHeights = {}
            for name, camera in pairs(value.cameras) do
                if type(name) == "string" and type(camera) == "table" and name ~= "birdseye" then
                    table.insert(discovered, name)
                    detectHeights[name] = type(camera.detect) == "table" and tonumber(camera.detect.height) or nil
                end
            end
            table.sort(discovered)
            cameras = discovered
            connected = true
            problem = ""
            if autoSelect and #discovered > 0 then
                autoSelect = false
                selected = { table.unpack(discovered) }
                resetCamera()
                persist()
            end
        end
        publish()
        requestFrame()
    end)
end

local function health()
    nextHealthAt = noctalia.nowMs() + 30000
    request("/api/version", "health", function(response)
        local err = responseError(response)
        if err then
            fail(err, response)
            -- Reconnect quickly while the panel is open (closed update ticks are 30 s).
            nextHealthAt = noctalia.nowMs() + 5000
        else
            local value = noctalia.json.decode(response.body)
            version = noctalia.string.trim(tostring(type(value) == "table" and value.version or response.body or "")):sub(1, 32)
            connected = true
            problem = ""
            if #cameras == 0 then discover() end
        end
        publish()
    end)
end

requestFrame = function()
    if not opened or not previewVisible or not credentialsReady or baseUrl == "" or currentCamera() == "" or frameInFlight then return end
    if not frameDir then message = "runtimeUnavailable"; publish(); return end
    local generation, cameraGeneration = epoch, frameEpoch
    -- latest.jpg is the detect frame; asking for more than its height only upscales it.
    local height = math.min(detectHeights[currentCamera()] or 640, 720)
    frameInFlight = true
    local accepted = noctalia.http({
        url = baseUrl .. "/api/" .. noctalia.string.urlEncode(currentCamera())
            .. "/latest.jpg?height=" .. tostring(height) .. "&quality=90&t=" .. tostring(noctalia.nowMs()),
        basic_username = username ~= "" and username or nil,
        basic_password = username ~= "" and password or nil,
        follow_redirects = false,
    }, function(response)
        frameInFlight = false
        if generation ~= epoch or cameraGeneration ~= frameEpoch or not opened or not previewVisible then
            requestFrame()
            return
        end
        local netErr = responseError(response)
        local err = netErr
        -- Reject login pages and truncated JPEGs before handing data to the host decoder.
        local jpeg = response.body or ""
        if not err and (jpeg:sub(1, 3) ~= "\255\216\255" or jpeg:sub(-2) ~= "\255\217") then
            err = "streamError"
        end
        if not err then
            frameSerial = frameSerial + 1
            local path = frameDir .. "/frame-" .. tostring(frameSerial) .. ".jpg"
            if noctalia.writeFile(path, jpeg) then
                frame = path
                table.insert(files, path)
                -- Unique paths force native image reloads; keep only current + previous frame.
                while #files > 2 do noctalia.removeFile(table.remove(files, 1)) end
                failures = 0
                connected = true
                problem = ""
                message = ""
                nextFrameAt = noctalia.nowMs() + 1000
                publish()
                return
            end
            noctalia.removeFile(path)
            err = "snapshotWriteFailed"
        end
        failures = math.min(failures + 1, 5)
        nextFrameAt = noctalia.nowMs() + math.min(30000, 2000 * 2 ^ (failures - 1))
        if netErr == "authFailed" or netErr == "cannotReachServer" then
            fail(netErr, response)
        else
            -- A single camera failing (offline, 404, bad image) is not a server problem.
            message = err == "snapshotWriteFailed" and err or "streamError"
        end
        publish()
    end)
    if not accepted then
        frameInFlight = false
        failures = math.min(failures + 1, 5)
        nextFrameAt = noctalia.nowMs() + math.min(30000, 2000 * 2 ^ (failures - 1))
        fail("cannotReachServer")
        publish()
    end
end

-- XDG_PICTURES_DIR is localized (e.g. ~/Imagens), so read user-dirs.dirs instead of assuming ~/Pictures.
local function snapshotDir()
    local home = noctalia.expandPath("~")
    local configDir = noctalia.getenv("XDG_CONFIG_HOME") or (home .. "/.config")
    local dirs = noctalia.readFile(configDir .. "/user-dirs.dirs") or ""
    local dir = ("\n" .. dirs):match('\nXDG_PICTURES_DIR="([^"]+)"')
    dir = dir and dir:gsub("^%$HOME", home) or (home .. "/Pictures")
    return dir .. "/cameras"
end

local function saveSnapshot(live)
    local camera = currentCamera()
    if camera == "" then return end
    -- Recording frames are full resolution but only exist once the ~10 s segment is written; latest.jpg is detect-sized.
    local frameTime = os.time() - (live and 0 or 30)
    local path = live and ("/latest.jpg?quality=95&t=" .. tostring(noctalia.nowMs()))
        or ("/recordings/" .. tostring(frameTime) .. "/snapshot.jpg")
    local accepted = request("/api/" .. noctalia.string.urlEncode(camera) .. path, "snapshot", function(response)
        local jpeg = response.body or ""
        local valid = not responseError(response) and jpeg:sub(1, 3) == "\255\216\255" and jpeg:sub(-2) == "\255\217"
        if not valid and not live then saveSnapshot(true); return end
        local dir = snapshotDir()
        local file = dir .. "/" .. camera:gsub("[^%w%-_]", "_") .. "-" .. os.date("%Y-%m-%d_%H-%M-%S", frameTime) .. ".jpg"
        if valid and noctalia.mkdirAll(dir) and noctalia.writeFile(file, jpeg) then
            savedSnapshot = file
        else
            noctalia.notifyError(noctalia.tr("title"), noctalia.tr("snapshotSaveFailed"))
        end
        publish()
    end)
    if accepted then publish() end
end

-- Health success discovers cameras when none are known yet.
local function connect()
    health()
    requestFrame()
end

local function loadCredentials()
    credentialGeneration = credentialGeneration + 1
    local generation = credentialGeneration
    credentialsReady = false
    username, password = "", ""
    problem = urlError
    publish()
    if not noctalia.commandExists("secret-tool") then
        credentialsReady = true
        connect()
        return
    end
    local remaining = 2
    local failed = false
    for _, key in ipairs({ "username", "password" }) do
        local function done(result)
            if generation ~= credentialGeneration then return end
            if result.exitCode == 0 and not result.stdoutTruncated then
                local value = result.stdout:gsub("\n$", "")
                if key == "username" then username = value else password = value end
            elseif result.exitCode ~= 1 or result.timedOut or result.stdoutTruncated then
                failed = true
            end
            remaining = remaining - 1
            if remaining == 0 then
                credentialsReady = not failed
                if failed then problem = "keyringFailed"; publish(); return end
                connect()
            end
        end
        if not noctalia.runAsync({ "secret-tool", "lookup", "service", "noctalia-frigate", "key", key }, done, 5000) then
            done({ exitCode = -1 })
        end
    end
end

local function applyUrl()
    urlApplyAt = nil
    if urlDraft == serverUrl then return end
    serverUrl = urlDraft
    persist()
    epoch = epoch + 1
    pending = {}
    connected = false
    version = ""
    clearFrames()
    local oldUrl = baseUrl
    configureUrl()
    if oldUrl ~= baseUrl then cameras = {} end
    problem = urlError
    publish()
    connect()
end

function update()
    local now = noctalia.nowMs()
    if urlApplyAt and now >= urlApplyAt then applyUrl() end
    if credentialsReady and now >= nextHealthAt then health() end
    if opened and previewVisible and now >= nextFrameAt then requestFrame() end
end

state.watch("command", function(command)
    if type(command) ~= "table" then return end
    state.set("command", nil)
    local action = command.action
    if action == "ring" then
        state.set("panelPage", "viewer")
        if not opened then
            noctalia.togglePanel("pir0c0pter0/frigate:viewer")
            return
        end
        action = "open"
    end
    if action == "open" then
        opened = true
        previewVisible = true
        clearFrames()
        resetCamera()
        message = ""
        noctalia.setUpdateInterval(1000)
        publish()
        connect()
    elseif action == "close" then
        opened = false
        if urlApplyAt then applyUrl() end
        clearFrames()
        noctalia.setUpdateInterval(30000)
        publish()
    elseif action == "preview" then
        previewVisible = command.value == true
        clearFrames()
        publish()
        requestFrame()
    elseif action == "next" or action == "previous" then
        if #selected > 0 then
            index = (index - 1 + (action == "next" and 1 or -1)) % #selected + 1
            clearFrames()
            message = ""
            publish()
            requestFrame()
        end
    elseif action == "toggle" then
        local name = command.value
        local found = false
        for _, camera in ipairs(cameras) do if camera == name then found = true; break end end
        if not found then return end
        local nextSelected = {}
        local included = false
        for _, camera in ipairs(selected) do
            if camera == name then included = true else table.insert(nextSelected, camera) end
        end
        if not included then table.insert(nextSelected, name) end
        selected = nextSelected
        autoSelect = false
        resetCamera()
        clearFrames()
        message = ""
        persist()
        publish()
        requestFrame()
    elseif action == "default" then
        if type(command.value) ~= "string" then return end
        defaultCamera = command.value
        persist()
        publish()
    elseif action == "url" then
        if type(command.value) ~= "string" then return end
        -- Debounced so typing does not fire a request per keystroke.
        urlDraft = command.value
        urlApplyAt = noctalia.nowMs() + 800
    elseif action == "snapshot" then
        saveSnapshot(false)
    elseif action == "discover" then
        discover()
    elseif action == "retry" or action == "reloadCredentials" then
        epoch = epoch + 1
        pending = {}
        clearFrames()
        loadCredentials()
    end
end)

function onIpc(event)
    if event == "refresh" then state.set("command", { action = "reloadCredentials" }) end
end

function onExit()
    opened = false
    epoch = epoch + 1
    credentialGeneration = credentialGeneration + 1
    clearFrames()
    -- The host cancels outstanding HTTP work when this runtime unloads.
end

configureUrl()
resetCamera()
problem = urlError
if not savedFileExists then persist() end
publish()
noctalia.setUpdateInterval(30000)
loadCredentials()
