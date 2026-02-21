import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root
    property var pluginApi: null

    readonly property var mainInst: pluginApi?.mainInstance ?? null

    property string editUrl: pluginApi?.pluginSettings?.frigateUrl ?? ""
    property string editUsername: pluginApi?.pluginSettings?.username ?? ""
    property string editPassword: pluginApi?.pluginSettings?.password ?? ""
    property var editSelectedCameras: {
        var saved = pluginApi?.pluginSettings?.selectedCameras
        return saved ? Array.from(saved) : []
    }

    function tr(key) {
        return pluginApi?.tr(key) ?? key
    }

    function saveSettings() {
        if (!pluginApi) return
        pluginApi.pluginSettings.frigateUrl = editUrl.replace(/\/+$/, "")
        pluginApi.pluginSettings.username = editUsername
        pluginApi.pluginSettings.password = editPassword
        pluginApi.pluginSettings.selectedCameras = editSelectedCameras
        pluginApi.pluginSettings.cameraOrder = editSelectedCameras
        pluginApi.saveSettings()
        if (mainInst) {
            mainInst.selectedCameras = editSelectedCameras
        }
    }

    function isCameraSelected(name) {
        return editSelectedCameras.indexOf(name) !== -1
    }

    function toggleCamera(name) {
        var idx = editSelectedCameras.indexOf(name)
        var updated = Array.from(editSelectedCameras)
        if (idx !== -1) {
            updated.splice(idx, 1)
        } else {
            updated.push(name)
        }
        editSelectedCameras = updated
    }

    spacing: Style.marginM

    NLabel {
        text: root.tr("frigateConnection")
        Layout.fillWidth: true
    }

    NTextInput {
        id: urlInput
        Layout.fillWidth: true
        label: root.tr("frigateServerUrl")
        placeholderText: root.tr("urlPlaceholder")
        text: root.editUrl
        onTextChanged: root.editUrl = text
    }

    NTextInput {
        id: usernameInput
        Layout.fillWidth: true
        label: root.tr("usernameOptional")
        placeholderText: root.tr("leaveBlankIfNoAuth")
        text: root.editUsername
        onTextChanged: root.editUsername = text
    }

    NTextInput {
        id: passwordInput
        Layout.fillWidth: true
        label: root.tr("passwordOptional")
        placeholderText: root.tr("leaveBlankIfNoAuth")
        text: root.editPassword
        echoMode: TextInput.Password
        onTextChanged: root.editPassword = text
    }

    NDivider {
        Layout.fillWidth: true
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        Rectangle {
            Layout.preferredWidth: saveLabel.width + 24
            Layout.preferredHeight: saveLabel.height + 12
            color: saveMouseArea.containsMouse ? Color.mHover : Color.mPrimary
            radius: Style.radiusM

            NText {
                id: saveLabel
                anchors.centerIn: parent
                text: root.tr("save")
                color: Color.mOnPrimary
            }

            MouseArea {
                id: saveMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.saveSettings()
                    saveStatus.text = root.tr("saved")
                    saveStatusTimer.restart()
                }
            }
        }

        Rectangle {
            Layout.preferredWidth: testLabel.width + 24
            Layout.preferredHeight: testLabel.height + 12
            color: testMouseArea.containsMouse ? Color.mHover : Color.mSecondary
            radius: Style.radiusM

            NText {
                id: testLabel
                anchors.centerIn: parent
                text: root.tr("testConnection")
                color: Color.mOnSecondary
            }

            MouseArea {
                id: testMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.saveSettings()
                    if (mainInst) {
                        mainInst.testConnection()
                    }
                }
            }
        }

        Rectangle {
            Layout.preferredWidth: listLabel.width + 24
            Layout.preferredHeight: listLabel.height + 12
            color: listMouseArea.containsMouse ? Color.mHover : Color.mSecondary
            radius: Style.radiusM

            NText {
                id: listLabel
                anchors.centerIn: parent
                text: root.tr("listCameras")
                color: Color.mOnSecondary
            }

            MouseArea {
                id: listMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.saveSettings()
                    if (mainInst) {
                        mainInst.fetchCameras()
                    }
                }
            }
        }
    }

    NText {
        id: testStatus
        Layout.fillWidth: true
        text: mainInst?.testResultMessage ?? ""
        color: {
            var status = mainInst?.testResultStatus ?? ""
            if (status === "ok") return Color.mPrimary
            if (status === "error") return Color.mError
            return Color.mOnSurface
        }
        wrapMode: Text.Wrap
        visible: text !== ""
    }

    Timer {
        id: saveStatusTimer
        interval: 2000
        onTriggered: saveStatus.text = ""
    }

    NText {
        id: saveStatus
        text: ""
        opacity: 0.7
    }

    NDivider {
        Layout.fillWidth: true
        visible: cameraListView.count > 0
    }

    NLabel {
        text: root.tr("cameraSelection")
        Layout.fillWidth: true
        visible: cameraListView.count > 0
    }

    NText {
        Layout.fillWidth: true
        text: root.tr("selectCamerasHint")
        opacity: 0.6
        visible: cameraListView.count > 0
    }

    Repeater {
        id: cameraListView
        model: mainInst?.cameraList ?? []

        RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            NCheckbox {
                checked: root.isCameraSelected(modelData)
                onToggled: {
                    root.toggleCamera(modelData)
                    root.saveSettings()
                }
            }

            NText {
                text: modelData
                Layout.fillWidth: true

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.toggleCamera(modelData)
                        root.saveSettings()
                    }
                }
            }
        }
    }

    NText {
        Layout.fillWidth: true
        text: editSelectedCameras.length + " " + root.tr("camerasSelected").replace("{count}", "").trim()
        opacity: 0.5
        visible: cameraListView.count > 0
    }

    Item {
        Layout.fillHeight: true
    }
}
