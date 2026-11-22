#!/bin/bash
# Records the README GIFs from the release bundle in dist/ (skill: build-and-run).
# Usage: scripts/record-gif.sh <island|hide-mode> [out.gif]
# Captures only the app's window (screencapture -l), so no other screen content can appear.
# Needs the Screen Recording permission and the Bash sandbox disabled. Backs up and restores config.json.
set -euo pipefail
cd "$(dirname "$0")/.."

scene="${1:?usage: record-gif.sh <island|hide-mode> [out.gif]}"
out="${2:-docs/media/$scene.gif}"
config="$HOME/Library/Application Support/ClawdIsland/config.json"
work="$(mktemp -d)"
backup="$work/config.json.bak"
sim=scripts/simulate.sh
fps=10

cp "$config" "$backup"
cleanup() {
    kill "${scene_pid:-}" 2>/dev/null || true
    $sim end >/dev/null 2>&1 || true
    swift scripts/hover.swift off 2>/dev/null || true
    pkill -x ClawdIsland 2>/dev/null || true
    cp "$backup" "$config"
}
trap cleanup EXIT

# Scene timelines run in the background while the frames are captured.
scene_island() {
    sleep 1.5; $sim start; sleep 1
    $sim think; sleep 1.2
    $sim tool; sleep 1.5
    $sim done; sleep 1.5
    swift scripts/hover.swift on; sleep 3
    swift scripts/hover.swift off; sleep 1.5
}
scene_hide_mode() {
    sleep 1.5; $sim start; sleep 2
    $sim think; sleep 2
    $sim text; sleep 4.5
    sleep 1
}

case "$scene" in
    island)    hide=false ;;
    hide-mode) hide=true ;;
    *) echo "unknown scene $scene" >&2; exit 1 ;;
esac

# Quiet, deterministic config for the recording: no sound, chosen mini mode.
plutil -replace miniMode -bool "$hide" "$config"
plutil -replace soundCues -bool false "$config"

swift scripts/hover.swift off 2>/dev/null || true
pkill -x ClawdIsland 2>/dev/null || true
while pgrep -x ClawdIsland >/dev/null; do sleep 0.1; done
open dist/ClawdIsland.app
sleep 2

mkdir -p "$work/bin" "$work/frames"
swiftc -O scripts/window-id.swift -o "$work/bin/window-id"

"scene_${scene//-/_}" &
scene_pid=$!

n=0
start=$(date +%s.%N)
while kill -0 "$scene_pid" 2>/dev/null; do
    # The window resizes and may vanish (mini mode), so resolve its ID for every frame.
    # One screencapture takes ~300 ms, so captures overlap to reach the target fps.
    if read -r id x < <("$work/bin/window-id"); then
        n=$((n + 1))
        # The left edge goes into the name: the island is asymmetric around the notch, so the encoder aligns by it.
        screencapture -x -o -l "$id" "$work/frames/tick-$(printf %03d "$n")_x$x.png" &
    fi
    sleep "$(echo "scale=3; 1/$fps" | bc)"
done
wait
# Drop captures that failed (window vanished mid-capture) and renumber for the encoder.
n=0
for f in "$work"/frames/tick-*.png; do
    if [[ -s "$f" ]]; then
        n=$((n + 1))
        mv "$f" "$work/frames/frame-$(printf %03d "$n")_${f##*_}"
    else
        rm -f "$f"
    fi
done
elapsed=$(echo "$(date +%s.%N) - $start" | bc)
delay=$(echo "scale=3; $elapsed / $n" | bc)
echo "captured $n frames in ${elapsed}s (delay $delay s)"

swift scripts/make-gif.swift "$work/frames" "$out" "$delay" "${GIF_MAX_WIDTH:-816}" 1
ls -l "$out"
echo "frames kept in $work/frames"
