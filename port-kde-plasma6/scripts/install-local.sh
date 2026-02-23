#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKAGE_DIR="$REPO_ROOT/port-kde-plasma6/package"

if ! command -v kpackagetool6 >/dev/null 2>&1; then
  echo "kpackagetool6 nao encontrado. Instale Plasma 6 development tools."
  exit 1
fi

kpackagetool6 --type Plasma/Applet --upgrade "$PACKAGE_DIR" 2>/dev/null \
  || kpackagetool6 --type Plasma/Applet --install "$PACKAGE_DIR"

echo "Plasmoid instalado/atualizado: com.noctalia.frigateviewer"
