# Phase 1: Plugin Skeleton + MJPEG Spike - Context

**Gathered:** 2026-02-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Register the Frigate Viewer plugin in Noctalia, display a camera icon in the bar with open/close panel behavior, and validate that MJPEG streaming works on Qt6/Quickshell via a hardcoded stream URL spike. No settings, no API calls, no camera selection — those are later phases.

</domain>

<decisions>
## Implementation Decisions

### Bar icon appearance
- Security camera (CCTV) style icon — matches the Frigate NVR surveillance context
- Same size as other Noctalia bar icons — consistent with bar conventions
- Icon highlights (color/opacity change) when the panel is currently open, providing active state feedback
- Tooltip on hover showing plugin name + connection status (e.g. "Frigate Viewer — Connected"); in Phase 1 status can be static/placeholder since connection polling comes in Phase 3

### Plugin identity
- **Display name**: "Frigate Viewer"
- **Plugin ID/slug**: `noctalia-frigate`
- **Description**: Short and functional, e.g. "Live camera viewer for Frigate NVR"
- **Author**: pir0c0pter0 (GitHub username, matching niri-auto-tile conventions)

### Claude's Discretion
- Panel size and positioning (640x400 from PROJECT.md is the baseline, Claude decides anchor direction and offset)
- Spike go/no-go documentation format
- MJPEG vs snapshot polling comparison scope during spike
- File structure details beyond the established pattern (manifest.json, Main.qml, BarWidget.qml, Panel.qml, Settings.qml)

</decisions>

<specifics>
## Specific Ideas

- Follow the niri-auto-tile plugin structure as the reference implementation (https://github.com/pir0c0pter0/niri-auto-tile)
- The tooltip with connection status sets up the pattern that Phase 3 will make dynamic with real polling data

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-plugin-skeleton-mjpeg-spike*
*Context gathered: 2026-02-21*
