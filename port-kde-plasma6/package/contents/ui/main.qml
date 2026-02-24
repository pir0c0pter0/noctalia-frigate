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
    readonly property string haEventType: String(Plasmoid.configuration.haEventType || "").trim()
    readonly property string effectiveHaEventType: haEventType.length > 0 ? haEventType : "reolink_person_detected"
    readonly property bool haConfigured: root.enableHaIntegration && root.haUrl !== "" && root.haToken !== ""

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
    property bool haSocketEnabled: true
    property bool haReconnectInProgress: false
    property bool haAuthenticated: false
    property bool haSubscribed: false
    property int haSubscriptionRequestId: -1
    property int haSubscriptionId: -1
    property int haPendingPingId: -1
    property int haMissedPongs: 0

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
        if (expanded && root.haConfigured && haSocket.status !== WebSocket.Open && haSocket.status !== WebSocket.Connecting) {
            root.requestHaReconnect("widget expanded")
        }
    }

    onHaConfiguredChanged: {
        root.resetHaSessionState()
        root.haSocketEnabled = true
        root.haReconnectInProgress = false

        if (root.haConfigured) {
            root.requestHaReconnect("HA configuration changed")
        }
    }

    onEffectiveHaEventTypeChanged: {
        if (root.haConfigured && haSocket.status === WebSocket.Open) {
            root.requestHaReconnect("HA event type changed")
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
        var target = String(cameraName).toLowerCase().replace(/_/g, ' ')

        for (var i = 0; i < list.length; i++) {
            var current = String(list[i]).toLowerCase().replace(/_/g, ' ')
            if (current === target || target.indexOf(current) !== -1 || current.indexOf(target) !== -1) {
                currentIndex = i
                return true
            }
        }
        return false
    }

    function nextHaMessageId() {
        var id = haMessageId
        haMessageId = haMessageId + 1
        return id
    }

    function resetHaSessionState() {
        haAuthenticated = false
        haSubscribed = false
        haSubscriptionRequestId = -1
        haSubscriptionId = -1
        haPendingPingId = -1
        haMissedPongs = 0
    }

    function requestHaReconnect(reason) {
        if (!root.haConfigured || root.haReconnectInProgress) {
            return
        }

        root.haReconnectInProgress = true
        root.haSocketEnabled = false
        console.log("HA reconnect requested:", reason || "unspecified")
        haReconnectPulseTimer.restart()
    }

    function subscribeToHaEvents() {
        if (haSocket.status !== WebSocket.Open || !root.haAuthenticated) {
            return
        }

        var requestId = root.nextHaMessageId()
        root.haSubscriptionRequestId = requestId
        root.haSubscribed = false
        haSocket.sendTextMessage(JSON.stringify({
            "id": requestId,
            "type": "subscribe_events",
            "event_type": root.effectiveHaEventType
        }))
    }

    function trackHaPong(pongId) {
        if (root.haPendingPingId === -1) {
            return
        }

        if (pongId === undefined || pongId === null || pongId === root.haPendingPingId) {
            root.haPendingPingId = -1
            root.haMissedPongs = 0
        }
    }

    function handleHaResult(data) {
        if (!data || typeof data !== "object") {
            return
        }

        var resultId = data.id
        if (resultId === root.haSubscriptionRequestId) {
            if (data.success === true) {
                root.haSubscribed = true
                if (data.result !== undefined && data.result !== null) {
                    var parsedSubscriptionId = Number(data.result)
                    root.haSubscriptionId = isFinite(parsedSubscriptionId) ? parsedSubscriptionId : -1
                } else {
                    root.haSubscriptionId = -1
                }
            } else {
                root.haSubscribed = false
                var message = data.error && data.error.message ? data.error.message : "Unknown subscribe error"
                console.error("HA subscribe_events failed:", message)
                root.requestHaReconnect("HA subscribe_events failed")
            }
            return
        }

        if (resultId === root.haPendingPingId) {
            root.trackHaPong(resultId)
        }
    }

    function handleHaEvent(data) {
        if (!data || typeof data !== "object") {
            return
        }

        if (!data.event || data.event.event_type !== root.effectiveHaEventType) {
            return
        }

        var eventData = data.event.data
        if (!eventData || typeof eventData !== "object") {
            eventData = {}
        }

        var cameraName = eventData.camera || eventData.camera_name || eventData.camera_id
        if (cameraName !== undefined && cameraName !== null && String(cameraName).length > 0) {
            if (root.switchToCamera(String(cameraName))) {
                root.expanded = true
            }
        }
    }

    WebSocket {
        id: haSocket
        url: root.haUrl
        active: root.haConfigured && root.haSocketEnabled
        onTextMessageReceived: function(message) {
            var data = null
            try {
                data = JSON.parse(message)
            } catch (error) {
                console.error("HA WebSocket JSON parse error:", error)
                return
            }

            if (!data || typeof data !== "object") {
                return
            }

            if (data.type === "auth_required") {
                root.resetHaSessionState()
                haSocket.sendTextMessage(JSON.stringify({
                    "type": "auth",
                    "access_token": root.haToken
                }))
                return
            }

            if (data.type === "auth_ok") {
                root.haAuthenticated = true
                root.subscribeToHaEvents()
                return
            }

            if (data.type === "auth_invalid") {
                console.error("HA WebSocket auth invalid:", data.message || "unknown error")
                root.requestHaReconnect("HA auth_invalid")
                return
            }

            if (data.type === "result") {
                root.handleHaResult(data)
                return
            }

            if (data.type === "pong") {
                root.trackHaPong(data.id)
                return
            }

            if (data.type === "event") {
                root.handleHaEvent(data)
            }
        }
        onStatusChanged: {
            if (haSocket.status === WebSocket.Error) {
                console.error("HA WebSocket Error:", haSocket.errorString)
                root.resetHaSessionState()
                root.haReconnectInProgress = false
            } else if (haSocket.status === WebSocket.Open) {
                root.haMessageId = 1
                root.resetHaSessionState()
                root.haReconnectInProgress = false
            } else if (haSocket.status === WebSocket.Closed) {
                root.resetHaSessionState()
            }
        }
    }

    Timer {
        id: haReconnectPulseTimer
        interval: 600
        repeat: false
        onTriggered: {
            root.haSocketEnabled = true
            root.haReconnectInProgress = false
        }
    }

    Timer {
        id: haReconnectTimer
        interval: 10000
        running: root.haConfigured && (haSocket.status === WebSocket.Closed || haSocket.status === WebSocket.Error)
        repeat: true
        onTriggered: {
            root.requestHaReconnect("HA retry timer")
        }
    }

    Timer {
        id: haPingTimer
        interval: 30000
        running: haSocket.status === WebSocket.Open && root.haConfigured && root.haAuthenticated
        repeat: true
        onTriggered: {
            if (root.haPendingPingId !== -1) {
                root.haMissedPongs = root.haMissedPongs + 1
                if (root.haMissedPongs >= 2) {
                    console.error("HA ping timeout detected. Forcing reconnect.")
                    root.requestHaReconnect("HA ping timeout")
                }
                return
            }

            var pingId = root.nextHaMessageId()
            root.haPendingPingId = pingId
            haSocket.sendTextMessage(JSON.stringify({
                "id": pingId,
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
