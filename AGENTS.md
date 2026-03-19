# Repository Guidelines

## Project Structure & Module Organization
This repository contains a pure QML Noctalia plugin at the root and a KDE Plasma 6 port under `port-kde-plasma6/`.

- Root plugin files: `Main.qml`, `BarWidget.qml`, `Panel.qml`, `Settings.qml`, and `manifest.json`
- Translations: `i18n/en.json` and `i18n/pt.json`
- Example local config: `settings.example.json`
- Plasma port package: `port-kde-plasma6/package/contents/ui/`
- Plasma port docs and validation notes: `port-kde-plasma6/README.md`, `TEST_MATRIX.md`, `PORT_BASELINE.md`
- Plasma install helpers: `port-kde-plasma6/scripts/install-local.sh` and `uninstall-local.sh`

## Build, Test, and Development Commands
There is no build step; changes are loaded by the host shell.

- `ln -sf "$(pwd)" ~/.config/noctalia/plugins/noctalia-frigate`: symlink the plugin for local Noctalia development
- `NOCTALIA_DEBUG=1 qs -c noctalia-shell --no-duplicate`: run Noctalia in debug mode with hot reload
- `qmllint port-kde-plasma6/package/contents/ui/*.qml port-kde-plasma6/package/contents/ui/components/*.qml port-kde-plasma6/package/contents/ui/config/*.qml`: lint the Plasma 6 QML files
- `./port-kde-plasma6/scripts/install-local.sh`: install or upgrade the Plasma plasmoid locally
- `./port-kde-plasma6/scripts/uninstall-local.sh`: remove the local Plasma plasmoid

## Coding Style & Naming Conventions
Use 4-space indentation in QML and keep component files in `PascalCase.qml`. Use `camelCase` for QML properties, functions, and JavaScript helpers, and `lowerCamelCase` keys in translation JSON. Prefer descriptive state names such as `connectionStatus` and `selectedCameras`. Follow the existing theme-safe approach: use shell or Plasma theme tokens instead of hardcoded colors.

## Testing Guidelines
There is no automated unit-test suite in this repository. Run `qmllint` for the Plasma port before opening a PR, then manually verify the relevant flow in Noctalia or Plasma with a real Frigate instance. Use `port-kde-plasma6/TEST_MATRIX.md` as the baseline for manual coverage, especially connection handling, camera selection, navigation wraparound, persistence, and i18n.

## Commit & Pull Request Guidelines
Recent history follows Conventional Commit style with scopes, for example `feat(ha): ...`, `fix(plasma6): ...`, and `chore(root): ...`. Keep that pattern. PRs should include a short problem statement, the user-visible impact, validation steps you ran, and screenshots or screen recordings for UI changes. Link the related issue when one exists.

## Security & Configuration Tips
Do not commit real Frigate URLs, usernames, passwords, or local environment details. Start from `settings.example.json` for shared examples, and redact credentials from logs and screenshots.
