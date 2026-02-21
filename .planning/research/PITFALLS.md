# Domain Pitfalls

**Domain:** Frigate NVR Camera Viewer — Noctalia Shell QML Plugin
**Researched:** 2026-02-21
**Confidence:** MEDIUM (WebSearch verified against Qt forum discussions and Frigate GitHub issues; some claims LOW confidence where single-source)

---

## Critical Pitfalls

Mistakes that cause rewrites or total feature failure.

---

### Pitfall C1: QML `Image` Component Cannot Set HTTP Headers — Basic Auth via URL Only

**What goes wrong:**
The QML `Image` component has no API to set HTTP request headers. There is no `.setRequestHeader()` equivalent on `Image`. This means sending an `Authorization: Bearer <token>` or `Authorization: Basic <base64>` header directly from an `Image { source: url }` is impossible. The only path for auth is embedding credentials in the URL itself: `http://user:pass@host/api/camera`.

**Why it happens:**
Qt's `QNetworkAccessManager` underpinning the `Image` component does not expose header control to QML. The `Image` type accepts only a URL string; no request customisation is possible at the QML layer.

**Consequences:**
- If Frigate is deployed behind a reverse proxy requiring `Authorization` header (not credentials-in-URL), the stream will always receive a 401.
- If the team later decides to use Frigate's native JWT Bearer token auth (not basic auth), the entire streaming approach must be reconsidered — there is no clean path to inject a Bearer token into an `Image` source.
- Attempting `XMLHttpRequest` to manually fetch a MJPEG stream is also blocked: **there is no way to receive binary data using `XMLHttpRequest` in QML**. `XMLHttpRequest` in Qt QML cannot consume a multipart/x-mixed-replace binary stream.

**Prevention:**
- Commit to Basic Auth via URL embedding for all authentication scenarios (matching the project's current decision).
- Do not plan a future migration path to JWT Bearer tokens from pure QML — it requires a C++ `QQuickImageProvider` bridge or shell-level proxy.
- Document this constraint prominently so future contributors don't waste time attempting header injection.

**Detection (warning signs):**
- Any issue report saying "authentication works in browser but not in plugin" — the browser is sending a header, the `Image` component cannot.
- Planning discussions that mention switching to Frigate's `/api/login` JWT flow without also planning a C++ component.

**Phase:** Address in Phase 1 (foundation). The auth approach must be locked before any stream code is written.

---

### Pitfall C2: Frigate 0.14+ Built-In Auth Uses JWT, Not Basic Auth — Port Architecture Matters

**What goes wrong:**
Frigate 0.14 (released 2024) introduced native built-in authentication. The authenticated port is **8971**. The unauthenticated port is **5000** (internal/Docker-only). Frigate's built-in auth system is **JWT-based, not Basic Auth**. Users who configure Frigate's built-in auth and give the plugin a URL on port 8971 will face auth failures, because:
1. The plugin sends Basic Auth credentials via URL embedding.
2. Frigate 0.14+ on port 8971 does not accept credentials-in-URL as HTTP Basic Auth — it expects a JWT token in the cookie or `Authorization: Bearer` header.

**Why it happens:**
The project assumes "Basic Auth" refers to HTTP Basic Auth sent by the server. But many Frigate deployments use a **reverse proxy** (Traefik, nginx, Caddy) that adds HTTP Basic Auth in front of Frigate. These setups accept credentials-in-URL. Frigate's *own* auth on port 8971 is entirely different (JWT). The distinction is not obvious to users.

**Consequences:**
- Users configure Frigate's native auth, enter their credentials in plugin settings, and get a perpetual 401.
- Users on port 5000 without any proxy get unauthenticated access (this works, but is insecure if exposed).
- Connection status polling will show "disconnected" for any user with Frigate native auth on port 8971.

**Prevention:**
- In Settings UI, provide explicit documentation: "Basic Auth credentials only work with reverse-proxy-level authentication (nginx/Caddy/Traefik). Frigate's built-in auth (port 8971) is not supported in this plugin."
- In the "Test Connection" button feedback, detect 401 responses and display a message explaining the limitation.
- Support the port-5000 unauthenticated path as the primary tested configuration.
- Consider supporting an optional API token field as a future enhancement for users who can configure Frigate to allow token query parameters.

**Detection (warning signs):**
- User reports "Test Connection fails with 401 even with correct credentials."
- Users on Frigate 0.14+ with built-in auth enabled.

**Phase:** Address in Phase 1 (settings + auth model), Phase 2 (error messaging). Must be documented before any user-facing release.

---

### Pitfall C3: QML `Image` Does Not Natively Stream MJPEG — It May Load Only the First Frame

**What goes wrong:**
MJPEG is a `multipart/x-mixed-replace` stream where the server pushes JPEG frames continuously. The QML `Image` component was designed for static images. Whether it correctly handles a live MJPEG stream depends entirely on the underlying Qt network stack and platform. In many configurations, Qt's `Image` component:
- Loads only the *first frame* and treats the connection as closed when no Content-Length is present.
- Or freezes on the first frame after a network hiccup.
- Or (best case) works correctly on Linux with a full Qt install, which is the target platform.

**Why it happens:**
Qt's network image loading expects a bounded response. MJPEG streams have no Content-Length and never terminate normally. Qt's internal HTTP handling with multipart responses has had varying behaviour across versions and platforms. On Linux desktop with full Qt install, MJPEG via `Image { source: }` tends to work because Qt's `QNetworkAccessManager` processes the multipart boundaries. But this is not guaranteed behaviour.

**Consequences:**
- If `Image` only shows one frame, the viewer appears as a still photo, not live video.
- If the stream freezes after a network drop, users see a stale frozen frame with no indication that the feed is dead.
- There is no `Image.status` value for "stream stalled" — `status` stays at `Image.Ready` even when the stream has silently died.

**Prevention:**
- Test MJPEG streaming via `Image { source: "http://frigate:5000/api/camera_name" }` on the target platform (niri + Quickshell + full Qt) in Phase 1 before building the UI around it.
- Implement a "stream health" watchdog: use a Timer to periodically fetch `/api/<camera>/latest.jpg` (snapshot endpoint) as a separate probe. If the snapshot fetch fails, flag the stream as dead.
- Always set `cache: false` on the `Image` component to prevent Qt from caching a stale frame.
- Implement a manual reconnect by toggling `source` to `""` then back to the stream URL.

**Detection (warning signs):**
- Panel shows a still image that matches the first frame captured.
- Changing cameras and switching back shows an old frame.
- Stream works for 30 seconds then freezes.

**Phase:** Address in Phase 1 (spike test MJPEG behaviour on target platform before committing to the approach).

---

### Pitfall C4: QML Image Memory Accumulation with Continuous Network Images

**What goes wrong:**
Qt's Quick Pixmap Cache retains images in memory. When an `Image` component loads many frames over time (or when `source` is toggled for reconnection), memory grows unboundedly. Qt maintains an internal cache of ~2MB (configurable) but the actual in-use image can remain referenced. In older Qt versions there is a documented memory leak in the quick pixmap cache that was fixed in Qt 6.7+.

**Why it happens:**
`Image` with `cache: true` (default) retains every URL it loads. For MJPEG where the URL is static this is less of an issue (same URL = same cache slot), but for reconnection patterns where a timestamp is appended to bust cache, each unique URL creates a new cache entry that may never be evicted.

**Consequences:**
- Long-running desktop session (shell stays open for days) slowly consumes memory.
- Cache-busting timestamp patterns (`source = url + "?t=" + Date.now()`) create unbounded cache entries.

**Prevention:**
- Always set `cache: false` on `Image` components used for camera streams.
- Do NOT use timestamp-based cache busting. For reconnection, toggle source to `""` then back to the original URL with `cache: false`.
- If implementing a snapshot-based fallback (fetching latest.jpg on a timer), set `cache: false` on that Image too.

**Detection (warning signs):**
- Shell process memory grows steadily over 24+ hours.
- Memory spike when switching between cameras rapidly.

**Phase:** Address in Phase 1 (set cache: false from day one), monitor in Phase 2.

---

## Moderate Pitfalls

Mistakes that cause degraded functionality or user confusion.

---

### Pitfall M1: Special Characters in Credentials Break URL-Embedded Basic Auth

**What goes wrong:**
Basic Auth credentials embedded in a URL must be percent-encoded. Characters like `@`, `:`, `/`, `?`, `#`, and `&` in usernames or passwords break URL parsing. The `@` is especially dangerous — it appears to be the host separator in `user:pass@host` and a literal `@` in the password (`user:p@ssw0rd@host`) will be parsed incorrectly.

**Why it happens:**
URL parsing splits on the first `@` to find credentials and the remaining string as the host. A password containing `@` produces `user:p` as credentials and `ssw0rd@host` as the host.

**Consequences:**
- Users with passwords containing special characters get silent 401 failures.
- The plugin appears to not work for a subset of users based on their password complexity.
- No error message distinguishes "wrong credentials" from "credentials not parsed correctly."

**Prevention:**
- When constructing auth URLs, always percent-encode username and password separately using `encodeURIComponent()` in QML JavaScript.
- Correct pattern: `"http://" + encodeURIComponent(user) + ":" + encodeURIComponent(pass) + "@" + host + path`
- Note: `encodeURIComponent` does NOT encode `@`, `:` — these still need manual handling. Use `encodeURIComponent(pass).replace(/@/g, '%40').replace(/:/g, '%3A')` for the password specifically (colon in password is ambiguous). For username, colon must not be present (RFC 7617).
- Add input validation in Settings: warn users if username contains `:` (invalid in Basic Auth username per spec).

**Detection (warning signs):**
- "Test Connection" fails for users despite correct credentials.
- Works when credentials are simple ASCII, fails when password has symbols.

**Phase:** Address in Phase 1 (credential URL builder utility function), Phase 2 (Settings validation UI).

---

### Pitfall M2: `Image.status` Does Not Reliably Detect Stream Death

**What goes wrong:**
`Image.status` transitions through `Null → Loading → Ready` (or `→ Error`). Once `Ready`, it does not revert to `Error` if the underlying network stream silently dies. A MJPEG stream that stops pushing frames after 60 seconds leaves `status` at `Image.Ready`. There is no `Image.Stalled` state.

**Why it happens:**
QML `Image` was designed for discrete resource loading, not continuous streams. The network layer doesn't surface "server stopped sending" as a status change — from Qt's perspective, the response body is still open (the TCP connection may still be alive).

**Consequences:**
- Bar widget connection status dot shows green even when the camera is offline.
- User opens panel and sees a frozen frame, not a clear "offline" indicator.

**Prevention:**
- Implement connection status via the `/api/version` or `/api/stats` REST endpoint, not via `Image.status`.
- Use `XMLHttpRequest` with a `Timer` (poll every 30 seconds) to fetch a lightweight JSON endpoint. If the request fails or times out, mark the connection as lost.
- Display last-known-alive timestamp in the UI ("Last seen: 2 min ago") for transparency.
- When polling confirms the server is reachable but the Image is frozen, force a reconnection.

**Detection (warning signs):**
- Status dot stays green after turning off the Frigate server.
- Frozen frame in panel with no user-visible indication of the problem.

**Phase:** Address in Phase 1 (polling architecture), Phase 2 (UI error states).

---

### Pitfall M3: Frigate Camera List API — Using the Wrong Endpoint

**What goes wrong:**
Developers often assume a `/api/cameras` endpoint exists. It does not. To list cameras, you must either:
- Parse `/api/config` (returns full Frigate config JSON — extract `.cameras` object keys)
- Or parse `/api/stats` (returns per-camera stats keyed by camera name)

Both endpoints return objects keyed by camera name, not arrays. Parsing them requires `Object.keys()` in JavaScript.

**Why it happens:**
Frigate's API is designed for internal use and lacks a simple flat `/cameras` list endpoint. Documentation is incomplete and community usage examples vary.

**Consequences:**
- "List Cameras" button returns empty list or crashes with a JSON parsing error.
- `for (var cam of response.cameras)` fails because `cameras` is an object, not an array.

**Prevention:**
- Use `/api/stats` to enumerate cameras: `Object.keys(JSON.parse(xhr.responseText))` — each key is a camera name.
- Alternatively `/api/config` → `.cameras` object keys.
- Verify during Phase 1 development by curling against a real Frigate instance.
- Write a dedicated `CameraListParser` utility function (single-responsibility) tested against both endpoint shapes.

**Detection (warning signs):**
- "List Cameras" returns an empty list even when cameras are configured.
- Console errors showing `undefined is not iterable` or similar.

**Phase:** Address in Phase 1 (API integration spike).

---

### Pitfall M4: MJPEG Stream URL Is Considered "Debugging Only" by Frigate — CPU Impact

**What goes wrong:**
Frigate's official documentation explicitly states that the MJPEG endpoint at `GET /api/<camera_name>` is **for debugging only** and "will put additional load on the system when in use." This is because Frigate must re-encode frames to JPEG for the MJPEG stream separately from its normal processing pipeline. Having the stream open continuously while the plugin's panel is visible adds measurable CPU load to the Frigate host.

**Why it happens:**
Frigate's internal pipeline uses restreamed H264 (via go2rtc) for efficiency. The MJPEG endpoint forces a parallel JPEG encode path.

**Consequences:**
- On low-power Frigate hosts (Raspberry Pi, NUC), leaving the panel open for extended periods may impact detection performance.
- Users may report that Frigate feels sluggish while the plugin is in use.

**Prevention:**
- Only open the MJPEG stream when the panel is visible. Stop the stream (set `Image.source = ""`) when the panel closes.
- Provide a setting for users to limit stream FPS via the `fps` query parameter: `?fps=5` significantly reduces server load while remaining useful for monitoring.
- Default to a low FPS (e.g., `fps=5`) out-of-the-box; let users increase it.
- In the panel's `Component.onDestruction` (or panel `visible: false` binding), clear the Image source.

**Detection (warning signs):**
- Frigate host CPU spikes when plugin panel is opened.
- Users with Raspberry Pi hosts report detection delays correlated with plugin usage.

**Phase:** Address in Phase 1 (stream lifecycle management), expose fps setting in Phase 2.

---

### Pitfall M5: Noctalia Settings Stored as Plaintext JSON — Credentials Exposed

**What goes wrong:**
Noctalia plugin settings are persisted to `~/.config/noctalia/plugins/{plugin-id}/settings.json` as plain JSON. Any credentials saved via `pluginApi.saveSettings()` are stored in plaintext on disk. Username and password for Frigate Basic Auth will be readable by any process with user-level access.

**Why it happens:**
Noctalia's plugin API provides simple JSON persistence. There is no secret store or encrypted credential vault abstraction in the plugin API.

**Consequences:**
- Passwords visible in plaintext to any process running as the user.
- Credentials visible in file manager, editor, or backup tools.
- If users sync `~/.config` via cloud backup, credentials are transmitted to the cloud provider.

**Prevention:**
- The constraint cannot be fully mitigated within the plugin's pure-QML architecture without a system keyring integration (not available in the plugin API).
- Mitigate by using the OS-native keyring via a helper script (`secret-tool` or `kwallet-query`) invoked via Quickshell's `Process` component if available, or accept the limitation.
- Add a prominent warning in the Settings UI: "Credentials are stored locally in plain text. Do not use your primary account password."
- Recommend users create a dedicated read-only Frigate user account for the plugin.

**Detection (warning signs):**
- Security-conscious users inspect `~/.config/noctalia/plugins/` and find plaintext credentials.

**Phase:** Address in Phase 1 (settings design) — accept the limitation with a clear warning. Potential improvement in a later phase if Quickshell gains keyring support.

---

### Pitfall M6: QML `Image` Error Retry — `onStatusChanged` Does Not Fire If Status Stays `Error`

**What goes wrong:**
After an `Image` enters `status: Image.Error`, setting `source` to a new (or same) URL may not trigger `onStatusChanged` again. This is a known Qt bug/behaviour: the status signal only fires when status *changes*. If the new source also fails, status stays `Error` and no signal fires, breaking retry loops.

**Why it happens:**
Qt's signal system emits only on property value change. `Error → Error` is not a change.

**Consequences:**
- Auto-reconnect logic using `onStatusChanged` silently stops working after the first failed reconnection attempt.
- The stream stays frozen/blank with no further reconnection attempts despite a Timer running.

**Prevention:**
- Always transition through `Image.Null` between retry attempts:
  ```qml
  // Correct retry pattern
  function reconnect() {
      cameraImage.source = ""        // → status becomes Null → onStatusChanged fires
      reconnectTimer.interval = 3000
      reconnectTimer.restart()       // delay before re-setting source
  }
  Timer {
      id: reconnectTimer
      onTriggered: cameraImage.source = streamUrl
  }
  ```
- Never set the new source synchronously after clearing — use a Timer with a brief delay.

**Detection (warning signs):**
- Reconnect button appears to do nothing after the first failed attempt.
- Stream stays black even after Frigate comes back online.

**Phase:** Address in Phase 1 (stream component implementation).

---

## Minor Pitfalls

Issues that cause friction but not total failure.

---

### Pitfall N1: HTTPS TLS Certificate Validation May Block Streams

**What goes wrong:**
When a user configures an HTTPS Frigate URL with a self-signed certificate, Qt's network stack performs TLS validation and rejects the connection. There is no `Image.ignoreSslErrors` property at the QML level. The stream fails silently or with a generic network error.

**Prevention:**
- Document that self-signed certificates require system-level trust (add to OS certificate store) rather than a plugin-level bypass.
- In the "Test Connection" feedback, distinguish TLS errors from auth errors where possible (check `XMLHttpRequest` `status` — TLS failures typically produce `status: 0` rather than `401`/`403`).
- Recommend users access Frigate via a properly signed certificate (Let's Encrypt via reverse proxy) or via HTTP on trusted LAN.

**Phase:** Address in Phase 2 (error messaging and diagnostics).

---

### Pitfall N2: Camera Navigation State Lost on Panel Close

**What goes wrong:**
If camera index (the currently viewed camera in the navigation) is held only in component-local state (`property int currentIndex: 0`), closing and reopening the panel resets to the first camera every time.

**Prevention:**
- Persist the last-viewed camera index via `pluginApi.saveSettings()`.
- Or accept "always start at first camera" as intentional UX — the PROJECT.md says "Panel shows first selected camera on open," which means this is correct behaviour. Do not fight it.

**Phase:** Clarify as intentional in Phase 1 design; no fix needed.

---

### Pitfall N3: Frigate `birdseye` View Has No MJPEG Feed Endpoint

**What goes wrong:**
Frigate does not expose a MJPEG stream for the "birdseye" composite view at `/api/birdseye`. The endpoint returns 404. Snapshot (`/api/birdseye/snapshot.jpg`) works, but continuous stream does not.

**Prevention:**
- Do not add "birdseye" as a camera option in the camera list. Filter it out when parsing the camera list from `/api/stats` or `/api/config`.
- The camera keys from `/api/stats` may include `birdseye` — add an explicit exclusion filter.

**Phase:** Address in Phase 1 (camera list parser).

---

### Pitfall N4: MJPEG URL Query Parameters Are Fragile With No Validation

**What goes wrong:**
The MJPEG endpoint accepts `?fps=N&h=HEIGHT` parameters. Invalid values (negative, zero, extremely high) are not validated by Frigate and may produce errors or unexpected behaviour. A user entering `fps=0` could trigger a server-side divide-by-zero or infinite wait.

**Prevention:**
- Validate FPS and resolution settings in the plugin before constructing the URL:
  - FPS: clamp to 1–30 range
  - Height: clamp to 144–2160 range
- Use sensible defaults (fps=5, no height override — use native resolution).

**Phase:** Address in Phase 2 (settings for FPS).

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Phase 1: MJPEG stream display | C3 — `Image` may not stream MJPEG | Spike test on niri+Quickshell before building UI |
| Phase 1: Auth URL construction | C1, M1 — No header injection, special char encoding | Lock in URL-embedded Basic Auth with encodeURIComponent |
| Phase 1: Camera list fetch | M3 — Wrong endpoint, wrong data shape | Use `/api/stats` object keys; test against real Frigate |
| Phase 1: Stream reconnect | M6 — Status change loop breaks | Always transition through `source = ""` before retry |
| Phase 1: Memory management | C4 — Cache accumulation | Set `cache: false` on all stream Image components |
| Phase 2: Frigate auth model | C2 — Built-in JWT auth incompatibility | Document limitation in Settings UI with clear warning |
| Phase 2: Error states | M2 — Status dot stays green on offline | Implement XHR polling probe, not `Image.status` |
| Phase 2: Settings security | M5 — Plaintext credential storage | Add disclaimer in Settings, recommend dedicated Frigate user |
| Phase 2: Stream lifecycle | M4 — MJPEG CPU cost on Frigate | Stop stream when panel closes (`visible` binding) |

---

## Sources

- [Qt Bug Tracker: Memory leak in QML quick pixmap cache](https://bugreports.qt.io/browse/QTBUG-43089) — MEDIUM confidence
- [Qt Forum: QtQuick/QML Display MJPEG Image Stream from C++](https://forum.qt.io/topic/32948/qtquick-qml-display-mjpeg-image-stream-qimages-from-c) — MEDIUM confidence
- [Qt Forum: Load MJPEG video stream to QML](https://forum.qt.io/topic/109624/load-mjpeg-video-stream-to-qml) — MEDIUM confidence
- [Qt Forum: How to set the header when Image source=https?](https://forum.qt.io/topic/130167/how-to-set-the-header-when-image-source-https) — HIGH confidence (documents `Image` header limitation)
- [Qt Forum: How to reload an image in QML?](https://forum.qt.io/topic/6935/how-to-reload-an-image-in-qml) — HIGH confidence (documents status transition pattern)
- [Jolla Together: QML Image.source authentication](https://together.jolla.com/question/27665/qml-imagesource-authentication/) — MEDIUM confidence
- [Frigate Docs: Authentication](https://docs.frigate.video/configuration/authentication/) — HIGH confidence
- [Frigate Docs: MJPEG Feed Endpoint](https://docs.frigate.video/integrations/api/mjpeg-feed-camera-name-get/) — MEDIUM confidence (docs page rendered minimal content)
- [Frigate GitHub Discussion #12994: HA integration with authenticated UI on 0.14](https://github.com/blakeblackshear/frigate/discussions/12994) — HIGH confidence
- [Frigate GitHub Discussion #21149: MJPEG stream behind basic auth](https://github.com/blakeblackshear/frigate/discussions/21149) — HIGH confidence
- [Frigate GitHub Discussion #13956: HTTP API and Authentication](https://github.com/blakeblackshear/frigate/discussions/13956) — MEDIUM confidence
- [Frigate GitHub Issue #5879: MJPEG stream of birdseye](https://github.com/blakeblackshear/frigate/issues/5879) — HIGH confidence (confirms birdseye has no stream endpoint)
- [Frigate GitHub Discussion #5201: Best way to get a direct stream from Frigate](https://github.com/blakeblackshear/frigate/discussions/5201) — MEDIUM confidence
- [Noctalia Plugin System (DeepWiki)](https://deepwiki.com/noctalia-dev/noctalia-shell/2.4-plugin-system) — MEDIUM confidence (settings JSON path confirmed)
- [Qt Image QML Type — Qt 6 Documentation](https://doc.qt.io/qt-6/qml-qtquick-image.html) — HIGH confidence
