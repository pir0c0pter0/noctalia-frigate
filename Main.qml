import QtQuick

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

    property var selectedCameras: pluginApi?.pluginSettings?.selectedCameras ?? []
    property int currentIndex: 0

    readonly property string currentCameraName: {
        if (selectedCameras.length === 0) return ""
        var idx = Math.min(currentIndex, selectedCameras.length - 1)
        return selectedCameras[idx] ?? ""
    }

    readonly property string snapshotBaseUrl: buildAuthUrl("/api/" + encodeURIComponent(currentCameraName) + "/latest.jpg")

    signal camerasLoaded(var cameras)
    signal testCompleted(string status, string message)

    function tr(key, params) {
        var value = pluginApi?.tr(key)
        if (value === undefined || value === null) {
            value = key
        }
        value = String(value)
        if (/^!!.*!!$/.test(value)) {
            value = key
        }
        if (!params) {
            return value
        }
        return value.replace(/\{([a-zA-Z0-9_]+)\}/g, function(match, name) {
            if (Object.prototype.hasOwnProperty.call(params, name)) {
                return String(params[name])
            }
            return match
        })
    }

    function indexForCamera(cameraName) {
        return selectedCameras.indexOf(cameraName)
    }

    function defaultCameraIndex() {
        var idx = indexForCamera(defaultCamera)
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
        var base = frigateUrl.replace(/\/+$/, "")
        if (username && password) {
            var protocol = base.startsWith("https") ? "https" : "http"
            var rest = base.replace(/^https?:\/\//, "")
            var encodedUser = encodeURIComponent(username)
            var encodedPass = encodeURIComponent(password)
            return protocol + "://" + encodedUser + ":" + encodedPass + "@" + rest + path
        }
        return base + path
    }

    function nextCamera() {
        var count = selectedCameras.length
        if (count === 0) return
        currentIndex = (currentIndex + 1) % count
    }

    function prevCamera() {
        var count = selectedCameras.length
        if (count === 0) return
        currentIndex = (currentIndex - 1 + count) % count
    }

    function makeAuthRequest(url, callback) {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status >= 200 && xhr.status < 300) {
                    var text = xhr.responseText
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
        xhr.open("GET", url, true)
        if (username && password) {
            xhr.setRequestHeader("Authorization", "Basic " + Qt.btoa(username + ":" + password))
        }
        xhr.send()
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

        var url = frigateUrl.replace(/\/+$/, "") + "/api/version"
        makeAuthRequest(url, function(err, data) {
            if (err) {
                testResultMessage = err
                testResultStatus = "error"
                root.connectionStatus = "disconnected"
            } else {
                var version = data.version ?? data ?? "unknown"
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

        var url = frigateUrl.replace(/\/+$/, "") + "/api/config"
        makeAuthRequest(url, function(err, data) {
            if (err) {
                testResultMessage = root.tr("fetchCamerasFailed", {
                    "error": err
                })
                testResultStatus = "error"
                return
            }
            var cameras = data.cameras ? Object.keys(data.cameras) : []
            var filtered = cameras.filter(function(name) {
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
        var url = frigateUrl.replace(/\/+$/, "") + "/api/version"
        makeAuthRequest(url, function(err) {
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
