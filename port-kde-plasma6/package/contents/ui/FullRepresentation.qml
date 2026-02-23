import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasmoid

import "components"

PlasmaExtras.Representation {
    id: root

    required property PlasmoidItem plasmoidItem
    clip: true

    readonly property int cameraCount: root.plasmoidItem.effectiveSelectedCameras.length
    readonly property string cameraName: root.plasmoidItem.currentCameraName
    readonly property bool connected: root.plasmoidItem.connectionStatus === "connected"
    readonly property string modeChipText: streamView.liveMode ? root.plasmoidItem.tr("liveModeChip") : root.plasmoidItem.tr("previewModeChip")
    readonly property int streamMargin: Kirigami.Units.smallSpacing
    readonly property int baseMinWidth: Math.round(Kirigami.Units.gridUnit * 24)
    readonly property int baseMinHeight: Math.round(Kirigami.Units.gridUnit * 16)
    readonly property int preferredStreamFrameWidth: streamView.preferredVideoWidth + (streamMargin * 4)
    readonly property int preferredStreamFrameHeight: streamView.preferredVideoHeight + (streamMargin * 4)
    readonly property int chromeHeight: Math.round(headerRow.implicitHeight + chipRow.implicitHeight + footerLabel.implicitHeight + (Kirigami.Units.smallSpacing * 6))
    readonly property int preferredPanelWidth: Math.max(baseMinWidth, preferredStreamFrameWidth)
    readonly property int preferredPanelHeight: Math.max(baseMinHeight, chromeHeight + preferredStreamFrameHeight)

    Layout.minimumWidth: baseMinWidth
    Layout.minimumHeight: baseMinHeight
    Layout.preferredWidth: preferredPanelWidth
    Layout.preferredHeight: preferredPanelHeight
    implicitWidth: preferredPanelWidth
    implicitHeight: preferredPanelHeight

    collapseMarginsHint: true

    contentItem: Item {
        clip: true
        implicitWidth: root.preferredPanelWidth
        implicitHeight: root.preferredPanelHeight

        Rectangle {
            anchors.fill: parent
            radius: Kirigami.Units.cornerRadius + 2
            border.width: 1
            border.color: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.textColor, Kirigami.Theme.backgroundColor, 0.75)
            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, Kirigami.Theme.highlightColor, 0.09)
                }
                GradientStop {
                    position: 0.5
                    color: Kirigami.Theme.backgroundColor
                }
                GradientStop {
                    position: 1.0
                    color: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, Kirigami.Theme.textColor, 0.02)
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Math.round(Kirigami.Units.smallSpacing * 1.5)
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                id: headerRow
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.ToolButton {
                    visible: root.cameraCount > 1
                    icon.name: "go-previous-symbolic"
                    display: PlasmaComponents3.AbstractButton.IconOnly
                    onClicked: root.plasmoidItem.prevCamera()
                }

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.cameraName || root.plasmoidItem.tr("noCameraSelected")
                    elide: Text.ElideRight
                    opacity: root.cameraName ? 1.0 : 0.65
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                    font.weight: Font.Medium
                }

                PlasmaComponents3.ToolButton {
                    visible: root.cameraCount > 1
                    icon.name: "go-next-symbolic"
                    display: PlasmaComponents3.AbstractButton.IconOnly
                    onClicked: root.plasmoidItem.nextCamera()
                }

                PlasmaComponents3.ToolButton {
                    icon.name: "window-close-symbolic"
                    display: PlasmaComponents3.AbstractButton.IconOnly
                    onClicked: root.plasmoidItem.expanded = false
                }
            }

            RowLayout {
                id: chipRow
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Rectangle {
                    radius: height / 2
                    color: root.connected
                        ? Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.positiveTextColor, Kirigami.Theme.backgroundColor, 0.84)
                        : Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.negativeTextColor, Kirigami.Theme.backgroundColor, 0.84)
                    border.width: 1
                    border.color: root.connected
                        ? Qt.darker(Kirigami.Theme.positiveTextColor, 1.2)
                        : Qt.darker(Kirigami.Theme.negativeTextColor, 1.2)
                    implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.25)
                    implicitWidth: statusRow.implicitWidth + Kirigami.Units.smallSpacing * 2

                    RowLayout {
                        id: statusRow
                        anchors.centerIn: parent
                        spacing: Kirigami.Units.smallSpacing

                        StatusDot {
                            connected: root.connected
                            implicitWidth: 8
                            implicitHeight: 8
                        }

                        PlasmaComponents3.Label {
                            text: root.connected
                                ? root.plasmoidItem.tr("tooltipConnected")
                                : root.plasmoidItem.tr("tooltipDisconnected")
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                            font.weight: Font.Medium
                        }
                    }
                }

                Rectangle {
                    radius: height / 2
                    color: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.highlightColor, Kirigami.Theme.backgroundColor, 0.82)
                    border.width: 1
                    border.color: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.textColor, Kirigami.Theme.backgroundColor, 0.65)
                    implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.25)
                    implicitWidth: modeLabel.implicitWidth + Kirigami.Units.smallSpacing * 2

                    PlasmaComponents3.Label {
                        id: modeLabel
                        anchors.centerIn: parent
                        text: root.modeChipText
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        font.weight: Font.Medium
                    }
                }

                Item {
                    Layout.fillWidth: true
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: root.preferredStreamFrameWidth
                Layout.preferredHeight: root.preferredStreamFrameHeight
                Layout.minimumWidth: 0
                Layout.minimumHeight: 0
                Layout.maximumWidth: parent.width
                Layout.maximumHeight: parent.height
                radius: Kirigami.Units.cornerRadius + 2
                border.width: 1
                border.color: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.textColor, Kirigami.Theme.backgroundColor, 0.64)
                color: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, Kirigami.Theme.textColor, 0.03)
                clip: true

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.highlightColor, Kirigami.Theme.backgroundColor, 0.06)
                        }
                        GradientStop {
                            position: 1.0
                            color: "transparent"
                        }
                    }
                }

                StreamView {
                    id: streamView
                    anchors.fill: parent
                    anchors.margins: root.streamMargin * 1.3
                    snapshotBaseUrl: root.plasmoidItem.snapshotBaseUrl
                    streamBaseUrl: root.plasmoidItem.streamBaseUrl
                    cameraName: root.cameraName
                    connected: root.connected
                    active: root.plasmoidItem.expanded
                    noCameraText: root.plasmoidItem.tr("noCamerasConfigured")
                    loadingStreamText: root.plasmoidItem.tr("loadingStream")
                    streamErrorText: root.plasmoidItem.tr("streamError")
                    offlineText: root.plasmoidItem.tr("frigateOffline")
                    previewHintText: root.plasmoidItem.tr("previewHint")
                    liveHintText: root.plasmoidItem.tr("liveHint")
                }
            }

            PlasmaComponents3.Label {
                id: footerLabel
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.cameraName.length > 0
                    ? root.cameraName + " | " + streamView.frameCount + " frames"
                    : ""
                visible: text.length > 0
                opacity: 0.58
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }
    }
}
