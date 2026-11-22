# 08 — Performance (REQ-08)

## Budget (measured with `scripts/perf.sh`, Apple silicon, release build)
| Scenario | CPU (process avg over 60 s) | RSS |
|---|---|---|
| sleeping (no sessions) | < 0.1 % | < 40 MB |
| idle / thinking / usingTools / talking | < 1 % | < 40 MB |
| burst: 50 hook events/s for 10 s | < 3 % | < 45 MB |
| `clawd-bridge statusline` | < 20 ms wall time per run | — |

## Rules
1. **Event-driven only.** The only repeating timer is the 30 s liveness check, and it is suspended while there are no sessions. The talking-decay check is a one-shot timer that is rescheduled, never a repeating one. The HUD has one more one-shot, at `usage.resetsAt` (30 s tolerance), which flips the HP bar to full and stale (REQ-04 AC3).
2. **Animation runs in the render server.** The pet uses Core Animation layer animations. No `TimelineView`, `CADisplayLink`, `Timer`, or SwiftUI `repeatForever` drives the pet.
3. **Render only on change.** `AppModel` publishes a new `Snapshot` only when it is `!=` to the previous one. `MessageDisplay` floods are coalesced, so at most one snapshot is built per 100 ms.
4. **Pause when nobody can see it.** Respond to `NSWorkspace.screensDidSleepNotification` and `sessionDidResignActiveNotification` by pausing layers (`speed = 0`) and stopping the liveness timer. Resume on the matching wake notifications.
5. **Lean decoding.** Read only the fields we use from a `JSONSerialization` object, field by field, so a missing or mistyped field becomes nil instead of failing the whole event (bodies are capped at 64 KiB). Ignore large fields. Store nothing per event beyond the session state.
6. **No logging in hot paths in release builds.** Use `os.Logger` at `.debug` level only.
7. **Small binary.** No dependencies. Build release with `-Osize` if it is not slower in practice.
8. **No App Nap fights.** Do not disable App Nap. The app should be naturally idle.
9. **Music and sound are event-driven (v3).** `NowPlayingWatcher` only observes distributed notifications; `SoundCues` plays cached `NSSound`s on `popToken` edges. No polling, no timers, no AppleScript. The headphones and broom/ball overlays are Core Animation layers like every other part, hidden (not animating) when unused.
10. **Cheap effects only.** The hover glow (REQ-11) is a layer shadow with an explicit `shadowPath`, and only its opacity is animated. Never use a blur filter, `NSVisualEffectView`, or a per-frame redraw for it.

## Measured (latest, release bundle, settled; `scripts/perf.sh`)
| Scenario | CPU avg / max | RSS max | Result |
|---|---|---|---|
| launch, first 20 s (lazy panel) | 0.42 / 8.4 % | 40.0 MB | borderline (budget `<= 40`) |
| steady after launch | 0.00 / 0.00 % | 37.3 MB | PASS |
| sleeping 60 s | 0.00 / 0.00 % | 37.7 MB | PASS |
| thinking 60 s | 0.06 / 3.1 % | 38.3 MB | PASS |
| usingTools 30 s | 0.00 / 0.00 % | 38.3 MB | PASS |
| burst 15 s (50 `MessageDisplay`/s) | 1.85 / 9.6 % | 41.2 MB | PASS (< 3 %, < 45 MB) |
| hidden idle (corner peek) / after pop-out | 0.00 % | 35.0 / 34.9 MB | PASS |
| idle with permission cards, new-session menu (WP-9/11) | 0.00–0.11 % | 37.7–38.6 MB | PASS |
| `clawd-bridge statusline` with the extra `/session-meta` POST | about 13 ms | n/a | PASS (< 20 ms) |

- Process CPU excludes Core Animation work in the render server (`WindowServer`).
- **Known exception, post-burst RSS:** about 41 MB (up to 43.9 MB after repeated bursts) is retained by the allocator from concurrent HTTP connections in `Server/` (`footprint` 14–16 MB). Bounded, not a leak, under the 45 MB burst budget. Fix, if wanted: cap concurrent connections in `EventServer` (deferred, `09`).
- **Known exception, Settings window:** plain AppKit, released on close, but framework pages stay resident (debug: 42 → 55 MB after closing). Opened rarely; accepted.
- **Rules learned:** no full-window `CALayer.mask` (it forced offscreen rendering in-process: +45 MB RSS and CPU spikes; an opaque notch-cover layer does the same job for free). `ps %cpu` is a decaying average: read it at least 30 s after a launch or a state change.
- **Still to measure by a human:** `perf.sh 30` with the mouse on the expanded panel (hover glow, REQ-11 AC2). If CPU at rest rises measurably or steady RSS passes 40 MB, drop the glow and record the numbers here.

## v4 targets (WP-22)
- Launch peak ≤ 38 MB, steady ≤ 37 MB, post-burst ≤ 40 MB (cap concurrent `EventServer` connections; held `PermissionRequest`s are counted separately and never dropped), idle CPU ≈ 0 % settled, expanded panel with glow < 1 % (REQ-11 AC2).
- `scripts/perf-suite.sh` runs every scenario on a release bundle and prints one table (CPU avg/max after a settle, RSS max, `footprint`): launch, sleeping, thinking, usingTools, burst + post-burst, hidden idle, hide-mode pop-out, expanded hover (cursor moved with `CGWarpMouseCursorPosition`, no permission needed), permission card, Settings open/close (`--open-settings`).
- Remaining exceptions are kept only with numbers and a reason.

## How to measure
`scripts/perf.sh 60` samples `ps -o %cpu=,rss= -p <pid>` every second for the given number of seconds and prints the average, the maximum, and a PASS/FAIL against the budget. Use it together with `scripts/simulate.sh burst`. Optional deeper check: `sudo powermetrics --samplers tasks -n 5 -i 1000 | grep ClawdNotch` for wakeups per second.
