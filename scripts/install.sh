#!/bin/bash
# Builds a release ClawdNotch.app, replaces the installed copy and launches it (REQ-15 AC4).
# Usage: scripts/install.sh [--dest DIR]   (default ~/Applications; pass /Applications for all users)
set -euo pipefail
cd "$(dirname "$0")/.."

dest="$HOME/Applications"
if [[ "${1:-}" == "--dest" ]]; then dest="${2:?--dest needs a directory}"; elif [[ $# -gt 0 ]]; then
    echo "Usage: scripts/install.sh [--dest DIR]" >&2; exit 2
fi

scripts/bundle.sh release

# Quit politely, then wait: the new copy must not start while the old one still holds the port.
osascript -e 'tell application id "dev.clawdnotch.app" to quit' >/dev/null 2>&1 || true
for _ in {1..20}; do pgrep -x ClawdNotch >/dev/null || break; sleep 0.25; done
pkill -x ClawdNotch 2>/dev/null || true

mkdir -p "$dest"
rm -rf "$dest/ClawdNotch.app"
ditto dist/ClawdNotch.app "$dest/ClawdNotch.app"
open "$dest/ClawdNotch.app"

echo "Installed $dest/ClawdNotch.app"
echo "Open the menu → Install Hooks so hooks point at the new bridge path"
