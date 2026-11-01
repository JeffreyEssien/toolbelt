#!/bin/bash
# Builds Toolbelt.app with Apple's Command Line Tools, signs it for this Mac,
# installs it in ~/Applications and opens it.
#   ./install.sh               build, install and open
#   ./install.sh --build-only  just build build/Toolbelt.app
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Toolbelt.app"
DEST="$HOME/Applications"

echo "Building…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/Toolbelt"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Toolbelt"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] || swift Scripts/make-icon.swift Resources/AppIcon.icns
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# "-" signs it for this Mac only. Sharing it with others needs a paid Developer ID.
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--build-only" ]]; then
    exit 0
fi

pkill -x Toolbelt 2>/dev/null && sleep 0.5 || true
mkdir -p "$DEST"
rm -rf "$DEST/Toolbelt.app"
cp -R "$APP" "$DEST/"
open "$DEST/Toolbelt.app"
echo "Installed in $DEST and opened. It's in your Dock, and the wrench icon is in your menu bar."
