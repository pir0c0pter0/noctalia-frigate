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

local selected = {}
local seen = {}
if type(saved.selectedCameras) == "table" then
    for _, name in ipairs(saved.selectedCameras) do
        if type(name) == "string" and name ~= "" and name ~= "birdseye" and not seen[name] then
            table.insert(selected, name)
            seen[name] = true
        end
    end
end
local cameras = {}
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
local message = ""
local messageParams = {}
local username, password = "", ""
local credentialsReady = false
local credentialGeneration = 0
local baseUrl = ""
local urlError = ""
local runtimeDir = noctalia.getenv("XDG_RUNTIME_DIR")
local frameDir = runtimeDir and (runtimeDir .. "/noctalia-frigate-" .. tostring(noctalia.nowMs()))
if frameDir and not noctalia.mkdirAll(frameDir) then frameDir = nil end

local function currentCamera()
    return selected[index] or ""
end

local function resetCamera()
    local preferred = noctalia.getConfig("defaultCamera")
    index = 1
    for i, name in ipairs(selected) do
        if name == preferred then index = i; break end
    end
end

local function publish()
    state.set("viewer", {
        camera = currentCamera(), cameras = cameras, selected = selected,
        connected = connected, frame = frame, message = message,
        credentialsReady = credentialsReady, messageParams = messageParams,
    })
end

local function persist()
    if not savedPath then
        message = "saveFailed"
        noctalia.notifyError(noctalia.tr("title"), noctalia.tr("saveFailed"))
        return
    end
    local text = noctalia.json.encode({
        selectedCameras = selected,
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
    failures = 0
    nextFrameAt = 0
    for _, path in ipairs(files) do noctalia.removeFile(path) end
    files = {}
end

local function configureUrl()
    local value = noctalia.getConfig("frigateUrl")
    value = noctalia.string.trim(value)
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

local function health(explicit)
    nextHealthAt = noctalia.nowMs() + 30000
    if baseUrl == "" then message = urlError; connected = false; publish(); return end
    if not credentialsReady then publish(); return end
    if explicit then message = "testing"; publish() end
    request("/api/version", explicit and "test" or "health", function(response)
        local err = responseError(response)
        connected = err == nil
        if explicit then
            local value = noctalia.json.decode(response.body)
            local version = type(value) == "table" and value.version or response.body
            message = err or "connectedVersion"
            messageParams = { status = response.status, version = tostring(version) }
        end
        publish()
    end)
end

local function discover()
    if baseUrl == "" then message = urlError; publish(); return end
    request("/api/config", "cameras", function(response)
        local err = responseError(response)
        local value = not err and noctalia.json.decode(response.body)
        if err then
            message = err
            messageParams = { status = response.status }
        elseif type(value) ~= "table" or type(value.cameras) ~= "table" then
            message = "invalidResponse"
        else
            local discovered = {}
            for name, camera in pairs(value.cameras) do
                if type(name) == "string" and type(camera) == "table" and name ~= "birdseye" then
                    table.insert(discovered, name)
                end
            end
            table.sort(discovered)
            cameras = discovered
            message = ""
        end
        publish()
    end)
end

local requestFrame
requestFrame = function()
    if not opened or not previewVisible or not credentialsReady or baseUrl == "" or currentCamera() == "" or frameInFlight then return end
    if not frameDir then message = "runtimeUnavailable"; publish(); return end
    local generation, cameraGeneration = epoch, frameEpoch
    frameInFlight = true
    local accepted = noctalia.http({
        url = baseUrl .. "/api/" .. noctalia.string.urlEncode(currentCamera())
            .. "/latest.jpg?height=640&quality=75&t=" .. tostring(noctalia.nowMs()),
        basic_username = username ~= "" and username or nil,
        basic_password = username ~= "" and password or nil,
        follow_redirects = false,
    }, function(response)
        frameInFlight = false
        if generation ~= epoch or cameraGeneration ~= frameEpoch or not opened or not previewVisible then
            requestFrame()
            return
        end
        local err = responseError(response)
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
        if responseError(response) then connected = false end
        message = err
        messageParams = { status = response.status }
        publish()
    end)
    if not accepted then
        frameInFlight = false
        failures = math.min(failures + 1, 5)
        nextFrameAt = noctalia.nowMs() + math.min(30000, 2000 * 2 ^ (failures - 1))
        message = "cannotReachServer"
        publish()
    end
end

local function loadCredentials()
    credentialGeneration = credentialGeneration + 1
    local generation = credentialGeneration
    credentialsReady = false
    username, password = "", ""
    message = urlError
    publish()
    if not noctalia.commandExists("secret-tool") then
        credentialsReady = true
        health(false)
        requestFrame()
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
                if failed then message = "keyringFailed"; publish(); return end
                health(false)
                requestFrame()
            end
        end
        if not noctalia.runAsync({ "secret-tool", "lookup", "service", "noctalia-frigate", "key", key }, done, 5000) then
            done({ exitCode = -1 })
        end
    end
end

function update()
    if credentialsReady and noctalia.nowMs() >= nextHealthAt then health(false) end
    if opened and previewVisible and noctalia.nowMs() >= nextFrameAt then requestFrame() end
end

function onConfigChanged()
    epoch = epoch + 1
    pending = {}
    connected = false
    clearFrames()
    local oldUrl = baseUrl
    configureUrl()
    if oldUrl ~= baseUrl then cameras = {} end
    resetCamera()
    message = urlError
    nextHealthAt = 0
    publish()
    health(false)
    requestFrame()
end

state.watch("command", function(command)
    if type(command) ~= "table" then return end
    state.set("command", nil)
    local action = command.action
    if action == "open" then
        opened = true
        previewVisible = true
        clearFrames()
        resetCamera()
        message = urlError
        noctalia.setUpdateInterval(1000)
        publish()
        health(false)
        requestFrame()
        if #cameras == 0 then discover() end
    elseif action == "close" then
        opened = false
        clearFrames()
        noctalia.setUpdateInterval(30000)
        publish()
    elseif action == "preview" then
        previewVisible = command.value == true
        clearFrames()
        noctalia.setUpdateInterval(opened and previewVisible and 1000 or 30000)
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
        resetCamera()
        clearFrames()
        message = ""
        persist()
        publish()
        requestFrame()
    elseif action == "test" then
        health(true)
    elseif action == "discover" then
        discover()
    elseif action == "reloadCredentials" then
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
message = urlError
if not savedFileExists then persist() end
publish()
noctalia.setUpdateInterval(30000)
loadCredentials()
