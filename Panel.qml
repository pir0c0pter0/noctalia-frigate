import QtQuick
import Quickshell
import qs.Commons
import qs.Widgets

Item {
    id: root
    property var pluginApi: null
    property ShellScreen screen

    readonly property var mainInst: pluginApi?.mainInstance ?? null
    readonly property string streamUrl: mainInst?.streamUrl ?? ""
    readonly property string cameraName: mainInst?.currentCameraName ?? ""
    readonly property int cameraCount: mainInst?.selectedCameras?.length ?? 0
    readonly property bool hasStream: streamUrl !== ""
    readonly property bool isConnected: mainInst?.connectionStatus === "connected"

    function tr(key) {
        return pluginApi?.tr(key) ?? key
    }

    width: 640
    height: 400

    Rectangle {
        anchors.fill: parent
        color: Color.mSurface

        Rectangle {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 36
            color: Color.mSurfaceVariant

            Rectangle {
                id: prevButton
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 4
                width: 28
                height: 28
                radius: Style.radiusS
                color: prevMouseArea.containsMouse ? Color.mHover : "transparent"
                visible: root.cameraCount > 1

                NIcon {
                    anchors.centerIn: parent
                    icon: "chevron-left"
                }

                MouseArea {
                    id: prevMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (mainInst) mainInst.prevCamera()
                    }
                }
            }

            NText {
                anchors.centerIn: parent
                text: root.cameraName || root.tr("noCameraSelected")
                opacity: root.cameraName ? 1.0 : 0.5
            }

            Rectangle {
                id: nextButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: 4
                width: 28
                height: 28
                radius: Style.radiusS
                color: nextMouseArea.containsMouse ? Color.mHover : "transparent"
                visible: root.cameraCount > 1

                NIcon {
                    anchors.centerIn: parent
                    icon: "chevron-right"
                }

                MouseArea {
                    id: nextMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (mainInst) mainInst.nextCamera()
                    }
                }
            }
        }

        Image {
            id: streamView
            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: debugLabel.top
            anchors.margins: 4
            source: root.streamUrl
            cache: false
            fillMode: Image.PreserveAspectFit

            onStatusChanged: {
                if (status === Image.Ready) {
                    statusLabel.text = ""
                } else if (status === Image.Loading) {
                    statusLabel.text = root.tr("loadingStream")
                } else if (status === Image.Error) {
                    statusLabel.text = root.isConnected ? root.tr("streamError") : root.tr("frigateOffline")
                }
            }
        }

        NText {
            id: statusLabel
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: root.hasStream ? "" : root.tr("noCamerasConfigured")
            opacity: 0.5
            wrapMode: Text.Wrap
        }

        NText {
            id: debugLabel
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 4
            text: "URL: " + root.streamUrl
            opacity: 0.3
            font.pixelSize: 10
            wrapMode: Text.Wrap
        }
    }
}
