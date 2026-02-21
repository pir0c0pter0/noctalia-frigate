import QtQuick

Item {
    id: root
    property var pluginApi: null

    readonly property string frigateUrl: pluginApi?.pluginSettings?.frigateUrl ?? ""
    readonly property string username: pluginApi?.pluginSettings?.username ?? ""
    readonly property string password: pluginApi?.pluginSettings?.password ?? ""

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

    readonly property string streamUrl: buildAuthUrl("/api/" + currentCameraName + "?fps=5")

    signal camerasLoaded(var cameras)
    signal testCompleted(string status, string message)

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
                    callback("Authentication failed (401). Check your username and password. Note: Frigate's native JWT auth (port 8971) is not supported \u2014 use port 5000 or a reverse proxy with Basic Auth.", null, 401)
                } else if (xhr.status === 0) {
                    callback("Cannot reach server. Check the URL and ensure Frigate is running.", null, 0)
                } else {
                    callback("HTTP " + xhr.status + ": " + xhr.statusText, null, xhr.status)
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
            testResultMessage = "No Frigate URL configured"
            testResultStatus = "error"
            testCompleted("error", testResultMessage)
            return
        }
        testResultMessage = "Testing..."
        testResultStatus = "testing"

        var url = frigateUrl.replace(/\/+$/, "") + "/api/version"
        makeAuthRequest(url, function(err, data) {
            if (err) {
                testResultMessage = err
                testResultStatus = "error"
                root.connectionStatus = "disconnected"
            } else {
                var version = data.version ?? data ?? "unknown"
                testResultMessage = "Connected! Frigate v" + version
                testResultStatus = "ok"
                root.connectionStatus = "connected"
            }
            testCompleted(testResultStatus, testResultMessage)
        })
    }

    function fetchCameras() {
        if (!frigateUrl) return

        var url = frigateUrl.replace(/\/+$/, "") + "/api/config"
        makeAuthRequest(url, function(err, data) {
            if (err) {
                testResultMessage = "Failed to fetch cameras: " + err
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

    Timer {
        id: connectionPoller
        interval: 30000
        repeat: true
        running: root.frigateUrl !== ""
        onTriggered: root.pollConnection()
    }

    Component.onCompleted: {
        if (frigateUrl) {
            pollConnection()
        }
    }
}
