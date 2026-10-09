#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
# Use Command Line Tools explicitly; a full Xcode installation is not required.
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
swift build -c release
BUILD_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$PWD/dist/DrummFix.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
ICON_PNG="$PWD/assets/DrummFixIcon.png"
ICONSET="$PWD/.build/DrummFix.iconset"
swift scripts/generate-icon.swift "$ICON_PNG"
mkdir -p "$ICONSET"
for spec in '16 icon_16x16.png' '32 icon_16x16@2x.png' \
            '32 icon_32x32.png' '64 icon_32x32@2x.png' \
            '128 icon_128x128.png' '256 icon_128x128@2x.png' \
            '256 icon_256x256.png' '512 icon_256x256@2x.png' \
            '512 icon_512x512.png' '1024 icon_512x512@2x.png'; do
    read -r dimension filename <<< "$spec"
    sips --resampleHeightWidth "$dimension" "$dimension" "$ICON_PNG" \
         --out "$ICONSET/$filename" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/DrummFix.icns"
cp "$BUILD_DIR/DrummFix" "$APP_DIR/Contents/MacOS/DrummFix"
cp "$BUILD_DIR/DrummFixGuard" "$APP_DIR/Contents/MacOS/DrummFixGuard"
cp "$BUILD_DIR/DrummFixProbe" "$APP_DIR/Contents/MacOS/DrummFixProbe"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DrummFix</string>
<key>CFBundleIdentifier</key><string>local.drummfix.app</string>
<key>CFBundleName</key><string>DrummFix</string>
<key>CFBundleDisplayName</key><string>DrummFix</string>
<key>CFBundleIconFile</key><string>DrummFix</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.2</string>
<key>CFBundleVersion</key><string>4</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP_DIR/Contents/MacOS/DrummFixGuard"
codesign --force --sign - "$APP_DIR/Contents/MacOS/DrummFixProbe"
codesign --force --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
echo "Built: $APP_DIR"
