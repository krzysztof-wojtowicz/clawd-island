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
- WP-8 owns this headroom. The first lever, building `SessionPanelView` lazily on the first expand, is done (`IslandView.panelProvider`, `HUDController.makePanel`).
- WP-5.1 (release, `perf.sh`, one usage post, collapsed): launch peak 37.6 MB, steady 33.9 MB, sleeping 0.03 % avg, thinking 0.00 %. That is below WP-5, so the launch-RSS overshoot above is gone. At rest the glow has opacity 0 and no animation.
- WP-5.1 expanded with the glow is **not yet measured**, because a hover cannot be scripted. Run `perf.sh 30` with the mouse resting on the expanded panel. If CPU at rest rises measurably, or steady RSS goes over 40 MB, drop the glow (REQ-11 AC2) and record the numbers here.

### WP-8 (release bundle, `perf.sh`, Apple silicon)
| Scenario | CPU avg / max | RSS max | Result |
|---|---|---|---|
| launch, first 20 s (before lazy panel) | 0.00 / 0.00 % | 40.5 MB | FAIL |
| launch, first 20 s (lazy panel; run 1) | 0.42 / 8.4 % | 40.0 MB | borderline (budget is `<= 40`) |
| steady after launch, 20 s | 0.00 / 0.00 % | 37.3 MB | PASS |
| sleeping 60 s | 0.00 / 0.00 % | 37.7 MB | PASS |
| thinking 60 s | 0.06 / 3.1 % | 38.3 MB | PASS |
| usingTools 30 s | 0.00 / 0.00 % | 38.3 MB | PASS |
| burst 15 s (50 `MessageDisplay`/s) | 1.85 / 9.6 % | 41.2 MB | PASS (budget < 3 %, < 45 MB) |
| 30 s after the burst | 0.07 / 1.9 % | 41.2 MB | FAIL on RSS (known exception below) |
| `clawd-bridge statusline`, warm | about 10 ms | n/a | PASS (first cold run about 30 ms) |

- Process CPU excludes Core Animation work done in the render server (`WindowServer`), so the pet's animation cost is not in these numbers.
- `MessageDisplay` coalescing (rule 3) and "no rebuild while the panel is hidden" were already in place and are verified by code reading. They are not the cause of post-burst RSS.
- Known exception, post-burst RSS: RSS stays at about 41 MB after a 500-event burst and is not returned. `footprint` shows 14 MB, of which about 9 MB is `MALLOC_SMALL` dirty. This is the allocator's high-water mark from the burst's concurrent HTTP connections in `Server/`, not live objects. Ending the sessions does not lower it. Repeated bursts (6 in a row, each with its own session) plateau at 43.9 MB RSS / 16 MB `footprint` from the third burst on, so it is bounded and not a leak. It stays under the 45 MB burst budget. A real fix would cap concurrent connections in `EventServer` (owner: core-engineer).
- Known exception, Settings window: it is plain AppKit, created on open and released on close (`windowWillClose` drops every reference). In debug, opening it raised RSS from 42 to 60 MB and closing left 55 MB. `footprint` said about 18 MB, so most of that is shared framework pages (AppKit control and window machinery) that stay resident. The window is opened rarely, so this is accepted and not worked on further. It was not re-measured on a release build, because opening it cannot be scripted.
- TODO (human): measure the expanded panel with the hover glow. Run `perf.sh 30` with the mouse resting on the expanded panel, and record CPU and RSS here.

### WP-5.4 / WP-7.1 (release bundle)
- Hide mode off, after `start` + `think` (10 s): 0.00 % CPU settled, 39.0 MB. Hidden idle: 0.00 %, 37.5 MB. Hidden after a pop-out: 0.00 %, 36.4 MB.
- Rule learned: no full-window `CALayer.mask`. A first version tucked the hidden pet with an even-odd `CAShapeLayer` mask, which made Core Animation render offscreen in-process (RenderBox loaded), at +45 MB RSS and a CPU spike on every state change. An opaque black notch-cover layer above the pet does the same job at no cost.
- `ps %cpu` is a decaying average: read it at least 30 s after a launch or a state change.

### WP-5.5 … WP-11 (release bundle, settled)
- Hidden idle (corner peek): 0.00 % CPU, 35 MB. After a pop-out: 0.00 %, 34.9 MB.
- Idle with permission cards, WP-10 and WP-11 code: 0.00–0.11 % CPU, 37.7–38.6 MB.
- `clawd-bridge statusline` with the extra `/session-meta` POST: about 13 ms per run (20 runs, shell overhead subtracted), within the 20 ms budget.

## How to measure
`scripts/perf.sh 60` samples `ps -o %cpu=,rss= -p <pid>` every second for the given number of seconds and prints the average, the maximum, and a PASS/FAIL against the budget. Use it together with `scripts/simulate.sh burst`. Optional deeper check: `sudo powermetrics --samplers tasks -n 5 -i 1000 | grep ClawdNotch` for wakeups per second.
