#!/bin/bash
# Builds a release bundle and zips it as dist/ClawdNotch-<version>.zip with a .sha256 next to it (REQ-15 AC4).
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/bundle.sh release
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' dist/ClawdNotch.app/Contents/Info.plist)"
zip="ClawdNotch-$version.zip"
rm -f "dist/$zip" "dist/$zip.sha256"
ditto -c -k --keepParent dist/ClawdNotch.app "dist/$zip"
(cd dist && shasum -a 256 "$zip" > "$zip.sha256")
echo "Packaged dist/$zip"
cat "dist/$zip.sha256"
