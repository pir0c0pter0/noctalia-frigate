# Project Research Summary

**Project:** Frigate Camera Viewer — Noctalia Shell Plugin
**Domain:** Desktop bar plugin / quick-glance NVR camera viewer (QML, no build step)
**Researched:** 2026-02-21
**Confidence:** MEDIUM

## Executive Summary

This project is a pure-QML Noctalia Shell plugin that exposes a floating panel displaying a live Frigate NVR camera stream. The architecture is well-constrained by the Noctalia plugin contract: no compilation, no npm, no C++ extensions — just QML files loaded into the Quickshell runtime. The recommended pattern, validated by reference plugins (niri-auto-tile, ip-monitor), is a unidirectional state hub in Main.qml that drives stateless BarWidget and Panel components through `pluginApi.mainInstance` property bindings. The 6-phase build order from skeleton to polish is clear, dependency-driven, and leaves no ambiguity about ordering.

The single largest technical risk is that QML's `Image` component was not designed for continuous MJPEG streams (`multipart/x-mixed-replace`). It works on Linux desktop with a full Qt install — which is the target platform — but this must be validated with a real Frigate instance in Phase 1 before the UI is built around it. The fallback is snapshot polling of `/api/<camera>/latest.jpg` at ~1 FPS via a `Timer`, which is reliable but lower-quality. The auth model has a hard constraint: `Image.source` cannot set HTTP headers, so Basic Auth credentials must be embedded in the URL (`http://user:pass@host/path`). Frigate's own JWT auth (port 8971, version 0.14+) is incompatible with this approach; only reverse-proxy-level Basic Auth and the unauthenticated port 5000 are supported.

The scope must be held tightly. The most successful comparable tools (Periscope, ZipNVR widget) succeed precisely because they refuse to be full NVR clients. The plugin should deliver: bar widget with connection status dot, floating panel with MJPEG stream and left/right camera navigation, settings with URL/auth/camera-selection/persistence. Everything else — recording playback, PTZ, notifications, multi-server, full-screen — is an anti-feature for v1.

## Key Findings

### Recommended Stack

The entire plugin runs inside the Quickshell QML engine that Noctalia is built on. No separate install is needed. All networking (`XMLHttpRequest`, `Image`, `Timer`), i18n (`pluginApi.tr()`), and persistence (`pluginApi.saveSettings()`) are provided by Qt6 and the Noctalia plugin API. The development loop is `NOCTALIA_DEBUG=1 qs -c noctalia-shell --no-duplicate` for hot-reload; `qmllint` for static analysis. Deployment is a symlink or directory copy to `~/.config/noctalia/plugins/frigate-viewer/`.

**Core technologies:**
- **Noctalia Shell 4.5.0**: Host environment providing pluginApi, settings persistence, i18n, panel lifecycle — required, no alternative
- **Qt6 / QtQuick (via system Quickshell)**: All UI components, HTTP networking, timers — zero install overhead
- **QML (pure, no build step)**: Implementation language mandated by Noctalia plugin contract — no npm, no webpack, no compilation
- **Frigate HTTP API**: Camera listing via `GET /api/config`, stream via `GET /api/<camera_name>`, health via `GET /api/version` — verified stable since v0.9.0
- **XMLHttpRequest (built-in QML)**: JSON API calls with `setRequestHeader()` for Basic Auth on proxy-level auth scenarios

### Expected Features

The feature set is deliberately minimal. The mental model is "tap bar icon, see camera, close" — equivalent to a volume popup, not a monitoring dashboard.

**Must have (table stakes):**
- Live camera stream display in floating panel — core product value
- Camera name label in panel header — users must know which camera they see
- Left/right camera navigation — for multi-camera setups
- Connection status dot in bar widget — green/red polling indicator
- Settings: Frigate URL + optional credentials + Test Connection + List Cameras + camera selection
- Persist settings and selected camera list across sessions
- Open/close panel on bar icon click
- Graceful empty state when no cameras are configured

**Should have (differentiators):**
- Basic Auth via URL-embedded credentials for reverse proxy setups
- Connection status polling on a timer (30s interval) to detect server going offline
- Visual loading feedback in panel while MJPEG stream starts
- i18n support (English + Portuguese) — near-zero cost given existing Noctalia infrastructure
- Snapshot polling fallback when MJPEG fails (automatic or configurable)
- Birdseye composite snapshot option (snapshot only, not streaming — Frigate HTTP API limitation confirmed)

**Defer (v2+):**
- Birdseye as first-class camera option (needs user demand validation; birdseye MJPEG not available via HTTP API)
- Snapshot polling fallback exposed as a user setting (add only if MJPEG auth failures reported in practice)
- Object detection bounding box toggle (`?bbox=1`) — clutters quick-glance UX, low priority
- FPS control in settings (add when Frigate host performance complaints arise)

**Explicit anti-features (do not build):**
- Recording playback, event history, PTZ, audio, notifications, multi-server, full-screen mode, multi-camera grid

### Architecture Approach

The plugin follows a unidirectional data flow with Main.qml as the single source of truth. BarWidget and Panel are pure readers that bind to `pluginApi.mainInstance` properties — they hold no state. Settings writes to `pluginApi.pluginSettings` and triggers property change handlers in Main.qml. This is the standard Noctalia pattern confirmed by two reference plugins (niri-auto-tile, ip-monitor). All state mutations go through Main.qml; components are stateless views.

**Major components:**
1. **manifest.json** — Plugin identity, entry points, defaultSettings schema (frigateUrl, username, password, selectedCameras)
2. **Main.qml** — State hub: connectionPoller Timer, testConnection(), fetchCameras(), nextCamera()/prevCamera(), streamUrl computation with URL-embedded auth
3. **BarWidget.qml** — Reads connectionStatus and currentCameraName from mainInstance; opens panel on click; renders camera icon + status dot using theme tokens (Color.mPrimary / Color.mError)
4. **Panel.qml** — Renders MJPEG stream via `Image { source: streamUrl; cache: false }`, camera name header, prev/next navigation buttons; clears Image.source when panel is not visible
5. **Settings.qml** — URL/credentials inputs, Test Connection button, List Cameras button, camera checkbox list, Save; writes to pluginApi.pluginSettings and calls saveSettings()
6. **i18n/en.json + pt.json** — All user-visible strings; accessed via pluginApi.tr()

### Critical Pitfalls

1. **QML Image cannot set HTTP headers** — The only auth option for MJPEG streaming is embedding credentials in the URL (`http://user:pass@host/path`). Always use `encodeURIComponent()` on both username and password separately. Frigate native JWT auth (port 8971) is incompatible with this plugin without a C++ bridge — document this limitation explicitly in Settings UI. Lock this decision in Phase 1 before writing stream code.

2. **MJPEG may not stream continuously from QML Image** — Qt's `Image` component was designed for static images. On Linux with full Qt install it typically handles `multipart/x-mixed-replace` correctly, but this is not guaranteed. Must spike-test against a real Frigate instance in Phase 1. If it fails, fall back to snapshot polling with `Timer { interval: 1000 }`. Always set `cache: false` to prevent stale frame retention.

3. **Image.status does not detect stream death** — `status` stays at `Image.Ready` even when the MJPEG connection silently dies. Connection health must come from XMLHttpRequest polling of `/api/version` on a 30-second Timer — not from `Image.status`. When polling detects server offline, force stream reconnection by transitioning Image.source through `""` before re-assigning (never set directly from Error → same URL, the signal won't fire).

4. **Frigate 0.14+ JWT auth incompatibility** — Users who enable Frigate's built-in auth on port 8971 and enter credentials in plugin settings will get persistent 401s. The plugin only supports reverse-proxy Basic Auth and unauthenticated port 5000. Detect 401 in Test Connection and show a clear explanation. Do not let users discover this silently.

5. **MJPEG endpoint is debugging-only, adds CPU load** — Frigate documentation explicitly marks `/api/<camera_name>` as for debugging, noting it adds parallel JPEG encoding load. Stop the MJPEG stream (`Image.source = ""`) whenever the panel is closed. Default FPS should be low (5 fps) via `?fps=5` query parameter.

## Implications for Roadmap

Based on research, the architecture file already specifies a clear dependency-driven 6-phase build order. The phases below map directly to that recommendation with additional rationale from pitfalls and feature research.

### Phase 1: Plugin Skeleton + MJPEG Spike

**Rationale:** Must validate two unknowns before building anything: (1) that the plugin loads and wires correctly in Noctalia, and (2) that QML Image actually streams MJPEG on the target platform. These are foundational — if either fails, the architecture changes. Run both in Phase 1, not later.

**Delivers:** Plugin registered in Noctalia bar, icon visible, panel opens/closes on click, MJPEG streaming spike result (go/no-go for primary display strategy), all Image cache settings locked in

**Addresses features:** Bar widget presence, open/close panel interaction, live stream display (spike)

**Avoids pitfalls:** C3 (MJPEG unknown resolved early), C4 (cache: false set from day one), M6 (Image retry pattern established), N3 (birdseye exclusion filter in camera list parser)

**Research flag:** NEEDS runtime validation — MJPEG behavior on niri+Quickshell+Qt6 is MEDIUM confidence only; spike is mandatory before committing to the approach

### Phase 2: Settings UI + Persistence + Auth Model

**Rationale:** All Frigate API calls depend on URL and credentials being available in pluginApi.pluginSettings. Settings must exist before any network code can be written or tested. The auth model (URL-embedded Basic Auth) must be locked here before it propagates into every component.

**Delivers:** Settings.qml with URL, username, password inputs; pluginApi.saveSettings() integration; credential URL builder utility with proper encodeURIComponent encoding; defaultSettings in manifest.json

**Addresses features:** Settings URL + auth, settings persistence

**Avoids pitfalls:** C1 (no header injection — locked in URL-embedded approach), C2 (JWT incompatibility warning in Settings UI), M1 (encodeURIComponent encoding), M5 (plaintext credential warning in Settings)

**Research flag:** STANDARD PATTERNS — Noctalia settings API is fully documented and HIGH confidence

### Phase 3: Frigate API Integration (Main.qml Core)

**Rationale:** testConnection(), fetchCameras(), and connectionPoller are the prerequisite for both the camera list in Settings and the status dot in BarWidget. Phase 4 (MJPEG viewer) depends on streamUrl being computed correctly in this phase.

**Delivers:** Main.qml with: XHR-based testConnection() and fetchCameras(), 30-second connectionPoller Timer, connectionStatus property, cameraList property, streamUrl computed property with URL-embedded auth, nextCamera()/prevCamera() index management

**Addresses features:** Connection status polling, Test Connection button, List Cameras button, camera navigation state

**Avoids pitfalls:** C2 (Test Connection shows 401-specific messaging), M2 (polling via XHR not Image.status), M3 (correct /api/config endpoint, Object.keys parsing), N3 (birdseye filtered from camera list)

**Research flag:** STANDARD PATTERNS — Frigate API endpoints and QML XMLHttpRequest are HIGH confidence

### Phase 4: MJPEG Viewer Panel

**Rationale:** Depends on Phase 3 streamUrl property being available. This is the core user-facing feature delivery. If Phase 1 spike showed MJPEG works, implement it here. If spike showed MJPEG unreliable, implement snapshot polling fallback instead.

**Delivers:** Panel.qml with Image { source: streamUrl; cache: false }, camera name header, prev/next navigation buttons, loading state indicator, stream reconnection via source-to-empty-to-url pattern, Image.source cleared when panel is not visible

**Addresses features:** Live stream display, camera navigation in panel, loading feedback, stream lifecycle management

**Avoids pitfalls:** C3 (stream reconnect implemented), C4 (cache: false, no timestamp busting), M4 (stream stopped on panel close, default fps=5), M6 (Error→Null→URL retry pattern)

**Research flag:** CONDITIONAL — if Phase 1 MJPEG spike fails, this phase needs replanning for snapshot polling primary strategy

### Phase 5: Camera Selection UI

**Rationale:** Depends on Phase 3 fetchCameras() populating the camera list. Delivers the settings UI that makes the viewer actually configurable by the user. This is the last "new feature" phase before polish.

**Delivers:** Settings.qml camera checkbox list populated from fetchCameras(), camera order persistence in pluginApi.pluginSettings, selectedCameras array saved to settings, camera order array saved

**Addresses features:** Camera selection, persist camera order, handle "no cameras selected" empty state

**Avoids pitfalls:** N2 (camera navigation reset on close — accepted as intentional, first camera on open), N4 (FPS clamped to 1-30, validated before URL construction)

**Research flag:** STANDARD PATTERNS — Noctalia settings persistence is well-documented

### Phase 6: Polish, Edge Cases, i18n

**Rationale:** Polish depends on all features existing. All edge cases (Frigate offline, auth failure, no cameras, TLS error) need error states only after the happy path is working. i18n strings go in last to avoid churn on UI copy.

**Delivers:** All user-facing strings via pluginApi.tr() in en.json and pt.json; error states for all failure modes (no cameras, Frigate offline, 401 auth failure, TLS error); theme compliance audit (no hardcoded colors — all Color.mPrimary / Style.* tokens); "last seen" timestamp display; empty state messaging

**Addresses features:** i18n (English + Portuguese), graceful error states, HTTP and HTTPS support messaging

**Avoids pitfalls:** N1 (HTTPS TLS errors distinguished from 401 in Test Connection feedback), M2 (offline state shown clearly with last-seen time), C2 (JWT limitation documented in UI)

**Research flag:** STANDARD PATTERNS — i18n API and Noctalia theme tokens are fully documented

### Phase Ordering Rationale

- Phases 1-3 are fully dependency-driven: skeleton before settings before API before viewer
- Phase 1 includes the MJPEG spike because the entire panel design depends on its result — discovering MJPEG is broken in Phase 4 would require replanning Phase 4
- Phase 5 (camera selection) is separated from Phase 2 (settings persistence) because it depends on fetchCameras() from Phase 3
- Phase 6 (polish) last because edge cases and error states require all features to exist first
- The ordering also naturally avoids pitfall concentration: critical auth and stream decisions are resolved in Phases 1-2 before any UI is built

### Research Flags

Phases likely needing deeper research or validation during planning:
- **Phase 1:** MJPEG spike on niri+Quickshell+Qt6 — MEDIUM confidence, must validate before building Panel UI
- **Phase 4:** Conditional replanning if Phase 1 MJPEG spike shows streaming is unreliable — snapshot polling fallback is the alternative architecture

Phases with standard, well-documented patterns (skip research-phase):
- **Phase 2:** Noctalia settings API is HIGH confidence from official docs
- **Phase 3:** Frigate API endpoints are HIGH confidence, QML XHR is well-documented
- **Phase 5:** Noctalia settings persistence patterns established in Phase 2
- **Phase 6:** Noctalia theme tokens and i18n API are fully documented

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Noctalia plugin contract, Quickshell/Qt6 versions, and Frigate API all verified from official docs and AUR package. No ambiguity on toolchain. |
| Features | HIGH | Table stakes and anti-features strongly validated by Periscope, ZipNVR, HA Advanced Camera Card. Birdseye limitation confirmed via GitHub issues. |
| Architecture | MEDIUM | Main.qml hub pattern is HIGH confidence. QML Image MJPEG streaming behavior is MEDIUM — Linux desktop with full Qt likely works, but not officially confirmed for Qt 6 multipart/x-mixed-replace. Requires runtime validation. |
| Pitfalls | MEDIUM | Auth header limitation and Frigate JWT incompatibility are HIGH confidence. MJPEG frame streaming behavior and retry patterns are MEDIUM confidence from community sources. Memory accumulation confirmed in Qt bug tracker. |

**Overall confidence:** MEDIUM — the well-documented Noctalia plugin structure and Frigate API give HIGH confidence on infrastructure. The one real unknown is MJPEG streaming behavior on the target platform, which requires a runtime spike in Phase 1 to resolve.

### Gaps to Address

- **MJPEG streaming on Qt6 Linux**: No Qt 6 official documentation explicitly confirms `multipart/x-mixed-replace` support in the `Image` component. Community sources on Linux desktop confirm it works, but behavior on stream death and reconnection is poorly documented. Phase 1 spike must cover: (1) does first frame display, (2) does stream update continuously, (3) does `source = ""` followed by URL reassignment reconnect reliably.

- **Frigate version compatibility**: Research is primarily based on Frigate v0.9.0 API docs (highest confidence archived source) and v0.14+ auth docs. Users on very old Frigate versions (pre-0.9) may have different API shapes. Document minimum supported Frigate version in README and manifest.

- **QML `Qt.btoa` availability**: The `Qt.btoa()` function used for Base64 encoding Basic Auth credentials is confirmed in Qt6 docs but the exact QML namespace availability in Quickshell needs verification during Phase 3 implementation. Fallback is a manual Base64 implementation in JavaScript.

- **`pluginApi.mainInstance` access pattern**: The research confirms this is the standard pattern from niri-auto-tile, but the exact property name and availability timing (is it null during Component.onCompleted?) needs care. Add null guards everywhere (`pluginApi?.mainInstance?.property ?? defaultValue`).

## Sources

### Primary (HIGH confidence)
- [Noctalia Plugin Getting Started + API Reference](https://docs.noctalia.dev/development/plugins/) — plugin contract, pluginApi surface, settings persistence
- [niri-auto-tile source code](https://github.com/pir0c0pter0/niri-auto-tile) — reference plugin structure and patterns
- [Frigate API docs (v0.9.0-rc5)](https://github.com/blakeblackshear/frigate/blob/v0.9.0-rc5/docs/docs/integrations/api.md) — camera endpoints, /api/config structure
- [Frigate Authentication docs](https://docs.frigate.video/configuration/authentication/) — JWT vs Basic Auth, port 5000 vs 8971
- [Qt6 XMLHttpRequest QML Type](https://doc.qt.io/qt-6/qml-qtqml-xmlhttprequest.html) — XHR API, setRequestHeader
- [Qt Image QML Type — Qt6 docs](https://doc.qt.io/qt-6/qml-qtquick-image.html) — Image component API, status values
- [Qt Forum: How to set the header when Image source=https?](https://forum.qt.io/topic/130167) — confirms Image header injection is impossible
- [Frigate GitHub Issue #5879](https://github.com/blakeblackshear/frigate/issues/5879) — confirms birdseye has no MJPEG stream endpoint
- [Frigate GitHub Discussion #12994](https://github.com/blakeblackshear/frigate/discussions/12994) — JWT incompatibility confirmation
- [Noctalia AUR package](https://aur.archlinux.org/packages/noctalia-shell) — qt6-multimedia dependency confirmed

### Secondary (MEDIUM confidence)
- [Qt Forum: Load MJPEG video stream to QML](https://forum.qt.io/topic/109624) — MJPEG in QML behavior on Linux
- [Qt Forum: How to reload an image in QML](https://forum.qt.io/topic/6935) — Image status transition patterns, retry via source=""
- [Jolla Together: QML Image.source authentication](https://together.jolla.com/question/27665) — URL-embedded credentials behavior
- [Frigate GitHub Discussion #21149](https://github.com/blakeblackshear/frigate/discussions/21149) — MJPEG stream behind basic auth
- [Periscope (Android Frigate viewer)](https://github.com/maksz42/periscope) — minimal scope philosophy, snapshot polling pattern
- [Noctalia Shell DeepWiki](https://deepwiki.com/noctalia-dev/noctalia-shell) — plugin system internals, settings path
- [Qt Bug Tracker: QTBUG-43089](https://bugreports.qt.io/browse/QTBUG-43089) — QML pixmap cache memory leak

### Tertiary (LOW confidence)
- [Arlo widget features](https://eftm.com/2024/10/arlo-adds-a-widget-for-quick-access-to-your-security-system-status-255832) — bar widget mental model analogy only
- [Frigate iOS discussion #4002](https://github.com/blakeblackshear/frigate/discussions/4002) — user wish list, not authoritative

---
*Research completed: 2026-02-21*
*Ready for roadmap: yes*
