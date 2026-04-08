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
    property bool nextBufferIsA: true
    property bool waitingFrame: false
    property var cameraAspectRatios: ({})

    readonly property int previewIntervalMs: 1000
    readonly property real defaultAspectRatio: 16 / 9
    readonly property real minAspectRatio: 0.4
    readonly property real maxAspectRatio: 3.0
    readonly property real streamMargin: 4 * Style.uiScaleRatio
    readonly property real headerHeightPx: 36
    readonly property real footerHeightPx: 18 * Style.uiScaleRatio
    readonly property real minPanelWidth: 260 * Style.uiScaleRatio
    readonly property real minPanelHeight: 190 * Style.uiScaleRatio
    readonly property real maxPanelWidth: screen ? screen.width * 0.86 : 960 * Style.uiScaleRatio
    readonly property real maxPanelHeight: screen ? screen.height * 0.82 : 820 * Style.uiScaleRatio
    readonly property real baseStreamArea: 472 * 250 * Style.uiScaleRatio * Style.uiScaleRatio

    readonly property real currentAspectRatio: {
        var ratio = cameraAspectRatios[cameraName]
        if (typeof ratio !== "number" || !isFinite(ratio) || ratio <= 0) {
            ratio = defaultAspectRatio
        }

        return Math.max(minAspectRatio, Math.min(maxAspectRatio, ratio))
    }

    readonly property var streamSize: streamSizeForAspect(currentAspectRatio)

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
        nextBufferIsA = true
        waitingFrame = false
        statusLabel.text = ""
        frameTimer.stop()
        retryTimer.stop()
        requestNextFrame()
    }

    function stopStreaming() {
        streaming = false
        waitingFrame = false
        frameTimer.stop()
        retryTimer.stop()
        bufferA.source = ""
        bufferB.source = ""
    }

    function scheduleNextFrame() {
        if (!streaming || !hasSnapshot) {
            frameTimer.stop()
            return
        }

        frameTimer.interval = previewIntervalMs
        frameTimer.restart()
    }

    function requestNextFrame() {
        if (!streaming || !hasSnapshot || waitingFrame) return

        var url = stampedUrl()
        if (!url) return

        waitingFrame = true
        if (nextBufferIsA) {
            bufferA.source = url
        } else {
            bufferB.source = url
        }
    }

    function handleFrameReady(imageItem, loadedBufferIsA) {
        if (!streaming) return

        updateAspectRatio(imageItem)
        statusLabel.text = ""
        frameCount++
        waitingFrame = false
        bufferFlip = !loadedBufferIsA
        nextBufferIsA = !loadedBufferIsA
        scheduleNextFrame()
    }

    function handleFrameError() {
        if (!streaming) return

        waitingFrame = false
        frameTimer.stop()
        statusLabel.text = isConnected ? tr("streamError") : tr("frigateOffline")
        retryTimer.restart()
    }

    function updateAspectRatio(imageItem) {
        var width = imageItem?.sourceSize?.width ?? 0
        var height = imageItem?.sourceSize?.height ?? 0

        if ((width <= 0 || height <= 0) && imageItem) {
            width = imageItem.implicitWidth
            height = imageItem.implicitHeight
        }

        if (!cameraName || width <= 0 || height <= 0) return

        var ratio = width / height
        if (!isFinite(ratio) || ratio <= 0) return

        if (cameraAspectRatios[cameraName] === ratio) return

        var nextRatios = Object.assign({}, cameraAspectRatios)
        nextRatios[cameraName] = ratio
        cameraAspectRatios = nextRatios
    }

    function streamSizeForAspect(aspectRatio) {
        var ratio = Math.max(minAspectRatio, Math.min(maxAspectRatio, aspectRatio))
        var chromeWidth = streamMargin * 2
        var chromeHeight = headerHeightPx + footerHeightPx + (streamMargin * 2)
        var minStreamWidth = Math.max(120 * Style.uiScaleRatio, minPanelWidth - chromeWidth)
        var minStreamHeight = Math.max(90 * Style.uiScaleRatio, minPanelHeight - chromeHeight)
        var maxStreamWidth = Math.max(minStreamWidth, maxPanelWidth - chromeWidth)
        var maxStreamHeight = Math.max(minStreamHeight, maxPanelHeight - chromeHeight)

        var width = Math.sqrt(baseStreamArea * ratio)
        var height = width / ratio

        if (width < minStreamWidth) {
            width = minStreamWidth
            height = width / ratio
        }
        if (height < minStreamHeight) {
            height = minStreamHeight
            width = height * ratio
        }
        if (width > maxStreamWidth) {
            width = maxStreamWidth
            height = width / ratio
        }
        if (height > maxStreamHeight) {
            height = maxStreamHeight
            width = height * ratio
        }

        return {
            "width": Math.round(width),
            "height": Math.round(height)
        }
    }

    onSnapshotBaseUrlChanged: {
        stopStreaming()
        if (snapshotBaseUrl) startStreaming()
    }

    onVisibleChanged: {
        if (visible && hasSnapshot) startStreaming()
        else stopStreaming()
    }

    property real contentPreferredWidth: streamSize.width + (streamMargin * 2)
    property real contentPreferredHeight: headerHeightPx + streamSize.height + footerHeightPx + (streamMargin * 2)
    anchors.fill: parent

    Rectangle {
        anchors.fill: parent
        color: Color.mSurface

        Rectangle {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: root.headerHeightPx
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
            anchors.margins: root.streamMargin

            Image {
                id: bufferA
                anchors.fill: parent
                cache: false
                fillMode: Image.PreserveAspectFit
                visible: !root.bufferFlip
                asynchronous: true

                onStatusChanged: {
                    if (status === Image.Ready) {
                        root.handleFrameReady(bufferA, true)
                    } else if (status === Image.Error) {
                        root.handleFrameError()
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
                        root.handleFrameReady(bufferB, false)
                    } else if (status === Image.Error) {
                        root.handleFrameError()
                    }
                }
            }
        }

        Timer {
            id: frameTimer
            interval: root.previewIntervalMs
            repeat: false
            onTriggered: root.requestNextFrame()
        }

        Timer {
            id: retryTimer
            interval: 2000
            repeat: false
            onTriggered: {
                if (root.streaming && root.hasSnapshot) {
                    root.requestNextFrame()
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
            height: root.footerHeightPx
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: root.streamMargin
            anchors.rightMargin: root.streamMargin
            text: root.cameraName + " | " + root.frameCount + " frames"
            opacity: 0.3
            font.pixelSize: 10
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
    }
}
