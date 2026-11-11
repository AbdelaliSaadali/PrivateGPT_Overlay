#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="PrivateGPTOverlay"
APP="$PROJECT_DIR/build/${APP_NAME}.app"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Apple Swift compiler not found. Install Xcode Command Line Tools with:"
  echo "  xcode-select --install"
  exit 1
fi

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$PROJECT_DIR/Info.plist" "$APP/Contents/Info.plist"
rm -f "$APP/Contents/Resources/AppIcon.icns"
cp "$PROJECT_DIR/Assets/AppIcon.icns" "$APP/Contents/Resources/PrivateGPTCrowned.icns"
mkdir -p "$APP/Contents/Resources/Brand"
cp "$PROJECT_DIR"/Assets/Brand/*.png "$APP/Contents/Resources/Brand/"

# Compile a native executable for this Mac. No CocoaPods, packages, or API keys.
MACOSX_DEPLOYMENT_TARGET=13.0 xcrun swiftc -swift-version 5 -O \
  -framework AppKit -framework WebKit -framework Carbon \
  "$PROJECT_DIR/PrivateGPTOverlay.swift" \
  "$PROJECT_DIR/DesktopClipboardCapture.swift" \
  "$PROJECT_DIR/AudioRouting.swift" \
  "$PROJECT_DIR/AudioControls.swift" \
  -o "$APP/Contents/MacOS/$APP_NAME"

plutil -lint "$APP/Contents/Info.plist"

# Prefer the Mac owner's persistent Apple Development certificate.
# Ad-hoc signatures pin TCC permissions to a new cdhash after EVERY rebuild.
# Stable signing keeps the screenshot authorization valid across app updates.
SIGNING_IDENTITY="${PRIVATEGPT_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | grep '"Apple Development:' | awk '{print $2}' | head -n 1 || true)}"
if [[ -n "$SIGNING_IDENTITY" ]]; then
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none \
    --entitlements "$PROJECT_DIR/Entitlements.plist" "$APP"
  echo "Signed with persistent Apple Development identity."
else
  echo "WARNING: No Apple Development certificate is available."
  echo "Ad-hoc signing will require regranting Screen Recording after each rebuild."
  codesign --force --sign - --entitlements "$PROJECT_DIR/Entitlements.plist" "$APP"
fi

echo ""
echo "Built: $APP"
if [[ "${1:-}" != "--no-open" ]]; then
  echo "Opening app..."
  open "$APP"
else
  echo "Build only (app was not opened)."
fi
echo ""
echo "Shortcut: Control+Option+Space = show/hide"
echo "Shortcut: Control+Option+M = toggle audio mode"
echo "Shortcut: Control+Option+3 = silently capture desktop to clipboard"
echo "Shortcut: Control+Option+S = settings (recommended)"
echo "Shortcut: Control+Option+, = settings (alternative)"
echo "Shortcut: Control+Option+Q = quit"
echo ""
echo "TEST visibility with a local recording and your actual screen-sharing app."
echo "Do not assume this window is hidden from screen capture."
