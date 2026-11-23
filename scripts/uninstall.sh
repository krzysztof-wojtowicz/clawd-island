#!/bin/bash
# Removes ClawdIsland: its hooks (through the app's reversible uninstaller), the app and its config (REQ-15 AC3).
# Usage: scripts/uninstall.sh [--dest DIR] [--yes]   (default ~/Applications)
set -euo pipefail

dest="$HOME/Applications"
yes=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dest) dest="${2:?--dest needs a directory}"; shift 2 ;;
        --yes) yes=true; shift ;;
        *) echo "Usage: scripts/uninstall.sh [--dest DIR] [--yes]" >&2; exit 2 ;;
    esac
done

app="$dest/ClawdIsland.app"
support="$HOME/Library/Application Support/ClawdIsland"
[[ -d "$app" ]] || { echo "No $app; use --dest if you installed elsewhere." >&2; exit 1; }

if [[ "$yes" != true ]]; then
    echo "This removes the hooks from ~/.claude/settings.json (restoring your statusline), $app and $support."
    read -r -p "Continue? [y/N] " answer
    [[ "$answer" == [yY]* ]] || { echo "Cancelled."; exit 1; }
fi

osascript -e 'tell application id "dev.clawdisland.app" to quit' >/dev/null 2>&1 || true
for _ in {1..20}; do pgrep -x ClawdIsland >/dev/null || break; sleep 0.25; done
pkill -x ClawdIsland 2>/dev/null || true

# Must run before the config is deleted: it holds the statusline to restore.
"$app/Contents/MacOS/ClawdIsland" --uninstall-hooks
rm -rf "$app" "$support"
echo "Uninstalled ClawdIsland."
