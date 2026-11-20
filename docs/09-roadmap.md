# 09 — Roadmap and work packages

How to use this file: the orchestrator picks every WP whose dependencies are `done`, delegates it to the owner agent (run WPs in parallel when their file ownership does not overlap), has `reviewer` check it, commits, and then updates **Status** here in the same commit.

Status values: `todo` · `in-progress` · `done` · `blocked(<reason>)`

## Dependency graph
```
WP-0 ──┬──▶ WP-1 (core) ───────┬──▶ WP-4 (server+bridge+installer) ──▶ WP-6 (focus/read)
       ├──▶ WP-2 (window) ─────┤                                         │
       └──▶ WP-3 (pet) ────────┴──▶ WP-5 (HUD + wiring) ──▶ WP-5.1 (right wing + glow) ──┴──▶ WP-7 (hide/autostart/settings) ──▶ WP-8 (perf pass)
```
WP-1, WP-2, and WP-3 run **in parallel** because they touch disjoint directories. WP-5.1 (Window/, HUD/) and WP-6 (Integration/) can also run in parallel. WP-2.1 (one new file in Window/) is ready now. It is independent of WP-6. Run it before or after WP-5.1, not at the same time, because both touch `NotchWindowController`.

---

### WP-0 — Skeleton and spikes · owner: orchestrator (or core-engineer) · status: `done` (full-screen visibility confirmed by the user)
Goal: a buildable skeleton, and answers to the risky unknowns.
- `Package.swift` with the 4 targets (see `03`). Swift 6 language mode. Platform `.macOS(.v14)`.
- Minimal `ClawdNotch` app: `NSApplication` + `AppDelegate`, `LSUIElement`, an empty black `NSPanel` at the notch.
- `scripts/bundle.sh`, `scripts/run.sh`, `scripts/simulate.sh` (with the scenario stubs listed in the skill), and `scripts/perf.sh`.
- `.gitignore` entries are already present. The smoke test is `Tests/ClawdCoreTests/NotchGeometryTests.swift`: `NotchGeometry` was pulled forward from WP-1 because the panel needed it.
- **Spike A:** find the window level and collection behaviour that stays visible over full-screen apps and on all Spaces. Record the result in `06`.
- **Spike B:** register one http hook pointing at a closed port and start `claude`. Confirm there is no blocking and no noisy errors. Record the result in ADR-0002.
- **Spike C:** confirm that `swift test` runs swift-testing with Command Line Tools only. **Result:** plain `swift test` builds but silently runs 0 tests, and `_Testing_Foundation` has no module. `scripts/test.sh` adds `-F <CLT>/Library/Developer/Frameworks`, an rpath, and `-disable-cross-import-overlays` (see ADR-0001).
- AC: `swift build`, `scripts/test.sh`, and `scripts/run.sh` all work. A black island appears at the notch over a full-screen app.

### WP-1 — ClawdCore · owner: core-engineer · deps: WP-0 · status: `done`
- `ClawdEvent` + lenient decoder, `SessionMeta`, `UsageSnapshot` (statusline decoder), `Session`, `SessionStore`, `Snapshot`, `PetState`, aggregate, `popToken`, talking decay, liveness expiry.
- All the tests listed in `04`, plus decoder tests built from the sample payloads.
- AC: REQ-03 AC3 and REQ-04 AC1 are provable by tests. Coverage of the transition table is 100 %.

### WP-2 — Window and notch · owner: macos-ui-engineer · deps: WP-0 · status: `done` (physical-notch fit, full-screen hover and no-focus right-click still to be checked by eye)
- `NotchPanel`, `NotchWindowController`: screen choice, geometry, re-layout on screen changes, hover expand/collapse, right-click menu (items may be stubs), click-through sizing.
- An island view with placeholder slots for the pet (left), the counters (right), and the expanded panel.
- AC: REQ-01 AC1–3, REQ-02 AC1–3.

### WP-2.1 — Pin the island across Space switches · owner: macos-ui-engineer · deps: WP-2 · status: `todo`
The island currently slides away and back during a Space switch or a full-screen transition.
- A new `Window/SpaceAnchor.swift` (SkyLight Space via `dlsym`, with a silent fallback; see ADR-0005), called once from `NotchWindowController` after `orderFrontRegardless()`.
- AC: REQ-02 AC4, checked by the user by eye (swipe, Ctrl+←/→, entering and leaving full screen). Hover, right-click and the tooltip still work. `perf.sh` shows no change.

### WP-3 — Clawd pet · owner: pet-animator · deps: WP-0 · status: `done` (measured: debug demo 0.00 % CPU / 35.7 MB; release sleeping 0.16 % / 38.9 MB)
- `PetTokens`, `PetView` (the layer tree from `07`), all 6 poses with loops, transitions, `popOut()`, `setPaused(_:)`, and Reduce Motion support.
- A debug-only state cycler (for example, launching with `--pet-demo` cycles the states every 3 s), used for screenshots.
- AC: REQ-03 AC1, REQ-06 AC1. The perf budget holds while it animates (perf-check skill).

### WP-4 — Event server, bridge, installer · owner: core-engineer (server), integration-engineer (bridge + installer) · deps: WP-1 · status: `done` (e2e: a real `claude -p` with scratch `--settings` drove idle → thinking → talking → done → sleeping)
- `EventServer` (`03`, `05`), feeding into the `AppModel` → `SessionStore`.
- `clawd-bridge` with the `hook session-start` and `statusline` subcommands.
- `HookInstaller` install/uninstall, with round-trip and idempotency tests (put the pure JSON-merge logic in Core so it can be tested).
- AC: REQ-09 AC1–3. `scripts/simulate.sh` drives the app end-to-end. A real `claude` session changes the state.

### WP-5 — HUD and wiring · owner: macos-ui-engineer · deps: WP-2, WP-3, WP-4 · status: `done` (launch RSS peak 42.6 MB > budget, steady 39.7 MB; handed to WP-8, see `08`)
- Bind the `Snapshot` to `PetView` and the counters, the HP bar (with its tooltip and reset countdown), the expanded session list, and "mark read" / "mark all read".
- AC: REQ-03 AC2, REQ-04 AC1–3.

### WP-5.1 — Compact right-wing layout and hover glow · owner: macos-ui-engineer (pet-animator only if the pet size changes) · deps: WP-5 · status: `todo`
A design change requested after WP-5: everything moves to the right of the notch, and the island gets more compact.
- `IslandView`: one right wing instead of two symmetric `wingWidth` wings. The pet slot moves into the right wing, between the HP bar and the counts.
- `NotchWindowController.islandFrame`: collapsed = notch + right wing. Expanded = centred under the notch as before, plus the glow margin.
- `CountersView`: a vertical HP bar left of the pet, and a counts column right of it (the active number on top, the attention badge below). Both counts are always visible. The badge is blue/orange/red (REQ-04).
- `PetTokens.badgeCalm` (`#0A84FF`).
- The hover glow (REQ-11): a `shadowPath` shadow with an opacity fade (`06`). Measure it with `perf.sh` and drop it if it breaks the budget.
- AC: REQ-01 AC1–2 (updated), REQ-04 AC1–4, REQ-11 AC1–2 (or a recorded drop in `08`).

### WP-6 — Focus and read tracking · owner: integration-engineer · deps: WP-4, WP-5 · status: `todo`
- `TerminalFocusWatcher` (Terminal.app and iTerm2 tab-precise; others app-level after a 2 s dwell), and click a session → focus its terminal or tab.
- AC: REQ-10 AC1–2.

### WP-7 — Hide mode, autostart, settings · owner: macos-ui-engineer · deps: WP-5.1 · status: `todo`
- Hide mode with pop-out rules, `SMAppService` launch at login, the Settings window, and persisting the config.
- AC: REQ-05 AC1–3.

### WP-8 — Performance pass · owner: reviewer (audit) + owners (fixes) · deps: WP-7 · status: `todo`
- Run every scenario in `08`, fix the regressions, and record the measured numbers in `08`.
- AC: REQ-08 AC1–2.

## v2 backlog
- REQ-V2-01: approve permissions from the notch.
- REQ-V2-02: tab-precise focus for more terminals.
- REQ-V2-03: start a new Claude Code session from the notch panel (builds on the WP-6 terminal mechanism).
- Possible extras: a compaction "sweeping" pose, a subagent "juggling" pose, sound cues.
