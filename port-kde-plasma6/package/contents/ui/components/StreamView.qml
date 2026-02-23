import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: root
    clip: true

    required property string snapshotBaseUrl
    required property string streamBaseUrl
    required property string cameraName
    required property bool connected
    required property bool active
    required property string noCameraText
    required property string loadingStreamText
    required property string streamErrorText
    required property string offlineText
    required property string previewHintText
    required property string liveHintText

    property bool streaming: false
    property bool liveMode: false
    property bool bufferFlip: false
    property bool nextBufferIsA: true
    property bool waitingFrame: false
    property int frameCount: 0
    property string statusText: noCameraText
    property var cameraAspectRatios: ({})
    readonly property int previewIntervalMs: 1000
    readonly property int liveIntervalMs: 180
    readonly property string interactionHint: {
        if (!streaming || !snapshotBaseUrl || statusText.length > 0) {
            return ""
        }
        return liveMode ? liveHintText : previewHintText
    }

    readonly property real defaultAspectRatio: 16 / 9
    readonly property real minAspectRatio: 0.4
    readonly property real maxAspectRatio: 3.0
    readonly property real minVideoWidth: 260
    readonly property real minVideoHeight: 150
    readonly property real maxVideoWidth: 1400
    readonly property real maxVideoHeight: 900
    readonly property real baseVideoArea: 472 * 250

    readonly property real currentAspectRatio: {
        var ratio = cameraAspectRatios[cameraName]
        if (typeof ratio !== "number" || !isFinite(ratio) || ratio <= 0) {
            ratio = defaultAspectRatio
        }

        return Math.max(minAspectRatio, Math.min(maxAspectRatio, ratio))
    }

    readonly property var preferredVideoSize: preferredVideoSizeForAspect(currentAspectRatio)
    readonly property int preferredVideoWidth: preferredVideoSize.width
    readonly property int preferredVideoHeight: preferredVideoSize.height

    anchors.fill: parent

    function updateAspectRatio(imageItem) {
        var width = imageItem && imageItem.sourceSize ? imageItem.sourceSize.width : 0
        var height = imageItem && imageItem.sourceSize ? imageItem.sourceSize.height : 0

        if ((width <= 0 || height <= 0) && imageItem) {
            width = imageItem.implicitWidth
            height = imageItem.implicitHeight
        }

        if (!cameraName || width <= 0 || height <= 0) {
            return
        }

        var ratio = width / height
        if (!isFinite(ratio) || ratio <= 0) {
            return
        }

        if (cameraAspectRatios[cameraName] === ratio) {
            return
        }

        var nextRatios = Object.assign({}, cameraAspectRatios)
        nextRatios[cameraName] = ratio
        cameraAspectRatios = nextRatios
    }

    function preferredVideoSizeForAspect(aspectRatio) {
        var ratio = Math.max(minAspectRatio, Math.min(maxAspectRatio, aspectRatio))
        var width = Math.sqrt(baseVideoArea * ratio)
        var height = width / ratio

        if (width < minVideoWidth) {
            width = minVideoWidth
            height = width / ratio
        }
        if (height < minVideoHeight) {
            height = minVideoHeight
            width = height * ratio
        }
        if (width > maxVideoWidth) {
            width = maxVideoWidth
            height = width / ratio
        }
        if (height > maxVideoHeight) {
            height = maxVideoHeight
            width = height * ratio
        }

        return {
            "width": Math.round(width),
            "height": Math.round(height)
        }
    }

    function stampedUrl() {
        if (!snapshotBaseUrl) {
            return ""
        }

        var separator = snapshotBaseUrl.indexOf("?") === -1 ? "?" : "&"
        return snapshotBaseUrl + separator + "t=" + Date.now()
    }

    function scheduleNextFrame() {
        if (!streaming || !snapshotBaseUrl) {
            frameTimer.stop()
            return
        }

        frameTimer.interval = liveMode ? liveIntervalMs : previewIntervalMs
        frameTimer.restart()
    }

    function requestNextFrame() {
        if (!streaming || !snapshotBaseUrl || waitingFrame) {
            return
        }

        var url = stampedUrl()
        if (!url) {
            return
        }

        waitingFrame = true
        if (nextBufferIsA) {
            bufferA.source = url
        } else {
            bufferB.source = url
        }
    }

    function handleFrameReady(imageItem, loadedBufferIsA) {
        if (!streaming) {
            return
        }

        updateAspectRatio(imageItem)
        statusText = ""
        frameCount = frameCount + 1
        waitingFrame = false
        bufferFlip = !loadedBufferIsA
        nextBufferIsA = !loadedBufferIsA
        scheduleNextFrame()
    }

    function handleFrameError() {
        waitingFrame = false
        statusText = connected ? streamErrorText : offlineText
        retryTimer.restart()
    }

    function toggleLiveMode() {
        if (!streaming || !snapshotBaseUrl || statusText.length > 0) {
            return
        }

        liveMode = !liveMode
        scheduleNextFrame()
    }

    function startStreaming() {
        if (!snapshotBaseUrl || !active) {
            stopStreaming()
            return
        }

        streaming = true
        liveMode = false
        bufferFlip = false
        nextBufferIsA = true
        waitingFrame = false
        frameCount = 0
        statusText = ""
        frameTimer.stop()
        retryTimer.stop()
        requestNextFrame()
    }

    function stopStreaming() {
        streaming = false
        liveMode = false
        waitingFrame = false
        frameTimer.stop()
        retryTimer.stop()
        bufferA.source = ""
        bufferB.source = ""
        statusText = snapshotBaseUrl ? "" : noCameraText
    }

    onSnapshotBaseUrlChanged: {
        stopStreaming()
        if (snapshotBaseUrl && active) {
            startStreaming()
        }
    }

    onActiveChanged: {
        if (active && snapshotBaseUrl) {
            startStreaming()
        } else {
            stopStreaming()
        }
    }

    Component.onCompleted: {
        if (active && snapshotBaseUrl) {
            startStreaming()
        }
    }

    Image {
        id: bufferA
        anchors.fill: parent
        cache: false
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        visible: !root.bufferFlip

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
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        visible: root.bufferFlip

        onStatusChanged: {
            if (status === Image.Ready) {
                root.handleFrameReady(bufferB, false)
            } else if (status === Image.Error) {
                root.handleFrameError()
            }
        }
    }

    Timer {
        id: frameTimer
        interval: root.previewIntervalMs
        repeat: false
        onTriggered: {
            root.requestNextFrame()
        }
    }

    Timer {
        id: retryTimer
        interval: 2000
        repeat: false
        onTriggered: {
            if (root.streaming && root.snapshotBaseUrl) {
                root.requestNextFrame()
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.streaming && root.snapshotBaseUrl.length > 0 && root.statusText.length === 0
        hoverEnabled: enabled
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.toggleLiveMode()
    }

    Rectangle {
        id: statusPill
        anchors.centerIn: parent
        width: Math.min(root.width * 0.92, statusLabel.implicitWidth + Kirigami.Units.largeSpacing * 1.5)
        height: statusLabel.implicitHeight + Kirigami.Units.smallSpacing * 1.8
        radius: height / 2
        visible: statusLabel.visible
        color: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, Kirigami.Theme.textColor, 0.12)
        border.width: 1
        border.color: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.textColor, Kirigami.Theme.backgroundColor, 0.70)

        Text {
            id: statusLabel
            anchors.centerIn: parent
            width: Math.max(0, statusPill.width - Kirigami.Units.largeSpacing)
            text: root.statusText
            visible: text.length > 0
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            opacity: 0.85
        }
    }

    Rectangle {
        id: hintPill
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        radius: height / 2
        visible: hintLabel.visible
        color: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, Kirigami.Theme.highlightColor, 0.12)
        border.width: 1
        border.color: Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.textColor, Kirigami.Theme.backgroundColor, 0.70)
        implicitWidth: Math.min(parent.width * 0.92, hintLabel.implicitWidth + Kirigami.Units.largeSpacing * 1.2)
        implicitHeight: hintLabel.implicitHeight + Kirigami.Units.smallSpacing * 1.5

        Text {
            id: hintLabel
            anchors.centerIn: parent
            width: Math.max(0, hintPill.width - Kirigami.Units.largeSpacing)
            text: root.interactionHint
            visible: text.length > 0
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            opacity: 0.75
            font.pixelSize: 11
        }
    }
}
