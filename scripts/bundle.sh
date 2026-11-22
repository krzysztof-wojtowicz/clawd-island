#!/bin/bash
# Assembles and signs dist/ClawdNotch.app from the SwiftPM build products (ADR-0001, ADR-0008).
# Usage: scripts/bundle.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."

config="${1:-debug}"
swift build -c "$config"
bin="$(swift build -c "$config" --show-bin-path)"

app=dist/ClawdNotch.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
mkdir -p "$app/Contents/Resources"
cp "$bin/ClawdNotch" "$bin/clawd-bridge" "$app/Contents/MacOS/"
cp -R Resources/Fonts "$app/Contents/Resources/Fonts"
cp Resources/AppIcon.icns "$app/Contents/Resources/"

version=1.0.0 # keep in sync with CHANGELOG.md
build="$(git rev-list --count HEAD)"

cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>dev.clawdnotch.app</string>
    <key>CFBundleName</key><string>ClawdNotch</string>
    <key>CFBundleExecutable</key><string>ClawdNotch</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$build</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Krzysztof Wójtowicz. MIT License.</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>ClawdNotch asks Terminal and iTerm2 which tab is in front, so it can mark that tab's Claude Code session as read, and focuses a session's tab when you click it.</string>
</dict>
</plist>
EOF

# Sign the nested CLI first; the outer signature covers it. A stable identity keeps TCC grants across rebuilds.
identity="-"
if security find-identity -v -p codesigning | grep -q '"ClawdNotch Dev"'; then identity="ClawdNotch Dev"; fi
codesign --force -s "$identity" "$app/Contents/MacOS/clawd-bridge"
codesign --force --deep -s "$identity" "$app"
if [[ "$identity" == "-" ]]; then
    echo "Signed ad-hoc (run scripts/make-signing-cert.sh once so permissions survive rebuilds)"
else
    echo "Signed with \"$identity\""
fi
echo "Built $app ($config) $version ($build)"
