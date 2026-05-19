pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Commons
import qs.Widgets
import "Translation.js" as Translation

ColumnLayout {
    id: root

    property var pluginApi: null

    readonly property var mainInst: pluginApi?.mainInstance ?? null

    property string editUrl: pluginApi?.pluginSettings?.frigateUrl ?? ""
    // SEC-3: credentials come from the OS keyring via the running Main
    // instance, not from pluginSettings.
    property string editUsername: mainInst?.username ?? ""
    property string editPassword: mainInst?.password ?? ""
    property string editDefaultCamera: pluginApi?.pluginSettings?.defaultCamera ?? ""
    property var editSelectedCameras: {
        const saved = pluginApi?.pluginSettings?.selectedCameras
        return saved ? Array.from(saved) : []
    }

    spacing: Style.marginM

    function tr(key, params) {
        return Translation.tr(pluginApi, key, params)
    }

    // Normalize a user-entered URL: default the scheme to https:// when
    // none was given (an explicit http:// is kept), and drop trailing slashes.
    function normalizeUrl(u) {
        let v = (u || "").trim()
        if (v === "") return ""
        if (!/^https?:\/\//i.test(v)) {
            v = "https://" + v
        }
        return v.replace(/\/+$/, "")
    }

    function syncDefaultCamera() {
        if (editSelectedCameras.length === 0) {
            editDefaultCamera = ""
            return
        }
        if (editSelectedCameras.indexOf(editDefaultCamera) === -1) {
            editDefaultCamera = editSelectedCameras[0]
        }
    }

    function reconcileCameras() {
        // A camera removed from Frigate must not stay selected with no
        // checkbox row to deselect it -- prune to the current list.
        const list = mainInst?.cameraList ?? []
        const pruned = editSelectedCameras.filter(function (cam) {
            return list.indexOf(cam) !== -1
        })
        if (pruned.length !== editSelectedCameras.length) {
            editSelectedCameras = pruned
            // Orphan(s) actually removed -- persist immediately so the saved
            // settings and the running Main instance drop them too, instead
            // of lingering until the next manual Save.
            syncDefaultCamera()
            saveSettings()
            return
        }
        syncDefaultCamera()
    }

    function saveSettings() {
        if (!pluginApi) return
        syncDefaultCamera()
        editUrl = normalizeUrl(editUrl)
        pluginApi.pluginSettings.frigateUrl = editUrl
        pluginApi.pluginSettings.selectedCameras = editSelectedCameras
        pluginApi.pluginSettings.defaultCamera = editDefaultCamera
        pluginApi.saveSettings()
        if (mainInst) {
            // SEC-3: credentials are persisted to the OS keyring via
            // applyCredentials(), never into pluginSettings/settings.json.
            mainInst.applyCredentials(editUsername, editPassword)
            // Explicit live sync into the running Main instance -- intentional,
            // keeps the open panel in step with freshly saved settings.
            mainInst.selectedCameras = editSelectedCameras
            mainInst.resetToDefaultCamera()
        }
    }

    function isCameraSelected(camName) {
        return editSelectedCameras.indexOf(camName) !== -1
    }

    function toggleCamera(camName) {
        const idx = editSelectedCameras.indexOf(camName)
        const updated = Array.from(editSelectedCameras)
        if (idx !== -1) {
            updated.splice(idx, 1)
        } else {
            updated.push(camName)
        }
        editSelectedCameras = updated
        syncDefaultCamera()
    }

    Component.onCompleted: {
        // Re-seed the edit buffers explicitly: the property bindings to
        // pluginApi.pluginSettings.* break on the first user edit, so they
        // cannot be relied on for initialization.
        editUrl = pluginApi?.pluginSettings?.frigateUrl ?? ""
        // SEC-3: credentials are read back from the keyring via Main, which
        // loads them at shell startup (well before this panel can open).
        editUsername = mainInst?.username ?? ""
        editPassword = mainInst?.password ?? ""
        editDefaultCamera = pluginApi?.pluginSettings?.defaultCamera ?? ""
        const saved = pluginApi?.pluginSettings?.selectedCameras
        editSelectedCameras = saved ? Array.from(saved) : []
        syncDefaultCamera()
    }

    // Prune orphaned cameras whenever the camera list is re-fetched.
    Connections {
        target: root.mainInst
        function onCameraListChanged() {
            root.reconcileCameras()
        }
    }

    // ─── Connection ───
    NLabel {
        label: root.tr("frigateConnection")
        description: root.tr("connectionDescription")
    }

    LabeledTextField {
        id: urlField
        label: root.tr("frigateServerUrl")
        placeholder: root.tr("urlPlaceholder")
        text: root.editUrl
        onTextChanged: root.editUrl = text
        // Auto-format: prepend https:// when no scheme was typed.
        onEditingFinished: root.editUrl = root.normalizeUrl(root.editUrl)
        tabTarget: usernameField.inputItem
    }

    LabeledTextField {
        id: usernameField
        label: root.tr("usernameOptional")
        placeholder: root.tr("leaveBlankIfNoAuth")
        text: root.editUsername
        onTextChanged: root.editUsername = text
        tabTarget: passwordField.inputItem
        backtabTarget: urlField.inputItem
    }

    LabeledTextField {
        id: passwordField
        label: root.tr("passwordOptional")
        placeholder: root.tr("leaveBlankIfNoAuth")
        echoMode: TextInput.Password
        text: root.editPassword
        onTextChanged: root.editPassword = text
        backtabTarget: usernameField.inputItem
    }

    // SEC-3: reassure the user that credentials go to the system keyring.
    NText {
        text: root.tr("passwordStorageNote")
        opacity: 0.5
        font.pixelSize: 11
    }

    // ─── Buttons ───
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginS
        spacing: Style.marginS

        Rectangle {
            id: saveButton

            function activate() {
                root.saveSettings()
                saveStatus.text = root.tr("saved")
                saveStatusTimer.restart()
            }

            Layout.preferredWidth: saveLabel.width + 24
            Layout.preferredHeight: 32
            color: saveMouseArea.containsMouse ? Qt.darker(Color.mPrimary, 1.1) : Color.mPrimary
            radius: Style.radiusM
            border.color: Color.mOnPrimary
            border.width: saveButton.activeFocus ? 2 : 0

            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: root.tr("save")
            Accessible.onPressAction: saveButton.activate()
            Keys.onReturnPressed: saveButton.activate()
            Keys.onEnterPressed: saveButton.activate()
            Keys.onSpacePressed: saveButton.activate()

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
                onClicked: saveButton.activate()
            }
        }

        Rectangle {
            id: testButton

            function activate() {
                root.saveSettings()
                if (root.mainInst) root.mainInst.testConnection()
            }

            Layout.preferredWidth: testLabel.width + 24
            Layout.preferredHeight: 32
            color: testMouseArea.containsMouse ? Color.mOutline : Color.mSurfaceVariant
            radius: Style.radiusM
            border.color: testButton.activeFocus ? Color.mPrimary : Color.mOutline
            border.width: testButton.activeFocus ? 2 : 1

            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: root.tr("testConnection")
            Accessible.onPressAction: testButton.activate()
            Keys.onReturnPressed: testButton.activate()
            Keys.onEnterPressed: testButton.activate()
            Keys.onSpacePressed: testButton.activate()

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
                onClicked: testButton.activate()
            }
        }

        Rectangle {
            id: listButton

            function activate() {
                root.saveSettings()
                if (root.mainInst) root.mainInst.fetchCameras()
            }

            Layout.preferredWidth: listLabel.width + 24
            Layout.preferredHeight: 32
            color: listMouseArea.containsMouse ? Color.mOutline : Color.mSurfaceVariant
            radius: Style.radiusM
            border.color: listButton.activeFocus ? Color.mPrimary : Color.mOutline
            border.width: listButton.activeFocus ? 2 : 1

            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: root.tr("listCameras")
            Accessible.onPressAction: listButton.activate()
            Keys.onReturnPressed: listButton.activate()
            Keys.onEnterPressed: listButton.activate()
            Keys.onSpacePressed: listButton.activate()

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
                onClicked: listButton.activate()
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
        text: root.mainInst?.testResultMessage ?? ""
        color: {
            const s = root.mainInst?.testResultStatus ?? ""
            if (s === "ok") return Color.mPrimary
            if (s === "error") return Color.mError
            return Color.mOnSurface
        }
        wrapMode: Text.Wrap
        visible: (root.mainInst?.testResultMessage ?? "") !== ""
    }

    // ─── Camera Selection ───
    NLabel {
        label: root.tr("cameraSelection")
        description: root.tr("selectCamerasHint")
        visible: cameraRepeater.count > 0
    }

    Repeater {
        id: cameraRepeater
        model: root.mainInst?.cameraList ?? []

        delegate: RowLayout {
            id: cameraRow

            required property string modelData

            function activate() {
                root.toggleCamera(cameraRow.modelData)
                root.saveSettings()
            }

            Layout.fillWidth: true
            spacing: Style.marginS

            Rectangle {
                id: cameraCheckbox
                width: 20
                height: 20
                radius: 4
                color: root.isCameraSelected(cameraRow.modelData) ? Color.mPrimary : "transparent"
                border.color: cameraCheckbox.activeFocus
                              ? Color.mPrimary
                              : (root.isCameraSelected(cameraRow.modelData) ? Color.mPrimary : Color.mOutline)
                border.width: cameraCheckbox.activeFocus ? 3 : 2

                activeFocusOnTab: true
                Accessible.role: Accessible.CheckBox
                Accessible.name: cameraRow.modelData
                Accessible.checked: root.isCameraSelected(cameraRow.modelData)
                Accessible.onPressAction: cameraRow.activate()
                Keys.onReturnPressed: cameraRow.activate()
                Keys.onEnterPressed: cameraRow.activate()
                Keys.onSpacePressed: cameraRow.activate()

                NText {
                    anchors.centerIn: parent
                    text: "✓"
                    color: Color.mOnPrimary
                    font.pixelSize: 12
                    font.bold: true
                    visible: root.isCameraSelected(cameraRow.modelData)
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: cameraRow.activate()
                }
            }

            NText {
                text: cameraRow.modelData
                Layout.fillWidth: true

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: cameraRow.activate()
                }
            }
        }
    }

    NText {
        text: root.tr("camerasSelected", {
            "count": root.editSelectedCameras.length
        })
        opacity: 0.5
        visible: cameraRepeater.count > 0
    }

    NLabel {
        label: root.tr("defaultCamera")
        description: root.tr("defaultCameraHint")
        visible: root.editSelectedCameras.length > 0
    }

    ComboBox {
        Layout.fillWidth: true
        visible: root.editSelectedCameras.length > 0
        model: root.editSelectedCameras
        currentIndex: Math.max(0, root.editSelectedCameras.indexOf(root.editDefaultCamera))
        onActivated: {
            root.editDefaultCamera = currentText
            root.saveSettings()
        }
    }

    // ─── About ───
    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginM
        spacing: 4

        NText {
            text: root.tr("about")
            font.bold: true
        }

        NText {
            text: root.tr("developedBy")
            opacity: 0.7
            font.pixelSize: 12
        }

        NText {
            text: root.tr("version", {
                "version": pluginApi?.manifest?.version ?? "1.0.0"
            })
            opacity: 0.5
            font.pixelSize: 11
        }
    }

    Item {
        Layout.fillHeight: true
    }
}
