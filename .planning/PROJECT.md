# Frigate Camera Viewer — Noctalia Plugin

## What This Is

A Noctalia Shell plugin that integrates with Frigate NVR to provide a camera viewer directly from the desktop bar. Clicking the bar icon opens a floating panel with live MJPEG stream of the first selected camera, with left/right navigation buttons to cycle through other cameras. Settings allow configuring the Frigate server connection (URL, optional credentials), testing connectivity, listing available cameras, and selecting which cameras to display.

## Core Value

Quick, always-accessible live camera viewing from the Noctalia bar — one click to see your cameras, arrows to navigate between them, no browser needed.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Bar widget with camera icon and connection status dot (green=connected, red=disconnected)
- [ ] Click bar icon opens floating panel (640x400) with live MJPEG stream
- [ ] Panel shows first selected camera on open
- [ ] Left/right navigation buttons to cycle between selected cameras
- [ ] Camera name displayed in panel header
- [ ] Settings: Frigate server URL field (supports HTTP and HTTPS)
- [ ] Settings: optional username and password fields (Basic Auth)
- [ ] Settings: "Test Connection" button with visual feedback (success/error)
- [ ] Settings: "List Cameras" button that fetches available cameras from Frigate API
- [ ] Settings: camera selection (checkboxes to pick which cameras appear in viewer)
- [ ] Support Frigate local without auth (HTTP, no credentials)
- [ ] Support Frigate local with Basic Auth (HTTP + user/pass)
- [ ] Support Frigate remote/LAN without auth (HTTPS, no credentials)
- [ ] Support Frigate remote/LAN with Basic Auth (HTTPS + user/pass)
- [ ] Camera order persisted in settings
- [ ] Connection status polling (periodic check if Frigate is reachable)

### Out of Scope

- Recording playback or event history — Frigate web UI handles this
- PTZ camera controls — too complex for v1, Frigate UI covers this
- Motion detection alerts/notifications — separate concern
- Multi-server support (multiple Frigate instances) — v1 targets single server
- Audio streaming — MJPEG is video-only
- Full-screen mode — panel is a quick-glance tool

## Context

- **Noctalia Shell** v4.4+ plugin system with QML/Quickshell
- Plugin architecture follows the pattern established in `niri-auto-tile`: `manifest.json` + `Main.qml` + `BarWidget.qml` + `Panel.qml` + `Settings.qml`
- Reference plugin: https://github.com/pir0c0pter0/niri-auto-tile
- Frigate exposes REST API at `/api/` for camera listing and MJPEG streams at `/api/<camera_name>/latest.jpg` (snapshot) and MJPEG endpoint
- All QML UI uses Noctalia's theme system (`qs.Commons`, `qs.Widgets`, `Color.*`, `Style.*`) — no hardcoded colors
- Settings persisted via `pluginApi.saveSettings()`
- i18n support via `pluginApi?.tr("key")` with English/Portuguese

## Constraints

- **Platform**: Noctalia Shell 4.4+ on niri Wayland compositor (Linux only)
- **UI Framework**: QML/Qt Quick via Quickshell — no web technologies
- **Network**: QML `Image` component can load MJPEG from HTTP/HTTPS URLs natively
- **Auth**: Basic Auth via URL encoding (`http://user:pass@host/path`) or HTTP headers
- **No build step**: Plugin is pure QML + optional helper scripts, no compilation needed

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| MJPEG for live streaming | Frigate serves MJPEG natively, QML Image supports it, simplest approach | — Pending |
| Basic Auth for all auth scenarios | Covers local and remote setups, user's proxy uses Basic Auth | — Pending |
| Single server only in v1 | Simplifies settings and state management, most users have one Frigate instance | — Pending |
| 640x400 panel size | Good balance for 16:9 camera aspect ratio visibility | — Pending |
| Follow niri-auto-tile plugin structure | Proven architecture, user already familiar with it | — Pending |

---
*Last updated: 2026-02-21 after initialization*
