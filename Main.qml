import QtQuick
import Quickshell.Io
import "Translation.js" as Translation

Item {
    id: root
    property var pluginApi: null

    readonly property string frigateUrl: pluginApi?.pluginSettings?.frigateUrl ?? ""
    // SEC-3: credentials live in the OS keyring (Secret Service), never in
    // pluginSettings/settings.json. Loaded asynchronously at startup and
    // updated in place by Settings.qml via applyCredentials() on save.
    property string username: ""
    property string password: ""
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

    // ─── Credential keyring (Secret Service via secret-tool) ───
    // SEC-3: username/password are kept in the OS keyring, never written to
    // settings.json. Reads run once at startup; writes run when Settings
    // saves. All access goes through `sh -c` so PATH resolves secret-tool;
    // the secret is handed to the store process via its environment, never
    // on the command line (argv is world-readable via `ps`).
    readonly property string keyringService: "noctalia-frigate"

    // Counts the two startup lookups so the first poll waits for credentials.
    property int credentialLookupsPending: 0

    function loadCredentials() {
        root.credentialLookupsPending = 2
        usernameLookup.running = true
        passwordLookup.running = true
    }

    function noteCredentialLookupDone() {
        if (root.credentialLookupsPending > 0) {
            root.credentialLookupsPending--
        }
        if (root.credentialLookupsPending === 0 && root.frigateUrl) {
            root.pollConnection()
        }
    }

    // Persist credentials to the keyring and update the in-memory copy so an
    // already-open panel picks them up immediately. An empty value clears
    // the corresponding keyring entry.
    function applyCredentials(user, pass) {
        root.username = user
        root.password = pass
        usernameStore.environment = ({
            "NF_SECRET": user
        })
        passwordStore.environment = ({
            "NF_SECRET": pass
        })
        usernameStore.running = true
        passwordStore.running = true
    }

    Process {
        id: usernameLookup
        command: ["sh", "-c", "secret-tool lookup service " + root.keyringService + " key username"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.username = text
                root.noteCredentialLookupDone()
            }
        }
    }

    Process {
        id: passwordLookup
        command: ["sh", "-c", "secret-tool lookup service " + root.keyringService + " key password"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.password = text
                root.noteCredentialLookupDone()
            }
        }
    }

    // SEC-3: store pipes the secret through stdin (printf | secret-tool) so it
    // never appears in argv; an empty value clears the entry instead.
    Process {
        id: usernameStore
        command: ["sh", "-c", "if [ -n \"$NF_SECRET\" ]; then printf '%s' \"$NF_SECRET\" | secret-tool store --label='Noctalia Frigate (username)' service " + root.keyringService + " key username; else secret-tool clear service " + root.keyringService + " key username || true; fi"]
        onExited: code => {
            if (code !== 0) {
                console.warn("noctalia-frigate: failed to store username in keyring (exit " + code + ")")
            }
        }
    }

    Process {
        id: passwordStore
        command: ["sh", "-c", "if [ -n \"$NF_SECRET\" ]; then printf '%s' \"$NF_SECRET\" | secret-tool store --label='Noctalia Frigate (password)' service " + root.keyringService + " key password; else secret-tool clear service " + root.keyringService + " key password || true; fi"]
        onExited: code => {
            if (code !== 0) {
                console.warn("noctalia-frigate: failed to store password in keyring (exit " + code + ")")
            }
        }
    }

    Component.onCompleted: {
        root.ensureValidCurrentCamera()
        // pollConnection() is deferred until the keyring lookups finish
        // (noteCredentialLookupDone) so the first poll is authenticated.
        root.loadCredentials()
    }
}
