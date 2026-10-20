# Noctalia 5 migration

Target: Noctalia v5.3.0. Replace the QML/Quickshell plugin with native Luau
entries and plugin.toml. Install locally, document configuration and migration,
verify the implementation, then commit and push the migration branch.

## Design

- Main.luau is a singleton service: native asynchronous HTTP, connection health,
  camera discovery/navigation/selection, keyring lookup, and snapshot scheduling.
- BarWidget.luau uses host glyphs/tooltips/actions and watches shared state.
- Panel.luau uses retained native controls, keyboard navigation and ui.image.
  Its open/close lifecycle owns the preview; no frame ticks or idle snapshot work.
- The native settings editor owns server URL and default camera. Camera selection
  stays interactive in the panel and is persisted with the native filesystem API.
- Credentials keep the existing Secret Service attributes. No public secret-store
  or subprocess-stdin API exists: Credentials.sh uses terminal input and passes
  secrets to secret-tool on stdin, never argv or plain-text settings.
- Snapshots use native binary HTTP and bounded temporary files in XDG_RUNTIME_DIR;
  unique paths bypass the host image path cache. Server-side height/quality bounds
  network/decode/upload work. Native image rendering uses the host GPU pipeline;
  JPEG decoding is not hardware video decoding.
- Import selected cameras from old settings.json when present; never overwrite v4
  settings/keyring. URL/default are entered in native settings so clearing them
  cannot reactivate a hidden legacy value.

## Execution and verification

1. [x] Write behavior checks for service lifecycle, auth, errors, persistence,
   migration, wraparound, stale callbacks, single-flight requests and backoff.
2. [x] Implement service, native UI and secure credential editing; remove obsolete
   QML/JS/manifest files and move translations to the host's translations folder.
3. [x] Update installation/configuration docs, example config and repository guide.
4. [x] Run Lua checks, shell syntax, JSON/TOML checks, native plugin lint and review
   the diff for secrets, missing call sites and resource leaks.

Real camera and GPU/performance verification requires a configured Frigate
instance and a running graphical Noctalia session. IPC commands must inherit
that session's XDG_RUNTIME_DIR and WAYLAND_DISPLAY.

## Review decisions

- An independent read-only review found stale legacy config fallback, stale camera
  discovery after server changes, and an explicit test blocked by health polling.
  All three have regression checks and fixes.
- Camera-picker mode also pauses preview work. One native snapshot HTTP request
  remains in flight across camera/config changes; the next starts when it returns.
  The public HTTP API has no cancellation handle, so close discards outstanding
  responses rather than claiming to cancel their underlying transport.
- Native settings alone own URL/default; only camera selections auto-migrate.
  This avoids silently contacting a server after the user clears its URL.

## Verification result

- 23 service behavior checks pass in system Lua and the official Luau VM.
- Panel/bar lifecycle, native actions, picker pause and credential path quoting pass.
- Fake-keyring store/clear and literal secret handling pass; Bash syntax passes.
- All production Luau entries compile with the official Luau compiler.
- Native plugin lint: 0 errors, 0 warnings. Isolated native config validation:
  valid, no warnings. JSON/TOML/translation schemas and git diff whitespace pass.
- Local installation smoke test: plugin enabled, service started, native widget
  instantiated on the bar, and panel opened/closed over IPC. No plugin errors
  appeared in the host log. Existing bar settings were backed up before editing.
- The live merged Noctalia configuration validates successfully.
- Real camera preview and GPU/performance measurements remain unverified;
  no Frigate server URL was configured during the installation smoke test.

- Follow-up review caught Test while keyring is unavailable: readiness now guards
  the service and native buttons, and retry clears stale keyring errors. Regression
  verifies both failed lookup and successful reload.
