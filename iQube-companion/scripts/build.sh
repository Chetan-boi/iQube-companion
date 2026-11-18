#!/bin/zsh
# Build, sign with a stable local identity, install to /Applications and relaunch.
#
# Why: ad-hoc signed builds get a new identity on every rebuild, so macOS treats each build as a new app
# and asks for the Keychain password again. Signing with the same self-signed certificate every time
# keeps the app's identity stable, so "Always Allow" sticks across rebuilds.
#
# One-time setup (creates the certificate in its own keychain): scripts/setup-signing.sh
set -euo pipefail

cd "$(dirname "$0")/.."
KC="$HOME/Library/Keychains/iqube-signing.keychain-db"
PWF="$HOME/.config/iqube-companion/signing-keychain-password"
IDENTITY="iQube Companion Local Signing"
APP_NAME="iQube Companion"   # PRODUCT_NAME in project.yml
BUILT="build/Build/Products/Release/$APP_NAME.app"
DEST="/Applications/$APP_NAME.app"

[[ -f "$PWF" && -f "$KC" ]] || { echo "Signing keychain missing. Run scripts/setup-signing.sh first."; exit 1; }
security unlock-keychain -p "$(cat "$PWF")" "$KC"

xcodegen generate --quiet
xcodebuild -project TVSConnect.xcodeproj -scheme TVSConnect -configuration Release \
  -derivedDataPath build build -quiet 2>&1 | grep -v 'CoreSimulator is out of date' || true
[[ -d "$BUILT" ]] || { echo "Build failed."; exit 1; }

# Inside-out: extension first, then the app. Keep the entitlements Xcode generated.
codesign -f -s "$IDENTITY" --keychain "$KC" --preserve-metadata=entitlements \
  "$BUILT/Contents/PlugIns/TVSConnectWidget.appex"
codesign -f -s "$IDENTITY" --keychain "$KC" --preserve-metadata=entitlements "$BUILT"
codesign --verify --deep --strict "$BUILT"

pkill -x "$APP_NAME" 2>/dev/null || true
sleep 1
rm -rf "$DEST"
ditto "$BUILT" "$DEST"
open "$DEST"
echo "Installed $DEST"
codesign -d -r- "$DEST" 2>&1 | tail -1
