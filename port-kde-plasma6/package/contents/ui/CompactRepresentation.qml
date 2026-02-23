import QtQuick

import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

import "components"

Item {
    id: root

    required property PlasmoidItem plasmoidItem

    implicitWidth: Math.round(Kirigami.Units.iconSizes.medium * 1.45)
    implicitHeight: implicitWidth

    Rectangle {
        id: capsule
        anchors.centerIn: parent
        width: parent.width
        height: parent.height
        radius: height / 2
        color: mouseArea.containsMouse
            ? Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, Kirigami.Theme.textColor, 0.10)
            : Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, Kirigami.Theme.textColor, 0.04)
        border.width: 1
        border.color: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.textColor, Kirigami.Theme.backgroundColor, 0.70)

        Kirigami.Icon {
            anchors.centerIn: parent
            source: "camera-video"
            width: Math.round(parent.width * 0.58)
            height: width
            opacity: root.plasmoidItem.expanded ? 1.0 : 0.8
        }

        StatusDot {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: 3
            anchors.bottomMargin: 3
            connected: root.plasmoidItem.connectionStatus === "connected"
            implicitWidth: 7
            implicitHeight: 7
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor

        onClicked: {
            root.plasmoidItem.expanded = !root.plasmoidItem.expanded
        }
    }
}
