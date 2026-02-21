# Phase 1: Plugin Skeleton + MJPEG Spike - Research

**Researched:** 2026-02-21
**Domain:** Noctalia Shell plugin scaffolding (QML/Quickshell) + MJPEG streaming spike (Qt6 `Image` component)
**Confidence:** MEDIUM

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **Bar icon appearance**: Security camera (CCTV) style icon — matches Frigate NVR surveillance context; same size as other Noctalia bar icons; icon highlights (color/opacity change) when panel is open; tooltip on hover showing plugin name + connection status (e.g. "Frigate Viewer — Connected"); in Phase 1 status is static/placeholder
- **Plugin identity**: Display name "Frigate Viewer", plugin ID/slug `noctalia-frigate`, description "Live camera viewer for Frigate NVR", author pir0c0pter0
- **Reference implementation**: Follow the niri-auto-tile plugin structure (https://github.com/pir0c0pter0/niri-auto-tile)

### Claude's Discretion

- Panel size and positioning (640x400 from PROJECT.md is the baseline, Claude decides anchor direction and offset)
- Spike go/no-go documentation format
- MJPEG vs snapshot polling comparison scope during spike
- File structure details beyond the established pattern (manifest.json, Main.qml, BarWidget.qml, Panel.qml, Settings.qml)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| BAR-01 | Camera icon visible in Noctalia bar | NIcon with `name: "camera-cctv"` (Tabler icon) in BarWidget.qml inside a BarPill or manual Rectangle+Icon structure; icon highlights via opacity/color binding to panel-open state |
| BAR-03 | Clicking bar icon opens floating camera viewer panel | `pluginApi.togglePanel(root.screen, root)` in MouseArea.onClicked inside BarWidget.qml |
| VIEW-01 | User sees live MJPEG stream (with snapshot polling fallback if MJPEG unsupported) | Phase 1 spike validates: `Image { source: "http://host:5000/api/camera_name"; cache: false }` — if multipart/x-mixed-replace streams continuously, MJPEG is go; otherwise document as no-go and prepare snapshot polling fallback for Phase 4 |
</phase_requirements>

---

## Summary

Phase 1 has two distinct goals that must not be conflated: (1) scaffolding the plugin so it loads in Noctalia and the bar icon appears with open/close panel behavior, and (2) running a quick spike to determine whether the `Image` QML component handles MJPEG streams continuously on the target platform (niri + Quickshell + Qt6 on Linux). The scaffold goal is well-understood — the niri-auto-tile reference plugin provides a directly copyable pattern for every required file, and the Noctalia plugin API for bar widgets, panel toggle, and manifest format is fully documented. The spike goal is the one technical unknown: Qt's `Image` component was designed for static image loading, not multipart HTTP streams, and whether it handles `multipart/x-mixed-replace` continuously on Qt6 Linux is MEDIUM confidence only (community-confirmed but not officially documented for Qt6).

The scaffold work requires: `manifest.json` with the correct `noctalia-frigate` ID and entry points, stub QML files for all four components, a BarWidget with the `camera-cctv` Tabler icon that highlights when the panel is open, a tooltip using `TooltipService`, and the panel toggle wired via `pluginApi.togglePanel()`. The MJPEG spike requires only a hardcoded stream URL in a Panel stub's `Image` component — no real camera selection, no settings, no API calls. The spike result (go/no-go with observations on first-frame display, continuous update, and reconnect behavior) must be written to a short document before Phase 4 begins.

The ip-monitor plugin (the most recent official Noctalia plugin example) uses a `BarPill` wrapper component rather than a raw `Item + Rectangle + MouseArea` structure used in niri-auto-tile. Both approaches work. For Phase 1, the ip-monitor's `BarPill` approach is simpler to wire but slightly less visually customizable. Given the locked decision to match other bar icons in size, either pattern is valid — Claude's discretion.

**Primary recommendation:** Scaffold using niri-auto-tile structure (raw Item pattern) for maximum control over icon highlight state, wire panel toggle with `pluginApi.togglePanel()`, then add a hardcoded `Image { source: "http://..."; cache: false }` spike in the Panel stub and observe behavior with a real Frigate stream.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Noctalia Shell | 4.4.0+ (4.5.0 current) | Host — injects `pluginApi`, loads QML, renders bar and panel | The plugin system being extended; mandatory |
| Qt6 / QtQuick | 6.x (system, via Quickshell) | QML runtime: `Item`, `Rectangle`, `Image`, `Timer`, `MouseArea` | Built-in to the Quickshell engine Noctalia runs on |
| Quickshell | system (nixpkgs Jan 2025) | Shell toolkit: `ShellScreen`, `IpcHandler`, `Process` | Noctalia's underlying engine |
| qs.Commons | bundled with Noctalia | Theme tokens: `Color.*`, `Style.*`, `Settings` | All plugins must use these — no hardcoded colors |
| qs.Widgets | bundled with Noctalia | `NIcon`, `NText`, `BarPill`, `NPopupContextMenu` | Standard widget library — icon rendering |
| qs.Services.UI | bundled with Noctalia | `TooltipService`, `PanelService`, `BarService` | Tooltip show/hide, panel open, bar positioning |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| qs.Modules.Bar.Extras | bundled | `BarPill` — opinionated bar widget container | Optional: simplifies icon+text bar widget; use if raw Item structure is unnecessary complexity |
| Tabler Icons | bundled with Noctalia | Icon font used by `NIcon` | Any icon in bar or panel |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Raw `Item + Rectangle + MouseArea` (niri-auto-tile pattern) | `BarPill` wrapper (ip-monitor pattern) | BarPill is simpler to wire but more opinionated; raw Item gives full control over highlight state — use for Phase 1 given the active-state highlight requirement |
| `pluginApi.togglePanel()` | `pluginApi.openPanel()` + separate close logic | togglePanel is the correct API for bar icon behavior (single click to open OR close) |

**Installation:** No installation needed. Pure QML files, no build step. Deploy by placing files in `~/.config/noctalia/plugins/noctalia-frigate/`.

---

## Architecture Patterns

### Recommended Project Structure

```
~/.config/noctalia/plugins/noctalia-frigate/
├── manifest.json          # Plugin identity, entry points, defaultSettings
├── Main.qml               # State hub stub (Phase 1: empty Item with pluginApi property)
├── BarWidget.qml          # Bar icon + panel toggle + tooltip (Phase 1: full implementation)
├── Panel.qml              # Panel stub + MJPEG spike Image component
└── Settings.qml           # Settings stub (Phase 1: placeholder text only)
```

### Pattern 1: manifest.json — Correct Format

**What:** Every Noctalia plugin must have a `manifest.json` at the plugin directory root. The `id` field must match the directory name exactly.

**Example (manifest.json):**
```json
{
  "id": "noctalia-frigate",
  "name": "Frigate Viewer",
  "version": "1.0.0",
  "minNoctaliaVersion": "4.4.0",
  "author": "pir0c0pter0",
  "license": "MIT",
  "repository": "https://github.com/pir0c0pter0/noctalia-frigate",
  "description": "Live camera viewer for Frigate NVR",
  "tags": ["Bar", "Panel", "System"],
  "entryPoints": {
    "main": "Main.qml",
    "barWidget": "BarWidget.qml",
    "panel": "Panel.qml",
    "settings": "Settings.qml"
  },
  "dependencies": {
    "plugins": []
  },
  "metadata": {
    "defaultSettings": {
      "frigateUrl": "",
      "username": "",
      "password": "",
      "selectedCameras": [],
      "cameraOrder": []
    }
  }
}
```

**Source:** Noctalia plugin manifest reference docs + niri-auto-tile manifest (HIGH confidence)

### Pattern 2: BarWidget.qml — Icon + Active State + Tooltip + Panel Toggle

**What:** The bar widget uses the standard `Item` root with a centered `Rectangle` (visualCapsule). The CCTV icon is rendered via `NIcon` with the Tabler icon name `"camera-cctv"`. The active state (panel open) changes the icon's opacity. The tooltip uses `TooltipService`. Panel opens/closes via `pluginApi.togglePanel()`.

**When:** This is the core BAR-01 and BAR-03 implementation.

**Example (BarWidget.qml):**
```qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
    id: root

    property var pluginApi: null
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""
    property int sectionWidgetIndex: -1
    property int sectionWidgetsCount: 0

    // Read panel-open state from mainInstance (Phase 3+ will have real state)
    readonly property var mainInst: pluginApi?.mainInstance ?? null
    readonly property bool isPanelOpen: pluginApi?.isPanelOpen ?? false

    readonly property string screenName: screen ? screen.name : ""
    readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
    readonly property bool isVertical: barPosition === "left" || barPosition === "right"
    readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)

    implicitWidth: visualCapsule.width
    implicitHeight: visualCapsule.height

    Rectangle {
        id: visualCapsule
        anchors.centerIn: parent
        width: capsuleHeight
        height: capsuleHeight
        color: mouseArea.containsMouse ? Color.mHover : Style.capsuleColor
        radius: Style.radiusL
        border.color: Style.capsuleBorderColor
        border.width: Style.capsuleBorderWidth

        NIcon {
            anchors.centerIn: parent
            name: "camera-cctv"
            // Active state: full opacity when panel open, reduced when closed
            opacity: root.isPanelOpen ? 1.0 : 0.7
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onClicked: {
            if (pluginApi) {
                pluginApi.togglePanel(root.screen, root)
            }
        }

        onEntered: {
            TooltipService.show(
                root,
                // Phase 1: static status; Phase 3 will make this dynamic
                "Frigate Viewer — Connected",
                BarService.getTooltipDirection(root)
            )
        }

        onExited: {
            TooltipService.hide()
        }
    }
}
```

**Note on `isPanelOpen`:** The exact API to detect panel-open state needs verification during implementation. The `pluginApi.isPanelOpen` property name is inferred from the Noctalia plugin system design — verify against actual API during Phase 1 implementation. If unavailable, maintain a local `property bool panelOpen: false` toggled in `onClicked`. (LOW confidence on exact property name)

**Source:** niri-auto-tile BarWidget.qml (directly verified), Noctalia bar-widget docs (HIGH confidence for structure); ip-monitor BarWidget.qml (HIGH confidence for BarPill/TooltipService pattern)

### Pattern 3: MJPEG Spike — Image Component Test

**What:** The spike places a hardcoded `Image` component in Panel.qml with a real Frigate stream URL. The spike validates three behaviors:
1. First frame displays at all
2. Stream updates continuously (it's live, not a still)
3. Setting `source = ""` then reassigning URL reconnects the stream

**When:** Phase 1 spike only. The hardcoded URL is replaced in Phase 4.

**Example (Panel.qml spike section):**
```qml
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Item {
    id: root
    property var pluginApi: null
    property ShellScreen screen

    // Spike: hardcoded URL — replace with real URL in Phase 4
    readonly property string spikeUrl: "http://FRIGATE_HOST:5000/api/CAMERA_NAME"

    width: 640
    height: 400

    Image {
        id: streamView
        anchors.fill: parent
        source: spikeUrl
        cache: false
        fillMode: Image.PreserveAspectFit

        onStatusChanged: {
            if (status === Image.Ready) {
                console.log("[spike] MJPEG frame loaded, status: Ready")
            } else if (status === Image.Error) {
                console.log("[spike] MJPEG stream error")
            } else if (status === Image.Loading) {
                console.log("[spike] MJPEG loading...")
            }
        }
    }

    // Spike reconnect test button
    NText {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Click to reconnect"

        MouseArea {
            anchors.fill: parent
            onClicked: {
                streamView.source = ""
                reconnectTimer.start()
            }
        }
    }

    Timer {
        id: reconnectTimer
        interval: 200
        onTriggered: streamView.source = root.spikeUrl
    }
}
```

**What to observe during spike:**
- Does `status` reach `Image.Ready`? (first frame check)
- Does the image visually update over 30+ seconds? (continuous stream check)
- After `source = ""` + Timer reassignment, does stream resume? (reconnect check)

**Source:** Qt6 Image QML docs, existing research PITFALLS.md (C3, M6); pattern confirmed by research team

### Pattern 4: Main.qml Stub

**What:** For Phase 1, Main.qml is a minimal stub that satisfies the plugin contract. It only exposes `pluginApi` and nothing else. Phase 3 adds the real state hub logic.

**Example (Main.qml stub):**
```qml
import QtQuick

Item {
    id: root
    property var pluginApi: null

    // Phase 1 stub — state hub implemented in Phase 3
    // BarWidget and Panel read properties from pluginApi.mainInstance
    // Nothing to expose yet
}
```

### Pattern 5: Settings.qml Stub

**What:** A minimal placeholder that satisfies the `settings` entry point requirement without any functionality.

**Example (Settings.qml stub):**
```qml
import QtQuick
import qs.Widgets

Item {
    property var pluginApi: null

    NText {
        anchors.centerIn: parent
        text: "Settings coming in Phase 2"
    }
}
```

### Anti-Patterns to Avoid

- **Hardcoding any color values:** All colors must use `Color.mPrimary`, `Color.mHover`, `Color.mOnSurface`, etc. — never `"#A8AEFF"` or similar hex values
- **State in BarWidget or Panel:** Even in Phase 1 stubs, don't put mutable state in BarWidget.qml or Panel.qml — all state belongs in Main.qml
- **Synchronous `Image.source` reassignment for reconnect:** Always transition through `source = ""` first, then use a Timer (even 100-200ms) before reassigning — direct same-URL reassignment may not trigger a reload
- **`cache: true` on any stream Image:** Must be `cache: false` from day one; the default `cache: true` will hold stale frames indefinitely
- **Using `pluginApi.openPanel()` instead of `pluginApi.togglePanel()`:** `openPanel()` does not close on second click; `togglePanel()` is the correct bar-icon behavior

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Bar icon click → panel toggle | Custom open/close state tracking | `pluginApi.togglePanel(root.screen, root)` | Noctalia handles panel lifecycle; rolling your own breaks multi-screen behavior |
| Tooltip on hover | Custom `Rectangle` popup | `TooltipService.show()` / `TooltipService.hide()` | Noctalia handles positioning relative to bar position (top/bottom/left/right) automatically via `BarService.getTooltipDirection()` |
| Icon rendering | Embedding SVG or image files | `NIcon { name: "camera-cctv" }` | Tabler icon font bundled with Noctalia; `NIcon` handles scaling and theme color |
| Bar hover color | Manual color management | `Color.mHover` on `containsMouse` | Theme token; respects user's color scheme |

**Key insight:** The Noctalia plugin API handles nearly all bar widget complexity. Rolling custom solutions breaks multi-monitor, theme, and tooltip positioning that the framework provides for free.

---

## Common Pitfalls

### Pitfall 1: `manifest.json` id must match directory name exactly

**What goes wrong:** Plugin fails to load or loads with wrong identity if `"id": "noctalia-frigate"` doesn't match the directory name `noctalia-frigate/` in `~/.config/noctalia/plugins/`.

**Why it happens:** The PluginService uses the directory name as the primary lookup key and validates it against the manifest id.

**How to avoid:** Name the directory `noctalia-frigate` and set `"id": "noctalia-frigate"` in manifest.json. Verify with `cat ~/.config/noctalia/plugins.json` after enabling.

**Warning signs:** Plugin doesn't appear in Settings > Plugins list after install.

### Pitfall 2: MJPEG spike may show only the first frame

**What goes wrong:** `Image { source: mjpegUrl }` loads successfully (status = Ready) but the displayed frame never updates. The stream appears as a still photo.

**Why it happens:** Qt's Image component was designed for bounded HTTP responses. MJPEG streams (multipart/x-mixed-replace) have no Content-Length and never terminate. Qt may treat the first boundary frame as the complete response.

**How to avoid:** Run the spike and observe visually over 30+ seconds. If the image doesn't change, MJPEG streaming via `Image` is not working on this platform. Document this as a no-go and plan snapshot polling for Phase 4.

**Warning signs:** The spike image loads a single frame and stays static even though the Frigate feed is active.

### Pitfall 3: `pluginApi.isPanelOpen` may not exist

**What goes wrong:** The exact property name for detecting whether the panel is currently open may differ from `isPanelOpen`. If the property doesn't exist, the icon highlight (opacity change when panel is open) silently defaults to the `??` fallback and always shows the closed state.

**Why it happens:** The Noctalia plugin API for panel state introspection was not verified in documentation research — it's inferred from the niri-auto-tile pattern and the bar-widget docs.

**How to avoid:** During implementation, check `Object.keys(pluginApi)` in the QML console to see available properties. Fallback: track panel state locally with a `property bool panelOpen: false` toggled in `onClicked` with a signal connection to panel close events.

**Warning signs:** Icon highlight never changes regardless of panel open/close state.

### Pitfall 4: NIcon property name may be `icon` not `name`

**What goes wrong:** If `NIcon` uses `icon: "camera-cctv"` as the property (as suggested by ip-monitor's BarPill usage) instead of `name: "camera-cctv"`, the wrong property causes the icon to not render.

**Why it happens:** The NIcon API was not directly verified from source — it's inferred from documentation references to "Tabler font system" and the niri-auto-tile BarWidget which uses NIcon but the exact property name was not captured in the raw source.

**How to avoid:** During Phase 1 implementation, try `NIcon { name: "camera-cctv" }` first (niri-auto-tile pattern). If nothing renders, try `NIcon { icon: "camera-cctv" }`. The `qmllint` tool will report the property error.

**Warning signs:** No icon visible in bar widget after plugin loads.

### Pitfall 5: Image reconnect loop breaks when status stays Error

**What goes wrong:** After the first failed stream load, the Image enters `status: Image.Error`. Setting `source` to the same URL again does NOT fire `onStatusChanged` because the status value hasn't changed (Error → Error is not a change event).

**Why it happens:** QML property signals only fire when the value changes. The reconnect pattern must pass through `Null` state by setting `source = ""` first.

**How to avoid:** Always clear source to `""` before reassigning. Add a brief Timer (100-200ms) between clearing and reassigning — do not reassign synchronously.

**Warning signs:** Manual reconnect button appears to do nothing after the first stream error.

---

## Code Examples

Verified patterns from official sources and reference plugins:

### BarWidget complete structure (from niri-auto-tile + bar-widget docs)

```qml
// Source: niri-auto-tile BarWidget.qml (verified) + Noctalia bar-widget docs
import QtQuick
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
    id: root
    property var pluginApi: null
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""
    property int sectionWidgetIndex: -1
    property int sectionWidgetsCount: 0

    readonly property string screenName: screen ? screen.name : ""
    readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)

    implicitWidth: visualCapsule.width
    implicitHeight: capsuleHeight

    Rectangle {
        id: visualCapsule
        anchors.centerIn: parent
        width: capsuleHeight
        height: capsuleHeight
        color: mouseArea.containsMouse ? Color.mHover : Style.capsuleColor
        radius: Style.radiusL
        border.color: Style.capsuleBorderColor
        border.width: Style.capsuleBorderWidth

        NIcon {
            anchors.centerIn: parent
            name: "camera-cctv"    // Tabler icon name — verify property is "name" not "icon"
            opacity: 0.7           // Reduced when panel closed; 1.0 when open
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: pluginApi?.togglePanel(root.screen, root)
        onEntered: TooltipService.show(root, "Frigate Viewer — Connected", BarService.getTooltipDirection(root))
        onExited: TooltipService.hide()
    }
}
```

### MJPEG spike reconnect via Timer (from research PITFALLS.md M6)

```qml
// Source: Qt forum established pattern (MEDIUM confidence) + PITFALLS.md M6
function reconnect() {
    streamView.source = ""           // Must go through Null state
    reconnectTimer.restart()         // Brief delay before reassigning
}

Timer {
    id: reconnectTimer
    interval: 200                    // 200ms delay — do not reconnect synchronously
    onTriggered: streamView.source = spikeUrl
}
```

### Correct manifest.json field structure (from niri-auto-tile manifest — HIGH confidence)

```json
{
  "id": "noctalia-frigate",
  "name": "Frigate Viewer",
  "version": "1.0.0",
  "minNoctaliaVersion": "4.4.0",
  "author": "pir0c0pter0",
  "license": "MIT",
  "description": "Live camera viewer for Frigate NVR",
  "tags": ["Bar", "Panel"],
  "entryPoints": {
    "main": "Main.qml",
    "barWidget": "BarWidget.qml",
    "panel": "Panel.qml",
    "settings": "Settings.qml"
  },
  "dependencies": { "plugins": [] },
  "metadata": {
    "defaultSettings": {
      "frigateUrl": "",
      "username": "",
      "password": "",
      "selectedCameras": [],
      "cameraOrder": []
    }
  }
}
```

### Development hot-reload command (from Noctalia getting-started docs — HIGH confidence)

```bash
NOCTALIA_DEBUG=1 qs -c noctalia-shell --no-duplicate
```

### Install plugin for testing (from getting-started docs — HIGH confidence)

```bash
# Symlink for hot development (changes in project dir reflect immediately)
ln -sf /path/to/Plugin_Frigate ~/.config/noctalia/plugins/noctalia-frigate

# Or copy
cp -r /path/to/Plugin_Frigate ~/.config/noctalia/plugins/noctalia-frigate

# Enable plugin in Noctalia: Settings > Plugins > enable "Frigate Viewer"
# Add to bar: Settings > Bar > add "Frigate Viewer" widget
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Raw `Item + Rectangle` for all bar widgets | `BarPill` wrapper for icon+text combos | Noctalia v4.x | ip-monitor now uses BarPill; niri-auto-tile still uses raw Item; both valid in 4.4+ |
| `pluginApi.openPanel()` for open | `pluginApi.togglePanel()` for open+close | Noctalia v4.x | togglePanel handles the "click again to close" behavior — use it |

**Deprecated/outdated:**
- Direct `MediaPlayer` + `VideoOutput` for MJPEG: confirmed broken in Qt6 for multipart/x-mixed-replace without GStreamer pipeline; incompatible with pure-QML plugin constraint

---

## Open Questions

1. **Does `pluginApi` expose a panel-open state property?**
   - What we know: `pluginApi.togglePanel()` opens/closes the panel. The API reference mentions `barWidget`, `desktopWidget` references.
   - What's unclear: Whether `pluginApi.isPanelOpen` (or equivalent) exists, or if panel state must be tracked locally in BarWidget.
   - Recommendation: During Phase 1 implementation, inspect `Object.keys(pluginApi)` in QML console. If no panel-open property exists, use a local `property bool panelOpen: false` toggled on click, and connect to a signal if available. The icon highlight requirement is satisfied either way.

2. **Is `NIcon`'s icon property `name` or `icon`?**
   - What we know: niri-auto-tile uses `NIcon` in BarWidget (confirmed from source). ip-monitor uses `BarPill { icon: "network" }` which passes icon to NIcon internally.
   - What's unclear: The exact property name on the raw `NIcon` component (`name:` vs `icon:`).
   - Recommendation: Try `name: "camera-cctv"` first (consistent with niri-auto-tile patterns). The `qmllint` tool will identify the correct property if wrong.

3. **Will MJPEG stream continuously on niri + Quickshell + Qt6?**
   - What we know: Qt's `Image` component handles HTTP URLs natively. MJPEG is multipart/x-mixed-replace. On Linux desktop with full Qt install, community sources say it works (MEDIUM confidence). Qt6 changes to MediaPlayer/GStreamer do NOT affect `Image` component behavior.
   - What's unclear: Whether Qt6's network layer processes multipart boundaries and updates the displayed image frame-by-frame on this specific Quickshell build.
   - Recommendation: Run the spike against a real Frigate instance. Observe over 30 seconds minimum. Document result. If it fails, the fallback (snapshot polling via `Timer + Image` with timestamp cache-bust) is already designed in PITFALLS.md and ARCHITECTURE.md.

4. **What is the correct MJPEG endpoint format for the spike?**
   - What we know: `GET /api/<camera_name>` returns `multipart/x-mixed-replace` MJPEG stream. Port 5000 is unauthenticated. Supports `?fps=N` query parameter.
   - What's unclear: Nothing — this is HIGH confidence from Frigate API docs.
   - Recommendation: Spike URL = `http://FRIGATE_HOST:5000/api/CAMERA_NAME?fps=5`; replace with real values from the user's Frigate instance.

---

## Sources

### Primary (HIGH confidence)

- niri-auto-tile source code (https://github.com/pir0c0pter0/niri-auto-tile) — BarWidget.qml and Main.qml directly reviewed; manifest.json structure confirmed
- ip-monitor BarWidget.qml (noctalia-dev/noctalia-plugins) — directly reviewed; confirms BarPill pattern, TooltipService usage, pluginApi.openPanel()
- Noctalia bar-widget docs (https://docs.noctalia.dev/development/plugins/bar-widget/) — required properties, panel open, tooltip setup
- Noctalia plugin getting-started docs (https://docs.noctalia.dev/development/plugins/getting-started/) — manifest format, install workflow, hot-reload command
- Noctalia plugin API overview (https://docs.noctalia.dev/development/plugins/overview/) — pluginApi methods: saveSettings, openPanel, closePanel, togglePanel, tr
- Qt6 Image QML Type (https://doc.qt.io/qt-6/qml-qtquick-image.html) — cache property, status values, source property
- Pre-existing project research: ARCHITECTURE.md, STACK.md, PITFALLS.md, SUMMARY.md (all in .planning/research/) — HIGH confidence baseline

### Secondary (MEDIUM confidence)

- Tabler Icons (https://tabler.io/icons/icon/camera-cctv) — confirms `camera-cctv` is a valid Tabler icon name
- Noctalia plugin system DeepWiki (https://deepwiki.com/noctalia-dev/noctalia-shell/2.4-plugin-system) — pluginApi.mainInstance access pattern, BarWidget required properties
- Qt Forum MJPEG threads — confirm Image component behavior is undefined/unreliable for multipart streams; no Qt6-specific confirmation

### Tertiary (LOW confidence)

- WebSearch results on QML MJPEG + Qt6 — no direct confirmation of continuous multipart display; GStreamer-based solutions mentioned are not applicable (pure QML constraint)

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — fully verified from official Noctalia docs and reference plugin source
- Architecture: HIGH — scaffold pattern directly copied from niri-auto-tile (verified source); Panel stub pattern is straightforward
- Pitfalls: MEDIUM — scaffolding pitfalls (manifest id, NIcon property name) are LOW risk with qmllint catching them; MJPEG spike behavior is genuine MEDIUM uncertainty requiring runtime validation
- MJPEG spike outcome: LOW (unknown until runtime) — this is the sole unresolved technical risk

**Research date:** 2026-02-21
**Valid until:** 2026-03-21 (stable Noctalia API; spike result locked after Phase 1 execution)

**Critical action before planning:** The planner must create plans that treat the MJPEG spike as a blocking discovery task. Plans 01-03 (the spike plan) must document the outcome explicitly. If MJPEG is no-go, Phase 4 needs a replanning flag — but this does NOT block Phase 1 completion, which only requires the spike to be run and documented.
