import QtQuick
import Quickshell
import qs.Commons
import qs.Widgets
import "Translation.js" as Translation

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

    // HTTP Basic Auth credentials (SEC-1). When both are set, image requests
    // must be authenticated manually because snapshotBaseUrl is credential-free.
    readonly property string authUsername: mainInst?.username ?? ""
    readonly property string authPassword: mainInst?.password ?? ""
    readonly property bool needsAuth: authUsername !== "" && authPassword !== ""

    property bool streaming: false
    property int frameCount: 0

    // QUAL-5: single state property. true => buffer A is the load target /
    // currently-hidden buffer; the visible buffer is the *other* one.
    // Pre-first-frame both buffers are blank; we deliberately show buffer A
    // (loadTargetIsA stays true until the first successful frame flips it).
    property bool loadTargetIsA: true

    property bool waitingFrame: false
    property var cameraAspectRatios: ({})

    // ROB-3: request-generation counter. Bumped on every fetch start and on
    // stop; a stale ready/error carrying an old generation is ignored.
    property int requestGeneration: 0

    // ROB-3b: per-buffer generation captured at the moment a frame source is
    // assigned. An Image.onStatusChanged event whose buffer generation no
    // longer matches requestGeneration is from a superseded load cycle and
    // must be ignored. -1 means "no frame currently assigned to this buffer".
    property int bufferAGen: -1
    property int bufferBGen: -1

    // ROB-4: exponential backoff bookkeeping.
    property int consecutiveFailures: 0
    readonly property int retryBaseMs: 2000
    readonly property int retryMaxMs: 30000

    // BND-B: streaming phase drives statusText. One of:
    // "" (frames flowing) | "loading" | "error".
    property string streamPhase: ""

    readonly property int previewIntervalMs: 1000
    readonly property real defaultAspectRatio: 16 / 9
    readonly property real minAspectRatio: 0.4
    readonly property real maxAspectRatio: 3.0
    readonly property real streamMargin: 4 * Style.uiScaleRatio
    readonly property real headerHeightPx: 36 * Style.uiScaleRatio
    readonly property real footerHeightPx: 18 * Style.uiScaleRatio
    readonly property real navButtonSize: 28 * Style.uiScaleRatio
    readonly property real navButtonMargin: 4 * Style.uiScaleRatio
    readonly property real minPanelWidth: 260 * Style.uiScaleRatio
    readonly property real minPanelHeight: 190 * Style.uiScaleRatio
    readonly property real maxPanelWidth: screen ? screen.width * 0.86 : 960 * Style.uiScaleRatio
    readonly property real maxPanelHeight: screen ? screen.height * 0.82 : 820 * Style.uiScaleRatio
    readonly property real baseStreamArea: 472 * 250 * Style.uiScaleRatio * Style.uiScaleRatio

    readonly property real currentAspectRatio: {
        let ratio = cameraAspectRatios[cameraName]
        if (typeof ratio !== "number" || !isFinite(ratio) || ratio <= 0) {
            ratio = defaultAspectRatio
        }

        return Math.max(minAspectRatio, Math.min(maxAspectRatio, ratio))
    }

    readonly property var streamSize: streamSizeForAspect(currentAspectRatio)

    // BND-B: single derived status string. Streaming functions only mutate
    // plain state properties; this binding turns state into displayed text.
    readonly property string statusText: {
        if (!hasSnapshot) return root.tr("noCamerasConfigured")
        if (streamPhase === "loading") return root.tr("loadingStream")
        if (streamPhase === "error") {
            return isConnected ? root.tr("streamError") : root.tr("frigateOffline")
        }
        return ""
    }

    function tr(key, params) {
        return Translation.tr(pluginApi, key, params)
    }

    function stampedUrl() {
        if (!snapshotBaseUrl) return ""
        return snapshotBaseUrl + "?t=" + Date.now()
    }

    function startStreaming() {
        if (!hasSnapshot) return
        // ROB-3: no-op if already streaming the same URL.
        if (streaming && activeStreamUrl === snapshotBaseUrl) return

        streaming = true
        activeStreamUrl = snapshotBaseUrl
        frameCount = 0
        loadTargetIsA = true
        waitingFrame = false
        consecutiveFailures = 0
        streamPhase = "loading"
        abortInFlight()
        flushFrameBuffers()
        frameTimer.stop()
        retryTimer.stop()
        watchdogTimer.stop()
        requestNextFrame()
    }

    function stopStreaming() {
        streaming = false
        activeStreamUrl = ""
        waitingFrame = false
        // ROB-3: invalidate any in-flight load so its late ready/error is dropped.
        requestGeneration++
        abortInFlight()
        frameTimer.stop()
        retryTimer.stop()
        watchdogTimer.stop()
        streamPhase = ""
        flushFrameBuffers()
    }

    // ROB-3: tracks which URL the current streaming session is bound to.
    property string activeStreamUrl: ""

    // SEC-1: handle to the in-flight authenticated XMLHttpRequest, if any.
    property var inFlightXhr: null

    function abortInFlight() {
        if (inFlightXhr) {
            try {
                inFlightXhr.onreadystatechange = function () {}
                inFlightXhr.ontimeout = function () {}
                inFlightXhr.abort()
            } catch (e) {
                // ignore: aborting an already-finished request is harmless
            }
            inFlightXhr = null
        }
    }

    function flushFrameBuffers() {
        bufferA.source = ""
        bufferB.source = ""
        // ROB-3b: clearing the sources invalidates any captured generation.
        bufferAGen = -1
        bufferBGen = -1
    }

    function scheduleNextFrame() {
        if (!streaming || !hasSnapshot) {
            frameTimer.stop()
            return
        }

        frameTimer.interval = previewIntervalMs
        frameTimer.restart()
    }

    // SEC-1: convert an ArrayBuffer of JPEG bytes into a data: URI.
    function arrayBufferToDataUri(buffer) {
        const bytes = new Uint8Array(buffer)
        let binary = ""
        const chunk = 8192
        for (let i = 0; i < bytes.length; i += chunk) {
            const slice = bytes.subarray(i, Math.min(i + chunk, bytes.length))
            binary += String.fromCharCode.apply(null, slice)
        }
        return "data:image/jpeg;base64," + Qt.btoa(binary)
    }

    function assignSource(url) {
        // ROB-3b: stamp the load-target buffer with the current generation so
        // a late Image.onStatusChanged event can be matched to its load cycle.
        if (loadTargetIsA) {
            bufferA.source = ""
            bufferAGen = requestGeneration
            bufferA.source = url
        } else {
            bufferB.source = ""
            bufferBGen = requestGeneration
            bufferB.source = url
        }
    }

    function requestNextFrame() {
        if (!streaming || !hasSnapshot || waitingFrame) return

        const url = stampedUrl()
        if (!url) return

        waitingFrame = true
        // ROB-3: bump the generation for every fetch start (auth and no-auth
        // alike) so each load cycle is uniquely identifiable. assignSource
        // captures this value per-buffer; stale buffer events are dropped.
        const generation = ++requestGeneration
        // ROB-2: arm the per-frame watchdog as soon as a fetch starts.
        watchdogTimer.restart()

        if (!needsAuth) {
            // NO-AUTH: assign the URL directly; the Image element fetches it.
            assignSource(url)
            return
        }

        // AUTH: fetch bytes ourselves so we can attach the Authorization header.
        const xhr = new XMLHttpRequest()
        inFlightXhr = xhr
        xhr.open("GET", url)
        xhr.responseType = "arraybuffer"
        xhr.timeout = 7000

        // UTF-8-encode credentials so non-ASCII passwords survive base64.
        const credentials = unescape(encodeURIComponent(authUsername + ":" + authPassword))
        xhr.setRequestHeader("Authorization", "Basic " + Qt.btoa(credentials))

        xhr.ontimeout = function () {
            if (generation !== root.requestGeneration) return
            root.inFlightXhr = null
            root.handleFrameError(generation)
        }

        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (generation !== root.requestGeneration) return
            root.inFlightXhr = null

            const status = xhr.status
            if (status === 0 || status < 200 || status >= 300) {
                // HTTP error or network failure.
                root.handleFrameError(generation)
                return
            }

            try {
                const dataUri = root.arrayBufferToDataUri(xhr.response)
                root.assignSource(dataUri)
            } catch (e) {
                root.handleFrameError(generation)
            }
        }

        xhr.send()
    }

    function handleFrameReady(imageItem, loadedBufferIsA, bufferGen) {
        if (!streaming) return
        // ROB-3b: drop a late ready whose buffer was stamped by an earlier
        // load cycle (camera switch, retry, watchdog abort, stop).
        if (bufferGen !== requestGeneration) return
        // ROB-3: drop a late ready from an aborted/superseded load.
        // The currently-pending load always targets loadTargetIsA.
        if (loadedBufferIsA !== loadTargetIsA) return
        if (!waitingFrame) return

        watchdogTimer.stop()
        updateAspectRatio(imageItem)
        streamPhase = ""
        frameCount++
        waitingFrame = false
        // ROB-4: reset backoff on a successful frame.
        consecutiveFailures = 0
        retryTimer.interval = retryBaseMs
        // QUAL-5: flip the single state property; the just-loaded buffer
        // becomes visible, the other becomes the next load target.
        loadTargetIsA = !loadedBufferIsA
        scheduleNextFrame()
    }

    // ROB-3: generation is optional; when supplied a stale call is ignored.
    // ROB-3b: errorBufferIsA is supplied only by Image.onStatusChanged paths;
    // when present, the errored buffer must be the current load target.
    function handleFrameError(generation, errorBufferIsA) {
        if (!streaming) return
        // ROB-3b: a frame error is only valid for an in-flight fetch. Without
        // an active wait there is no terminal event to deliver.
        if (!waitingFrame) return
        if (generation !== undefined && generation !== requestGeneration) return
        // ROB-3b: an Image.Error must originate from the current load-target
        // buffer; an error from the visible/stale buffer is ignored.
        if (errorBufferIsA !== undefined && errorBufferIsA !== loadTargetIsA) return

        watchdogTimer.stop()
        abortInFlight()
        waitingFrame = false
        frameTimer.stop()
        streamPhase = "error"

        // ROB-4: exponential backoff, doubling per consecutive failure.
        consecutiveFailures++
        let delay = retryBaseMs * Math.pow(2, consecutiveFailures - 1)
        if (delay > retryMaxMs) delay = retryMaxMs
        retryTimer.interval = delay
        retryTimer.restart()
    }

    function updateAspectRatio(imageItem) {
        // PERF-1 coupling: sourceSize is now set explicitly, so it no longer
        // reports the native frame dimensions. Use the painted size instead.
        let width = imageItem?.paintedWidth ?? 0
        let height = imageItem?.paintedHeight ?? 0

        if ((width <= 0 || height <= 0) && imageItem) {
            width = imageItem.implicitWidth
            height = imageItem.implicitHeight
        }

        if (!cameraName || width <= 0 || height <= 0) return

        const ratio = width / height
        if (!isFinite(ratio) || ratio <= 0) return

        if (cameraAspectRatios[cameraName] === ratio) return

        const nextRatios = Object.assign({}, cameraAspectRatios)
        nextRatios[cameraName] = ratio
        cameraAspectRatios = nextRatios
    }

    function streamSizeForAspect(aspectRatio) {
        const ratio = Math.max(minAspectRatio, Math.min(maxAspectRatio, aspectRatio))
        const chromeWidth = streamMargin * 2
        const chromeHeight = headerHeightPx + footerHeightPx + (streamMargin * 2)
        const minStreamWidth = Math.max(120 * Style.uiScaleRatio, minPanelWidth - chromeWidth)
        const minStreamHeight = Math.max(90 * Style.uiScaleRatio, minPanelHeight - chromeHeight)
        const maxStreamWidth = Math.max(minStreamWidth, maxPanelWidth - chromeWidth)
        const maxStreamHeight = Math.max(minStreamHeight, maxPanelHeight - chromeHeight)

        let width = Math.sqrt(baseStreamArea * ratio)
        let height = width / ratio

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

    // ROB-3: single guarded streaming transition. Compute the desired state
    // and only act when it actually changes; startStreaming itself is a no-op
    // when already streaming the same URL.
    function syncStreamingState() {
        const shouldStream = visible && hasSnapshot
        if (shouldStream) {
            startStreaming()
        } else if (streaming) {
            stopStreaming()
        }
    }

    onSnapshotBaseUrlChanged: {
        // A URL change means a different camera/endpoint: drop the old session.
        if (streaming && activeStreamUrl !== snapshotBaseUrl) {
            stopStreaming()
        }
        syncStreamingState()
    }

    onVisibleChanged: syncStreamingState()

    readonly property real contentPreferredWidth: streamSize.width + (streamMargin * 2)
    readonly property real contentPreferredHeight: headerHeightPx + streamSize.height + footerHeightPx + (streamMargin * 2)
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
                anchors.leftMargin: root.navButtonMargin
                width: root.navButtonSize
                height: root.navButtonSize
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
                anchors.rightMargin: root.navButtonMargin
                width: root.navButtonSize
                height: root.navButtonSize
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
            // QUAL-1: re-anchored to a stable, clean footer (camera name only).
            anchors.bottom: footerLabel.top
            anchors.margins: root.streamMargin

            Image {
                id: bufferA
                anchors.fill: parent
                cache: false
                fillMode: Image.PreserveAspectFit
                // QUAL-5: visibility derived from the single state property.
                // The load target is hidden; the other buffer is shown.
                visible: !root.loadTargetIsA
                asynchronous: true
                // PERF-1: decode at on-screen pixel size.
                sourceSize.width: root.streamSize.width
                sourceSize.height: root.streamSize.height

                onStatusChanged: {
                    if (status === Image.Ready) {
                        root.handleFrameReady(bufferA, true, root.bufferAGen)
                    } else if (status === Image.Error) {
                        // ROB-3b: report this buffer's captured generation and
                        // side so a stale/non-target error is dropped.
                        root.handleFrameError(root.bufferAGen, true)
                    }
                }
            }

            Image {
                id: bufferB
                anchors.fill: parent
                cache: false
                fillMode: Image.PreserveAspectFit
                visible: root.loadTargetIsA
                asynchronous: true
                // PERF-1: decode at on-screen pixel size.
                sourceSize.width: root.streamSize.width
                sourceSize.height: root.streamSize.height

                onStatusChanged: {
                    if (status === Image.Ready) {
                        root.handleFrameReady(bufferB, false, root.bufferBGen)
                    } else if (status === Image.Error) {
                        // ROB-3b: report this buffer's captured generation and
                        // side so a stale/non-target error is dropped.
                        root.handleFrameError(root.bufferBGen, false)
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
            // ROB-4: interval is set dynamically (exponential backoff).
            interval: root.retryBaseMs
            repeat: false
            onTriggered: {
                if (root.streaming && root.hasSnapshot) {
                    root.requestNextFrame()
                }
            }
        }

        // ROB-2: per-frame watchdog. Interval comfortably above
        // previewIntervalMs so a healthy fetch always resolves first.
        Timer {
            id: watchdogTimer
            interval: 8000
            repeat: false
            onTriggered: {
                if (!root.streaming || !root.waitingFrame) return
                // Treat a stuck fetch as a frame error.
                // ROB-3b: blank the affected (load-target) buffer and clear
                // its captured generation so the stale Image event is dropped.
                if (root.loadTargetIsA) {
                    bufferA.source = ""
                    root.bufferAGen = -1
                } else {
                    bufferB.source = ""
                    root.bufferBGen = -1
                }
                // handleFrameError aborts the in-flight XHR and clears
                // waitingFrame itself; it requires waitingFrame to still be
                // true here (it is, per the guard above), so it is invoked
                // before any clearing to deliver the terminal error.
                root.handleFrameError(root.requestGeneration)
            }
        }

        NText {
            id: statusLabel
            // ROB/I1: center on the actual stream viewport.
            anchors.centerIn: streamContainer
            horizontalAlignment: Text.AlignHCenter
            // BND-B: single bound source of truth; never assigned imperatively.
            text: root.statusText
            opacity: 0.5
            wrapMode: Text.Wrap
        }

        // QUAL-1: clean footer showing only the camera name.
        NText {
            id: footerLabel
            height: root.footerHeightPx
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: root.streamMargin
            anchors.rightMargin: root.streamMargin
            text: root.cameraName
            opacity: 0.3
            font.pixelSize: 10 * Style.uiScaleRatio
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
    }
}
