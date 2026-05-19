import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

// Reusable labeled text field: a small caption label above a bordered
// input box with placeholder text. Extracted from the repeated
// URL / username / password blocks in Settings.qml.
ColumnLayout {
    id: control

    property string label: ""
    property string placeholder: ""
    // Two-way usable editable string. Bind with `text: control.text`
    // from the parent and react to onTextChanged, or alias directly.
    property alias text: input.text
    property alias value: input.text
    property int echoMode: TextInput.Normal

    Layout.fillWidth: true
    spacing: Style.marginS

    NText {
        text: control.label
        opacity: 0.7
        font.pixelSize: 12
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 36
        radius: Style.radiusM
        color: Color.mSurfaceVariant
        border.color: input.activeFocus ? Color.mPrimary : Color.mOutline
        border.width: 1

        TextInput {
            id: input
            anchors.fill: parent
            anchors.margins: 8
            verticalAlignment: TextInput.AlignVCenter
            color: Color.mOnSurface
            selectionColor: Color.mPrimary
            selectedTextColor: Color.mOnPrimary
            clip: true
            echoMode: control.echoMode

            NText {
                anchors.verticalCenter: parent.verticalCenter
                text: control.placeholder
                visible: !input.text && !input.activeFocus
                opacity: 0.4
            }
        }
    }
}
