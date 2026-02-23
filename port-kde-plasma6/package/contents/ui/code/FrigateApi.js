.pragma library

function normalizeBaseUrl(rawUrl) {
    var value = rawUrl || ""
    value = String(value).trim()
    return value.replace(/\/+$/, "")
}

function toStringArray(value) {
    if (!value || value.length === undefined) {
        return []
    }

    var out = []
    for (var i = 0; i < value.length; i++) {
        var item = value[i]
        if (item === null || item === undefined) {
            continue
        }
        var text = String(item)
        if (text.length > 0) {
            out.push(text)
        }
    }
    return out
}

function hasCredentials(username, password) {
    return String(username || "") !== "" && String(password || "") !== ""
}

function encodeCredential(value) {
    return encodeURIComponent(String(value || ""))
}

function buildAuthUrl(baseUrl, path, username, password) {
    var base = normalizeBaseUrl(baseUrl)
    if (!base) {
        return ""
    }

    var safePath = path || ""
    if (safePath && safePath.charAt(0) !== "/") {
        safePath = "/" + safePath
    }

    if (!hasCredentials(username, password)) {
        return base + safePath
    }

    var protocol = "http"
    if (base.indexOf("https://") === 0) {
        protocol = "https"
    }

    var rest = base.replace(/^https?:\/\//, "")
    var encodedUser = encodeCredential(username)
    var encodedPass = encodeCredential(password)

    return protocol + "://" + encodedUser + ":" + encodedPass + "@" + rest + safePath
}

function orderedSelection(selectedCameras, cameraOrder) {
    var selected = toStringArray(selectedCameras)
    var order = toStringArray(cameraOrder)

    if (!selected.length) {
        return []
    }

    var selectedMap = {}
    var i
    for (i = 0; i < selected.length; i++) {
        selectedMap[selected[i]] = true
    }

    var result = []
    var added = {}

    for (i = 0; i < order.length; i++) {
        var camera = order[i]
        if (selectedMap[camera] && !added[camera]) {
            result.push(camera)
            added[camera] = true
        }
    }

    for (i = 0; i < selected.length; i++) {
        camera = selected[i]
        if (!added[camera]) {
            result.push(camera)
            added[camera] = true
        }
    }

    return result
}

function parseCameraList(configPayload) {
    var camerasObj = {}
    if (configPayload && typeof configPayload === "object" && configPayload.cameras) {
        camerasObj = configPayload.cameras
    }

    var names = []
    for (var key in camerasObj) {
        if (!Object.prototype.hasOwnProperty.call(camerasObj, key)) {
            continue
        }
        if (key === "birdseye") {
            continue
        }
        names.push(key)
    }

    names.sort()
    return names
}

function mergeCameraSelection(existingSelection, discoveredCameraList) {
    var selected = toStringArray(existingSelection)
    var discovered = toStringArray(discoveredCameraList)

    var discoveredMap = {}
    for (var i = 0; i < discovered.length; i++) {
        discoveredMap[discovered[i]] = true
    }

    var kept = []
    for (i = 0; i < selected.length; i++) {
        if (discoveredMap[selected[i]]) {
            kept.push(selected[i])
        }
    }

    return kept
}
