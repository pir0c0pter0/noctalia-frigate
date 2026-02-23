import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

import "../code/FrigateApi.js" as FrigateApi

Item {
    id: root
    implicitWidth: Math.round(Kirigami.Units.gridUnit * 28)
    implicitHeight: Math.round(Kirigami.Units.gridUnit * 32)

    property alias cfg_frigateUrl: urlField.text
    property alias cfg_username: userField.text
    property alias cfg_password: passField.text
    property alias cfg_haUrl: haUrlField.text
    property alias cfg_haToken: haTokenField.text
    property alias cfg_enableHaIntegration: haEnableCheck.checked
    property var cfg_selectedCameras: []
    property var cfg_cameraOrder: []
    property string cfg_frigateUrlDefault: ""
    property string cfg_usernameDefault: ""
    property string cfg_passwordDefault: ""
    property string cfg_haUrlDefault: ""
    property string cfg_haTokenDefault: ""
    property bool cfg_enableHaIntegrationDefault: false
    property var cfg_selectedCamerasDefault: []
    property var cfg_cameraOrderDefault: []

    property var discoveredCameras: []
    property string testResultMessage: ""
    property string testResultStatus: ""
    property string saveStatus: ""

    signal configurationChanged

    function saveConfig() {
        cfg_frigateUrl = FrigateApi.normalizeBaseUrl(cfg_frigateUrl)
        cfg_selectedCameras = FrigateApi.toStringArray(cfg_selectedCameras)
        cfg_cameraOrder = FrigateApi.orderedSelection(cfg_selectedCameras, cfg_cameraOrder)
    }

    function authToken(user, pass) {
        if (!FrigateApi.hasCredentials(user, pass)) {
            return ""
        }

        if (typeof Qt.btoa === "function") {
            return Qt.btoa(user + ":" + pass)
        }

        if (typeof btoa === "function") {
            return btoa(user + ":" + pass)
        }

        return ""
    }

    function applySettingsNow() {
        saveConfig()

        Plasmoid.configuration.frigateUrl = cfg_frigateUrl
        Plasmoid.configuration.username = cfg_username
        Plasmoid.configuration.password = cfg_password
        Plasmoid.configuration.haUrl = cfg_haUrl
        Plasmoid.configuration.haToken = cfg_haToken
        Plasmoid.configuration.enableHaIntegration = cfg_enableHaIntegration
        Plasmoid.configuration.selectedCameras = cfg_selectedCameras
        Plasmoid.configuration.cameraOrder = cfg_cameraOrder

        saveStatus = i18n("Saved!")
        saveStatusTimer.restart()
        configurationChanged()
    }

    function makeAuthRequest(url, user, pass, callback) {
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

        var token = authToken(user, pass)
        if (token) {
            xhr.setRequestHeader("Authorization", "Basic " + token)
        }

        xhr.send()
    }

    function testConnection() {
        var baseUrl = FrigateApi.normalizeBaseUrl(cfg_frigateUrl)
        cfg_frigateUrl = baseUrl

        if (!baseUrl) {
            testResultStatus = "error"
            testResultMessage = i18n("No Frigate URL configured")
            return
        }

        testResultStatus = "testing"
        testResultMessage = i18n("Testing...")

        var user = String(cfg_username || "")
        var pass = String(cfg_password || "")

        makeAuthRequest(baseUrl + "/api/version", user, pass, function(err, data) {
            if (err) {
                testResultStatus = "error"
                testResultMessage = err
                return
            }

            var version = "unknown"
            if (typeof data === "object" && data && data.version !== undefined) {
                version = data.version
            } else if (data !== null && data !== undefined) {
                version = data
            }

            testResultStatus = "ok"
            testResultMessage = i18n("Connected! Frigate v%1", version)
        })
    }

    function listCameras() {
        var baseUrl = FrigateApi.normalizeBaseUrl(cfg_frigateUrl)
        cfg_frigateUrl = baseUrl

        if (!baseUrl) {
            testResultStatus = "error"
            testResultMessage = i18n("No Frigate URL configured")
            return
        }

        var user = String(cfg_username || "")
        var pass = String(cfg_password || "")

        makeAuthRequest(baseUrl + "/api/config", user, pass, function(err, data) {
            if (err) {
                testResultStatus = "error"
                testResultMessage = i18n("Failed to fetch cameras: %1", err)
                return
            }

            discoveredCameras = FrigateApi.parseCameraList(data)

            cfg_selectedCameras = FrigateApi.mergeCameraSelection(cfg_selectedCameras, discoveredCameras)
            cfg_cameraOrder = FrigateApi.orderedSelection(cfg_selectedCameras, cfg_cameraOrder)

            testResultStatus = "ok"
            testResultMessage = ""
            configurationChanged()
        })
    }

    function isCameraSelected(cameraName) {
        var selected = FrigateApi.toStringArray(cfg_selectedCameras)
        return selected.indexOf(cameraName) !== -1
    }

    function toggleCamera(cameraName) {
        var selected = FrigateApi.toStringArray(cfg_selectedCameras)
        var index = selected.indexOf(cameraName)
        if (index !== -1) {
            selected.splice(index, 1)
        } else {
            selected.push(cameraName)
        }

        cfg_selectedCameras = selected
        cfg_cameraOrder = FrigateApi.orderedSelection(cfg_selectedCameras, cfg_cameraOrder)
        configurationChanged()
    }

    Component.onCompleted: {
        cfg_frigateUrl = FrigateApi.normalizeBaseUrl(cfg_frigateUrl)
        cfg_selectedCameras = FrigateApi.toStringArray(cfg_selectedCameras)
        cfg_cameraOrder = FrigateApi.orderedSelection(cfg_selectedCameras, cfg_cameraOrder)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Heading {
            text: i18n("Frigate Connection")
            level: 3
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true

            QQC2.TextField {
                id: urlField
                Kirigami.FormData.label: i18n("Frigate Server URL") + ":"
                Layout.fillWidth: true
                placeholderText: "http://192.168.1.100:5000"
                inputMethodHints: Qt.ImhUrlCharactersOnly
            }

            QQC2.TextField {
                id: userField
                Kirigami.FormData.label: i18n("Username (optional)") + ":"
                Layout.fillWidth: true
                placeholderText: i18n("Leave blank if no auth")
                inputMethodHints: Qt.ImhNoPredictiveText
            }

            QQC2.TextField {
                id: passField
                Kirigami.FormData.label: i18n("Password (optional)") + ":"
                Layout.fillWidth: true
                placeholderText: i18n("Leave blank if no auth")
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                text: i18n("Save")
                icon.name: "document-save"
                onClicked: root.applySettingsNow()
            }

            QQC2.Button {
                text: i18n("Test Connection")
                icon.name: "network-connect"
                onClicked: {
                    root.applySettingsNow()
                    root.testConnection()
                }
            }

            QQC2.Button {
                text: i18n("List Cameras")
                icon.name: "view-list-details"
                onClicked: {
                    root.applySettingsNow()
                    root.listCameras()
                }
            }

            QQC2.Label {
                text: root.saveStatus
                visible: text.length > 0
                opacity: 0.75
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: root.testResultMessage
            visible: text.length > 0
            color: {
                if (root.testResultStatus === "ok") {
                    return Kirigami.Theme.positiveTextColor
                }
                if (root.testResultStatus === "error") {
                    return Kirigami.Theme.negativeTextColor
                }
                return Kirigami.Theme.textColor
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            opacity: 0.75
            text: i18n("Credentials are stored locally. Prefer a dedicated Frigate user with limited permissions.")
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        Kirigami.Heading {
            text: i18n("Camera Selection")
            level: 3
            visible: cameraRepeater.count > 0
        }

        QQC2.Label {
            Layout.fillWidth: true
            text: i18n("Select which cameras appear in the viewer panel:")
            wrapMode: Text.WordWrap
            visible: cameraRepeater.count > 0
            opacity: 0.8
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                id: cameraRepeater
                model: root.discoveredCameras

                delegate: RowLayout {
                    required property string modelData
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.CheckBox {
                        checked: root.isCameraSelected(modelData)
                        onClicked: root.toggleCamera(modelData)
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        text: modelData
                        elide: Text.ElideRight
                    }
                }
            }
        }

        QQC2.Label {
            text: i18np("%1 camera selected", "%1 cameras selected", FrigateApi.toStringArray(root.cfg_selectedCameras).length)
            visible: cameraRepeater.count > 0
            opacity: 0.7
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        Kirigami.Heading {
            text: "Home Assistant"
            level: 3
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true

            QQC2.CheckBox {
                id: haEnableCheck
                Kirigami.FormData.label: i18n("Enable Home Assistant Detection") + ":"
                text: i18n("Enable")
            }

            QQC2.TextField {
                id: haUrlField
                Kirigami.FormData.label: i18n("HA WebSocket URL") + ":"
                Layout.fillWidth: true
                placeholderText: "ws://192.168.1.100:8123/api/websocket"
                enabled: haEnableCheck.checked
            }

            QQC2.TextField {
                id: haTokenField
                Kirigami.FormData.label: i18n("HA Access Token") + ":"
                Layout.fillWidth: true
                placeholderText: i18n("Paste your Long-Lived Access Token")
                echoMode: TextInput.Password
                enabled: haEnableCheck.checked
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        Kirigami.Heading {
            text: i18n("About")
            level: 4
        }

        QQC2.Label {
            text: i18n("Developed by pir0c0pter0")
            opacity: 0.75
        }

        QQC2.Label {
            text: i18n("Version %1", String(Plasmoid.metaData.version || "1.0.0"))
            opacity: 0.65
        }

        QQC2.Label {
            Layout.fillWidth: true
            text: i18n("Tip: use Apply/OK to persist configuration in Plasma dialogs.")
            wrapMode: Text.WordWrap
            opacity: 0.65
        }
    }

    Timer {
        id: saveStatusTimer
        interval: 2000
        repeat: false
        onTriggered: root.saveStatus = ""
    }
}
