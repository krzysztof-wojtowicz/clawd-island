# 08 — Performance (REQ-08)

## Budget (release build, Apple silicon; `scripts/perf-suite.sh`)
Memory is judged by **`footprint`** (phys_footprint: the pages this process really owns). RSS also counts shared AppKit and system pages (an empty accessory AppKit app already reaches ~30 MB), so it gets a looser cap.

| Scenario | CPU (avg after settle) | footprint | RSS |
|---|---|---|---|
| sleeping (no sessions) | < 0.1 % | < 20 MB | < 45 MB |
| idle / thinking / usingTools / talking / mini mode / expanded panel | < 1 % | < 20 MB | < 45 MB |
| burst: 50 hook events/s for 10 s, and after it | < 3 % during | < 20 MB | < 48 MB |
| launch (first 10 s) | — | < 20 MB | spike allowed (LaunchServices mapping, unmapped by the system ~10 s later) |
| `clawd-bridge statusline` | < 20 ms wall time per run | — | — |

Accepted exception: the Settings window (rarely open), 60 MB RSS open and 55 MB after close, footprint 18–19 MB (see "Known limits").

## Rules
1. **Event-driven only.** The only repeating timer is the 30 s liveness check, suspended while there are no sessions. The talking decay is a rescheduled one-shot, never a repeating timer. The HUD has one more one-shot, at `usage.resetsAt` (30 s tolerance), which flips the HP bar to full and stale (REQ-04 AC3).
2. **Animation runs in the render server.** The pet uses Core Animation layer animations only. No `TimelineView`, `CADisplayLink`, `Timer`, or SwiftUI `repeatForever`.
3. **Render only on change.** `AppModel` publishes a new `Snapshot` only when it is `!=` to the previous one. `MessageDisplay` floods are coalesced to at most one snapshot per 100 ms.
4. **Pause when nobody can see it.** On `screensDidSleepNotification` and `sessionDidResignActiveNotification`, pause the layers (`speed = 0`) and the liveness timer; resume on the matching wake notifications.
5. **Lean decoding.** Read only the fields we use from a `JSONSerialization` object, field by field, so a missing or mistyped field becomes nil instead of failing the event (bodies capped at 64 KiB). Store nothing per event beyond the session state.
6. **No logging in hot paths** in release builds; `os.Logger` at `.debug` only.
7. **No dependencies, no SwiftUI.** A SwiftUI hosting view, an in-process `NSSound` (+7 MB RSS, never released) or a full-window `CALayer.mask` (offscreen rendering, +45 MB RSS) each break the budget on their own.
8. **No App Nap fights.** The app is naturally idle.
9. **Sound out of process.** `SoundCues` runs `/usr/bin/afplay` on `popToken` edges.
10. **Cheap effects only.** The hover glow is a layer shadow with an explicit `shadowPath`; only its opacity animates. No blur filter, `NSVisualEffectView` or per-frame redraw. Unused overlays (bubbles, broom, balls) are hidden, not animating.
11. **Lazy creation.** The session panel, Settings window and permission cards are built on first use; Settings is released on close.

## Measured (1.0.0)
`scripts/perf-suite.sh` run of 2026-11-23 at `cc25cb1` (same runtime behaviour as 1.0.0), release bundle, scratch port, settle 30 s, sample 20 s. CPU avg / max, RSS max, `footprint`.

| Scenario | CPU % | RSS MB | footprint MB |
|---|---|---|---|
| launch peak (first 30 s) | 0.22 / 6.6 | 40.7 | 11 |
| sleeping | 0.00 / 0.00 | 29.2 | 11 |
| thinking | 0.00 / 0.00 | 34.8 | 11 |
| usingTools | 0.00 / 0.00 | 34.9 | 11 |
| burst (50 events/s, 10 s) | 2.73 / 11.5 | 38.7 | 14 |
| post-burst | 0.00 / 0.00 | 38.6 | 14 |
| expanded hover (glow) | 0.00 / 0.00 | 40.1 | 15 |
| permission card | 0.00 / 0.00 | 40.8 | 15 |
| Settings open (first 10 s) / closed | 0.40 / 4.0, then 0.00 | 60.0 / 55.1 | 19 / 18 |
| mini mode idle | 0.00 / 0.00 | 40.7 | 11 |
| mini-mode pop-out (after a turn) | 0.08 / 1.4 | 41.4 | 11 |
| `clawd-bridge statusline` | about 13 ms per run | — | — |

Process CPU excludes Core Animation work in the render server (`WindowServer`). `ps %cpu` is a decaying average: read it at least 30 s after a launch or a state change.

## Known limits
- **RSS floor:** an empty accessory `NSApplication` settles at about 30 MB; our own share is about 9 MB (Network, Core Animation, ~3 MB malloc). `footprint` stays at 11 MB at rest.
- **Burst:** each hook connection leaves about 7.8 KB of Network.framework state alive for ~30 s after close, and the allocator keeps the pages (`malloc_zone_pressure_relief` changes nothing). Only a plain-socket accept loop instead of `NWListener` would remove it; not worth it within budget.
- **Settings window:** an empty titled window alone stays at 57 MB RSS after close; the controls add about 2 MB. Measured variants (pressure relief, system font, no controls) cannot reach 45 MB, so the exception stays.

## How to measure
- `scripts/perf-suite.sh [settle] [sample]` runs every scenario above on a release bundle and prints one table. It swaps the config `port` (47499), `token` (random) and `onboarded` for the run, so real Claude Code hooks and the bridge cannot reach the app and no first-run window opens; the backed-up config is restored on exit. Needs the sandbox off.
- `scripts/perf.sh 60` samples `ps -o %cpu=,rss=` of the running app every second and prints average, maximum and PASS/FAIL; pair it with `scripts/simulate.sh burst`.
- Deeper: `footprint <pid>`, `vmmap --summary <pid>`, and (sudo) `powermetrics --samplers tasks -n 5 -i 1000 | grep ClawdIsland` for wakeups.
