# Roadmap: Frigate Camera Viewer — Noctalia Plugin

## Overview

Six dependency-driven phases take the plugin from a bare registered skeleton to a fully polished, i18n-complete camera viewer. Phase 1 resolves the single largest unknown (MJPEG streaming behavior on Qt6/Quickshell) before any UI is built around it. Phases 2-3 lay the settings and API foundation that all viewer components depend on. Phase 4 delivers the core user value: a live camera stream in a floating panel. Phase 5 makes the viewer configurable. Phase 6 covers all error states, edge cases, and i18n so the plugin ships with no rough edges.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Plugin Skeleton + MJPEG Spike** - Register plugin, open/close panel, validate MJPEG streaming on target platform
- [ ] **Phase 2: Settings UI + Auth Model** - Settings form with URL/credentials, persistence, URL-embedded Basic Auth locked in
- [ ] **Phase 3: Frigate API + Connection Core** - Test Connection, List Cameras, status polling, streamUrl computation in Main.qml
- [ ] **Phase 4: MJPEG Viewer Panel** - Live stream display, camera name header, prev/next navigation, stream lifecycle management
- [ ] **Phase 5: Camera Selection** - Camera checkbox list in settings, order persistence, empty state handling
- [ ] **Phase 6: Polish + i18n** - All UI strings in en/pt, all error states, theme compliance audit

## Phase Details

### Phase 1: Plugin Skeleton + MJPEG Spike
**Goal**: Plugin loads in Noctalia bar and the MJPEG streaming approach is validated before any UI is built around it
**Depends on**: Nothing (first phase)
**Requirements**: BAR-01, BAR-03, VIEW-01
**Success Criteria** (what must be TRUE):
  1. Camera icon is visible in the Noctalia bar after plugin installation
  2. Clicking the bar icon opens the floating panel; clicking again (or closing) dismisses it
  3. A hardcoded MJPEG stream URL displays a live video frame in the panel (spike validates QML Image handles multipart/x-mixed-replace)
  4. The spike result (MJPEG go/no-go) is documented so Phase 4 can proceed without re-investigation
**Plans**: TBD

Plans:
- [ ] 01-01: Scaffold plugin file structure (manifest.json, Main.qml, BarWidget.qml, Panel.qml, Settings.qml stubs)
- [ ] 01-02: Wire bar icon click to panel open/close via pluginApi.mainInstance
- [ ] 01-03: MJPEG spike — hardcoded stream URL in Panel.qml, validate continuous display and source="" reconnect

### Phase 2: Settings UI + Auth Model
**Goal**: Users can configure the Frigate server URL and optional credentials, settings survive restarts, and the Basic Auth URL-embedding strategy is established for all downstream components
**Depends on**: Phase 1
**Requirements**: CONN-01, CONN-02, CONN-04, CONN-05, CONN-06, CONN-07, CONN-08
**Success Criteria** (what must be TRUE):
  1. User can type a Frigate URL (HTTP or HTTPS) into the settings form and save it
  2. User can optionally enter a username and password; leaving both blank works for unauthenticated Frigate setups
  3. Saved URL and credentials are present the next time Noctalia starts (settings survive restart)
  4. All four connection scenarios work as inputs (HTTP no-auth, HTTP+Basic, HTTPS no-auth, HTTPS+Basic) — the settings form accepts all without error
**Plans**: TBD

Plans:
- [ ] 02-01: Settings.qml UI — URL field, username field, password field, Save button; wire to pluginApi.pluginSettings
- [ ] 02-02: defaultSettings schema in manifest.json; credential URL builder with encodeURIComponent (URL-embedded auth locked in here)
- [ ] 02-03: Persistence round-trip — save and reload settings on plugin restart

### Phase 3: Frigate API + Connection Core
**Goal**: Main.qml is the single source of truth for connection state, camera list, and stream URL computation; Settings can test and discover cameras; the bar status dot reflects live server reachability
**Depends on**: Phase 2
**Requirements**: CONN-03, BAR-02, CAM-01
**Success Criteria** (what must be TRUE):
  1. Clicking "Test Connection" in Settings shows a success or error message within a few seconds (including a specific message for 401 auth failures)
  2. The bar icon shows a green dot when Frigate is reachable and a red dot when it is not, updating automatically without user action
  3. Clicking "List Cameras" in Settings fetches and displays the available camera names from the configured Frigate instance
  4. The streamUrl property in Main.qml correctly embeds credentials (or omits them when not set) for any of the four connection scenarios
**Plans**: TBD

Plans:
- [ ] 03-01: Main.qml — testConnection() via XHR to /api/version; 401-specific error message; connectionStatus property
- [ ] 03-02: Main.qml — connectionPoller Timer (30s interval); BarWidget reads connectionStatus for green/red dot
- [ ] 03-03: Main.qml — fetchCameras() via XHR to /api/config; Object.keys parsing; birdseye filtered out; cameraList property

### Phase 4: MJPEG Viewer Panel
**Goal**: Users can see a live camera stream in the floating panel, know which camera they are viewing, and the stream does not waste resources when the panel is closed
**Depends on**: Phase 3
**Requirements**: VIEW-01, VIEW-02, VIEW-03, VIEW-04
**Success Criteria** (what must be TRUE):
  1. Opening the panel displays a live stream (or snapshot-polling fallback if Phase 1 spike showed MJPEG unreliable) from the first selected camera
  2. The current camera name appears in the panel header
  3. Left and right navigation buttons cycle through selected cameras, updating both the stream and the header label
  4. Closing the panel stops the stream (Image.source set to empty string); reopening it resumes correctly
**Plans**: TBD

Plans:
- [ ] 04-01: Panel.qml — Image { source: streamUrl; cache: false }, camera name header, loading state indicator
- [ ] 04-02: Prev/next navigation — nextCamera()/prevCamera() in Main.qml; Panel buttons bound to mainInstance calls
- [ ] 04-03: Stream lifecycle — Image.source cleared on panel close; source-to-empty-to-url reconnect pattern on reopen; ?fps=5 default

### Phase 5: Camera Selection
**Goal**: Users can choose which cameras appear in the viewer, and that selection and order survive restarts
**Depends on**: Phase 3
**Requirements**: CAM-02, CAM-03
**Success Criteria** (what must be TRUE):
  1. After clicking "List Cameras" in Settings, each discovered camera appears as a checkbox that the user can check or uncheck
  2. Only checked cameras appear in the panel viewer navigation
  3. The selected cameras and their display order are present after Noctalia restarts
  4. When no cameras are selected (or none configured yet), the panel shows a clear empty state message rather than a broken stream
**Plans**: TBD

Plans:
- [ ] 05-01: Settings.qml — camera checkbox list populated from cameraList; selectedCameras array written to pluginApi.pluginSettings
- [ ] 05-02: Camera order persistence in pluginApi.pluginSettings; Main.qml reads selectedCameras on load
- [ ] 05-03: Empty state handling — panel shows instructional message when selectedCameras is empty

### Phase 6: Polish + i18n
**Goal**: Every user-facing string is translated, every failure mode shows a useful message, and the plugin uses only Noctalia theme tokens with no hardcoded values
**Depends on**: Phase 5
**Requirements**: I18N-01, I18N-02
**Success Criteria** (what must be TRUE):
  1. All labels, buttons, placeholders, and error messages appear in English by default
  2. All user-visible strings appear in Portuguese when the system locale is set to Portuguese
  3. When Frigate is unreachable the panel shows an offline state message (not a blank or broken stream)
  4. When auth fails (401) the Settings Test Connection result explains the JWT incompatibility limitation explicitly
  5. No hardcoded color values exist in any QML file — all colors reference Color.* or Style.* theme tokens
**Plans**: TBD

Plans:
- [ ] 06-01: i18n/en.json — all user-visible strings; i18n/pt.json — Portuguese translations; replace raw strings with pluginApi.tr() calls
- [ ] 06-02: Error states — Frigate offline, 401 auth failure, TLS error, no cameras configured; each shows a distinct actionable message
- [ ] 06-03: Theme compliance audit — scan all QML files for hardcoded colors; replace with Color.mPrimary / Color.mError / Style.* tokens

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Plugin Skeleton + MJPEG Spike | 0/3 | Not started | - |
| 2. Settings UI + Auth Model | 0/3 | Not started | - |
| 3. Frigate API + Connection Core | 0/3 | Not started | - |
| 4. MJPEG Viewer Panel | 0/3 | Not started | - |
| 5. Camera Selection | 0/3 | Not started | - |
| 6. Polish + i18n | 0/3 | Not started | - |
