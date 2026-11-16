#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP_VERSION="$(tr -d '[:space:]' < VERSION)"
APP_BUILD="$(tr -d '[:space:]' < BUILD_NUMBER)"
[[ "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid VERSION' >&2; exit 1; }
[[ "$APP_BUILD" =~ ^[1-9][0-9]*$ ]] || { echo 'Invalid BUILD_NUMBER' >&2; exit 1; }
swift build -c release
APP="$PWD/dist/AI Usage.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Tools"
cp .build/release/AIUsageBar "$APP/Contents/MacOS/AIUsageBar"
cp Tools/CodexBarCLI "$APP/Contents/Resources/Tools/"
rm -rf "$APP/Contents/Resources/Tools/CodexBar_CodexBarCore.bundle"
cp -R Tools/CodexBar_CodexBarCore.bundle "$APP/Contents/Resources/Tools/"
cp -R Assets "$APP/Contents/Resources/"
cp -R Tools/THIRD_PARTY_NOTICES "$APP/Contents/Resources/Tools/"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>personal.AIUsageBar</string>
<key>CFBundleName</key><string>AI Usage</string>
<key>CFBundleDisplayName</key><string>AI Usage</string>
<key>CFBundleExecutable</key><string>AIUsageBar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
<key>CFBundleVersion</key><string>$APP_BUILD</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP/Contents/MacOS/AIUsageBar"
codesign --force --sign - "$APP"
printf 'Built: %s\n' "$APP"
