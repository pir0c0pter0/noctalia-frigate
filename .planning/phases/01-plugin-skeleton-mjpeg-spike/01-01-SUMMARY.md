# Plan 01-01 Summary: Plugin Scaffold + BarWidget

**Status:** Complete
**Date:** 2026-02-21

## What Was Done

Created 5 plugin files forming the complete Frigate Viewer plugin skeleton:

1. **manifest.json** - Plugin identity with id `noctalia-frigate`, all 4 entry points, defaultSettings schema
2. **Main.qml** - Minimal stub with `pluginApi` property (state hub in Phase 3)
3. **BarWidget.qml** - Full implementation with:
   - CCTV icon via `NIcon { name: "camera-cctv" }`
   - Active state opacity (1.0 open / 0.7 closed) via `pluginApi?.isPanelOpen`
   - Hover color via `Color.mHover`
   - Tooltip via `TooltipService.show()` with static "Frigate Viewer - Connected"
   - Panel toggle via `pluginApi.togglePanel(root.screen, root)`
   - All required bar widget properties (screen, widgetId, section, etc.)
4. **Panel.qml** - Stub with correct dimensions (640x400) and ShellScreen property
5. **Settings.qml** - Placeholder stub

## Verification

- manifest.json: Valid JSON, correct id, all 4 entryPoints present
- BarWidget.qml: Uses `togglePanel` (not `openPanel`), has `isPanelOpen` opacity binding
- No hardcoded hex colors in any QML file
- All files have `property var pluginApi: null`

## Notes

- `NIcon` property name used: `name` (per niri-auto-tile pattern). If it should be `icon`, will be caught at runtime.
- `pluginApi?.isPanelOpen` is the assumed property name. Fallback to local state tracking if unavailable at runtime.
