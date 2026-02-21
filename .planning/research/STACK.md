# Technology Stack

**Project:** Frigate Camera Viewer — Noctalia Shell Plugin
**Researched:** 2026-02-21
**Overall Confidence:** MEDIUM (Noctalia plugin API is documented and verified; QML Image/MJPEG limitations verified via Qt forum; Frigate API verified from archived docs; Basic Auth constraint on QML Image is a real limitation verified from multiple sources)

---

## Recommended Stack

### Core Runtime

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Noctalia Shell | 4.5.0 (current) | Host environment | The plugin system this project extends. Latest release (2026-02-18) adds plugin debug mode toggle and hot-reload of all QML/JS. |
| Quickshell | pinned to nixpkgs (Jan 2025 lock) | QML shell toolkit | Noctalia is built on Quickshell; plugins run inside the Quickshell QML engine. No separate install needed. |
| Qt6 / QtQuick | 6.x (via system Quickshell) | QML runtime | All UI, Image loading, XMLHttpRequest, and Timer are Qt6 builtins available inside any QML plugin. Noctalia AUR package declares `qt6-multimedia` as dependency, confirming Qt6. |
| QML (pure, no build step) | — | Implementation language | Noctalia plugin contract requires pure QML files. No compilation, no npm, no webpack. |

**Confidence:** HIGH — verified from official Noctalia docs, AUR PKGBUILD, and DeepWiki analysis of the Noctalia repository.

---

### Plugin File Structure (Mandatory)

Follows the pattern established by `niri-auto-tile` and the official Noctalia plugin spec:

```
frigate-viewer/
├── manifest.json        # Required — declares plugin identity and entry points
├── Main.qml             # Optional — background timers, polling logic
├── BarWidget.qml        # Bar icon with connection status dot
├── Panel.qml            # Floating camera viewer (640×400)
├── Settings.qml         # Frigate URL, credentials, camera selection
└── i18n/
    ├── en.json           # English strings
    └── pt.json           # Portuguese strings
```

**manifest.json required fields:**
```json
{
  "id": "frigate-viewer",
  "name": "Frigate Camera Viewer",
  "version": "1.0.0",
  "minNoctaliaVersion": "4.4.0",
  "author": "...",
  "license": "MIT",
  "entryPoints": {
    "barWidget": "BarWidget.qml",
    "panel": "Panel.qml",
    "settings": "Settings.qml",
    "main": "Main.qml"
  },
  "metadata": {
    "defaultSettings": {
      "frigateUrl": "",
      "username": "",
      "password": "",
      "cameras": [],
      "selectedCameras": []
    }
  }
}
```

**Confidence:** HIGH — directly from Noctalia official getting-started docs and cross-verified against niri-auto-tile plugin structure.

---

### Frigate NVR API

| Endpoint | Method | Purpose | Notes |
|----------|--------|---------|-------|
| `GET /api/config` | GET | List all cameras (cameras key in response JSON) | Preferred over `/api/stats`. Returns full config including camera names as JSON keys. Port 5000 (no auth) or 8971 (JWT required). |
| `GET /api/<camera_name>/latest.jpg` | GET | Single JPEG snapshot, polled on timer | The only viable approach for MJPEG-like display in QML (see below). Supports `?h=400` height param and `?quality=70` (default). |
| `GET /api/<camera_name>` | GET | Native MJPEG stream (multipart/x-mixed-replace) | **NOT suitable for QML Image** (see Alternatives Considered). |
| `GET /api/version` | GET | Health check / connectivity test | Use for "Test Connection" button. Returns `{"version": "x.y.z"}`. |

**Port architecture — critical decision:**
- Port **5000**: Unauthenticated, all requests treated as admin. Safe for local Docker-internal use. Users on local LAN can hit this directly without credentials.
- Port **8971**: Authenticated. Requires JWT Bearer token in `Authorization` header. Basic Auth is **not natively supported** by Frigate's own authentication system.

**Confidence:** HIGH — `/api/config`, `/api/<camera>/latest.jpg`, MJPEG endpoint verified from Frigate v0.9.0 archived API docs on GitHub. Port architecture from official authentication docs at `docs.frigate.video/configuration/authentication/`.

---

### Authentication Strategy

| Scenario | Approach | Why |
|----------|----------|-----|
| Frigate on local LAN, no auth | Plain URL: `http://host:5000/api/...` | Port 5000 is unauthenticated by design |
| Frigate on local LAN, auth enabled | JWT Bearer via XMLHttpRequest `Authorization` header | Frigate 0.14+ uses JWT, not Basic Auth |
| Frigate behind reverse proxy with Basic Auth | URL-encoded credentials: `http://user:pass@host/api/...` in QML Image.source | For proxy-level Basic Auth only (not Frigate's own auth) |
| Frigate remote via HTTPS | HTTPS URL + JWT Bearer or proxy Basic Auth | Same patterns, different scheme |

**Critical constraint on QML Image + Basic Auth:**
QML `Image.source` only accepts a URL string. Credentials can be embedded as `http://user:pass@host/path`. This sends credentials in plain text over HTTP. Over HTTPS, this is acceptable. The `setRequestHeader()` approach works for XMLHttpRequest (for JSON API calls) but **cannot inject headers into QML Image.source loading** — Image uses Qt's internal network manager without an exposed header API in QML.

**Implementation pattern for API calls (camera listing, health check):**
```qml
function frigateGet(path, onSuccess, onError) {
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            if (xhr.status === 200) {
                onSuccess(JSON.parse(xhr.responseText))
            } else {
                onError(xhr.status, xhr.statusText)
            }
        }
    }
    xhr.open("GET", pluginSettings.frigateUrl + path)
    // For JWT bearer auth (port 8971):
    // xhr.setRequestHeader("Authorization", "Bearer " + token)
    // For proxy Basic Auth:
    // xhr.setRequestHeader("Authorization", "Basic " + Qt.btoa(user + ":" + pass))
    xhr.send()
}
```

**For JPEG snapshot polling (camera display):**
```qml
Image {
    id: cameraImage
    cache: false
    // Embed credentials in URL for proxy Basic Auth, or use port 5000 (no auth)
    source: buildSnapshotUrl(currentCamera)
}

Timer {
    interval: 1000   // 1 FPS — sufficient for quick-glance monitoring
    repeat: true
    running: panel.visible
    onTriggered: {
        // Cache-bust by appending timestamp query param
        cameraImage.source = ""
        cameraImage.source = buildSnapshotUrl(currentCamera) + "?t=" + Date.now()
    }
}
```

**Confidence:** MEDIUM — QML Image URL credential embedding confirmed from multiple Qt forum posts. Header injection limitation verified from Qt docs and Jolla community forum. XMLHttpRequest `setRequestHeader` for JWT confirmed from Qt6 official docs.

---

### QML Networking Components

| Component | Use Case | Notes |
|-----------|----------|-------|
| `XMLHttpRequest` (built into QML) | Camera listing, health check, settings validation | Standard W3C XHR API. `setRequestHeader()` for auth headers. Available in all Qt6 QML contexts without import. |
| `Image { source: url }` (QtQuick) | JPEG snapshot display | Loads HTTP/HTTPS URLs natively. Must use `cache: false` and timer-based URL mutation for live updates. |
| `Timer` (QtQml) | Polling snapshot refresh; periodic health check | `interval`, `repeat`, `running: panel.visible` to pause when panel is closed. |
| `Quickshell.Io.Process` | NOT needed for this plugin | Would be needed if using curl-based auth (like github-feed plugin). Avoid — adds complexity. XMLHttpRequest is sufficient. |

**What NOT to use:**
- **`Process` + curl for image fetching**: The github-feed plugin uses this for API calls because GitHub requires PAT tokens in headers and the plugin does complex parallel batching. For Frigate, XMLHttpRequest handles JSON API calls cleanly and Image handles snapshots. No need for curl subprocess overhead.
- **`MediaPlayer` / `VideoOutput`** for MJPEG: Qt's MediaPlayer does not reliably handle `multipart/x-mixed-replace` HTTP MJPEG streams without GStreamer pipeline configuration. This has been confirmed broken in forum threads and would require C++ extension code — incompatible with the plugin's pure-QML constraint.
- **Direct MJPEG stream URL in `Image.source`**: QML Image expects a single image response, not a continuous multipart stream. Behavior is undefined/broken.

**Confidence:** HIGH for XMLHttpRequest (Qt6 official docs). MEDIUM for Image polling approach (Qt forum + Frigate homepage community confirmation). HIGH for MediaPlayer MJPEG incompatibility (Qt forum confirmed broken).

---

### Noctalia Plugin API Surface

| API | Type | Purpose |
|-----|------|---------|
| `pluginApi.pluginSettings` | Object | Read current settings (frigateUrl, username, password, selectedCameras) |
| `pluginApi.saveSettings()` | Function | Persist settings to `~/.config/noctalia/plugins/frigate-viewer/settings.json` |
| `pluginApi.updatePluginSettings(key, value)` | Function | Update and auto-persist a single setting key |
| `pluginApi.openPanel(screen, buttonItem)` | Function | Open floating Panel.qml on bar widget click |
| `pluginApi.closePanel(screen)` | Function | Close panel |
| `pluginApi.togglePanel(screen, buttonItem)` | Function | Toggle panel on bar widget click |
| `pluginApi.tr(key, interpolations)` | Function | i18n translation lookup |
| `pluginApi.currentLanguage` | String | Active language code (for reactivity on language change) |

**Theme integration (no hardcoded colors):**
```qml
import qs.Commons
import qs.Widgets

// Use these, never hardcoded hex values:
Color.mPrimary           // Primary accent (status dot connected)
Color.mError             // Error red (status dot disconnected)
Color.mOnSurface         // Text color
Style.barHeight          // For bar widget sizing
Style.capsuleColor       // Panel/card background
Style.radiusM            // Corner radius
Style.marginM            // Standard spacing
Style.fontSizeS          // Small text
```

**Confidence:** HIGH — from official Noctalia plugin API reference docs and getting-started guide.

---

### Development Environment

| Tool | Version | Purpose |
|------|---------|---------|
| `NOCTALIA_DEBUG=1 qs -c noctalia-shell --no-duplicate` | — | Hot-reload development; watches QML files and reloads on save |
| `qmllint` (via kdePackages.qtdeclarative) | Qt6 bundled | Static QML linting. Catches type errors before runtime. |
| `qmlls` | Qt6 bundled | Language server for IDE support (LSP) |

No package manager (npm, pnpm, cargo) is needed. No build step. Plugin is deployed by symlinking or copying to `~/.config/noctalia/plugins/frigate-viewer/`.

**Confidence:** HIGH — hot-reload command from official Noctalia getting-started guide. No-build-step constraint confirmed from PROJECT.md.

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Live video display | `Image` polling `latest.jpg` at 1 FPS | MJPEG stream via `Image.source` or `MediaPlayer` | QML Image doesn't handle `multipart/x-mixed-replace` content type; MediaPlayer requires GStreamer MJPEG pipeline, incompatible with pure QML. Polling at 1 FPS is sufficient for a quick-glance panel. |
| API authentication | XMLHttpRequest with `setRequestHeader` for JWT; URL-embedded credentials for proxy Basic Auth | Process + curl (like github-feed plugin) | curl subprocess adds 50-100ms startup latency per request, creates orphan processes if mishandled, and adds complexity. XHR is synchronous-enough for settings-time API calls. |
| Frigate auth method | Port 5000 (no auth) or port 8971 with JWT Bearer | Basic Auth in Frigate itself | Frigate's own auth system (0.14+) uses JWT, not Basic Auth. Basic Auth only applies to reverse proxy setups (nginx, Traefik). The plugin supports both scenarios. |
| Networking for API calls | QML `XMLHttpRequest` | Quickshell `Process` + curl | Process-based approach is the pattern used when headers cannot be set (e.g., Image.source), but for JSON API calls, XHR is cleaner. |
| Camera config endpoint | `GET /api/config` (parse cameras key) | `GET /api/stats` | `/api/config` contains camera definitions; `/api/stats` contains runtime stats. Config is authoritative for camera names. |

---

## Sources

- [Noctalia Plugin Getting Started](https://docs.noctalia.dev/development/plugins/getting-started/) — MEDIUM confidence (official docs)
- [Noctalia Plugin API Reference](https://docs.noctalia.dev/development/plugins/api/) — MEDIUM confidence (official docs)
- [Noctalia Plugin System Overview](https://docs.noctalia.dev/development/plugins/overview/) — MEDIUM confidence (official docs)
- [Noctalia Shell GitHub](https://github.com/noctalia-dev/noctalia-shell) — v4.5.0 confirmed
- [noctalia-dev/noctalia-plugins](https://github.com/noctalia-dev/noctalia-plugins) — Plugin registry and community examples
- [github-feed-noctalia Main.qml](https://github.com/linuxmobile/github-feed-noctalia) — HIGH confidence (source code showing Process+curl pattern and why we avoid it)
- [Frigate API docs (v0.9.0-rc5)](https://github.com/blakeblackshear/frigate/blob/v0.9.0-rc5/docs/docs/integrations/api.md) — HIGH confidence (archived markdown, stable API surface)
- [Frigate Authentication docs](https://docs.frigate.video/configuration/authentication/) — MEDIUM confidence (official docs, dynamically rendered)
- [Qt6 XMLHttpRequest QML Type](https://doc.qt.io/qt-6/qml-qtqml-xmlhttprequest.html) — HIGH confidence (official Qt docs)
- [QML Image reload/cache patterns](https://forum.qt.io/topic/6935/how-to-reload-an-image-in-qml/14) — MEDIUM confidence (Qt forum, established pattern)
- [QML MJPEG incompatibility](https://forum.qt.io/topic/109624/load-mjpeg-video-stream-to-qml) — MEDIUM confidence (Qt forum, confirmed broken)
- [Frigate homepage MJPEG widget discussion](https://github.com/gethomepage/homepage/discussions/3784) — MEDIUM confidence (community verification of latest.jpg polling approach)
- [QML Image Basic Auth limitation](https://together.jolla.com/question/27665/qml-imagesource-authentication/) — MEDIUM confidence (Jolla Qt community)
- [niri-auto-tile reference plugin](https://github.com/pir0c0pter0/niri-auto-tile) — HIGH confidence (source code)
- [Noctalia AUR package](https://aur.archlinux.org/packages/noctalia-shell) — HIGH confidence (package dependencies including qt6-multimedia)
- [Quickshell Process API](https://quickshell.org/docs/v0.2.1/types/Quickshell.Io/Process/) — HIGH confidence (official Quickshell docs)
