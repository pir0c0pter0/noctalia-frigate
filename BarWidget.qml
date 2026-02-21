import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
    id: root

    property var pluginApi: null
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""
    property int sectionWidgetIndex: -1
    property int sectionWidgetsCount: 0

    readonly property var mainInst: pluginApi?.mainInstance ?? null
    readonly property bool isPanelOpen: pluginApi?.isPanelOpen ?? false
    readonly property bool isConnected: mainInst?.connectionStatus === "connected"

    readonly property string screenName: screen ? screen.name : ""
    readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
    readonly property bool isVertical: barPosition === "left" || barPosition === "right"
    readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)

    implicitWidth: visualCapsule.width
    implicitHeight: visualCapsule.height

    Rectangle {
        id: visualCapsule
        anchors.centerIn: parent
        width: root.capsuleHeight
        height: root.capsuleHeight
        color: mouseArea.containsMouse ? Color.mHover : Style.capsuleColor
        radius: Style.radiusL
        border.color: Style.capsuleBorderColor
        border.width: Style.capsuleBorderWidth

        NIcon {
            anchors.centerIn: parent
            name: "camera-cctv"
            opacity: root.isPanelOpen ? 1.0 : 0.7
        }

        Rectangle {
            id: statusDot
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.bottomMargin: 2
            anchors.rightMargin: 2
            width: 6
            height: 6
            radius: 3
            color: root.isConnected ? Color.mPrimary : Color.mError
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onClicked: {
            if (pluginApi) {
                pluginApi.togglePanel(root.screen, root)
            }
        }

        onEntered: {
            var key = root.isConnected ? "tooltipConnected" : "tooltipDisconnected"
            var tooltip = pluginApi?.tr(key) ?? (root.isConnected ? "Frigate Viewer \u2014 Connected" : "Frigate Viewer \u2014 Disconnected")
            TooltipService.show(
                root,
                tooltip,
                BarService.getTooltipDirection(root)
            )
        }

        onExited: {
            TooltipService.hide()
        }
    }
}
