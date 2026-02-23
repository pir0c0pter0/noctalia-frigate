<div align="center">

# Frigate Viewer

**Live camera streaming from [Frigate NVR](https://frigate.video) directly in your [Noctalia Shell](https://github.com/noctalia-dev/noctalia-shell) desktop bar.**

[![Noctalia](https://img.shields.io/badge/Noctalia-4.4%2B-blue?style=flat-square)](https://github.com/noctalia-dev/noctalia-shell)
[![Frigate](https://img.shields.io/badge/Frigate-0.9%2B-green?style=flat-square)](https://frigate.video)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](LICENSE)
[![QML](https://img.shields.io/badge/Pure-QML-orange?style=flat-square)](#)

One click to see your cameras. Arrows to navigate. No browser needed.

</div>

---

## Overview

Frigate Viewer is a Noctalia Shell plugin that puts your security cameras one click away. It streams live MJPEG video from your Frigate NVR instance in a compact floating panel, with quick navigation between cameras and real-time connection status in the bar.

### Key Features

- **Live MJPEG Streaming** — Real-time video from Frigate cameras using native QML Image rendering
- **Bar Widget with Status** — Camera icon with green/red connection status dot and dynamic tooltip
- **Camera Navigation** — Left/right buttons to cycle through selected cameras
- **Settings UI** — Configure Frigate URL, optional Basic Auth credentials, test connection, and discover cameras
- **Camera Selection** — Choose which cameras appear in the viewer via checkboxes
- **Persistence** — All settings and camera selections survive restarts
- **i18n** — Full English and Portuguese translations
- **Theme Compliance** — Zero hardcoded colors; all styling via Noctalia theme tokens

## Requirements

| Dependency | Version | Notes |
|------------|---------|-------|
| [Noctalia Shell](https://github.com/noctalia-dev/noctalia-shell) | 4.4.0+ | Plugin host environment |
| [Frigate NVR](https://frigate.video) | 0.9+ | Camera server |
| Linux + niri | — | Wayland compositor |

No build step required. Pure QML plugin.

## Installation

### Quick Install

```bash
# Clone the repository
git clone https://github.com/pir0c0pter0/noctalia-frigate.git

# Symlink to Noctalia plugins directory
ln -sf "$(pwd)/noctalia-frigate" ~/.config/noctalia/plugins/noctalia-frigate
```

### Manual Install

```bash
# Copy files directly
cp -r noctalia-frigate ~/.config/noctalia/plugins/noctalia-frigate
```

### Enable the Plugin

1. Open Noctalia **Settings > Plugins**
2. Enable **Frigate Viewer**
3. Go to **Settings > Bar**
4. Add **Frigate Viewer** widget to your bar

## Configuration

### Connection Setup

1. Open Noctalia **Settings > Plugins > Frigate Viewer**
2. Enter your Frigate server URL (e.g., `http://192.168.1.100:5000`)
3. *(Optional)* Enter username and password for Basic Auth
4. Click **Save**, then **Test Connection**
5. Click **List Cameras** to discover available cameras
6. Check the cameras you want in the viewer
7. Click **Save** again

### Supported Connection Scenarios

| Scenario | URL Example | Auth |
|----------|-------------|------|
| Local, no auth | `http://192.168.1.100:5000` | None |
| Local, Basic Auth (reverse proxy) | `http://192.168.1.100:8080` | Username + Password |
| Remote, HTTPS no auth | `https://frigate.example.com` | None |
| Remote, HTTPS + Basic Auth | `https://frigate.example.com` | Username + Password |

> **Note:** Frigate's native JWT authentication (port 8971) is **not supported**. Use port 5000 (unauthenticated) or a reverse proxy with Basic Auth (nginx, Traefik, Caddy).

## Usage

### Bar Widget

- **Camera icon** appears in your Noctalia bar
- **Status dot**: green = connected, red = disconnected
- **Hover** for tooltip showing connection status
- **Click** to open/close the viewer panel

### Viewer Panel

- **Live stream** from the currently selected camera
- **Camera name** displayed in the header
- **Left/Right arrows** to navigate between cameras (visible when 2+ cameras selected)
- **Auto-reconnect** when reopening the panel
- **Resource-friendly**: stream stops when panel is closed

## Architecture

```
manifest.json          Plugin identity + default settings
Main.qml               State hub: connection, cameras, stream URL, navigation
BarWidget.qml           Bar icon + status dot + tooltip + panel toggle
Panel.qml              MJPEG viewer + navigation + error states
Settings.qml           Connection config + camera selection
i18n/en.json           English translations
i18n/pt.json           Portuguese translations
```

### Data Flow

```
Main.qml (state hub)
  ├── BarWidget.qml reads: connectionStatus
  ├── Panel.qml reads: streamUrl, currentCameraName, selectedCameras
  ├── Settings.qml writes: frigateUrl, username, password, selectedCameras
  └── Frigate API: /api/version, /api/config, /api/<camera>?fps=5
```

### Frigate API Endpoints Used

| Endpoint | Purpose |
|----------|---------|
| `GET /api/version` | Connection test + health polling (30s interval) |
| `GET /api/config` | Discover camera names |
| `GET /api/<camera>?fps=5` | MJPEG live stream |

## Development

### Hot Reload

```bash
# Symlink for development
ln -sf ~/path/to/noctalia-frigate ~/.config/noctalia/plugins/noctalia-frigate

# Start Noctalia with debug mode
NOCTALIA_DEBUG=1 qs -c noctalia-shell --no-duplicate
```

Changes to QML files are picked up on save.

## KDE Plasma 6 Port

The complete Plasma 6 port is available in:

- `port-kde-plasma6/README.md`

It includes the full plasmoid package, installation scripts, feature-parity baseline, and test matrix.

### Project Structure

```
noctalia-frigate/
├── manifest.json        # Plugin manifest
├── Main.qml             # State hub + API logic
├── BarWidget.qml        # Bar widget
├── Panel.qml            # Viewer panel
├── Settings.qml         # Settings form
├── i18n/
│   ├── en.json          # English
│   └── pt.json          # Portuguese
└── .planning/           # Development planning docs
```

## Limitations

- **Single Frigate server** — v1 supports one Frigate instance
- **No JWT auth** — Frigate's native JWT (port 8971) is incompatible with QML Image; use port 5000 or a Basic Auth proxy
- **No audio** — MJPEG is video-only
- **No recording playback** — Use Frigate's web UI for event history
- **No PTZ controls** — Use Frigate's web UI for camera controls

## Roadmap

- [ ] Birdseye composite snapshot view
- [ ] Configurable FPS per camera
- [ ] Detection event alert indicator on bar icon
- [ ] Camera count badge
- [ ] Multi-server support

## Contributing

Contributions are welcome! This is a pure QML project — no build tools needed.

1. Fork the repository
2. Create your feature branch
3. Make your changes
4. Test with `NOCTALIA_DEBUG=1 qs -c noctalia-shell --no-duplicate`
5. Submit a pull request

## License

[MIT](LICENSE) &copy; [pir0c0pter0](https://github.com/pir0c0pter0)

---

<div align="center">

Built for [Noctalia Shell](https://github.com/noctalia-dev/noctalia-shell) | Powered by [Frigate NVR](https://frigate.video)

</div>
