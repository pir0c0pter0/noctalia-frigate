# Repository Guidelines

## Structure

This is a Noctalia 5 native Luau plugin. Root entries: `Main.luau` (singleton
service), `BarWidget.luau`, `Panel.luau`, `Credentials.sh`, and `plugin.toml`.
`Doorbell.luau` independently monitors a Reolink doorbell's button.
Translations live in `translations/en.json` and `translations/pt-BR.json`.
`settings.example.toml` contains non-secret example configuration. `.planning/`
includes historical v4 research and the Noctalia 5 migration record.

## Development and checks

There is no build step. Symlink the repository to
`${NOCTALIA_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}}/noctalia/plugins/frigate`,
reload config,
and enable `pir0c0pter0/frigate`. Luau edits hot-reload in the host. Run IPC commands
with the running Wayland session's `XDG_RUNTIME_DIR` and `WAYLAND_DISPLAY`.

- `noctalia plugins lint .`: native manifest/settings checks
- `lua tests/service.lua`: service behavior with stubbed host I/O
- `lua tests/doorbell.lua`: direct button detection, auth and reconnect behavior
- `lua tests/ui.lua`: panel/bar lifecycle and native controls
- `bash tests/credentials.sh`: credential helper with a fake secret-tool
- `bash -n Credentials.sh`: shell syntax
- `luau-compile --null *.luau`: optional official Luau syntax check

Manually verify against a real Frigate instance: auth/connection handling,
landscape/portrait previews, camera selection, wraparound, reopen/default,
persistence, i18n, keyboard use and shell scaling. Stubbed checks cannot verify
GPU rendering or compositor behavior.

## Style

Use 4-space indentation, PascalCase entry filenames, camelCase variables and
translation keys. Prefer Noctalia's native APIs, controls and theme roles.
Declare every `getConfig` key in `plugin.toml`. Keep preview work single-flight,
ignore stale responses and bound temporary files. Keep the main camera warm in
the background; stop other cameras' preview requests on close or Settings.

## Changes and security

Use Conventional Commits with scopes. PRs explain the problem, user impact and
validation; include screenshots or recordings for UI changes and link issues.
Never commit real Frigate endpoints, credentials or local environment details.
Credentials belong in Secret Service, never settings, argv, environment, shared
state or logs. Use the native HTTP client; do not introduce per-frame processes.
