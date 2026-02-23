import QtQuick
import QtWebSockets

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

import "code/FrigateApi.js" as FrigateApi

PlasmoidItem {
    id: root

    readonly property string frigateUrl: FrigateApi.normalizeBaseUrl(Plasmoid.configuration.frigateUrl || "")
    readonly property string username: String(Plasmoid.configuration.username || "")
    readonly property string password: String(Plasmoid.configuration.password || "")

    readonly property string haUrl: Plasmoid.configuration.haUrl || ""
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
    property int haMessageId: 1
    property bool haReconnectTrigger: true

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

    Plasmoid.title: i18n("Frigate Viewer")
    Plasmoid.icon: "camera-video"
    Plasmoid.status: connectionStatus === "connected" ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus
    toolTipSubText: connectionStatus === "connected" ? i18n("Frigate is reachable") : i18n("Frigate is offline")

    compactRepresentation: CompactRepresentation {
        plasmoidItem: root
    }

    fullRepresentation: FullRepresentation {
        plasmoidItem: root
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Test Connection")
            icon.name: "network-connect"
            onTriggered: root.testConnection()
        },
        PlasmaCore.Action {
            text: i18n("Settings")
            icon.name: "settings-configure"
            onTriggered: root.openSettingsDialog()
        }
    ]

    onExpandedChanged: {
        if (expanded && root.enableHaIntegration && haSocket.status !== WebSocket.Open && haSocket.status !== WebSocket.Connecting) {
            root.haReconnectTrigger = false
            root.haReconnectTrigger = true
        }
    }

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
                callback(i18n("Authentication failed (401). Check credentials."), null, 401)
                return
            }

            if (xhr.status === 0) {
                callback(i18n("Cannot reach server. Check URL and whether Frigate is running."), null, 0)
                return
            }

            callback(i18n("HTTP %1: %2", xhr.status, xhr.statusText || "Unknown"), null, xhr.status)
        }

        xhr.ontimeout = function() {
            callback(i18n("Cannot reach server. Check URL and whether Frigate is running."), null, 0)
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
            testResultMessage = i18n("No Frigate URL configured")
            testResultStatus = "error"
            testCompleted(testResultStatus, testResultMessage)
            return
        }

        testResultMessage = i18n("Testing...")
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

                testResultMessage = i18n("Connected! Frigate v%1", version)
                testResultStatus = "ok"
                connectionStatus = "connected"
            }

            testCompleted(testResultStatus, testResultMessage)
        })
    }

    function fetchCameras() {
        if (!frigateUrl) {
            testResultMessage = i18n("No Frigate URL configured")
            testResultStatus = "error"
            return
        }

        var url = frigateUrl + "/api/config"
        makeAuthRequest(url, function(err, data) {
            if (err) {
                testResultMessage = i18n("Failed to fetch cameras: %1", err)
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
        active: root.enableHaIntegration && root.haUrl !== "" && root.haToken !== "" && root.haReconnectTrigger
        onTextMessageReceived: function(message) {
            var data = JSON.parse(message)
            if (data.type === "auth_required") {
                haSocket.sendTextMessage(JSON.stringify({
                    "type": "auth",
                    "access_token": root.haToken
                }))
            } else if (data.type === "auth_ok") {
                haSocket.sendTextMessage(JSON.stringify({
                    "id": root.haMessageId++,
                    "type": "subscribe_events",
                    "event_type": "reolink_person_detected"
                }))
            } else if (data.type === "event" && data.event && data.event.event_type === "reolink_person_detected") {
                var eventData = data.event.data
                var cameraName = eventData.camera || eventData.camera_name || eventData.camera_id
                if (cameraName) {
                    if (root.switchToCamera(cameraName)) {
                        root.expanded = true
                    }
                }
            }
        }
        onStatusChanged: {
            if (haSocket.status === WebSocket.Error) {
                console.error("HA WebSocket Error:", haSocket.errorString)
            } else if (haSocket.status === WebSocket.Open) {
                root.haMessageId = 1
            }
        }
    }

    Timer {
        id: haReconnectTimer
        interval: 10000
        running: root.enableHaIntegration && root.haUrl !== "" && (haSocket.status === WebSocket.Closed || haSocket.status === WebSocket.Error)
        repeat: true
        onTriggered: {
            root.haReconnectTrigger = false
            root.haReconnectTrigger = true
        }
    }

    Timer {
        id: haPingTimer
        interval: 30000
        running: haSocket.status === WebSocket.Open && root.enableHaIntegration
        repeat: true
        onTriggered: {
            haSocket.sendTextMessage(JSON.stringify({
                "id": root.haMessageId++,
                "type": "ping"
            }))
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
        if (frigateUrl) {
            pollConnection()
        }
    }
}
