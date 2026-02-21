# Requirements: Frigate Camera Viewer

**Defined:** 2026-02-21
**Core Value:** Quick, always-accessible live camera viewing from the Noctalia bar — one click to see your cameras, arrows to navigate between them, no browser needed.

## v1 Requirements

### Connection

- [ ] **CONN-01**: User can configure Frigate server URL (HTTP or HTTPS)
- [ ] **CONN-02**: User can optionally provide username and password for Basic Auth
- [ ] **CONN-03**: User can test connection to Frigate server with visual success/error feedback
- [ ] **CONN-04**: Connection settings persist across plugin/shell restarts
- [ ] **CONN-05**: Plugin supports Frigate local without auth (HTTP, no credentials)
- [ ] **CONN-06**: Plugin supports Frigate local with Basic Auth (HTTP + credentials)
- [ ] **CONN-07**: Plugin supports Frigate remote/LAN without auth (HTTPS, no credentials)
- [ ] **CONN-08**: Plugin supports Frigate remote/LAN with Basic Auth (HTTPS + credentials)

### Camera Management

- [ ] **CAM-01**: User can fetch list of available cameras from Frigate API
- [ ] **CAM-02**: User can select which cameras to display via checkboxes
- [ ] **CAM-03**: Selected cameras and order persist across restarts

### Viewer

- [ ] **VIEW-01**: User sees live MJPEG stream (with snapshot polling fallback if MJPEG unsupported)
- [ ] **VIEW-02**: User can navigate between cameras with left/right buttons
- [ ] **VIEW-03**: Current camera name is displayed in the panel header
- [ ] **VIEW-04**: Stream stops when panel is closed to free resources

### Bar Widget

- [ ] **BAR-01**: Camera icon visible in Noctalia bar
- [ ] **BAR-02**: Connection status dot (green=connected, red=disconnected)
- [ ] **BAR-03**: Clicking bar icon opens floating camera viewer panel

### i18n

- [ ] **I18N-01**: All UI strings available in English
- [ ] **I18N-02**: All UI strings available in Portuguese

## v2 Requirements

### Viewer Enhancements

- **VIEW-05**: Birdseye composite snapshot view
- **VIEW-06**: Configurable FPS for snapshot polling mode
- **VIEW-07**: Toggle between MJPEG and snapshot mode per camera

### Camera Management Enhancements

- **CAM-04**: Drag-to-reorder cameras in settings
- **CAM-05**: Camera grouping/categories

### Advanced Features

- **ADV-01**: Detection event alert indicator on bar icon
- **ADV-02**: Camera count badge on bar icon
- **ADV-03**: Multi-server support (multiple Frigate instances)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Recording playback / event history | Frigate web UI handles this; would bloat the quick-viewer |
| PTZ camera controls | High complexity, Frigate UI covers this |
| Motion detection notifications | Separate concern, better handled by system notifications |
| Audio streaming | MJPEG is video-only; would require different streaming protocol |
| Full-screen mode | Panel is a quick-glance tool, not a full viewer |
| Mobile app | Desktop-only Noctalia Shell plugin |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CONN-01 | — | Pending |
| CONN-02 | — | Pending |
| CONN-03 | — | Pending |
| CONN-04 | — | Pending |
| CONN-05 | — | Pending |
| CONN-06 | — | Pending |
| CONN-07 | — | Pending |
| CONN-08 | — | Pending |
| CAM-01 | — | Pending |
| CAM-02 | — | Pending |
| CAM-03 | — | Pending |
| VIEW-01 | — | Pending |
| VIEW-02 | — | Pending |
| VIEW-03 | — | Pending |
| VIEW-04 | — | Pending |
| BAR-01 | — | Pending |
| BAR-02 | — | Pending |
| BAR-03 | — | Pending |
| I18N-01 | — | Pending |
| I18N-02 | — | Pending |

**Coverage:**
- v1 requirements: 20 total
- Mapped to phases: 0
- Unmapped: 20

---
*Requirements defined: 2026-02-21*
*Last updated: 2026-02-21 after initial definition*
