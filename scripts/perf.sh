#!/bin/bash
# Samples ClawdNotch CPU and memory once per second and checks them against the budget (docs/08).
# Usage: scripts/perf.sh [seconds=60] [max_avg_cpu_percent=1.0] [max_rss_mb=40]
set -euo pipefail
export LC_ALL=C # ps prints locale decimal commas (e.g. "1,5"), which awk would truncate.

seconds="${1:-60}"
cpu_budget="${2:-1.0}"
rss_budget_mb="${3:-40}"

pid="$(pgrep -nx ClawdNotch || true)" # -n: newest instance only
[[ -n "$pid" ]] || { echo "ClawdNotch is not running" >&2; exit 1; }

for ((i = 0; i < seconds; i++)); do
    ps -o %cpu=,rss= -p "$pid" || { echo "ClawdNotch exited" >&2; exit 1; }
    sleep 1
done | awk -v cpu_budget="$cpu_budget" -v rss_budget="$rss_budget_mb" '
    { cpu += $1; if ($1 > cpu_max) cpu_max = $1; rss = $2 / 1024; if (rss > rss_max) rss_max = rss; n++ }
    END {
        if (n == 0) { print "no samples (ClawdNotch exited?)"; exit 1 }
        avg = cpu / n
        ok = (avg <= cpu_budget && rss_max <= rss_budget)
        printf "samples=%d cpu_avg=%.2f%% cpu_max=%.2f%% rss_max=%.1fMB budget(cpu<=%s%%, rss<=%sMB) %s\n",
            n, avg, cpu_max, rss_max, cpu_budget, rss_budget, ok ? "PASS" : "FAIL"
        exit ok ? 0 : 2
    }'
