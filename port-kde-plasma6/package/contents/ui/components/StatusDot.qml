import QtQuick
import org.kde.kirigami as Kirigami

Rectangle {
    id: root

    property bool connected: false

    implicitWidth: 8
    implicitHeight: 8

    radius: width / 2
    color: connected ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
    border.width: 1
    border.color: connected ? Qt.darker(Kirigami.Theme.positiveTextColor, 1.4) : Qt.darker(Kirigami.Theme.negativeTextColor, 1.4)
}
