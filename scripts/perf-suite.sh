#!/bin/bash
# Runs every docs/08 v4 scenario on a release bundle and prints one table (WP-22, REQ-08).
# Usage: scripts/perf-suite.sh [settle=30] [sample=20]
# CPU is `ps %cpu`, a decaying average, so each scenario settles before it is sampled. Needs the sandbox off
# (localhost + launching). Restores config.json on exit and leaves no instance running.
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."

settle="${1:-30}"
sample="${2:-20}"
config="$HOME/Library/Application Support/ClawdNotch/config.json"
backup="$(mktemp -t clawd-config)"
had_config=0
if [[ -f "$config" ]]; then cp "$config" "$backup"; had_config=1; fi
rows=()
pid=""

cleanup() {
    pkill -x ClawdNotch 2>/dev/null || true
    sleep 1 # let the app finish any config write before we restore
    if (( had_config )); then cp "$backup" "$config"; else rm -f "$config"; fi
    rm -f "$backup"
}
trap cleanup EXIT

launch() {
    pkill -x ClawdNotch 2>/dev/null || true
    sleep 1
    open -n dist/ClawdNotch.app ${1:+--args "$@"}
    for _ in $(seq 1 50); do
        pid="$(pgrep -nx ClawdNotch || true)"
        [[ -n "$pid" ]] && break
        sleep 0.2
    done
    [[ -n "$pid" ]] || { echo "ClawdNotch did not start" >&2; exit 1; }
}

# measure <seconds>: prints "cpu_avg cpu_max rss_max_mb" over the window.
measure() {
    for ((i = 0; i < $1; i++)); do ps -o %cpu=,rss= -p "$pid" || break; sleep 1; done | awk '
        { c += $1; if ($1 > cm) cm = $1; r = $2 / 1024; if (r > rm) rm = r; n++ }
        END { if (n) printf "%.2f %.2f %.1f", c / n, cm, rm; else printf "- - -" }'
}

footprint_mb() {
    footprint "$pid" 2>/dev/null | awk '
        /phys_footprint:/ { v = $2; if ($3 ~ /^KB/) v /= 1024; else if ($3 ~ /^GB/) v *= 1024; printf "%.1f", v; f = 1 }
        END { if (!f) printf "-" }'
}

# record <name> <measure output>
record() {
    read -r avg max rss <<<"$2"
    rows+=("$(printf '%-34s %8s %8s %9s %10s' "$1" "$avg" "$max" "$rss" "$(footprint_mb)")")
    echo "${rows[${#rows[@]}-1]}"
}

settled() { sleep "$settle"; record "$1" "$(measure "$sample")"; }
sim() { scripts/simulate.sh "$@" >/dev/null; }
endall() { for s in sim-1 sim-a sim-b sim-c; do sim end "$s"; done; }

set_hide_mode() {
    mkdir -p "$(dirname "$config")"
    [[ -f "$config" ]] || echo '{}' >"$config"
    plutil -replace hideMode -bool "$1" "$config"
}

header() {
    printf '%-34s %8s %8s %9s %10s\n' scenario cpu_avg% cpu_max% rss_max_MB footprint_MB
}

echo "building release bundle..." >&2
scripts/bundle.sh release >/dev/null
header

# hideMode must be off for the normal scenarios, whatever the user's config says.
set_hide_mode false
launch
record "launch peak (first ${settle}s)" "$(measure "$settle")"
settled "sleeping"
sim start; sim think
settled "thinking"
sim tool
settled "usingTools"
sim done

scripts/simulate.sh burst >/dev/null &
burst=$!
record "burst (50 events/s, 10 s)" "$(measure 12)"
wait "$burst" || true
endall
settled "post-burst"

swift scripts/hover.swift on
settled "expanded hover"
swift scripts/hover.swift off

sim start; sim permission
settled "permission card"
endall

launch --open-settings --close-settings-after 10
record "settings open (first 10 s)" "$(measure 10)"
settled "settings closed"

set_hide_mode true
launch
settled "hidden idle"
sim start; sim think; sleep 3; sim done
record "hide-mode pop-out (after a turn)" "$(measure "$sample")"
endall

echo
echo "== summary =="
header
printf '%s\n' "${rows[@]}"
