#!/usr/bin/env bash
set -euo pipefail

if ! command -v kpackagetool6 >/dev/null 2>&1; then
  echo "kpackagetool6 nao encontrado."
  exit 1
fi

kpackagetool6 --type Plasma/Applet --remove com.noctalia.frigateviewer

echo "Plasmoid removido: com.noctalia.frigateviewer"
