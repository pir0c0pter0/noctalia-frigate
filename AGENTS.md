# Repository Guidelines

## Project Structure & Module Organization
This repository is a pure QML Noctalia plugin; everything lives at the root.

- Root plugin files: `Main.qml`, `BarWidget.qml`, `Panel.qml`, `Settings.qml`, and `manifest.json`
- Shared helpers: `Translation.js` (i18n helper) and `LabeledTextField.qml` (reusable settings input)
- Translations: `i18n/en.json` and `i18n/pt-BR.json`
- Example local config: `settings.example.json`

## Build, Test, and Development Commands
There is no build step; changes are loaded by the host shell.

- `ln -sf "$(pwd)" ~/.config/noctalia/plugins/noctalia-frigate`: symlink the plugin for local Noctalia development
- `NOCTALIA_DEBUG=1 qs -c noctalia-shell --no-duplicate`: run Noctalia in debug mode with hot reload
- `qmllint *.qml`: lint the root QML files

## Coding Style & Naming Conventions
Use 4-space indentation in QML and keep component files in `PascalCase.qml`. Use `camelCase` for QML properties, functions, and JavaScript helpers, and `lowerCamelCase` keys in translation JSON. Prefer descriptive state names such as `connectionStatus` and `selectedCameras`. Follow the existing theme-safe approach: use the Noctalia shell theme tokens instead of hardcoded colors.

## Testing Guidelines
There is no automated unit-test suite in this repository. Before opening a PR, manually verify the relevant flows in Noctalia against a real Frigate instance: connection handling, camera selection, navigation wraparound, persistence, and i18n.

## Commit & Pull Request Guidelines
Recent history follows Conventional Commit style with scopes, for example `feat(settings): ...`, `fix(panel): ...`, and `chore(root): ...`. Keep that pattern. PRs should include a short problem statement, the user-visible impact, validation steps you ran, and screenshots or screen recordings for UI changes. Link the related issue when one exists.

## Security & Configuration Tips
Do not commit real Frigate URLs, usernames, passwords, or local environment details. Start from `settings.example.json` for shared examples, and redact credentials from logs and screenshots.
