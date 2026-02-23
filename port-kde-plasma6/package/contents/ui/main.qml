import QtQuick
import QtWebSockets

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

import "code/FrigateApi.js" as FrigateApi
import "code/I18n.js" as I18n

PlasmoidItem {
    id: root

    readonly property string localeName: Qt.locale().name

    readonly property string frigateUrl: FrigateApi.normalizeBaseUrl(Plasmoid.configuration.frigateUrl || "")
    readonly property string username: String(Plasmoid.configuration.username || "")
    readonly property string password: String(Plasmoid.configuration.password || "")

    readonly property string haUrl: Plasmoid.configuration.haUrl || "ws://192.168.31.190:8123/api/websocket"
    readonly property string haToken: Plasmoid.configuration.haToken || ""
    readonly property bool enableHaIntegration: !!Plasmoid.configuration.enableHaIntegration

    readonly property var effectiveSelectedCameras: FrigateApi.orderedSelection(
        FrigateApi.toStringArray(Plasmoid.configuration.selectedCameras),
        FrigateApi.toStringArray(Plasmoid.configuration.cameraOrder)
    )

    property int currentIndex: 0
    property string connectionStatus: "disconnected"
    property var cameraList: []
    property string testResultMessage: ""
    property string testResultStatus: ""

    readonly property string currentCameraName: {
        var list = effectiveSelectedCameras
        if (!list || list.length === 0) {
            return ""
        }

        var clamped = Math.min(currentIndex, list.length - 1)
        if (clamped < 0) {
            return ""
        }
        return list[clamped] || ""
    }

    readonly property string snapshotBaseUrl: buildSnapshotUrl(currentCameraName)
    readonly property string streamBaseUrl: buildStreamUrl(currentCameraName)

    signal camerasLoaded(var cameras)
    signal testCompleted(string status, string message)

    Plasmoid.title: tr("frigateViewerTitle")
    Plasmoid.icon: "camera-video"
    Plasmoid.status: connectionStatus === "connected" ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus
    toolTipSubText: connectionStatus === "connected" ? tr("statusConnected") : tr("statusDisconnected")

    compactRepresentation: CompactRepresentation {
        plasmoidItem: root
    }

    fullRepresentation: FullRepresentation {
        plasmoidItem: root
    }

    PlasmaCore.Action {
        id: testAction
        text: root.tr("testConnection")
        icon.name: "network-connect"
        onTriggered: root.testConnection()
    }

    PlasmaCore.Action {
        id: settingsAction
        text: root.tr("settings")
        icon.name: "settings-configure"
        onTriggered: root.openSettingsDialog()
    }

    Plasmoid.contextualActions: [
        testAction,
        settingsAction
    ]

    onEffectiveSelectedCamerasChanged: {
        if (!effectiveSelectedCameras.length) {
            currentIndex = 0
            return
        }

        if (currentIndex >= effectiveSelectedCameras.length) {
            currentIndex = 0
        }
    }

    onFrigateUrlChanged: {
        if (!frigateUrl) {
            connectionStatus = "disconnected"
            return
        }
        pollConnection()
    }

    onUsernameChanged: {
        if (frigateUrl) {
            pollConnection()
        }
    }

    onPasswordChanged: {
        if (frigateUrl) {
            pollConnection()
        }
    }

    function tr(key, params) {
        return I18n.tr(localeName, key, params || {})
    }

    function openSettingsDialog() {
        var configureAction = null
        if (Plasmoid.internalAction) {
            configureAction = Plasmoid.internalAction("configure")
        }

        if (configureAction) {
            configureAction.trigger()
            return
        }

        if (Plasmoid.containment && Plasmoid.containment.configureRequested) {
            Plasmoid.containment.configureRequested(Plasmoid)
        }
    }

    function authToken() {
        if (!FrigateApi.hasCredentials(username, password)) {
            return ""
        }

        if (typeof Qt.btoa === "function") {
            return Qt.btoa(username + ":" + password)
        }

        if (typeof btoa === "function") {
            return btoa(username + ":" + password)
        }

        return ""
    }

    function buildSnapshotUrl(cameraName) {
        if (!cameraName || !frigateUrl) {
            return ""
        }

        var encodedCamera = encodeURIComponent(cameraName)
        return FrigateApi.buildAuthUrl(frigateUrl, "/api/" + encodedCamera + "/latest.jpg", username, password)
    }

    function buildStreamUrl(cameraName) {
        if (!cameraName || !frigateUrl) {
            return ""
        }

        var encodedCamera = encodeURIComponent(cameraName)
        var query = "?fps=5&h=480&quality=80"
        return FrigateApi.buildAuthUrl(frigateUrl, "/api/" + encodedCamera + query, username, password)
    }

    function makeAuthRequest(url, callback) {
        var xhr = new XMLHttpRequest()

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) {
                return
            }

            if (xhr.status >= 200 && xhr.status < 300) {
                var payload = xhr.responseText
                try {
                    payload = JSON.parse(payload)
                } catch (error) {
                    // Keep raw text payload when endpoint is plain text.
                }
                callback(null, payload, xhr.status)
                return
            }

            if (xhr.status === 401) {
                callback(tr("authFailed"), null, 401)
                return
            }

            if (xhr.status === 0) {
                callback(tr("cannotReachServer"), null, 0)
                return
            }

            callback(tr("httpError", {
                status: xhr.status,
                statusText: xhr.statusText || "Unknown"
            }), null, xhr.status)
        }

        xhr.ontimeout = function() {
            callback(tr("cannotReachServer"), null, 0)
        }

        xhr.open("GET", url, true)
        xhr.timeout = 10000

        var token = authToken()
        if (token) {
            xhr.setRequestHeader("Authorization", "Basic " + token)
        }

        xhr.send()
    }

    function testConnection() {
        if (!frigateUrl) {
            testResultMessage = tr("noUrlConfigured")
            testResultStatus = "error"
            testCompleted(testResultStatus, testResultMessage)
            return
        }

        testResultMessage = tr("testing")
        testResultStatus = "testing"

        var url = frigateUrl + "/api/version"
        makeAuthRequest(url, function(err, data) {
            if (err) {
                testResultMessage = err
                testResultStatus = "error"
                connectionStatus = "disconnected"
            } else {
                var version = "unknown"
                if (typeof data === "object" && data && data.version !== undefined) {
                    version = data.version
                } else if (data !== null && data !== undefined) {
                    version = data
                }

                testResultMessage = tr("connectedVersion", { version: version })
                testResultStatus = "ok"
                connectionStatus = "connected"
            }

            testCompleted(testResultStatus, testResultMessage)
        })
    }

    function fetchCameras() {
        if (!frigateUrl) {
            testResultMessage = tr("noUrlConfigured")
            testResultStatus = "error"
            return
        }

        var url = frigateUrl + "/api/config"
        makeAuthRequest(url, function(err, data) {
            if (err) {
                testResultMessage = tr("fetchCamerasFailed", { error: err })
                testResultStatus = "error"
                return
            }

            var cameras = FrigateApi.parseCameraList(data)
            cameraList = cameras
            camerasLoaded(cameras)
        })
    }

    function pollConnection() {
        if (!frigateUrl) {
            connectionStatus = "disconnected"
            return
        }

        var url = frigateUrl + "/api/version"
        makeAuthRequest(url, function(err) {
            connectionStatus = err ? "disconnected" : "connected"
        })
    }

    function nextCamera() {
        var count = effectiveSelectedCameras.length
        if (!count) {
            return
        }
        currentIndex = (currentIndex + 1) % count
    }

    function prevCamera() {
        var count = effectiveSelectedCameras.length
        if (!count) {
            return
        }
        currentIndex = (currentIndex - 1 + count) % count
    }

    function switchToCamera(cameraName) {
        var list = effectiveSelectedCameras
        var target = String(cameraName).toLowerCase()
        
        for (var i = 0; i < list.length; i++) {
            var current = String(list[i]).toLowerCase()
            if (current === target || target.indexOf(current) !== -1 || current.indexOf(target) !== -1) {
                currentIndex = i
                return true
            }
        }
        return false
    }

    WebSocket {
        id: haSocket
        url: root.haUrl
        active: root.enableHaIntegration && root.haToken !== ""
        onTextMessageReceived: function(message) {
            var data = JSON.parse(message)
            if (data.type === "auth_required") {
                haSocket.sendTextMessage(JSON.stringify({
                    "type": "auth",
                    "access_token": root.haToken
                }))
            } else if (data.type === "auth_ok") {
                haSocket.sendTextMessage(JSON.stringify({
                    "id": 1,
                    "type": "subscribe_events",
                    "event_type": "reolink_person_detected"
                }))
            } else if (data.type === "event" && data.event && data.event.event_type === "reolink_person_detected") {
                var eventData = data.event.data
                console.log("Person detected event received:", JSON.stringify(eventData))
                var cameraName = eventData.camera || eventData.camera_name || eventData.camera_id
                if (cameraName) {
                    if (root.switchToCamera(cameraName)) {
                        console.log("Expanding widget for camera:", cameraName)
                        root.expanded = true
                        Plasmoid.expanded = true
                    }
                }
            }
        }
        onStatusChanged: {
            if (haSocket.status === WebSocket.Error) {
                console.error("HA WebSocket Error:", haSocket.errorString)
            } else if (haSocket.status === WebSocket.Open) {
                console.log("HA WebSocket Connected")
            } else if (haSocket.status === WebSocket.Closed) {
                console.log("HA WebSocket Closed")
            }
        }
    }

    // Auto-reconnect logic
    Timer {
        id: haReconnectTimer
        interval: 5000
        running: haSocket.status === WebSocket.Closed && root.enableHaIntegration
        repeat: false
        onTriggered: haSocket.active = true
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
