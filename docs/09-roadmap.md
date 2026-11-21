# 09 — Roadmap and work packages

How to use this file: the orchestrator picks every WP whose dependencies are `done`, delegates it to the owner agent (run WPs in parallel when their file ownership does not overlap), has `reviewer` check it, commits, and then updates **Status** here in the same commit.

Status values: `todo` · `in-progress` · `done` · `blocked(<reason>)`

## Dependency graph
```
WP-0 ──┬──▶ WP-1 (core) ───────┬──▶ WP-4 (server+bridge+installer) ──▶ WP-6 (focus/read)
       ├──▶ WP-2 (window) ─────┤                                         │
       └──▶ WP-3 (pet) ────────┴──▶ WP-5 (HUD + wiring) ──▶ WP-5.1 (right wing + glow) ──▶ WP-3.1 (usingTools) ──▶ WP-5.2 (counter + sort) ──▶ WP-5.3 (panel counts + week) ──┴──▶ WP-7 (hide/autostart/settings) ──▶ WP-8 (perf pass)
```
WP-1, WP-2, and WP-3 run **in parallel** because they touch disjoint directories. WP-5.1 (Window/, HUD/) and WP-6 (Integration/) can also run in parallel. WP-2.1 (one new file in Window/) is ready now. It is independent of WP-6. Run it before or after WP-5.1, not at the same time, because both touch `NotchWindowController`. WP-3.1, WP-5.2, and WP-5.3 run one after another (they all touch `Snapshot`). WP-6 can run in parallel with either. After v1: WP-5.4 and WP-6.1 run in parallel; WP-7.1 follows WP-5.4 (same window files).

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

### WP-2.1 — Pin the island across Space switches · owner: macos-ui-engineer · deps: WP-2 · status: `done` (build, tests and perf unchanged; Space-switch behaviour still to be checked by eye)
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

### WP-5.1 — Compact right-wing layout and hover glow · owner: macos-ui-engineer (pet-animator only if the pet size changes) · deps: WP-5 · status: `done` (wing 72 pt, pet 26 pt; collapsed perf in `08`; expanded glow perf and visuals still to be checked by eye)
A design change requested after WP-5: everything moves to the right of the notch, and the island gets more compact.
- `IslandView`: one right wing instead of two symmetric `wingWidth` wings. The pet slot moves into the right wing, between the HP bar and the counts.
- `NotchWindowController.panelFrame`: collapsed = notch + right wing. Expanded = centred under the notch as before, plus the glow margin.
- `CountersView`: a vertical HP bar left of the pet, and a counts column right of it (the active number on top, the attention badge below). Both counts are always visible. The attention count is plain at 0, and in an orange or red circle above 0 (superseded by WP-5.2).
- The hover glow (REQ-11): a `shadowPath` shadow with an opacity fade (`06`). Measure it with `perf.sh` and drop it if it breaks the budget.
- AC: REQ-01 AC1–2 (updated), REQ-04 AC1–4, REQ-11 AC1–2 (or a recorded drop in `08`).

### WP-3.1 — `usingTools` state with a hammer · owner: core-engineer (state) + pet-animator (hammer) + macos-ui-engineer (panel text) · deps: WP-5.1 · status: `done` (hammering: CPU avg 0.09 % / peak 0.50 %; hammer look at notch size still to be checked by eye)
Follow the `add-pet-state` skill end to end.
- Core: a `usingTools` case in `PetState` and `SessionState` (replacing `talking(.tool)`), `PreToolUse` → `usingTools` with no decay, the new aggregate priority, and tests (`04`).
- Pet: the hammer accessory, the pose and the strike loop, the `tool.*` tokens, and Reduce Motion (`07`).
- HUD: the panel state text "using <tool>".
- Simulator: a tools scenario in `scripts/simulate.sh`, and a row in the `simulate-claude-events` skill.
- AC: REQ-03 AC1–3. `perf.sh` while hammering stays within the animating budget.

### WP-5.2 — Single session counter and importance-sorted panel · owner: core-engineer (sort) + macos-ui-engineer (counter) · deps: WP-3.1 · status: `done` (idle perf 0.00 % CPU / 39.0 MB; counter colours still to be checked by eye)
- Core: `Snapshot.sessions` sorted by rank, then by the newest `lastEventAt` (`04` "Panel order"), with a test.
- `CountersView`: one number in an always-visible circle, vertically centred on the pet and the HP bar. Its colour follows the red / orange / blue / grey rule. Add the `badge.active` and `badge.empty` tokens.
- AC: REQ-04 AC1–4, REQ-10 AC3.

### WP-5.3 — Panel status counts and weekly usage · owner: core-engineer (Core) + macos-ui-engineer (panel) · deps: WP-5.2 · status: `done` (perf 0.28 % CPU / 38.9 MB; panel row and footer still to be checked by eye)
- Core: `Snapshot.statusCounts` (`04`); `UsageSnapshot` reads `rate_limits.seven_day` (`sevenDayUsedPercent?`, `sevenDayResetsAt?`). Add tests for the bucket sum and the seven_day decoding, including absent and stale cases.
- `SessionPanelView`: the status-count row above the list, and the footer `HP 63% · resets in 1h 12m · WEEK 81%` with level-tinted percentages. The HP-bar tooltip shows the same line. `expandedExtraHeight` grows to about 182.
- AC: REQ-04 AC1 and AC5.

### WP-6 — Focus and read tracking · owner: integration-engineer · deps: WP-4, WP-5 · status: `done` (build + review; Automation prompt, tab-precise read and click-to-focus still to be checked by eye)
- `TerminalFocusWatcher` (Terminal.app and iTerm2 tab-precise; others app-level after a 2 s dwell), and click a session → focus its terminal or tab.
- AC: REQ-10 AC1–2.

### WP-7 — Hide mode, autostart, settings · owner: macos-ui-engineer · deps: WP-5.3 · status: `done` (hidden idle 0.00 % CPU / 38.3 MB; Settings is AppKit, open→close leaves RSS ~55 MB, handed to WP-8; sliver, menu and login item still to be checked by eye)
- Hide mode with pop-out rules, `SMAppService` launch at login, the Settings window, and persisting the config.
- AC: REQ-05 AC1–3.

### WP-8 — Performance pass · owner: reviewer (audit) + owners (fixes) · deps: WP-7 · status: `done` (release table in `08`; launch peak at the 40 MB line, post-burst 41–44 MB and Settings RSS recorded as known exceptions; expanded-glow run needs a human hover)
- Run every scenario in `08`, fix the regressions, and record the measured numbers in `08`.
- AC: REQ-08 AC1–2.

### WP-5.4 — Split wings and expanding counters · owner: macos-ui-engineer · deps: WP-8 · status: `done` (collapsed 28 + notch + 48 pt verified with window-info; idle 0.00 % CPU / 40.0 MB debug; counter morph and wing sizes still to be checked by eye)
A design change after v1: the counter moves left of the notch, and the panel's status row moves into the top row.
- `IslandView`: a left wing slot for the counter; the top row is left wing | notch | right wing (HP bar · pet), each wing sized to its content.
- `NotchWindowController.panelFrame`: asymmetric collapsed frame; expanded stays centred (`expandedMinWidth` 360).
- `CountersView`: the single counter plus the three expanded counters and the morph between them, driven by the expand state. The HP bar moves to the right wing.
- `SessionPanelView`: drop the status-count row; `expandedExtraHeight` about 164.
- AC: REQ-01 AC1–2, REQ-04 AC1 and AC4. `perf.sh` unchanged.

### WP-6.1 — Click focuses the session · owner: integration-engineer · deps: WP-6 · status: `done` (build + tests; the tab focus and read on click still to be checked by eye)
- `HUDController.onSelect` only focuses; `TerminalFocusWatcher.focus` marks read after a successful focus, unless the focus-read mode is `off`.
- Can run in parallel with WP-5.4 (worktree; one shared line in `HUDController`).
- AC: REQ-10 AC2.

### WP-7.1 — Half-hidden hide mode and smooth transitions · owner: macos-ui-engineer (frames) + pet-animator (tilt, spring) · deps: WP-5.4 · status: `done` (hidden 185×48, popped 261×32; release 0.00 % CPU / 36–39 MB settled; peek look, tilt and transitions still to be checked by eye)
- Hidden frame: notch width, notch height + about 16 pt. The pet peeks about halfway, tilted −9°, under the right part of the notch.
- Placement: `IslandView.setPetPlacement` computes the screen-space target and `PetView.setPlacement` animates the offset and tilt (pop-out spring), used for hidden / wing / expanded, replacing the width-driven slide and the 7 pt sliver constants.
- AC: REQ-05 AC1–4. `perf.sh` hidden idle and during a pop-out stays within budget.

### WP-5.5 — Panel polish · owner: macos-ui-engineer · deps: WP-7.1 · status: `done` (build + tests; footer, blue dot and hammer room still to be checked by eye)
- Footer `WK 81% · HP 63% · resets in 1h 12m` (WK first, tints kept; tooltip the same).
- Blue state dot for working sessions (`badge.active`), next to the existing orange and red ones.
- Right wing about 56 pt so the hammer swing is never clipped.
- AC: REQ-04 AC4–AC5, `06` state dot.

### WP-7.2 — Upside-down corner peek · owner: macos-ui-engineer (+ pet-animator) · deps: WP-5.5 · status: `done` (hidden 209×54, popped 269×32; release settled 0.00 % CPU / 35 MB; the corner hang and flip still to be checked by eye)
- Hidden: the pet hangs upside down from the notch's bottom-right corner, rotated about 150° clockwise, legs behind the notch cover, head and arms out; loops keep running. The hidden window grows right and down to fit (`06`).
- Keep the WP-7.1 spring transitions (short way round).
- AC: REQ-05 AC1–4.

### WP-6.2 — Focus that survives app restarts · owner: integration-engineer (+ core-engineer for the meta rule) · deps: WP-6.1 · status: `done (statusline meta, done-while-frontmost; needs a human check with iTerm2)`
- Bridge `statusline` also POSTs `SessionMeta` with `source: "statusline"`; Core attaches it without changing the state (test).
- "Done while frontmost": when a session becomes `done` and its terminal is in front, check the selected tab once.
- AC: REQ-10 AC1, AC1a. Fixes iTerm2 read/focus for sessions started before the app.

### WP-9 — Permissions from the notch · owner: core-engineer (decode, pending model, server hold, installer timeout) + macos-ui-engineer (cards, setting) · deps: WP-6.2 · status: `done` (e2e with real `claude` + scratch settings: allow created the dir, deny blocked it, setting off replies in 0.05 s; release idle 0.11 % / 38.6 MB; card look and real clicks still to be checked by eye; existing installs need Install Hooks again for `timeout: 120`)
- ADR-0006. Core: input summary, `PendingPermission`, removal rules, tests. Server: hold `PermissionRequest`, reply allow / deny / empty, 110 s cap, connection-close detection. Installer: `timeout: 120` for `PermissionRequest`, updating existing installs, tests.
- UI: permission cards with Allow / Deny, the `notchPermissions` setting.
- AC: REQ-V2-01 AC1–5, verified end-to-end with `claude` and scratch `--settings`.

### WP-10 — Window-level focus for the VS Code family · owner: integration-engineer · deps: WP-6.2 · status: `todo`
- Accessibility window match by project name for click and activation; app-level fallback.
- AC: REQ-V2-02 AC1–3.

### WP-11 — New session from the panel · owner: integration-engineer (launch, recent projects) + macos-ui-engineer (button, menu) · deps: WP-9 · status: `todo`
- "+ New" footer button, recent-projects menu and "Choose Folder…", Terminal.app / iTerm2 launch with safe quoting, `recentProjects` in config.
- AC: REQ-V2-03 AC1–2.

## v1 checks left for a human
Each item is in the WP status above. They need eyes or a hover, so no agent can do them:
- WP-2 / WP-2.1: physical-notch fit, full-screen hover, right-click without focus, no slide on Space switch.
- WP-3.1: the hammer reads at notch size and is not clipped (`scripts/simulate.sh tools`).
- WP-5.2 / WP-5.3: counter colours (grey → blue → red → orange), the panel status row and the `HP · resets · WEEK` footer (`simulate.sh start`, `permission`, `done`, `usage 37`).
- WP-6: the Automation prompt, tab-precise read in Terminal.app / iTerm2, click-to-focus.
- WP-7: the hide-mode sliver and pop-out, the menu checkmarks, Settings, launch at login (install to /Applications first).
- WP-8 / REQ-11: `scripts/perf.sh 30` with the mouse on the expanded panel (glow); drop the glow if it breaks the budget.

## v2 backlog (REQ-V2-01…03 are now WP-9, WP-10, WP-11)
- REQ-V2-01: approve permissions from the notch.
- REQ-V2-02: tab-precise focus for more terminals.
- REQ-V2-03: start a new Claude Code session from the notch panel (builds on the WP-6 terminal mechanism).
- Possible extras (`usingTools` is now in v1 as WP-3.1): a compaction "sweeping" pose, a subagent "juggling" pose, sound cues.
