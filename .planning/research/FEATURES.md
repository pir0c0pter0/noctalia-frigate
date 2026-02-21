# Feature Landscape

**Domain:** Desktop bar plugin / quick-glance camera viewer (Frigate NVR)
**Researched:** 2026-02-21
**Scope:** Features for a bar widget + floating panel camera viewer, NOT a full NVR client

---

## Context: What This Product Is

A Noctalia Shell bar plugin that surfaces a floating panel with a live camera feed. The user's
mental model is "tap the bar icon, see my cameras, close it." This is analogous to:

- Arlo's iOS home screen widget (arm/glance without opening the app)
- Periscope for Android (deliberately "live view only, not a full Frigate client")
- ZipNVR's CCTV Desktop Widget (single-camera always-on-top with auto-cycle)
- A volume popup or calendar popup — instant, transient, focused

The key insight from ecosystem research: the most successful quick-glance camera viewers are
the ones that deliberately *refuse* to be full NVR clients. Periscope's README explicitly
states "this is not a full Frigate client, it's only a live view" — and users love it for
that clarity.

---

## Table Stakes

Features users expect from any camera viewer widget/panel. Missing = product feels broken or
useless.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Live camera stream display | Core product value — if there's no live video, there's no product | Low | Frigate MJPEG via `GET /api/<camera_name>` — QML `Image` component loads it natively |
| Camera name visible in UI | Users must know which camera they're looking at | Low | Simple text label in panel header |
| Navigate between cameras (left/right) | Users have multiple cameras; sequential navigation is universal UX pattern | Low | State management: current index in selected camera list |
| Connection status indicator in bar | Users need to know if Frigate is reachable before they click | Low | Status dot (green/red) on bar widget; poll `/api/stats` or `/api/version` |
| Settings: Frigate server URL | Plugin is useless without knowing where Frigate lives | Low | Text field, validate on save |
| Settings: camera selection | Users do not want to see all cameras — they pick the relevant ones | Medium | Fetch camera list from `/api/config`, render checkboxes |
| Settings: test connection | Users need confidence the URL + auth works before committing | Low | Call `/api/version`, show success/error feedback |
| Persist settings across sessions | Plugin state survives reboots | Low | `pluginApi.saveSettings()` — already in Noctalia API |
| Persist camera order | Users arrange cameras in a preferred order | Low | Save ordered list of selected cameras |
| Open/close panel from bar icon click | Standard bar plugin interaction pattern — user expects toggle | Low | Follows niri-auto-tile reference plugin pattern |
| Handle "no cameras selected" gracefully | If user hasn't configured yet, show a useful empty state | Low | "Configure in settings" message instead of broken UI |
| HTTP and HTTPS support | Frigate runs on both — local typically HTTP, remote HTTPS | Low | URL field accepts both schemes |

**Confidence:** HIGH — derived from Zip NVR widget, Periscope, HA Advanced Camera Card, and
direct analysis of the reference plugin (niri-auto-tile).

---

## Differentiators

Features that set this plugin apart. Not universally expected in a bar plugin, but add
meaningful value without bloating scope.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Basic Auth support (user + password) | Covers users behind reverse proxies — a very common Frigate setup | Low | URL-encode credentials: `http://user:pass@host/path`; applies to stream URLs and API calls |
| Connection status polling (periodic) | Users know their cameras went offline without clicking; reduces surprise | Low | Interval timer calling `/api/version` every N seconds; update status dot |
| Birdseye snapshot as "all cameras" option | Frigate's Birdseye view is an at-a-glance composite; shows activity without cycling | Medium | Available via `/api/birdseye/latest.jpg`; cannot be MJPEG from HTTP API (only RTSP at :8554) — use snapshot polling mode for birdseye |
| Snapshot polling fallback when MJPEG fails | MJPEG behind auth in QML has known reliability quirks; polling `/api/<cam>/latest.jpg` at ~1fps is a reliable fallback | Medium | Configurable or automatic; adds resilience without requiring user troubleshooting |
| i18n support (English + Portuguese) | Project already targets bilingual locale via `pluginApi.tr()` | Low | Cost is near-zero given existing i18n infrastructure in Noctalia |
| Visual feedback when stream loads | Empty black box while stream starts feels broken; spinner or placeholder prevents user confusion | Low | Show loading state before first MJPEG frame arrives |

**Confidence:** MEDIUM — Birdseye MJPEG limitation confirmed via GitHub issue #5879 and
discussions #3137; snapshot polling is established pattern in Periscope.

---

## Anti-Features

Things to deliberately NOT build. Each one is a scope trap that has killed similar tools.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Recording playback / event history | Full NVR functionality; requires scrubbing timeline, clip management — 10x the scope | Link to Frigate web UI, which already handles this perfectly |
| PTZ camera controls | Complex UI, hardware-specific, test surface explodes; Frigate web UI covers it | Out of scope; mention in README that Frigate UI handles it |
| Motion detection alerts / notifications | Separate concern (MQTT, notification system); pulls in heavy dependencies | Frigate Notify (third-party extension) handles this |
| Multi-server / multiple Frigate instances | Settings complexity multiplies; state management becomes graph-shaped | v1 targets single server; explicit anti-feature until validated demand |
| Audio streaming | MJPEG is video-only by nature; audio requires separate stream + mixing | Not feasible with current approach; don't promise it |
| Full-screen mode / maximize panel | Panel is a quick-glance tool, not a monitoring station; if you want full-screen, open Frigate web UI | Keep panel fixed size (640x400); do not add resize handle |
| Multi-camera grid view in panel | Shows multiple feeds simultaneously; MJPEG per-camera multiplies bandwidth and CPU; QML layout complexity high | Single camera + navigation is the correct scope |
| Camera editing / renaming inside plugin | Camera names come from Frigate config; plugin does not own that data | Show Frigate's camera names read-only |
| Clip downloads | Requires event API + file system access; adds permissions complexity | Not needed; Frigate web UI handles this |
| Object detection overlay | Frigate's MJPEG debug stream can show bounding boxes via `?bbox=1` — useful but clutters quick-glance UX | Maybe a toggle in v2 if users request; omit in v1 |
| Auto-refresh settings from Frigate | Polling Frigate config in real-time for camera list changes; adds background complexity | User manually hits "List Cameras" in settings when needed |

**Confidence:** HIGH — anti-features confirmed against PROJECT.md "Out of Scope" section and
validated against patterns from Periscope (explicit minimal scope), ZipNVR widget (single
camera), and HA advanced card (scope bloat cautionary tale).

---

## Feature Dependencies

```
Settings: Server URL  ─────────────────────────────────────────────────────────────┐
                                                                                    │
Settings: Optional Auth (user/pass)  ──────────────────────────────────────────────┤
                                                                                    ▼
                                                                    Settings: Test Connection
                                                                            │
                                                                            ▼
                                                                    Settings: List Cameras
                                                                            │
                                                                            ▼
                                                                    Settings: Camera Selection
                                                                            │
                                                                            ▼
Bar Widget: Connection Status  ◄── Connection polling ──────────────────────┤
                                                                            │
                                                                            ▼
Panel: Live Stream Display  ◄── Camera navigation (←/→) ◄── Selected camera list
        │
        ▼
Snapshot polling fallback  (parallel path if MJPEG fails)
```

Key dependency chains:
- **URL + auth** must be set before **Test Connection** is meaningful
- **Test Connection** must succeed before **List Cameras** is callable
- **Camera Selection** (which cameras are picked + their order) gates everything in the panel
- **Connection polling** shares the same URL + auth as the stream URLs — configure once, use everywhere
- **Birdseye snapshot** depends on Birdseye being enabled in Frigate config — plugin cannot control this; fail gracefully if `/api/birdseye/latest.jpg` returns 404

---

## Frigate API: Relevant Endpoints

What the plugin actually uses (HIGH confidence, verified against official docs):

| Endpoint | Used For | Notes |
|----------|----------|-------|
| `GET /api/version` | Connection test, health polling | Lightweight; returns version string |
| `GET /api/config` | List available cameras | Returns full config JSON; cameras are keys under `cameras` object |
| `GET /api/stats` | Connection health (richer than version) | Includes per-camera FPS, uptime |
| `GET /api/<camera_name>` | Live MJPEG stream | Main stream URL; QML `Image` source |
| `GET /api/<camera_name>/latest.jpg` | Snapshot (fallback / birdseye-style) | Accepts `?h=` for height scaling |
| `GET /api/birdseye/latest.jpg` | Birdseye composite snapshot | Only snapshot available via HTTP API; MJPEG requires RTSP |

Endpoints the plugin deliberately does NOT use (v1):
- `/api/events` — event history, out of scope
- `/vod/...` — recording playback, out of scope
- `/api/events/<id>/clip.mp4` — clip downloads, out of scope

---

## MVP Recommendation

Prioritize for v1 (Milestone 1):

1. **Bar widget with connection status dot** — visible always, polling `/api/version`
2. **Click to open floating panel with live MJPEG** — core value delivered
3. **Left/right camera navigation** — immediately useful with 2+ cameras
4. **Settings: URL + auth + Test Connection + List Cameras + camera selection** — required for the above to function
5. **Settings persistence** — without this the plugin resets on every launch

Defer to v2 (validated demand required):
- **Birdseye snapshot option** — medium complexity, needs Birdseye enabled on server; validate that users actually want a composite view vs cycling
- **Snapshot polling fallback** — add only if MJPEG auth failures are reported in practice
- **Object detection bounding box toggle** — low value for quick-glance use case

Do not build (explicit anti-features above):
- Everything in the Anti-Features table

---

## Sources

- [Frigate API documentation (v0.9)](https://github.com/blakeblackshear/frigate/blob/v0.9.0-rc5/docs/docs/integrations/api.md) — MEDIUM confidence (older version, but core endpoints stable)
- [Frigate MJPEG Feed API](https://docs.frigate.video/integrations/api/mjpeg-feed-camera-name-get/) — HIGH confidence (official docs)
- [Frigate Birdseye configuration](https://docs.frigate.video/configuration/birdseye/) — HIGH confidence
- [Frigate issue #5879 — Birdseye MJPEG via HTTP API](https://github.com/blakeblackshear/frigate/issues/5879) — HIGH confidence (confirmed limitation)
- [Frigate discussion #3137 — HTTP API for Birdseye](https://github.com/blakeblackshear/frigate/discussions/3137) — HIGH confidence
- [Frigate third-party extensions](https://docs.frigate.video/integrations/third_party_extensions/) — HIGH confidence
- [Periscope — Android live viewer for Frigate](https://github.com/maksz42/periscope) — HIGH confidence (direct source)
- [Frigate iOS app discussion #4002](https://github.com/blakeblackshear/frigate/discussions/4002) — MEDIUM confidence (user wishes, not authoritative)
- [ZipNVR CCTV Desktop Widget](https://systemq.com/zip-nvr-dvr-cctv-desktop-widget) — MEDIUM confidence (competitor product page)
- [Advanced Camera Card for Home Assistant](https://github.com/dermotduffy/frigate-hass-card) — HIGH confidence (direct source)
- [Qt Forum — MJPEG in QML](https://forum.qt.io/topic/109624/load-mjpeg-video-stream-to-qml) — MEDIUM confidence (community forum)
- [MJPEG behind auth — Frigate discussion #21149](https://github.com/blakeblackshear/frigate/discussions/21149) — MEDIUM confidence
- [Arlo widget features](https://eftm.com/2024/10/arlo-adds-a-widget-for-quick-access-to-your-security-system-status-255832) — LOW confidence (press article, different product domain)
- [Noctalia Shell architecture](https://deepwiki.com/noctalia-dev/noctalia-shell) — MEDIUM confidence
