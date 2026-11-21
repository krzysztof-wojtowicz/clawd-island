#!/bin/bash
# Assembles and ad-hoc signs dist/ClawdNotch.app from the SwiftPM build products (ADR-0001).
# Usage: scripts/bundle.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."

config="${1:-debug}"
swift build -c "$config"
bin="$(swift build -c "$config" --show-bin-path)"

app=dist/ClawdNotch.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin/ClawdNotch" "$bin/clawd-bridge" "$app/Contents/MacOS/"

cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>dev.clawdnotch.app</string>
    <key>CFBundleName</key><string>ClawdNotch</string>
    <key>CFBundleExecutable</key><string>ClawdNotch</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>ClawdNotch asks Terminal and iTerm2 which tab is in front, so it can mark that tab's Claude Code session as read, and focuses a session's tab when you click it.</string>
</dict>
</plist>
EOF

# Sign the nested CLI first; the outer signature covers it.
codesign --force --sign - "$app/Contents/MacOS/clawd-bridge"
codesign --force --sign - "$app"
echo "Built $app ($config)"
