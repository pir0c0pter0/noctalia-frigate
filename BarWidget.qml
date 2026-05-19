import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI
import "Translation.js" as Translation

Item {
    id: root

    property var pluginApi: null
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""
    property int sectionWidgetIndex: -1
    property int sectionWidgetsCount: 0

    readonly property var mainInst: pluginApi?.mainInstance ?? null
    readonly property bool isPanelOpen: pluginApi?.panelOpenScreen !== null
    readonly property bool isConnected: mainInst?.connectionStatus === "connected"

    readonly property string screenName: screen ? screen.name : ""
    readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
    readonly property bool isVertical: barPosition === "left" || barPosition === "right"
    readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)

    implicitWidth: visualCapsule.width
    implicitHeight: visualCapsule.height

    function tr(key, params) {
        return Translation.tr(pluginApi, key, params)
    }

    NPopupContextMenu {
        id: contextMenu

        model: [
            {
                "label": root.tr("testConnection"),
                "action": "test",
                "icon": "plug-connected"
            },
            {
                "label": root.tr("settings"),
                "action": "settings",
                "icon": "settings"
            }
        ]

        onTriggered: action => {
            contextMenu.close()
            PanelService.closeContextMenu(root.screen)

            if (action === "test") {
                if (mainInst) mainInst.testConnection()
            } else if (action === "settings") {
                BarService.openPluginSettings(root.screen, pluginApi.manifest)
            }
        }
    }

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
            icon: "camera-video"
            opacity: root.isPanelOpen ? 1.0 : 0.7
        }

        Rectangle {
            id: statusDot
            anchors {
                bottom: parent.bottom
                right: parent.right
                bottomMargin: 2 * Style.uiScaleRatio
                rightMargin: 2 * Style.uiScaleRatio
            }
            width: 6 * Style.uiScaleRatio
            height: 6 * Style.uiScaleRatio
            radius: width / 2
            color: root.isConnected ? Color.mPrimary : Color.mError
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor

        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                PanelService.showContextMenu(contextMenu, root, root.screen)
            } else if (pluginApi) {
                pluginApi.togglePanel(root.screen, root)
            }
        }

        onEntered: {
            const key = root.isConnected ? "tooltipConnected" : "tooltipDisconnected"
            const tooltip = root.tr(key)
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
