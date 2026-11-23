#!/bin/bash
# Builds a release ClawdIsland.app, replaces the installed copy and launches it (REQ-15 AC3).
# Usage: scripts/install.sh [--dest DIR]   (default ~/Applications; pass /Applications for all users)
set -euo pipefail
cd "$(dirname "$0")/.."

dest="$HOME/Applications"
if [[ "${1:-}" == "--dest" ]]; then dest="${2:?--dest needs a directory}"; elif [[ $# -gt 0 ]]; then
    echo "Usage: scripts/install.sh [--dest DIR]" >&2; exit 2
fi

scripts/bundle.sh release

# Quit politely, then wait: the new copy must not start while the old one still holds the port.
osascript -e 'tell application id "dev.clawdisland.app" to quit' >/dev/null 2>&1 || true
for _ in {1..20}; do pgrep -x ClawdIsland >/dev/null || break; sleep 0.25; done
pkill -x ClawdIsland 2>/dev/null || true

mkdir -p "$dest"
# Copy first, swap after, so a failed copy never leaves the user without an app.
rm -rf "$dest/ClawdIsland.app.new"
ditto dist/ClawdIsland.app "$dest/ClawdIsland.app.new"
rm -rf "$dest/ClawdIsland.app"
mv "$dest/ClawdIsland.app.new" "$dest/ClawdIsland.app"
open "$dest/ClawdIsland.app"

echo "Installed $dest/ClawdIsland.app"
echo "Open Settings (right-click the notch) → Install in the hooks row so hooks point at the new bridge path"
