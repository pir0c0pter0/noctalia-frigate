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
    property bool streamError: false

    function tr(key) {
        return pluginApi?.tr(key) ?? key
    }

    width: 640
    height: 400

    onVisibleChanged: {
        if (visible) {
            streamError = false
            if (hasStream) {
                streamView.source = ""
                reconnectTimer.start()
            }
        } else {
            streamView.source = ""
        }
    }

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
                    name: "chevron-left"
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
                    name: "chevron-right"
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
            anchors.bottom: parent.bottom
            anchors.margins: 4
            source: root.hasStream ? root.streamUrl : ""
            cache: false
            fillMode: Image.PreserveAspectFit
            visible: root.hasStream && !root.streamError

            onStatusChanged: {
                if (status === Image.Ready) {
                    loadingIndicator.visible = false
                    root.streamError = false
                } else if (status === Image.Loading) {
                    loadingIndicator.visible = true
                    root.streamError = false
                } else if (status === Image.Error) {
                    loadingIndicator.visible = false
                    root.streamError = true
                }
            }
        }

        NText {
            id: loadingIndicator
            anchors.centerIn: parent
            text: root.tr("loadingStream")
            opacity: 0.5
            visible: false
        }

        Column {
            anchors.centerIn: parent
            spacing: Style.marginS
            visible: root.streamError && root.hasStream

            NIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "alert-triangle"
                opacity: 0.5
            }

            NText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.isConnected ? root.tr("streamError") : root.tr("frigateOffline")
                horizontalAlignment: Text.AlignHCenter
                opacity: 0.5
                wrapMode: Text.Wrap
            }
        }

        NText {
            anchors.centerIn: parent
            text: root.tr("noCamerasConfigured")
            horizontalAlignment: Text.AlignHCenter
            opacity: 0.5
            visible: !root.hasStream && !loadingIndicator.visible && !root.streamError
            wrapMode: Text.Wrap
        }

        Timer {
            id: reconnectTimer
            interval: 200
            onTriggered: {
                if (root.hasStream) {
                    streamView.source = root.streamUrl
                }
            }
        }
    }
}
