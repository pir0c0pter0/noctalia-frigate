# Frigate Viewer for Noctalia 5

Live Frigate camera snapshots in a native Noctalia panel, with camera selection,
keyboard navigation, connection status and English / Brazilian Portuguese UI.

This is the **v2 port for Noctalia 5**, developed against **Noctalia 5.3.0**.
It uses Luau and `plugin.toml`; QML/Quickshell is no longer required. The v1
implementation remains in Git history for Noctalia 4 users.

## Install

From this repository's root:

```bash
frigate_plugin_dir="${NOCTALIA_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}}/noctalia/plugins"
mkdir -p "$frigate_plugin_dir"
ln -s "$(pwd)" "$frigate_plugin_dir/frigate"
noctalia msg config-reload
noctalia msg plugins enable pir0c0pter0/frigate
```

If the destination already exists, inspect it before replacing it. Noctalia 5
loads local plugins from the **data directory**, not the v4 configuration directory.

Add **Frigate Viewer** through the bar's widget settings. Its widget type is
`pir0c0pter0/frigate:bar`. To open the panel directly:

```bash
noctalia msg panel-toggle pir0c0pter0/frigate:viewer
```

Requires a running Noctalia session and Frigate's HTTP API. For Basic Auth,
install `secret-tool` (libsecret), run a Secret Service keyring such as GNOME
Keyring or KWallet, and have Bash and a terminal available.

### Verify the installation

```bash
noctalia msg plugins list | rg 'pir0c0pter0/frigate'
noctalia msg panel-open pir0c0pter0/frigate:viewer
noctalia msg panel-close pir0c0pter0/frigate:viewer
```

The plugin should be listed as `enabled`. Enabling may export the plugin in the
background; allow it to finish before opening the panel. If IPC reports that
Noctalia is not running, run the commands in a terminal inside the same Wayland
session. Both `XDG_RUNTIME_DIR` and `WAYLAND_DISPLAY` must match that session.

To define the widget manually, merge this with your existing widget definitions
and add `"frigate"` to the appropriate bar's `start`, `center` or `end` list:

```toml
[widget.frigate]
type = "pir0c0pter0/frigate:bar"
```

### Update or remove

A development symlink tracks this checkout, including its current Git branch.
Pull updates in the checkout, then run `noctalia msg config-reload` when the
manifest changes. Keep the checkout in place while the plugin is installed.

To remove it, disable `pir0c0pter0/frigate` in Settings → Plugins, remove its bar
widget, and delete the `plugins/frigate` symlink. Camera selection and keyring
credentials remain available for reinstalling.

## Configure and use

1. Right-click the bar icon to open the native plugin settings editor.
2. Set **Frigate Server URL**, for example `http://frigate.example.com:5000`.
   An omitted scheme uses HTTPS. Put credentials in the keyring, not the URL.
3. Open the viewer and click **List Cameras**, then **Camera Selection**.
4. Toggle the cameras to display. The selection saves automatically.
5. Set **Default Camera** in native plugin settings to one selected camera's
   exact name. If unset or unavailable, the first selected camera opens.

Click the icon to toggle the viewer. Use the arrow buttons or **Left / Right**
keys to cycle, including wraparound. Native controls support keyboard focus;
theme, scale, hover feedback, tooltips, placement and outside-click dismissal
are supplied by Noctalia. The close button follows the shell's setting.

`settings.example.toml` shows plugin settings and a named bar widget definition;
merge these into your configuration rather than replacing your existing file.

### Credentials

Click **Edit credentials** in the panel. A terminal prompts for username and
password; the password is hidden. Empty username removes Basic Auth.
Then click **Reload credentials**, which also retries keyring access after unlock.

The Noctalia plugin API does not expose its internal secret store or a way to
feed subprocess stdin. This small terminal helper therefore sends the secrets
directly to `secret-tool` on stdin, keeping them out of process arguments,
environment variables, TOML, JSON, shared state and logs. HTTP requests use
Noctalia's in-process Basic Auth support. HTTPS certificate verification stays
enabled, and redirects are not followed.

Frigate's native JWT login on port 8971 is not implemented. Use its trusted
unauthenticated endpoint on port 5000 or a reverse proxy with Basic Auth.
Use HTTPS when credentials cross an untrusted network.

### Migrating from v1 / Noctalia 4

The plugin ID is now `pir0c0pter0/frigate`; add its new bar entry after enabling.
On first load, if the new viewer state does not exist, the service reads
`$XDG_CONFIG_HOME/noctalia/plugins/noctalia-frigate/settings.json`
(defaulting to `~/.config/...`). It imports the selected cameras without
modifying the old file. Set the server URL and default camera in Noctalia's native settings; these settings remain the
single source of truth, so clearing a URL actually disables server access.
Legacy plaintext credentials are never imported; existing
`service=noctalia-frigate` keyring entries are reused.

If your v4 settings live elsewhere, copy the non-secret URL/default into native
settings and select cameras in the viewer. New selection state lives in
`noctalia.pluginDataDir()/viewer.json`, honoring `NOCTALIA_STATE_HOME`.

## Performance and GPU

- A singleton service shares connection/camera state across bar instances.
- Native asynchronous HTTP handles JSON and binary JPEGs. There is **no curl,
  shell pipeline or base64 encoding per frame**.
- Preview requests run about once per second, one at a time. They stop when the
  panel closes or the camera picker is shown; health checks run every 30 seconds.
  Late callbacks after camera, configuration or panel changes cannot replace the current image.
- Failures back off from 2 seconds to a 30-second maximum. A successful frame
  resets the delay. The last valid image remains visible during transient errors.
- Frigate returns images bounded to 640 pixels high at JPEG quality 75. This
  reduces transfer, decode and texture-upload work while covering a 2× preview.
- Only the current and previous temporary JPEG are retained under a private
  `$XDG_RUNTIME_DIR` session directory. Unique filenames refresh the host image
  control correctly. Files are removed on close/unload; a crash may leave up to
  two files in that session directory until the runtime directory is cleared.
- Native `ui.image` preserves aspect ratio and uses Noctalia's GPU rendering
  pipeline. **JPEG decoding is not hardware video decoding.** There is no video
  player, VA-API/RTSP/WebRTC pipeline, audio or recording playback in this plugin.

## Development and checks

No build step or runtime dependencies on Qt/QML. Noctalia hot-reloads `.luau`
changes; reload configuration after editing the manifest.

```bash
noctalia plugins lint .
lua tests/service.lua
lua tests/ui.lua
bash tests/credentials.sh
bash -n Credentials.sh
# Optional: official Luau compiler, when installed
luau-compile --null Main.luau BarWidget.luau Panel.luau
```

The tests stub host I/O and exercise the real entry scripts; they do not replace
verification in a graphical Noctalia session against a real Frigate instance.
Check connection/auth failures, portrait/landscape previews, camera selection,
wraparound, reopen/default behavior, persistence, both languages and shell scaling.

Files: `Main.luau` (service), `BarWidget.luau`, `Panel.luau`, `Credentials.sh`,
`plugin.toml`, `translations/`, and `tests/`. Historical v4 research is kept in
`.planning/`; the migration record is `.planning/NOCTALIA-5.md`.

References: [Noctalia plugin API](https://docs.noctalia.dev/noctalia/plugins/development/runtime-api/),
[native UI](https://docs.noctalia.dev/noctalia/plugins/development/declarative-ui/),
[local development](https://docs.noctalia.dev/noctalia/plugins/development/workflow/),
[Frigate latest-frame API](https://docs.frigate.video/integrations/api/latest-frame-camera-name-latest-extension-get/).

[MIT](LICENSE) · pir0c0pter0
