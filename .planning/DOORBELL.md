# Direct Reolink doorbell detection

Detect the physical button on the configured Reolink doorbell and open the
existing viewer at its main camera. Use native HTTP `Login` / `GetEvents`
(standalone camera, channel 0), polling every two seconds even while closed.
Only a transition from inactive to active rings; seed the initial state without
opening, and retain it across transient connection/token failures.

Keep the monitor in its own singleton `Doorbell.luau` service. Store only its
address in `doorbell.json`; credentials use a separate Secret Service entry.
The panel provides address, credentials, status and retry. An empty address
disables monitoring. HTTP failures back off, requests stay single-flight and
stale callbacks cannot open the panel. Do not add MQTT, Home Assistant, sound,
recording or another video pipeline.

Implementation:

- [x] Add failing checks for direct detection, deduplication, reconnection,
  validation, credentials, stale callbacks and main-camera opening.
- [x] Implement the service, register it and wire the existing viewer lifecycle.
- [x] Add native settings, English/Portuguese text and scoped keyring editing.
- [x] Run behavior/shell/manifest checks and document setup and hardware limits.

Verification: 13 doorbell checks, 30 viewer-service checks, UI lifecycle checks,
fake-keyring checks, Bash syntax, matching translation keys, manifest entries,
native plugin lint (zero errors/warnings) and whitespace checks passed. An
independent review's persistence/session findings were fixed with regressions.
The installed plugin was re-enabled to register the new service; its refresh IPC
and viewer open/close commands were accepted by a running Noctalia session.

After the user enabled HTTP/HTTPS, a live login and channel-0 `GetEvents` request
confirmed visitor/button support and an inactive baseline. Existing working
camera credentials were saved to the graphical session's separate keyring entry,
the address was saved to private plugin data, and the plugin was re-enabled.
HTTPS certificate verification failed, so the monitor uses HTTP on the trusted
local network. No credentials were written to the repository or command arguments.

The physical button test passed: monitoring observed the visitor alarm becoming
active and the native Frigate viewer opening automatically about 1.1 seconds
after that observation. The temporary diagnostic session was logged out; the
plugin's background monitor remains configured and active.

GPU rendering and prolonged stability remain unverified. The optional official
Luau compiler is unavailable.
