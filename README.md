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

All configuration lives on the panel's **Settings** page (gear button, or
right-click the bar icon). Noctalia's native settings editor cannot list a
server's cameras, so the plugin has no native settings.

1. Under **Server**, enter the URL, for example `http://frigate.example.com:5000`.
   An omitted scheme uses HTTPS. Put credentials in the keyring, not the URL.
   The plugin connects automatically shortly after you stop typing.
2. Once connected, cameras are discovered automatically and all are shown
   until you toggle them under **Cameras in the viewer**.
3. Pick the **Main camera** from the list; it opens first every time.

The plugin reconnects on its own (health retries every 5 seconds).
Errors replace the preview with a short explanation and the action that fixes
it: open settings, edit credentials or try again.

### Open when the Reolink doorbell is pressed

The plugin can monitor a wired Reolink doorbell directly, without MQTT or Home
Assistant. Pressing its button opens the viewer at the **Main camera**. If the
viewer is already open, it returns to that camera and leaves the Settings page.

1. In the Reolink app, enable **HTTP** or **HTTPS** and **ONVIF** under the doorbell's
   **Network → Advanced → Server settings**. See [Reolink's port settings](https://support.reolink.com/articles/900000621783-How-to-Configure-Reolink-Ports-Settings/).
2. In the viewer's **Settings → Reolink doorbell**, enter the doorbell's own
   address, for example `http://doorbell.local` (include its port if customized).
   Use HTTPS with a valid certificate, or HTTP only on a trusted local network;
   certificate verification stays enabled. Do not enter the Frigate address here.
3. Click **Credentials** in that section and save the doorbell's own login.
   It is stored separately in the system keyring. Wait for **Waiting for the
   doorbell button**; use **Try again** after fixing access or unlocking the keyring.
4. Keep the doorbell selected as the **Main camera**, close the panel, then press
   the physical button to verify it opens.

The monitor uses native HTTP and subscribes to ONVIF visitor events, including
while the panel is closed. Motion/person detection does not open the viewer. If
the event connection is unavailable, the panel reports a fallback mode that
checks the button every two seconds while retrying the subscription; presses may
be missed in fallback mode or during a disconnection. Initial states and repeated
active alarms do not reopen the panel. Noctalia must be running; this does not
unlock or wake the desktop. Clear the doorbell address to disable monitoring.

Only the address is saved in `noctalia.pluginDataDir()/doorbell.json`. The
`noctalia-frigate-doorbell` Secret Service entry holds its credentials; passwords
are used in native HTTP authentication, never shell arguments or URL parameters.

### Send audio to the doorbell

Configure a go2rtc stream with a working two-way audio backchannel for the
doorbell. In **Settings → Doorbell audio (go2rtc)**, enter the go2rtc server's
direct HTTP/HTTPS address, the stream name, and the absolute path to a local
audio file (up to 10 MB). Press **Send audio to doorbell** or the speaker button
in the viewer. The file is played
once; prepare repeated messages in the file itself. A successful request means
go2rtc accepted playback, not that the camera's speaker was audible.

The plugin uses Python 3 to serve the selected file for at most 30 seconds on
the network interface used to reach go2rtc. Only requests from the configured
server's resolved IPv4 address are accepted. The server must be able to connect
back. If using an SSH tunnel for the API, the optional server address can name
the host's IPv4 address or be `ssh:host:/absolute/path/to/frigate/config`.
The latter copies the file via noninteractive SSH into the Frigate config mount
and removes it after playback starts; a remote cleanup also removes it after
60 seconds if the plugin is interrupted. Frigate must mount that directory at
`/config`. FFmpeg is required in go2rtc. The temporary HTTP transfer is intended
for a trusted local network.
The go2rtc API must be accessible without separate authentication; do not put
credentials in its address. When configured, the audio is also sent once for
each detected doorbell press. Detection may miss presses while disconnected or
using the polling fallback.

Click the icon to toggle the viewer. Use the arrow buttons or **Left / Right**
keys to cycle, including wraparound. Native controls support keyboard focus;
theme, scale, hover feedback, tooltips, placement and outside-click dismissal
are supplied by Noctalia. The close button follows the shell's setting.

The camera button next to the connection status saves a snapshot to
`$XDG_PICTURES_DIR/cameras` (for example `~/Pictures/cameras`). It saves the
full-resolution recording frame from about 30 seconds earlier, because newer
recording segments are not written yet. If the camera is not recording, it
saves the current detect-resolution image instead.

`settings.example.toml` shows a named bar widget definition;
merge these into your configuration rather than replacing your existing file.

### Credentials

Click **Credentials** on the Settings page. A terminal prompts for username and
password; the password is hidden. Empty username removes Basic Auth.
Saving automatically reloads credentials in the running plugin, including after
removing authentication. **Try again** reloads them after unlocking the keyring,
or if the terminal cannot reach Noctalia's IPC.

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
(defaulting to `~/.config/...`). It imports the URL, main camera and selected
cameras without modifying the old file; the old file is never read again.
Legacy plaintext credentials are never imported; existing
`service=noctalia-frigate` keyring entries are reused.

If your v4 settings live elsewhere, enter the URL on the Settings page. All
configuration lives in `noctalia.pluginDataDir()/viewer.json`, honoring
`NOCTALIA_STATE_HOME`. Early Noctalia 5 builds kept the URL in
`[plugin_settings."pir0c0pter0/frigate"]`; re-enter it once and delete that table.

## Performance and GPU

- A singleton viewer service shares connection/camera state across bar instances.
  An independent doorbell service monitors the button when configured; it does
  not fetch camera frames itself.
- Native asynchronous HTTP handles JSON and binary JPEGs. There is **no curl,
  shell pipeline or base64 encoding per frame**.
- The main camera stays updated in the background, including with the panel
  closed or on Settings. Opening reuses its latest image immediately. Without an
  explicit main camera, the first selected camera is kept ready.
- Previews target **5 updates per second per camera**, measured from request start
  so network time does not add an idle delay. Only one preview request runs at a
  time; overdue frames are requested without building a queue. While viewing
  another camera, it and the main camera share that request slot fairly.
  Actual FPS depends on HTTP latency, the camera's detect FPS and host rendering.
- Health checks run every 30 seconds. Preview failures back off independently per
  camera from 2 seconds to a 30-second maximum; success resets that camera's delay.
  The last valid image remains visible during transient errors. Responses for
  removed cameras, old configuration or an unloaded service are ignored.
- Previews come from Frigate's detect frame at JPEG quality 90, at the camera's
  detect height capped at 720 pixels, so they are never upscaled server-side.
  For sharper previews, raise the camera's `detect` resolution in Frigate.
- Only the current and previous temporary JPEG per active camera are retained
  under a private `$XDG_RUNTIME_DIR` session directory: two files for the main
  camera, at most four while another camera is visible. Unique filenames refresh
  the host image control correctly. Closing keeps only the main camera's files;
  unloading removes all of them. A crash may leave up to four files until the
  runtime directory is cleared.
- Background updates use network bandwidth and JPEG encoding even with the panel
  closed. Clearing the server URL or deselecting every camera stops preview work.
- Native `ui.image` preserves aspect ratio and uses Noctalia's GPU rendering
  pipeline. **JPEG decoding is not hardware video decoding.** There is no video
  player, VA-API/RTSP/WebRTC pipeline, audio or recording playback in this plugin.

## Development and checks

No build step or runtime dependencies on Qt/QML. Noctalia hot-reloads `.luau`
changes; reload configuration after editing the manifest.

```bash
noctalia plugins lint .
lua tests/service.lua
lua tests/doorbell.lua
lua tests/audio.lua
python3 tests/audio-server.py
lua tests/wssecurity.lua
lua tests/onvif_xml.lua
lua tests/ui.lua
bash tests/credentials.sh
bash -n Credentials.sh
# Optional: official Luau compiler, when installed
luau-compile --null Main.luau Doorbell.luau BarWidget.luau Panel.luau
```

The tests stub host I/O and exercise the real entry scripts; they do not replace
verification in a graphical Noctalia session against a real Frigate instance.
Check connection/auth failures, portrait/landscape previews, camera selection,
wraparound, reopen/default behavior, persistence, both languages and shell scaling.
For doorbells, also check the physical button with the panel closed, while viewing
another camera and while on Settings, plus reconnection without duplicate openings.

Files: `Main.luau` (viewer service), `Doorbell.luau` (button monitor), `BarWidget.luau`, `Panel.luau`, `Credentials.sh`,
`plugin.toml`, `translations/`, and `tests/`. Historical v4 research is kept in
`.planning/`; the migration record is `.planning/NOCTALIA-5.md`.

References: [Noctalia plugin API](https://docs.noctalia.dev/noctalia/plugins/development/runtime-api/),
[native UI](https://docs.noctalia.dev/noctalia/plugins/development/declarative-ui/),
[local development](https://docs.noctalia.dev/noctalia/plugins/development/workflow/),
[Frigate latest-frame API](https://docs.frigate.video/integrations/api/latest-frame-camera-name-latest-extension-get/).

[MIT](LICENSE) · pir0c0pter0
