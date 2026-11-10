#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$PROJECT_DIR/build.sh" --no-open

APP_SOURCE="$PROJECT_DIR/build/PrivateGPTOverlay.app"
APP_DEST="/Applications/PrivateGPT Overlay.app"

if [[ -d "$APP_DEST" ]]; then
  echo "An existing installed app was found. Quit it before updating."
  if pgrep -f '/Applications/PrivateGPT Overlay.app/Contents/MacOS/PrivateGPTOverlay' >/dev/null 2>&1; then
    echo "Please quit PrivateGPT Overlay before installing."
    exit 1
  fi
fi

ditto "$APP_SOURCE" "$APP_DEST"
codesign --verify --deep --strict "$APP_DEST"
echo ""
echo "Installed: $APP_DEST"
echo "Open PrivateGPT Overlay from Applications whenever you're ready."
echo "Settings: Control+Option+S (recommended), or Control+Option+,"
echo "Toggle audio: Control+Option+M"
