#!/bin/bash
# Builds a release bundle and zips it as dist/ClawdIsland-<version>.zip with a .sha256 next to it (REQ-15 AC3).
# Usage: scripts/package.sh [--adhoc]
# Refuses an ad-hoc signed build unless --adhoc is given: only the stable identity keeps TCC grants across updates (ADR-0008).
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/bundle.sh release
# `-dvv` lists the certificate chain as Authority= lines (`-dv` omits them); a self-signed one is a single line.
signature="$(codesign -dvv dist/ClawdIsland.app 2>&1)"
if [[ "${1:-}" != "--adhoc" ]] && ! grep -qx 'Authority=ClawdIsland' <<<"$signature"; then
    echo "package.sh: the build is not signed with \"ClawdIsland\"; run scripts/make-signing-cert.sh, or pass --adhoc" >&2
    exit 1
fi
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' dist/ClawdIsland.app/Contents/Info.plist)"
zip="ClawdIsland-$version.zip"
rm -f "dist/$zip" "dist/$zip.sha256"
ditto -c -k --keepParent dist/ClawdIsland.app "dist/$zip"
(cd dist && shasum -a 256 "$zip" > "$zip.sha256")
echo "Packaged dist/$zip"
cat "dist/$zip.sha256"
