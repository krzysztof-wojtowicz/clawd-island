---
name: perf-check
description: Measure ClawdIsland CPU and memory against the performance budget in docs/08-performance.md. Use after any change to the pet, window, HUD, event handling, or timers.
---

# Performance check

Full run: `scripts/perf-suite.sh` (sandbox off) measures every `08` scenario on a release bundle, isolated on a scratch port and token, and prints one table to compare with `08` "Measured". Use the steps below for a single scenario on a running app.

1. Build and launch a **release** bundle: `scripts/bundle.sh release && open dist/ClawdIsland.app`. Debug builds are not representative.
2. For each scenario in `docs/08-performance.md`:
   - sleeping: no sessions, then `scripts/perf.sh 60`
   - animating: `scripts/simulate.sh think` (`--pet-demo` is DEBUG-only, so in a release build pin a state with the simulator instead), then `scripts/perf.sh 60`
   - burst: run `scripts/simulate.sh burst &` and `scripts/perf.sh 15` at the same time
   - bridge: `time (echo '{}' | dist/ClawdIsland.app/Contents/MacOS/clawd-bridge statusline)`, which must take < 20 ms
3. `scripts/perf.sh` prints the average and maximum CPU and RSS, plus PASS/FAIL.
4. Optional wakeups check (needs sudo, so ask the user first): `sudo powermetrics --samplers tasks -n 5 -i 1000 | grep -i clawd`.
5. Report a table of scenario → CPU avg/max → RSS → PASS/FAIL. On a FAIL, look first for timers, display links, re-renders on unchanged snapshots, and per-event allocations.
