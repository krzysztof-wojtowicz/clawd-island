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
9. **Cheap effects only.** The hover glow (REQ-11) is a layer shadow with an explicit `shadowPath`, and only its opacity is animated. Never use a blur filter, `NSVisualEffectView`, or a per-frame redraw for it.

## Measured
- WP-5 (release, `perf.sh`, with one usage post): the HEAD baseline before WP-5 peaked at 37.9–40.0 MB RSS at launch. WP-5 peaks at 42.6 MB at launch and settles to 39.7 MB about 20 s later. CPU is 0.00 % idle and 0.99 % during a multi-session burst.
- WP-8 owns this headroom. The first lever: build `SessionPanelView`'s subviews lazily on the first expand (about 1.2 MB at launch).
- WP-5.1 (release, `perf.sh`, one usage post, collapsed): launch peak 37.6 MB, steady 33.9 MB, sleeping 0.03 % avg, thinking 0.00 %. That is below WP-5, so the launch-RSS overshoot above is gone. At rest the glow has opacity 0 and no animation.
- WP-5.1 expanded with the glow is **not yet measured**, because a hover cannot be scripted. Run `perf.sh 30` with the mouse resting on the expanded panel. If CPU at rest rises measurably, or steady RSS goes over 40 MB, drop the glow (REQ-11 AC2) and record the numbers here.

## How to measure
`scripts/perf.sh 60` samples `ps -o %cpu=,rss= -p <pid>` every second for the given number of seconds and prints the average, the maximum, and a PASS/FAIL against the budget. Use it together with `scripts/simulate.sh burst`. Optional deeper check: `sudo powermetrics --samplers tasks -n 5 -i 1000 | grep ClawdNotch` for wakeups per second.
