import QtQuick
import Quickshell
import qs.Commons
import qs.Widgets

Item {
    id: root
    property var pluginApi: null
    property ShellScreen screen

    readonly property var mainInst: pluginApi?.mainInstance ?? null
    readonly property string snapshotBaseUrl: mainInst?.snapshotBaseUrl ?? ""
    readonly property string cameraName: mainInst?.currentCameraName ?? ""
    readonly property int cameraCount: mainInst?.selectedCameras?.length ?? 0
    readonly property bool hasSnapshot: snapshotBaseUrl !== ""
    readonly property bool isConnected: mainInst?.connectionStatus === "connected"

    property bool streaming: false
    property int frameCount: 0
    property bool bufferFlip: false

    function tr(key) {
        return pluginApi?.tr(key) ?? key
    }

    function stampedUrl() {
        if (!snapshotBaseUrl) return ""
        return snapshotBaseUrl + "?t=" + Date.now()
    }

    function startStreaming() {
        if (!hasSnapshot) return
        streaming = true
        frameCount = 0
        bufferFlip = false
        bufferA.source = stampedUrl()
    }

    function stopStreaming() {
        streaming = false
        bufferA.source = ""
        bufferB.source = ""
    }

    onSnapshotBaseUrlChanged: {
        stopStreaming()
        if (snapshotBaseUrl) startStreaming()
    }

    onVisibleChanged: {
        if (visible && hasSnapshot) startStreaming()
        else stopStreaming()
    }

    readonly property real screenHeight: screen?.height ?? 1080
    readonly property real panelHeight: Math.round(screenHeight / 4)
    readonly property real aspectRatio: 16 / 9

    width: Math.round(panelHeight * aspectRatio)
    height: panelHeight

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

        Item {
            id: streamContainer
            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: debugLabel.top
            anchors.margins: 4

            Image {
                id: bufferA
                anchors.fill: parent
                cache: false
                fillMode: Image.PreserveAspectFit
                visible: !root.bufferFlip
                asynchronous: true

                onStatusChanged: {
                    if (status === Image.Ready) {
                        statusLabel.text = ""
                        root.frameCount++
                        if (root.streaming) {
                            root.bufferFlip = false
                            bufferB.source = root.stampedUrl()
                        }
                    } else if (status === Image.Error) {
                        statusLabel.text = root.isConnected ? root.tr("streamError") : root.tr("frigateOffline")
                        retryTimer.start()
                    }
                }
            }

            Image {
                id: bufferB
                anchors.fill: parent
                cache: false
                fillMode: Image.PreserveAspectFit
                visible: root.bufferFlip
                asynchronous: true

                onStatusChanged: {
                    if (status === Image.Ready) {
                        statusLabel.text = ""
                        root.frameCount++
                        if (root.streaming) {
                            root.bufferFlip = true
                            bufferA.source = root.stampedUrl()
                        }
                    } else if (status === Image.Error) {
                        statusLabel.text = root.isConnected ? root.tr("streamError") : root.tr("frigateOffline")
                        retryTimer.start()
                    }
                }
            }
        }

        Timer {
            id: retryTimer
            interval: 2000
            repeat: false
            onTriggered: {
                if (root.streaming && root.hasSnapshot) {
                    root.bufferFlip = false
                    bufferA.source = root.stampedUrl()
                }
            }
        }

        NText {
            id: statusLabel
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: root.hasSnapshot ? "" : root.tr("noCamerasConfigured")
            opacity: 0.5
            wrapMode: Text.Wrap
        }

        NText {
            id: debugLabel
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 4
            text: "FPS: ~" + root.frameCount + " frames | " + root.snapshotBaseUrl
            opacity: 0.3
            font.pixelSize: 10
            wrapMode: Text.Wrap
        }
    }
}
