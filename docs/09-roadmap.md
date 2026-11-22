# 09 — Roadmap and work packages

How to use this file: the orchestrator picks every WP whose dependencies are `done`, delegates it to the owner agent (parallel only when file ownership is disjoint, use a worktree), has `reviewer` check it, commits one WP per commit, and updates **Status** here in the same commit. Every v3 WP also runs `scripts/perf.sh` on a release build, settled, within the `08` budget.

Status values: `todo` · `in-progress` · `done` · `blocked(<reason>)`

## v3 order and parallelism
```
WP-12 (permission card) ──▶ WP-13 (typography) ──▶ WP-15 (sound cues)
WP-14 (JetBrains focus)            parallel with WP-12 (Integration/ only, worktree)
WP-16 (compacting) ──▶ WP-17 (juggling) ──▶ WP-18 (music headphones) ──▶ WP-19 (README + GIFs)
```
- WP-12 → WP-13 → WP-15 share the HUD files, so they run in sequence.
- WP-16 → WP-17 → WP-18 share `PetState` / Pet files, so they run in sequence. That chain runs in parallel with the HUD chain, because Core and Pet are disjoint from HUD.
- WP-19 is last: it needs every pose.
- Hide-mode note: the pop-out stays **4 s** (REQ-05 AC1) and `needsInput` stays out until resolved (AC2). That is designed behaviour, not a bug; it is not changed in v3.

## Done (v1, v2)
| WP | What | Key files / result |
|---|---|---|
| WP-0 | Skeleton + spikes (A: window level 27 over notch; B: closed-port hook is silent, ADR-0002; C: `scripts/test.sh` needed for swift-testing, ADR-0001) | `Package.swift`, `scripts/*`, `NotchGeometry` |
| WP-1 | ClawdCore: events, lenient decoder, store, state machine, aggregate, popToken, decay, liveness | `Sources/ClawdCore/`, tests per `04` row |
| WP-2 | Panel, screen choice, geometry, hover expand, right-click menu | `Window/NotchPanel`, `NotchWindowController` |
| WP-2.1 | Island pinned across Spaces via SkyLight (ADR-0005) | `Window/SpaceAnchor.swift` |
| WP-3 | `PetView` layer tree, 6 poses, `popOut`, `setPaused`, Reduce Motion, `--pet-demo` | `Pet/` |
| WP-4 | `EventServer`, `clawd-bridge`, `HookInstaller` (backup, idempotent, reversible) | `Server/`, `Sources/clawd-bridge/`, `Core/HookSettings` |
| WP-5 | HUD wiring: counters, HP bar, session panel, mark read | `HUD/` |
| WP-5.1 | Right-wing layout + hover glow (REQ-11, layer shadow, no blur) | `IslandView`, `CountersView` |
| WP-3.1 | `usingTools` state + hammer (replaced `talking(.tool)`); never decays | Core, `Pet/`, simulator `tools` |
| WP-5.2 | Single session counter, importance-sorted panel | `Snapshot.sessions`, `CountersView` |
| WP-5.3 | `statusCounts`, `seven_day` usage | `UsageSnapshot` |
| WP-6 | `TerminalFocusWatcher`: Terminal.app / iTerm2 tab-precise, others app-level (2 s dwell), click-to-focus | `Integration/` |
| WP-7 | Hide mode, launch at login, AppKit Settings window | `HUD/`, `Window/` |
| WP-8 | Perf pass, lazy `SessionPanelView`; known exceptions in `08` | `08` |
| WP-5.4 | Split wings (left counter, right HP bar + pet), three expanded counters | `IslandView`, `CountersView` |
| WP-6.1 | Click only focuses; read after a successful focus | `HUDController.onSelect` |
| WP-7.1 | Half-hidden hide mode, spring placement transitions | `IslandView.setPetPlacement`, `PetView.setPlacement` |
| WP-5.5 | Panel polish: `WK · HP · resets` footer, blue state dot, 56 pt right wing | `SessionPanelView` |
| WP-7.2 | Upside-down corner peek (about 150°), legs behind notch cover | `Window/`, `Pet/` |
| WP-6.2 | Focus survives app restarts: statusline `SessionMeta`, done-while-frontmost | bridge, `SessionStore.apply(meta:)` |
| WP-9 | Permissions from the notch (REQ-V2-01, ADR-0006): held `PermissionRequest`, cards, `timeout: 120`, `notchPermissions` | `Server/`, `PendingPermission`, `HUD/` |
| WP-10 | Window-level focus for the VS Code family via Accessibility (REQ-V2-02) | `Integration/` |
| WP-11 | "+ New" footer menu, recent projects, safe quoting (REQ-V2-03) | `Integration/`, `HUD/` |

## v3 work packages
Specs: REQ-V2-01, REQ-V2-02, REQ-03, REQ-12, REQ-13, REQ-14 in `02`; transitions in `04`; formats in `05`; layout in `06`; pet parts in `07`. Follow the `add-pet-state` skill for WP-16/17/18.

### WP-12 — Permission card: centred pills + Always allow · owner: core-engineer + macos-ui-engineer · deps: none · status: `todo`
- Core: `PendingPermission.suggestion` (first `permission_suggestions` entry, raw JSON, at most 2 KiB), decoded leniently; tests.
- Server: reply `allow` with `updatedPermissions` (format in `05`); the 64 KiB body cap stays.
- UI: three equal pills **Allow / Deny / Always allow** with centred labels; Always allow hidden without a suggestion, tooltip shows the rule.
- AC: REQ-V2-01 AC6–AC9, REQ-14 where fonts apply. E2E with real `claude` + scratch `--settings`: Always allow answers the prompt and the rule is saved.

### WP-13 — JetBrains Mono typography · owner: macos-ui-engineer · deps: WP-12 · status: `todo`
- One font helper (HUD, panel, cards, Settings): `NSFont(name: "JetBrains Mono", …)`, fallback `NSFont.monospacedSystemFont`.
- Check the footer, cards and counters still fit (monospace is wider); adjust `expandedMinWidth` only if needed.
- AC: REQ-14 AC1–AC3. RSS within budget.

### WP-14 — JetBrains window-level focus · owner: integration-engineer · deps: none (parallel with WP-12) · status: `todo`
- Extend the Accessibility focus path to the `com.jetbrains.` family; title rule per family (`05`); `WindowTitle` tests for both title shapes.
- AC: REQ-V2-02 AC4–AC6. Tab precision inside the IDE terminal is not possible and is not attempted.

### WP-15 — Sound cues + Settings toggle · owner: macos-ui-engineer · deps: WP-13 · status: `todo`
- `SoundCues`: cached `NSSound(named:)`, played once per edge (needsInput, unread done) using the `popToken` edge logic; `soundCues` config key, default on; Settings checkbox "Sound cues".
- AC: REQ-12 AC1–AC4. No timers added.

### WP-16 — `compacting` sweeping pose · owner: core-engineer + pet-animator · deps: none (parallel with WP-12) · status: `done` (Core state + priority + tests, broom/dust pose, simulator `compact`)
- Core: `PreCompact` → `compacting`; `SessionStart(compact)` and other state-setting events leave it; priority and panel text ("compacting"); tests (`04`).
- Pet: broom + dust puff, `broom.*` tokens, Reduce Motion pose (`07`). Simulator `compact` scenario + skill row.
- AC: REQ-03 AC1, AC3, AC4, AC5.

### WP-17 — `juggling` pose · owner: core-engineer + pet-animator · deps: WP-16 · status: `done` (derived in `SessionStore.snapshot`, balls on an elliptical orbit, simulator `subagents`)
- Core: derived `juggling` (`activeSubagents > 0`, not needsInput/done); counter resets on `Stop`, `StopFailure`, `UserPromptSubmit`; panel text "N subagents"; tests.
- Pet: three balls on keyframed arcs, `ball.1–3` tokens. Simulator `subagents` scenario + skill row.
- AC: REQ-03 AC1, AC3, AC4, AC5, AC6.

### WP-18 — Music → headphones · owner: integration-engineer + core-engineer + pet-animator · deps: WP-17 · status: `done` (NowPlaying + store, NowPlayingWatcher, headphones overlay, `--debug-headphones`)
- Integration: `NowPlayingWatcher` (ADR-0007, `05`). Core: `NowPlaying` in `Snapshot`. Pet: headphones overlay orthogonal to every pose and to hide mode (`07`).
- AC: REQ-13 AC1–AC5. Verify with a real Music or Spotify play/pause; CPU stays at the idle budget.

### WP-19 — README + pose GIFs · owner: pet-animator + orchestrator · deps: WP-18 · status: `todo`
- `README.md`: features, states and poses, notch layout, hide mode, permissions, focus support matrix, sound cues, requirements, "status: in development; install instructions later", JetBrains Mono note.
- GIFs in `docs/media/`, one per pose with and without headphones, from a DEBUG-only `--render-poses <dir>` mode: `PetView` offscreen via `CARenderer` into a Metal texture at fixed time steps, GIFs through ImageIO, no Screen Recording permission. Fallback if `CARenderer` cannot capture animations: one static PNG per pose (risk).
- Requirements to list: macOS 14+ (tested on macOS 26), Apple silicon; Claude Code with hooks and statusline; Pro/Max plan for HP and WK; Swift 6.2 Command Line Tools to build; optional permissions: Automation (Terminal.app / iTerm2), Accessibility (VS Code / JetBrains window focus), login item.
- AC: every pose has media; README claims match the specs.

## Checks left for a human
These need eyes, a hover, a click or a system permission:
- Notch fit, full-screen hover, right-click without focus, no slide on Space switch (WP-2, WP-2.1).
- Hammer not clipped in the 56 pt wing (`scripts/simulate.sh tools`); counter morph, WK-first footer, state dots (WP-5.4, WP-5.5).
- Hide mode: corner peek, flip into the wing and back, hover from hidden, toggled while expanded (WP-7.1, WP-7.2).
- iTerm2 / Terminal.app: a session started before the app becomes focusable after its next statusline refresh; a click focuses the tab and then marks read; a session finishing in the watched tab is marked read. If Automation never prompts: `tccutil reset AppleEvents dev.clawdnotch.ClawdNotch` (WP-6.x).
- Permissions: reinstall hooks once (right-click, Install Hooks) so `PermissionRequest` gets `timeout: 120`; a real prompt shows a card; Allow / Deny work and the terminal dialog still works (WP-9).
- Accessibility prompt on the first click on a VS Code session; the right window comes forward (WP-10).
- "+ New" menu, Choose Folder…, a new Terminal.app / iTerm2 window running `claude` there (WP-11).
- `scripts/perf.sh 30` with the mouse on the expanded panel (glow, REQ-11).
- v3: pill look and Always allow on a real prompt (WP-12), JetBrains window focus (WP-14), sounds audible (WP-15), broom / juggling at notch size (WP-16/17), headphones with Music and Spotify (WP-18).

## Deferred
- Install to `/Applications` with a stable signature (Developer ID or a self-made certificate), so Automation, Accessibility and login-item grants survive rebuilds.
- Perf follow-ups: cap concurrent `EventServer` connections (post-burst RSS, `08`); find about 1 MB of launch headroom.
- Ghostty and Warp stay app-level (no scripting API; Ghostty tab precision dropped unless it ships one).
- Bundle JetBrains Mono (OFL 1.1, with its license) at production time (REQ-14).
