#!/bin/bash
# Restarts ClawdIsland from a fresh debug bundle. Extra arguments go to the app (e.g. --pet-demo).
set -euo pipefail
cd "$(dirname "$0")/.."

pkill -x ClawdIsland || true
scripts/bundle.sh debug
# open would reactivate a still-terminating instance and drop the new --args.
while pgrep -x ClawdIsland >/dev/null; do sleep 0.1; done
open dist/ClawdIsland.app --args "$@"
