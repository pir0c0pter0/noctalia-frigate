import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

import "../code/FrigateApi.js" as FrigateApi
import "../code/I18n.js" as I18n

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
    property string cfg_haUrlDefault: "ws://192.168.31.190:8123/api/websocket"
    property string cfg_haTokenDefault: ""
    property bool cfg_enableHaIntegrationDefault: false
    property var cfg_selectedCamerasDefault: []
    property var cfg_cameraOrderDefault: []
    property int cfg_length: 0
    property bool cfg_expanding: false

    property var discoveredCameras: []
    property string testResultMessage: ""
    property string testResultStatus: ""
    property string saveStatus: ""

    readonly property string localeName: Qt.locale().name

    signal configurationChanged

    function tr(key, params) {
        return I18n.tr(localeName, key, params || {})
    }

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

        saveStatus = tr("saved")
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
            testResultMessage = tr("noUrlConfigured")
            return
        }

        testResultStatus = "testing"
        testResultMessage = tr("testing")

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
            testResultMessage = tr("connectedVersion", { version: version })
        })
    }

    function listCameras() {
        var baseUrl = FrigateApi.normalizeBaseUrl(cfg_frigateUrl)
        cfg_frigateUrl = baseUrl

        if (!baseUrl) {
            testResultStatus = "error"
            testResultMessage = tr("noUrlConfigured")
            return
        }

        var user = String(cfg_username || "")
        var pass = String(cfg_password || "")

        makeAuthRequest(baseUrl + "/api/config", user, pass, function(err, data) {
            if (err) {
                testResultStatus = "error"
                testResultMessage = tr("fetchCamerasFailed", { error: err })
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
            text: root.tr("frigateConnection")
            level: 3
        }

        Kirigami.FormLayout {
            Layout.fillWidth: true

            QQC2.TextField {
                id: urlField
                Kirigami.FormData.label: root.tr("frigateServerUrl") + ":"
                Layout.fillWidth: true
                placeholderText: "http://192.168.1.100:5000"
                inputMethodHints: Qt.ImhUrlCharactersOnly
            }

            QQC2.TextField {
                id: userField
                Kirigami.FormData.label: root.tr("usernameOptional") + ":"
                Layout.fillWidth: true
                placeholderText: root.tr("leaveBlankIfNoAuth")
                inputMethodHints: Qt.ImhNoPredictiveText
            }

            QQC2.TextField {
                id: passField
                Kirigami.FormData.label: root.tr("passwordOptional") + ":"
                Layout.fillWidth: true
                placeholderText: root.tr("leaveBlankIfNoAuth")
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                text: root.tr("save")
                icon.name: "document-save"
                onClicked: root.applySettingsNow()
            }

            QQC2.Button {
                text: root.tr("testConnection")
                icon.name: "network-connect"
                onClicked: {
                    root.applySettingsNow()
                    root.testConnection()
                }
            }

            QQC2.Button {
                text: root.tr("listCameras")
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
            text: root.tr("credentialsWarning")
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        Kirigami.Heading {
            text: root.tr("cameraSelection")
            level: 3
            visible: cameraRepeater.count > 0
        }

        QQC2.Label {
            Layout.fillWidth: true
            text: root.tr("selectCamerasHint")
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
            text: root.tr("camerasSelected", { count: FrigateApi.toStringArray(root.cfg_selectedCameras).length })
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
                Kirigami.FormData.label: root.tr("enableHaDetection") + ":"
                text: root.tr("haEnable")
            }

            QQC2.TextField {
                id: haUrlField
                Kirigami.FormData.label: root.tr("haWsUrl") + ":"
                Layout.fillWidth: true
                placeholderText: "ws://192.168.31.190:8123/api/websocket"
                enabled: haEnableCheck.checked
            }

            QQC2.TextField {
                id: haTokenField
                Kirigami.FormData.label: root.tr("haToken") + ":"
                Layout.fillWidth: true
                placeholderText: root.tr("haTokenPlaceholder")
                echoMode: TextInput.Password
                enabled: haEnableCheck.checked
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        Kirigami.Heading {
            text: root.tr("about")
            level: 4
        }

        QQC2.Label {
            text: root.tr("developedBy")
            opacity: 0.75
        }

        QQC2.Label {
            text: root.tr("version", { version: String(Plasmoid.metaData.version || "1.0.0") })
            opacity: 0.65
        }

        QQC2.Label {
            Layout.fillWidth: true
            text: root.tr("applyCloseHint")
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
