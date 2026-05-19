import QtQuick
import "Translation.js" as Translation

Item {
    id: root
    property var pluginApi: null

    readonly property string frigateUrl: pluginApi?.pluginSettings?.frigateUrl ?? ""
    readonly property string username: pluginApi?.pluginSettings?.username ?? ""
    readonly property string password: pluginApi?.pluginSettings?.password ?? ""
    readonly property string defaultCamera: pluginApi?.pluginSettings?.defaultCamera ?? ""
    readonly property bool isPanelOpen: pluginApi?.panelOpenScreen !== null

    property string connectionStatus: "disconnected"
    property var cameraList: []
    property string testResultMessage: ""
    property string testResultStatus: ""

    // Seeded from pluginSettings; kept in sync explicitly by Settings.qml saveSettings() (intentional, not readonly).
    property var selectedCameras: pluginApi?.pluginSettings?.selectedCameras ?? []
    property int currentIndex: 0

    // Independent per-operation request generations; each stale callback compares
    // against ONLY its own counter so a background poll cannot invalidate a
    // foreground test/fetch (and vice versa).
    property int testGeneration: 0
    property int fetchGeneration: 0
    property int pollGeneration: 0
    // In-flight poll XHR, kept for single-flight abort.
    property var pollXhr: null

    readonly property string currentCameraName: {
        if (selectedCameras.length === 0) return ""
        const idx = Math.min(currentIndex, selectedCameras.length - 1)
        return selectedCameras[idx] ?? ""
    }

    readonly property string snapshotBaseUrl: buildAuthUrl("/api/" + encodeURIComponent(currentCameraName) + "/latest.jpg")

    signal camerasLoaded(var cameras)
    signal testCompleted(string status, string message)

    function tr(key, params) {
        return Translation.tr(pluginApi, key, params)
    }

    function indexForCamera(cameraName) {
        return selectedCameras.indexOf(cameraName)
    }

    function defaultCameraIndex() {
        const idx = indexForCamera(defaultCamera)
        return idx !== -1 ? idx : 0
    }

    function ensureValidCurrentCamera() {
        if (selectedCameras.length === 0) {
            currentIndex = 0
            return
        }
        if (currentIndex < 0 || currentIndex >= selectedCameras.length) {
            currentIndex = defaultCameraIndex()
        }
    }

    function resetToDefaultCamera() {
        if (selectedCameras.length === 0) {
            currentIndex = 0
            return
        }
        currentIndex = defaultCameraIndex()
    }

    function buildAuthUrl(path) {
        if (!frigateUrl || !currentCameraName) return ""
        // Never embed credentials in the URL; callers authenticate their own requests.
        const base = frigateUrl.replace(/\/+$/, "")
        return base + path
    }

    function nextCamera() {
        const count = selectedCameras.length
        if (count === 0) return
        currentIndex = (currentIndex + 1) % count
    }

    function prevCamera() {
        const count = selectedCameras.length
        if (count === 0) return
        currentIndex = (currentIndex - 1 + count) % count
    }

    function makeAuthRequest(url, callback) {
        const xhr = new XMLHttpRequest()
        xhr.timeout = 10000
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status >= 200 && xhr.status < 300) {
                    const text = xhr.responseText
                    try {
                        callback(null, JSON.parse(text), xhr.status)
                    } catch (e) {
                        callback(null, text, xhr.status)
                    }
                } else if (xhr.status === 401) {
                    callback(root.tr("authFailed"), null, 401)
                } else if (xhr.status === 0) {
                    callback(root.tr("cannotReachServer"), null, 0)
                } else {
                    callback(root.tr("httpError", {
                        "status": xhr.status,
                        "statusText": xhr.statusText
                    }), null, xhr.status)
                }
            }
        }
        xhr.ontimeout = function() {
            callback(root.tr("cannotReachServer"), null, 0)
        }
        xhr.open("GET", url, true)
        if (username && password) {
            // UTF-8-encode the credential string so non-ASCII passwords survive base64.
            const credentials = unescape(encodeURIComponent(username + ":" + password))
            xhr.setRequestHeader("Authorization", "Basic " + Qt.btoa(credentials))
        }
        xhr.send()
        return xhr
    }

    function testConnection() {
        if (!frigateUrl) {
            testResultMessage = root.tr("noUrlConfigured")
            testResultStatus = "error"
            testCompleted("error", testResultMessage)
            return
        }
        testResultMessage = root.tr("testing")
        testResultStatus = "testing"

        const generation = ++root.testGeneration
        const url = frigateUrl.replace(/\/+$/, "") + "/api/version"
        makeAuthRequest(url, function(err, data) {
            if (generation !== root.testGeneration) return
            if (err) {
                testResultMessage = err
                testResultStatus = "error"
                root.connectionStatus = "disconnected"
            } else {
                // /api/version may return JSON or plain text.
                const version = (data && data.version) ? data.version : (data ?? "unknown")
                testResultMessage = root.tr("connectedVersion", {
                    "version": version
                })
                testResultStatus = "ok"
                root.connectionStatus = "connected"
            }
            testCompleted(testResultStatus, testResultMessage)
        })
    }

    function fetchCameras() {
        if (!frigateUrl) {
            testResultMessage = root.tr("noUrlConfigured")
            testResultStatus = "error"
            return
        }

        const generation = ++root.fetchGeneration
        const url = frigateUrl.replace(/\/+$/, "") + "/api/config"
        makeAuthRequest(url, function(err, data) {
            if (generation !== root.fetchGeneration) return
            if (err) {
                testResultMessage = root.tr("fetchCamerasFailed", {
                    "error": err
                })
                testResultStatus = "error"
                return
            }
            // /api/config must return a JSON object with a `cameras` field;
            // a non-JSON / unexpected payload (raw text passthrough) is a failure.
            if (typeof data !== "object" || data === null || typeof data.cameras !== "object" || data.cameras === null) {
                testResultMessage = root.tr("fetchCamerasFailed", {
                    "error": root.tr("invalidResponse")
                })
                testResultStatus = "error"
                return
            }
            const cameras = Object.keys(data.cameras)
            const filtered = cameras.filter(function(name) {
                return name !== "birdseye"
            })
            root.cameraList = filtered
            camerasLoaded(filtered)
        })
    }

    function pollConnection() {
        if (!frigateUrl) {
            connectionStatus = "disconnected"
            return
        }
        // Bump the poll generation BEFORE aborting: an aborted XHR still fires
        // onreadystatechange with readyState === DONE and status === 0, which
        // would otherwise mark the connection "disconnected". Incrementing first
        // ensures that stale abort callback fails its generation check.
        const generation = ++root.pollGeneration
        // Single-flight: abort any still-pending poll before starting a new one.
        if (root.pollXhr !== null) {
            root.pollXhr.abort()
            root.pollXhr = null
        }
        const url = frigateUrl.replace(/\/+$/, "") + "/api/version"
        root.pollXhr = makeAuthRequest(url, function(err) {
            if (generation !== root.pollGeneration) return
            root.pollXhr = null
            root.connectionStatus = err ? "disconnected" : "connected"
        })
    }

    onSelectedCamerasChanged: root.ensureValidCurrentCamera()

    onDefaultCameraChanged: {
        if (root.isPanelOpen) {
            root.resetToDefaultCamera()
        } else {
            root.ensureValidCurrentCamera()
        }
    }

    onIsPanelOpenChanged: {
        if (root.isPanelOpen) {
            root.resetToDefaultCamera()
        }
    }

    Timer {
        id: connectionPoller
        interval: 30000
        repeat: true
        running: root.frigateUrl !== ""
        onTriggered: root.pollConnection()
    }

    Component.onCompleted: {
        root.ensureValidCurrentCamera()
        if (frigateUrl) {
            pollConnection()
        }
    }
}
