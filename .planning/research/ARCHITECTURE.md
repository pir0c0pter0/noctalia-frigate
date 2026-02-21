# Architecture Patterns

**Domain:** Noctalia Shell plugin — Frigate NVR MJPEG camera viewer
**Researched:** 2026-02-21
**Confidence:** HIGH (Noctalia plugin structure) / MEDIUM (MJPEG rendering strategy)

---

## Recommended Architecture

```
manifest.json
├── Main.qml          (state hub + HTTP polling daemon)
├── BarWidget.qml     (bar icon + status dot)
├── Panel.qml         (MJPEG viewer + navigation)
└── Settings.qml      (connection config + camera selection)
```

Data flows unidirectionally: Main.qml is the single source of truth. BarWidget
and Panel consume state through `pluginApi.mainInstance`. Settings writes back
to `pluginApi.pluginSettings` and triggers Main.qml reactions via property
change handlers.

---

## Component Boundaries

| Component | Responsibility | Communicates With |
|-----------|---------------|-------------------|
| **manifest.json** | Plugin identity, entry points, default settings | Noctalia PluginService (load/unload) |
| **Main.qml** | HTTP polling to Frigate; exposes computed state (connectionStatus, cameraList, currentIndex); no UI | BarWidget, Panel (read via `pluginApi.mainInstance`); Settings (write via `pluginApi.pluginSettings`) |
| **BarWidget.qml** | Renders camera icon + green/red status dot; opens panel on click | Main.qml (reads `connectionStatus`, `currentCameraName`); Noctalia bar (receives `pluginApi`, `screen`) |
| **Panel.qml** | Renders MJPEG stream Image + camera name header + prev/next navigation buttons | Main.qml (reads `streamUrl`, `currentCameraName`, `cameraList`; calls `nextCamera()`, `prevCamera()`); Frigate HTTP directly (Image.source URL) |
| **Settings.qml** | Text inputs for URL, username, password; Test Connection button; List Cameras button; camera checkbox list | Main.qml (calls `testConnection()`, `fetchCameras()`); `pluginApi.pluginSettings` (read/write); `pluginApi.saveSettings()` (persist) |

---

## Data Flow

### Startup flow

```
Noctalia PluginService
  → injects pluginApi into all components
  → Main.qml Component.onCompleted
      → reads pluginApi.pluginSettings (frigateUrl, username, password, selectedCameras)
      → starts connectionPoller Timer (interval: 30s, repeat: true)
      → fires initial connection check immediately
```

### Connection polling (Main.qml internal)

```
connectionPoller.triggered
  → XMLHttpRequest GET /api/version  (or GET /api/stats)
      → success: connectionStatus = "connected"; parse/store version
      → failure: connectionStatus = "disconnected"
  → BarWidget.statusDot re-renders via QML property binding
```

### Panel open + stream display

```
BarWidget click
  → pluginApi.openPanel(screen, root)
      → Panel.qml becomes visible
      → Panel reads pluginApi.mainInstance.streamUrl
      → Image { source: streamUrl; cache: false }
          → Qt loads URL, Frigate streams MJPEG multipart/x-mixed-replace
          → each boundary frame replaces previous frame in Image
```

### Camera navigation (Panel.qml)

```
User clicks prev/next button
  → calls pluginApi.mainInstance.prevCamera() / nextCamera()
      → Main.qml updates currentIndex (immutable: currentIndex = (currentIndex + delta + count) % count)
      → Panel binds to pluginApi.mainInstance.streamUrl (recomputed from selectedCameras[currentIndex])
      → Image.source updates; stream switches
```

### Settings — Test Connection

```
User clicks "Test Connection"
  → Settings calls pluginApi.mainInstance.testConnection(url, user, pass)
      → Main.qml: XMLHttpRequest GET <url>/api/version
          → headers: Authorization: Basic base64(user:pass) if credentials provided
          → success: emit testResult("ok", version)
          → failure: emit testResult("error", errorMessage)
      → Settings.qml shows green or red feedback label
```

### Settings — List Cameras

```
User clicks "List Cameras"
  → Settings calls pluginApi.mainInstance.fetchCameras(url, user, pass)
      → Main.qml: XMLHttpRequest GET <url>/api/config
          → parse JSON: Object.keys(response.cameras) → camera name array
          → emit camerasLoaded(nameArray)
      → Settings.qml renders checkbox list from nameArray
```

### Settings — Save

```
User clicks Save (or NTextInput onTextChanged triggers auto-save)
  → Settings.qml:
      pluginApi.pluginSettings.frigateUrl = editUrl
      pluginApi.pluginSettings.username   = editUsername
      pluginApi.pluginSettings.password   = editPassword
      pluginApi.pluginSettings.selectedCameras = editSelectedCameras  // array of strings
      pluginApi.pluginSettings.cameraOrder     = editCameraOrder       // ordered array
      pluginApi.saveSettings()
  → Main.qml property change handlers fire:
      → restart connectionPoller with new URL/credentials
      → recompute streamUrl from new selectedCameras[currentIndex]
```

---

## Frigate API Endpoints Used

| Endpoint | Purpose | Auth |
|----------|---------|------|
| `GET /api/version` | Health check / connection test | Yes |
| `GET /api/stats` | Alternative health check with richer data | Yes |
| `GET /api/config` | Fetch camera list via `Object.keys(response.cameras)` | Yes |
| `GET /api/<camera_name>` | MJPEG stream (multipart/x-mixed-replace) — loaded directly by QML Image | Yes (URL-embedded or header) |
| `GET /api/<camera_name>/latest.jpg` | Static snapshot fallback if MJPEG fails | Yes |

**Frigate ports:**
- Port `5000` — unauthenticated (local Docker-internal; use when no auth configured)
- Port `8971` — authenticated UI + API (use for remote access or when auth enabled)

**Auth encoding:**
- XMLHttpRequest API calls: `xhr.setRequestHeader("Authorization", "Basic " + Qt.btoa(user + ":" + pass))`
- Image.source MJPEG URL: embed credentials as `http://user:pass@host:port/api/<camera>/`
  - Confidence: MEDIUM — Qt URL-embedded basic auth works but credentials are plaintext over HTTP

---

## Patterns to Follow

### Pattern 1: Main.qml as State Hub

**What:** Main.qml owns all mutable state. BarWidget and Panel are pure readers.

**When:** Always — this is the standard Noctalia plugin pattern confirmed by niri-auto-tile and ip-monitor.

**Example (Main.qml):**
```qml
Item {
    property var pluginApi: null

    // Derived state — read by BarWidget and Panel
    readonly property string connectionStatus: _connectionStatus
    readonly property string currentCameraName: selectedCameras[currentIndex] ?? ""
    readonly property string streamUrl: _buildStreamUrl(currentCameraName)
    readonly property var cameraList: []

    // Internal mutable state
    property string _connectionStatus: "disconnected"
    property int currentIndex: 0
    property var selectedCameras: []

    function _buildStreamUrl(cameraName) {
        if (!cameraName) return ""
        const base = pluginApi?.pluginSettings?.frigateUrl ?? ""
        const user = pluginApi?.pluginSettings?.username ?? ""
        const pass = pluginApi?.pluginSettings?.password ?? ""
        if (user && pass) {
            const protocol = base.startsWith("https") ? "https" : "http"
            const rest = base.replace(/^https?:\/\//, "")
            return protocol + "://" + encodeURIComponent(user) + ":" + encodeURIComponent(pass) + "@" + rest + "/api/" + cameraName
        }
        return base + "/api/" + cameraName
    }

    function nextCamera() {
        const count = selectedCameras.length
        if (count === 0) return
        currentIndex = (currentIndex + 1) % count
    }

    function prevCamera() {
        const count = selectedCameras.length
        if (count === 0) return
        currentIndex = (currentIndex - 1 + count) % count
    }
}
```

### Pattern 2: BarWidget reading mainInstance

**What:** BarWidget binds to Main.qml properties via `pluginApi.mainInstance`.

**When:** For any state that must be reflected in the bar icon.

**Example (BarWidget.qml):**
```qml
Item {
    property var pluginApi: null
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""

    readonly property var mainInst: pluginApi?.mainInstance ?? null
    readonly property bool isConnected: mainInst?.connectionStatus === "connected"
    readonly property string cameraName: mainInst?.currentCameraName ?? ""

    Rectangle {
        id: visualCapsule
        color: mouseArea.containsMouse ? Color.mHover : Style.capsuleColor

        // Camera icon
        NIcon { name: "camera" }

        // Status dot
        Rectangle {
            width: 4; height: 4; radius: 2
            color: isConnected ? Color.mPrimary : Color.mSecondary
            visible: true
        }
    }

    MouseArea {
        id: mouseArea
        hoverEnabled: true
        onClicked: pluginApi?.openPanel(screen, visualCapsule)
    }
}
```

### Pattern 3: MJPEG stream via QML Image

**What:** QML Image loads the MJPEG endpoint URL directly. Qt's network stack handles multipart/x-mixed-replace frames. `cache: false` prevents stale data.

**When:** Displaying the live camera stream in Panel.qml.

**Example (Panel.qml stream area):**
```qml
Image {
    id: streamView
    source: pluginApi?.mainInstance?.streamUrl ?? ""
    cache: false
    fillMode: Image.PreserveAspectFit
    width: 640
    height: 400

    // Fallback: if stream fails, show error state
    onStatusChanged: {
        if (status === Image.Error) {
            streamError = true
        }
    }
}
```

**Important caveat (MEDIUM confidence):** QML Image with MJPEG works because Qt's network layer processes the multipart stream and renders each boundary frame. This is documented behavior for Qt's Image component with HTTP, but is not explicitly confirmed in Qt 6 documentation for multipart/x-mixed-replace. If it fails, the fallback is snapshot polling (see Anti-Patterns below).

### Pattern 4: XMLHttpRequest with Basic Auth (API calls)

**What:** Use `xhr.setRequestHeader()` for Authorization header on JSON API calls.

**When:** testConnection(), fetchCameras(), connectionPoller in Main.qml.

**Example:**
```qml
function makeAuthRequest(url, user, pass, callback) {
    const xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    callback(null, JSON.parse(xhr.responseText))
                } catch (e) {
                    callback("JSON parse error: " + e.message, null)
                }
            } else {
                callback("HTTP " + xhr.status, null)
            }
        }
    }
    xhr.open("GET", url, true)
    if (user && pass) {
        xhr.setRequestHeader("Authorization", "Basic " + Qt.btoa(user + ":" + pass))
    }
    xhr.send()
}
```

### Pattern 5: Camera list from /api/config

**What:** Fetch full Frigate config, extract camera names as `Object.keys(response.cameras)`.

**When:** "List Cameras" button in Settings.qml.

**Example:**
```javascript
// In fetchCameras() in Main.qml
makeAuthRequest(url + "/api/config", user, pass, function(err, data) {
    if (err) { emit camerasError(err); return }
    const names = data.cameras ? Object.keys(data.cameras) : []
    cameraList = names  // property update triggers QML bindings
})
```

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Snapshot polling as primary stream strategy

**What:** Using a Timer to repeatedly set `Image.source = url + "?t=" + Date.now()` to simulate live video.

**Why bad:** High latency between frames (500ms minimum per request/response cycle), server load from constant HTTP requests, choppy experience. MJPEG multipart streaming is designed for this use case.

**Instead:** Use MJPEG endpoint directly (`/api/<camera_name>`). Keep snapshot polling only as fallback when MJPEG fails to load.

### Anti-Pattern 2: State in BarWidget or Panel

**What:** Storing camera list, connection status, or stream URL in BarWidget.qml or Panel.qml.

**Why bad:** State is lost when panel closes. Multiple screens would have divergent state. Breaks Noctalia's component model.

**Instead:** All state in Main.qml. BarWidget and Panel are stateless views reading from `pluginApi.mainInstance`.

### Anti-Pattern 3: Hardcoded Frigate port or protocol

**What:** `Image.source: "http://localhost:5000/api/frontdoor"`

**Why bad:** Breaks for HTTPS setups, remote access, custom ports. The user's settings provide all this context.

**Instead:** Build the full URL from `pluginApi.pluginSettings.frigateUrl` plus camera name. Validate the URL includes protocol in Settings.

### Anti-Pattern 4: Blocking the QML thread with synchronous network calls

**What:** Using `xhr.open("GET", url, false)` (synchronous mode) for connection checks.

**Why bad:** Freezes the entire Noctalia UI until the request completes. Frigate timeouts (5-10s) would make the shell unresponsive.

**Instead:** Always use `xhr.open("GET", url, true)` (async) with `onreadystatechange` callback.

### Anti-Pattern 5: Mutating settings objects directly without saveSettings()

**What:** `pluginApi.pluginSettings.frigateUrl = newUrl` without calling `pluginApi.saveSettings()`.

**Why bad:** Changes are lost on plugin reload or system restart.

**Instead:** Always call `pluginApi.saveSettings()` after any pluginSettings mutation.

---

## Suggested Build Order

Build in this order to respect dependencies:

### Phase 1: Plugin Skeleton

**Components:** `manifest.json`, `Main.qml` (stub), `BarWidget.qml` (stub), `Panel.qml` (stub)

**Goal:** Plugin loads in Noctalia, bar icon appears, panel opens/closes on click. No network yet.

**Why first:** Validates plugin registration, pluginApi injection, and component wiring before any domain logic.

**Dependencies:** None (only needs Noctalia 4.4+)

### Phase 2: Settings UI + Persistence

**Components:** `Settings.qml`, manifest `defaultSettings`

**Goal:** User can enter Frigate URL, username, password. Settings persist across sessions.

**Why second:** Settings are required before any network calls can be made. Unblocks Phase 3.

**Dependencies:** Phase 1 (pluginApi available)

### Phase 3: Frigate API Integration (Main.qml)

**Components:** Main.qml — `testConnection()`, `fetchCameras()`, `connectionPoller` Timer, `cameraList` property

**Goal:** "Test Connection" and "List Cameras" work in Settings. Status dot in BarWidget shows green/red.

**Why third:** Core Frigate API interaction. Validates auth handling and API response parsing. Unblocks Phase 4.

**Dependencies:** Phase 2 (settings available with URL/credentials)

### Phase 4: MJPEG Viewer (Panel.qml)

**Components:** Panel.qml — `Image` with `source: streamUrl`, camera name header, prev/next buttons

**Goal:** Clicking bar icon shows live MJPEG stream. Navigation between cameras works.

**Why fourth:** Requires Phase 3 to have validated that `streamUrl` is computed correctly.

**Dependencies:** Phase 3 (streamUrl property on mainInstance)

### Phase 5: Camera Selection UI (Settings.qml)

**Components:** Settings.qml camera checkbox list, camera order persistence

**Goal:** User can select which cameras appear in the viewer. Order is saved.

**Why fifth:** Requires Phase 3 to have working `fetchCameras()` to populate the checkbox list.

**Dependencies:** Phase 3 (cameraList populated from Frigate API)

### Phase 6: Polish

**Components:** All files — error states, empty states, i18n keys, theme compliance audit

**Goal:** All edge cases handled (no cameras selected, Frigate offline, auth failure). All text uses `pluginApi.tr()`.

**Why last:** Polish depends on all features existing.

---

## Dependency Graph (Build Order)

```
manifest.json + stubs (Phase 1)
        ↓
Settings persistence (Phase 2)
        ↓
Frigate API in Main.qml (Phase 3)
        ↓
MJPEG viewer in Panel.qml (Phase 4) ← depends on streamUrl from Phase 3
        ↓
Camera selection UI (Phase 5) ← depends on fetchCameras from Phase 3
        ↓
Polish + i18n (Phase 6)
```

---

## Key Architectural Decisions

| Decision | Rationale | Confidence |
|----------|-----------|------------|
| Main.qml as state hub | Noctalia standard pattern; confirmed by niri-auto-tile and ip-monitor reference plugins | HIGH |
| QML Image for MJPEG | Qt's Image supports multipart/x-mixed-replace HTTP streams; no C++ extension needed; simplest approach for a pure QML plugin | MEDIUM — needs validation at runtime |
| URL-embedded auth for Image.source | QML Image does not support `setRequestHeader`; only option is `user:pass@host` URL format or XMLHttpRequest-based frame polling | MEDIUM — credentials are plaintext over HTTP, acceptable for LAN use |
| XMLHttpRequest for JSON API calls | Standard QML networking; supports setRequestHeader for proper Basic Auth headers | HIGH |
| `/api/config` for camera list | `Object.keys(response.cameras)` extracts camera names; confirmed by Frigate API docs (v0.9.0+) | HIGH |
| Frigate port 5000 vs 8971 | 5000 is unauthenticated (local Docker), 8971 is authenticated (remote/auth). Plugin uses user-configured URL which can target either port | HIGH |
| Timer-based connection polling | Standard QML pattern; confirmed in ip-monitor plugin implementation | HIGH |

---

## Scalability Considerations

This is a single-user desktop plugin, not a server. Scalability concerns are minimal. The relevant concern is stream performance:

| Concern | Approach |
|---------|---------|
| MJPEG bandwidth | Frigate serves MJPEG at configurable FPS; panel size (640x400) limits bandwidth consumption |
| Multiple screens | BarWidget is instantiated per screen by Noctalia; Panel state managed in Main.qml singleton — all screens share the same camera view state |
| Connection failure | Timer-based polling degrades gracefully; status dot shows disconnected state without crashing |
| No cameras selected | Guard in `streamUrl` computation: return empty string when `selectedCameras.length === 0`; Panel shows empty state |

---

## Sources

- Noctalia plugin structure: [Getting Started](https://docs.noctalia.dev/development/plugins/getting-started/) — HIGH confidence
- Noctalia pluginApi: [Overview](https://docs.noctalia.dev/development/plugins/overview/) — HIGH confidence
- Noctalia BarWidget: [Bar Widget docs](https://docs.noctalia.dev/development/plugins/bar-widget/) — HIGH confidence
- Noctalia Settings UI: [Settings UI docs](https://docs.noctalia.dev/development/plugins/settings-ui/) — HIGH confidence
- Noctalia plugin system internals: [DeepWiki noctalia-shell plugin system](https://deepwiki.com/noctalia-dev/noctalia-shell/2.4-plugin-system) — MEDIUM confidence
- Reference plugin structure: [niri-auto-tile](https://github.com/pir0c0pter0/niri-auto-tile) — HIGH confidence (source code reviewed)
- ip-monitor Main.qml (curl + Timer pattern): noctalia-dev/noctalia-plugins — HIGH confidence (source code reviewed)
- Frigate API endpoints: [Frigate v0.9.0-rc5 api.md](https://github.com/blakeblackshear/frigate/blob/v0.9.0-rc5/docs/docs/integrations/api.md) — HIGH confidence
- Frigate authentication: [Authentication docs](https://docs.frigate.video/configuration/authentication/) — HIGH confidence
- QML XMLHttpRequest Basic Auth: `xhr.setRequestHeader("Authorization", "Basic " + Qt.btoa(...))` — MEDIUM confidence (multiple community sources agree)
- QML Image MJPEG: Multiple Qt forum discussions — MEDIUM confidence (no official Qt 6 doc explicitly confirms multipart/x-mixed-replace support)
