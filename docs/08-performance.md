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
9. **Music and sound are event-driven (v3).** `NowPlayingWatcher` only observes distributed notifications; `SoundCues` plays a system sound in a short-lived `afplay` process on `popToken` edges (`NSSound` in-process costs +7 MB RSS / +6 MB footprint, never released). No polling, no timers, no AppleScript. The headphones and broom/ball overlays are Core Animation layers like every other part, hidden (not animating) when unused.
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
- **Rules learned:** no full-window `CALayer.mask` (it forced offscreen rendering in-process: +45 MB RSS and CPU spikes; an opaque notch-cover layer does the same job for free). `ps %cpu` is a decaying average: read it at least 30 s after a launch or a state change.
- **Still to measure by a human:** `perf.sh 30` with the mouse on the expanded panel (hover glow, REQ-11 AC2). If CPU at rest rises measurably or steady RSS passes 40 MB, drop the glow and record the numbers here.

## v4 targets (WP-22)
- Launch peak ≤ 38 MB, steady ≤ 37 MB, post-burst ≤ 40 MB (cap concurrent `EventServer` connections; held `PermissionRequest`s are counted separately and never dropped), idle CPU ≈ 0 % settled, expanded panel with glow < 1 % (REQ-11 AC2).
- `scripts/perf-suite.sh` runs every scenario on a release bundle and prints one table (CPU avg/max after a settle, RSS max, `footprint`): launch, sleeping, thinking, usingTools, burst + post-burst, hidden idle, hide-mode pop-out, expanded hover (cursor moved with `CGWarpMouseCursorPosition`, no permission needed), permission card, Settings open/close (`--open-settings`).
- Remaining exceptions are kept only with numbers and a reason.

### WP-22 measurements (final)
`scripts/perf-suite.sh` (settle 30 s, sample 20 s, release bundle, `-O`). CPU avg / max %, RSS max MB, `footprint` MB. Before = main at `a8ea54b` (with the server cap), after = this change.

| Scenario | Before | After |
|---|---|---|
| launch peak (first 30 s) | 0.25 / 5.0, 41.1 MB, fp 11 | 0.26 / 5.1, 41.3 MB, fp 11 |
| sleeping | 0.00 / 0.00, 38.4, fp 11 | 0.00 / 0.00, 38.5, fp 11 |
| thinking | 0.00 / 0.00, 38.4, fp 11 | 0.00 / 0.00, 38.5, fp 11 |
| usingTools | 0.00 / 0.00, 38.4, fp 11 | 0.01 / 0.20, 38.5, fp 11 |
| burst (50 events/s, 10 s) | 3.43 / 12.9, 48.6, fp 18 | 2.42 / 7.5, 42.1, fp 14 |
| post-burst | 0.00 / 0.00, 48.6, fp 17 | 0.00 / 0.00, 42.0, fp 14 |
| expanded hover | 0.00 / 0.00, 49.7, fp 18 | 0.00 / 0.00, 43.3, fp 15 |
| permission card | 0.00 / 0.00, 50.7, fp 18 | 0.00 / 0.00, 43.8, fp 15 |
| Settings open (first 10 s) / closed | not measurable | 1.35 / 10.6, 60.0, fp 19 / 0.00, 55.2, fp 19 |
| hidden idle | 0.04 / 0.9, 38.5, fp 11 | 0.00 / 0.00, 40.6, fp 11 |
| hide-mode pop-out | 0.33 / 3.3, 45.5, fp 14 | 0.08 / 1.4, 41.3, fp 11 |

What moved what:
- **`SoundCues` (the one real lever, -6 to -7 MB RSS and -4 to -6 MB footprint):** the first `done`/`needsInput` cue called `NSSound`, which loads the audio stack into the process for good (RSS 39 -> 46 MB on the first `done`). The cue now runs `/usr/bin/afplay` as a child process, so the app stays at 39.6 MB after a cue. This is what the "post-burst 48 MB" and "hide-mode pop-out 45 MB" rows really were: the burst simulator runs after `sim done`, not connection buffers. `heap`/`vmmap` before and after a burst show live malloc objects back at the launch count (about 20k) once Network releases the connections (about 40 s later).
- `import AppKit` alone links `libswiftMetal`, `libswiftCoreImage`, `libswiftUniformTypeIdentifiers`, `libswiftXPC` and friends; an empty `NSApplication` accessory app links the same list, so they cost nothing we can remove. Release already excludes `PoseRenderer` (`#if DEBUG` wraps its imports). Removing the unused `@Observable` on `AppModel` (nothing observed it) dropped `libswiftObservation`: -0.05 MB, kept as dead-code removal. `-Osize` changed nothing (steady 39.0 MB either way, binary 1.0 MB), so it is not used. Lazy creation of everything else was already in place (HUD panel, Settings, `NowPlayingWatcher`, `NSSound`).
- `--open-settings` (and `--close-settings-after <s>`) added; the suite uses them for the Settings rows.

Remaining over target, with the cause:
- **Launch peak 41.3 MB (target 38) and steady 38.5 (target 37):** `footprint` is 11 MB. An empty accessory `NSApplication` (about 20 lines, no window) peaks at 31.8 MB and settles at 29.6 MB, so about 30 MB of our RSS is AppKit and shared-cache pages we cannot shed; our own share is about 9 MB (Network, Core Animation, 3 MB of malloc). The first 10 s peak is the LaunchServices database (`com.apple.LaunchServices-*.csstore`, 2.6 MB resident) which the system unmaps on its own about 10 s after launch (the empty app does the same, -2.1 MB). Needs a budget decision, not code.
- **Burst / post-burst 42 MB (target 40):** each hook connection costs about 7.8 KB of Network.framework state (`Endpoint`, `ProtocolStack`, path parameters) that stays alive about 30 s after the client closed, and the allocator keeps those pages (`malloc_zone_pressure_relief` and breaking the closure retention gave nothing, measured). Only dropping `NWListener` for a plain socket accept loop would remove it (and `Network.framework` from the launch set); not done here.
- **Settings window open 60 MB / closed 55 MB (`footprint` 19 MB):** plain AppKit controls, released on close (`windowWillClose` drops all references), but the AppKit controls/text-system pages stay resident. Opened rarely; accepted, with these numbers.

## How to measure
`scripts/perf.sh 60` samples `ps -o %cpu=,rss= -p <pid>` every second for the given number of seconds and prints the average, the maximum, and a PASS/FAIL against the budget. Use it together with `scripts/simulate.sh burst`. Optional deeper check: `sudo powermetrics --samplers tasks -n 5 -i 1000 | grep ClawdNotch` for wakeups per second.
