import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
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

    function isCameraSelected(camName) {
        return editSelectedCameras.indexOf(camName) !== -1
    }

    function toggleCamera(camName) {
        var idx = editSelectedCameras.indexOf(camName)
        var updated = Array.from(editSelectedCameras)
        if (idx !== -1) {
            updated.splice(idx, 1)
        } else {
            updated.push(camName)
        }
        editSelectedCameras = updated
    }

    spacing: Style.marginM

    // ─── Connection ───
    NLabel {
        label: root.tr("frigateConnection")
        description: "URL, username and password for your Frigate NVR"
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NText {
            text: root.tr("frigateServerUrl")
            opacity: 0.7
            font.pixelSize: 12
        }

        Rectangle {
            Layout.fillWidth: true
            height: 36
            radius: Style.radiusM
            color: Color.mSurfaceVariant
            border.color: urlField.activeFocus ? Color.mPrimary : Color.mOutline
            border.width: 1

            TextInput {
                id: urlField
                anchors.fill: parent
                anchors.margins: 8
                verticalAlignment: TextInput.AlignVCenter
                color: Color.mOnSurface
                selectionColor: Color.mPrimary
                selectedTextColor: Color.mOnPrimary
                clip: true
                text: root.editUrl
                onTextChanged: root.editUrl = text

                NText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "http://192.168.1.100:5000"
                    visible: !urlField.text && !urlField.activeFocus
                    opacity: 0.4
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NText {
            text: root.tr("usernameOptional")
            opacity: 0.7
            font.pixelSize: 12
        }

        Rectangle {
            Layout.fillWidth: true
            height: 36
            radius: Style.radiusM
            color: Color.mSurfaceVariant
            border.color: userField.activeFocus ? Color.mPrimary : Color.mOutline
            border.width: 1

            TextInput {
                id: userField
                anchors.fill: parent
                anchors.margins: 8
                verticalAlignment: TextInput.AlignVCenter
                color: Color.mOnSurface
                selectionColor: Color.mPrimary
                selectedTextColor: Color.mOnPrimary
                clip: true
                text: root.editUsername
                onTextChanged: root.editUsername = text

                NText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.tr("leaveBlankIfNoAuth")
                    visible: !userField.text && !userField.activeFocus
                    opacity: 0.4
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NText {
            text: root.tr("passwordOptional")
            opacity: 0.7
            font.pixelSize: 12
        }

        Rectangle {
            Layout.fillWidth: true
            height: 36
            radius: Style.radiusM
            color: Color.mSurfaceVariant
            border.color: passField.activeFocus ? Color.mPrimary : Color.mOutline
            border.width: 1

            TextInput {
                id: passField
                anchors.fill: parent
                anchors.margins: 8
                verticalAlignment: TextInput.AlignVCenter
                color: Color.mOnSurface
                selectionColor: Color.mPrimary
                selectedTextColor: Color.mOnPrimary
                clip: true
                echoMode: TextInput.Password
                text: root.editPassword
                onTextChanged: root.editPassword = text

                NText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.tr("leaveBlankIfNoAuth")
                    visible: !passField.text && !passField.activeFocus
                    opacity: 0.4
                }
            }
        }
    }

    // ─── Buttons ───
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginS
        spacing: Style.marginS

        Rectangle {
            Layout.preferredWidth: saveLabel.width + 24
            Layout.preferredHeight: 32
            color: saveMouseArea.containsMouse ? Qt.darker(Color.mPrimary, 1.1) : Color.mPrimary
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
            Layout.preferredHeight: 32
            color: testMouseArea.containsMouse ? Color.mOutline : Color.mSurfaceVariant
            radius: Style.radiusM
            border.color: Color.mOutline
            border.width: 1

            NText {
                id: testLabel
                anchors.centerIn: parent
                text: root.tr("testConnection")
            }

            MouseArea {
                id: testMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.saveSettings()
                    if (mainInst) mainInst.testConnection()
                }
            }
        }

        Rectangle {
            Layout.preferredWidth: listLabel.width + 24
            Layout.preferredHeight: 32
            color: listMouseArea.containsMouse ? Color.mOutline : Color.mSurfaceVariant
            radius: Style.radiusM
            border.color: Color.mOutline
            border.width: 1

            NText {
                id: listLabel
                anchors.centerIn: parent
                text: root.tr("listCameras")
            }

            MouseArea {
                id: listMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.saveSettings()
                    if (mainInst) mainInst.fetchCameras()
                }
            }
        }

        NText {
            id: saveStatus
            text: ""
            opacity: 0.7
        }
    }

    Timer {
        id: saveStatusTimer
        interval: 2000
        onTriggered: saveStatus.text = ""
    }

    // ─── Test Result ───
    NText {
        Layout.fillWidth: true
        text: mainInst?.testResultMessage ?? ""
        color: {
            var s = mainInst?.testResultStatus ?? ""
            if (s === "ok") return Color.mPrimary
            if (s === "error") return Color.mError
            return Color.mOnSurface
        }
        wrapMode: Text.Wrap
        visible: (mainInst?.testResultMessage ?? "") !== ""
    }

    // ─── Camera Selection ───
    NLabel {
        label: root.tr("cameraSelection")
        description: root.tr("selectCamerasHint")
        visible: cameraRepeater.count > 0
    }

    Repeater {
        id: cameraRepeater
        model: mainInst?.cameraList ?? []

        delegate: RowLayout {
            required property string modelData
            required property int index
            Layout.fillWidth: true
            spacing: Style.marginS

            Rectangle {
                width: 20
                height: 20
                radius: 4
                color: root.isCameraSelected(modelData) ? Color.mPrimary : "transparent"
                border.color: root.isCameraSelected(modelData) ? Color.mPrimary : Color.mOutline
                border.width: 2

                NText {
                    anchors.centerIn: parent
                    text: "\u2713"
                    color: Color.mOnPrimary
                    font.pixelSize: 12
                    font.bold: true
                    visible: root.isCameraSelected(modelData)
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.toggleCamera(modelData)
                        root.saveSettings()
                    }
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
        text: editSelectedCameras.length + " camera(s) selected"
        opacity: 0.5
        visible: cameraRepeater.count > 0
    }

    // ─── About ───
    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginM
        spacing: 4

        NText {
            text: "About"
            font.bold: true
        }

        NText {
            text: "Developed by pir0c0pter0"
            opacity: 0.7
            font.pixelSize: 12
        }

        NText {
            text: "v" + (pluginApi?.manifest?.version ?? "1.0.0")
            opacity: 0.5
            font.pixelSize: 11
        }
    }

    Item {
        Layout.fillHeight: true
    }
}
