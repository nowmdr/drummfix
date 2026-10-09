#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."
APP="$PWD/dist/DrummFix.app"
STAGING="$PWD/.build/dmg-staging"

if [[ ! -d "$APP" ]]; then
    echo "Build the app first: zsh scripts/build-app.sh" >&2
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="$PWD/dist/DrummFix-${VERSION}-macOS-arm64.dmg"
codesign --verify --deep --strict "$APP"
rm -rf "$STAGING"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/DrummFix.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "DrummFix $VERSION" -srcfolder "$STAGING" \
    -ov -format UDZO "$DMG" >/dev/null
shasum -a 256 "$DMG"
echo "Built: $DMG"
