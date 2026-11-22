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
- Mini-mode note (called hide mode until v5): the pop-out is **3 s** (REQ-05 AC1) and `needsInput` stays out until resolved (AC2). That is designed behaviour, not a bug; it is not changed in v3.

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

### WP-12 — Permission card: centred pills + Always allow · owner: core-engineer + macos-ui-engineer · deps: none · status: `done` (e2e with real `claude`: Always allow wrote `Bash(swift --version)` to the scratch `.claude/settings.local.json`, the repeat ran unprompted; `addDirectories` suggestions are session-only; release idle 0.00 % / 37.8 MB)
- Core: `PendingPermission.suggestion` (first `permission_suggestions` entry, raw JSON, at most 2 KiB), decoded leniently; tests.
- Server: reply `allow` with `updatedPermissions` (format in `05`); the 64 KiB body cap stays.
- UI: three equal pills **Allow / Deny / Always allow** with centred labels; Always allow hidden without a suggestion, tooltip shows the rule.
- AC: REQ-V2-01 AC6–AC9, REQ-14 where fonts apply. E2E with real `claude` + scratch `--settings`: Always allow answers the prompt and the rule is saved.

### WP-13 — JetBrains Mono typography · owner: macos-ui-engineer · deps: WP-12 · status: `done` (HUDStyle.font is the one lookup; footer compact rule re-measured with cell padding; release idle 0.00 % / 37.8 MB)
- One font helper (HUD, panel, cards, Settings): `NSFont(name: "JetBrains Mono", …)`, fallback `NSFont.monospacedSystemFont`.
- Check the footer, cards and counters still fit (monospace is wider); adjust `expandedMinWidth` only if needed.
- AC: REQ-14 AC1–AC3. RSS within budget.

### WP-14 — JetBrains window-level focus · owner: integration-engineer · deps: none (parallel with WP-12) · status: `done`
- Extend the Accessibility focus path to the `com.jetbrains.` family; title rule per family (`05`); `WindowTitle` tests for both title shapes.
- AC: REQ-V2-02 AC4–AC6. Tab precision inside the IDE terminal is not possible and is not attempted.

### WP-15 — Sound cues + Settings toggle · owner: macos-ui-engineer · deps: WP-13 · status: `done` (edge = `popToken` advance; Funk if the needs-input count rose, else Glass; lazy cached `NSSound`s; sound heard-check left to the user; release idle 0.00 % / 37.9 MB)
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

### WP-18 — Music → headphones (removed in v5, WP-25) · owner: integration-engineer + core-engineer + pet-animator · deps: WP-17 · status: `done` (NowPlaying + store, NowPlayingWatcher, headphones overlay, `--debug-headphones`)
- Integration: `NowPlayingWatcher` (ADR-0007, `05`). Core: `NowPlaying` in `Snapshot`. Pet: headphones overlay orthogonal to every pose and to hide mode (`07`).
- AC: REQ-13 AC1–AC5. Verify with a real Music or Spotify play/pause; CPU stays at the idle budget.

### WP-19 — README + pose GIFs · owner: pet-animator + orchestrator · deps: WP-18 · status: `done`
- `README.md`: features, states and poses, notch layout, hide mode, permissions, focus support matrix, sound cues, requirements, "status: in development; install instructions later", JetBrains Mono note.
- GIFs in `docs/media/`, one per pose with and without headphones, from a DEBUG-only `--render-poses <dir>` mode: `PetView` offscreen via `CARenderer` into a Metal texture at fixed time steps, GIFs through ImageIO, no Screen Recording permission. Fallback if `CARenderer` cannot capture animations: one static PNG per pose (risk).
- Requirements to list: macOS 14+ (tested on macOS 26), Apple silicon; Claude Code with hooks and statusline; Pro/Max plan for HP and WK; Swift 6.2 Command Line Tools to build; optional permissions: Automation (Terminal.app / iTerm2), Accessibility (VS Code / JetBrains window focus), login item.
- AC: every pose has media; README claims match the specs.

## v3.1 polish
WP-20 (Pet/) and WP-21 (Window/, App/, HUD/) touch disjoint directories, so they run in parallel (one in a worktree).

### WP-20 — Headphones redesign and bigger juggling balls · owner: pet-animator · deps: WP-19 · status: `done`
- Balls about 3.6 u, orbit raised to clear the head and the band.
- Headphones: bigger cups on the body's upper corners, below the arms in z-order; wider, lighter band; new token colours (`07`). Check every pose (raised arm, hammer, broom, balls) and the upside-down peek.
- Regenerate `docs/media/` GIFs with the DEBUG `--render-poses docs/media` mode, and update README.md's headphones line.
- AC: REQ-13 AC3, AC6; `07` anatomy. Release `perf.sh` settled within budget.

### WP-21 — Selective 3 s hide-mode pop-out and the headphones switch · owner: macos-ui-engineer (+ core-engineer for the config test) · deps: WP-19 · status: `done`
- Pop-out 3 s; triggers: `popToken` advance or the aggregate entering `talking`, `done`, `needsInput`, `juggling`; other changes only re-pose the peeking pet; `needsInput` holds.
- Settings checkbox "Show headphones when music plays" (`headphones`, default on, `decodeIfPresent`, Core test); off stops `NowPlayingWatcher` and hides the headphones at once.
- README.md: hide-mode text (3 s, which states pop out) and the headphones switch.
- AC: REQ-05 AC1–AC2, REQ-13 AC7. Release `perf.sh` settled within budget.

## Checks left for a human
These need eyes, a hover, a click or a system permission:
- Notch fit, full-screen hover, right-click without focus, no slide on Space switch (WP-2, WP-2.1).
- Hammer not clipped in the 56 pt wing (`scripts/simulate.sh tools`); counter morph, WK-first footer, state dots (WP-5.4, WP-5.5).
- Mini mode (hide mode until v5): corner peek, flip into the wing and back, hover from hidden, toggled while expanded (WP-7.1, WP-7.2).
- iTerm2 / Terminal.app: a session started before the app becomes focusable after its next statusline refresh; a click focuses the tab and then marks read; a session finishing in the watched tab is marked read. If Automation never prompts: `tccutil reset AppleEvents dev.clawdisland.app` (WP-6.x).
- Permissions: reinstall hooks once (Settings, hooks row, Install) so `PermissionRequest` gets `timeout: 120`; a real prompt shows a card; Allow / Deny work and the terminal dialog still works (WP-9).
- Accessibility prompt on the first click on a VS Code session; the right window comes forward (WP-10).
- "+ New" menu, Choose Folder…, a new Terminal.app / iTerm2 window running `claude` there (WP-11).
- `scripts/perf.sh 30` with the mouse on the expanded panel (glow, REQ-11).
- v3: Always allow on a real prompt (WP-12), JetBrains window focus (WP-14).
- v3.1: bigger balls (WP-20); 3 s pop-out only on talking / done / needsInput / juggling (WP-21).

## v4 — performance, README GIFs, production
Order: v3.1 (WP-20 ∥ WP-21) → WP-22 → WP-23 → WP-24 (WP-23 and WP-24 both edit README.md, so they run in sequence).

### WP-22 — Performance pass · owner: core-engineer (Server) + macos-ui-engineer (app) · deps: WP-20, WP-21 · status: `done` (server cap + suite; app half: `SoundCues` via `afplay` -6 MB RSS, `--open-settings`; burst 48.6 -> 42.1 MB, hide pop-out 45.5 -> 41.3 MB; launch peak 41.3 MB, steady 38.5 MB and post-burst 42 MB stay over target because the empty-AppKit floor is 29.6 MB while `footprint` is 11 MB, see `08`)
- `scripts/perf-suite.sh` with every scenario in `08` (v4 targets), including the expanded panel with the glow (REQ-11 AC2) and Settings open/close.
- Profile launch (`vmmap --summary`, `footprint`); lazy-create what is not needed at launch; release flags (`-Osize`), no DEBUG code in release.
- Cap concurrent `EventServer` connections (held permissions exempt); re-measure post-burst.
- AC: REQ-08 AC1, the `08` v4 targets; before → after table in `08`.

### WP-23 — README hide-mode and island GIFs · owner: macos-ui-engineer + orchestrator · deps: WP-22 · status: `done` (`scripts/record-gif.sh <island|hide-mode>`, `make-gif.swift`, `window-id.swift`; frames aligned by the window's left edge because the island is asymmetric around the notch; the scenes show the live Claude session of the machine too)
- `scripts/record-gif.sh` + `scripts/make-gif.swift`: capture only the app window (`screencapture -l <windowID> -o`, transparent, so no other screen content), composite on a dark background, loop.
- `docs/media/island.gif` (states + hover: counter morph, panel, glow) and `docs/media/hide-mode.gif` (corner peek, a 3 s pop-out on `talking`, a pose-only change), each < 600 KB, near the top of README.md.
- AC: both show motion and nothing outside the app window.

### WP-24 — Production readiness · owner: integration-engineer + macos-ui-engineer · deps: WP-23 · status: `done` (fonts are subset Latin weights, registered only when JetBrains Mono is not installed: a process-registered face costs ~3 MB RSS each; `CLAWD_SETTINGS_PATH` / `CLAWD_CONFIG_PATH` redirect `--uninstall-hooks` for tests; the user runs `make-signing-cert.sh`)
- `LICENSE` (MIT), `THIRD_PARTY_NOTICES.md` (JetBrains Mono, OFL 1.1), `CHANGELOG.md` (1.0.0).
- Bundle JetBrains Mono and register it at launch; version keys, `LSMinimumSystemVersion`, copyright, `AppIcon.icns` from the pet render.
- `scripts/make-signing-cert.sh` (the user runs it once), signing in `bundle.sh` (ADR-0008); `scripts/install.sh`, `scripts/uninstall.sh` (with `--uninstall-hooks` in the app), `scripts/package.sh`. Agents test them against temp destinations only.
- README.md: install, first-run permissions, updating, uninstall, license.
- AC: REQ-14 AC2, REQ-15 AC1–AC5.

## v5 — waving pet, no headphones, mini mode, ClawdIsland
Older entries above keep the names of their time ("hide mode", headphones, REQ-13). v5 removes REQ-13 (WP-25) and renames hide mode to mini mode (WP-27). Order: WP-25 → (WP-26 ∥ WP-27, disjoint directories) → WP-28 → WP-29. Every WP runs `swift build`, `scripts/test.sh` and the release `scripts/perf-suite.sh` within the `08` budget, then `reviewer`, then one local commit.

### WP-25 — Remove headphones and now-playing · owner: core-engineer + pet-animator + macos-ui-engineer (sequential) · deps: none · status: `done` (perf: steady RSS 38.0–38.7 MB, footprint 11 MB, unchanged vs v4)
- Core: delete `NowPlaying`, `Snapshot.nowPlaying`, the `SessionStore` player state and `AppConfig.headphones` (the decoder ignores the leftover key; test it); delete `NowPlayingTests` and the headphones cases in `AppConfigTests`.
- App: delete `NowPlayingWatcher` and its wiring (`AppModel`, `AppDelegate`, `Preferences`, the Settings checkbox).
- Pet: remove the headphone layers, tokens and `setHeadBob` (`PetRig`, `PetTokens`, `PetAnimations`, `PetView`, `PetDemo`, `PoseRenderer`); delete `docs/media/*-headphones.gif`; drop `headphones` from `record-gif.sh`.
- AC: REQ-13 removed, ADR-0007 superseded; no `headphone` / `NowPlaying` left in code or docs outside history; release perf-suite re-measured and recorded in `08`.

### WP-26 — Waving paw and two-pair legs · owner: pet-animator · deps: WP-25 · status: `done`
- Legs: two pairs with a visible middle gap (centres about x 7.5 / 11 and 21 / 24.5, `07`); tune against hero renders.
- Wave: in `done` and `needsInput` the raised paw loops three ±20° swings (about 0.9 s) then rests about 1.5 s, while the state holds; Core Animation only; none under Reduce Motion.
- Regenerate `docs/media/*.gif` (`--render-poses docs/media`).
- AC: REQ-03 AC7, REQ-06; the wave loop runs in both states, and idle CPU stays at budget.

### WP-27 — Mini mode, launch tilt fix, Settings-only hooks and login · owner: macos-ui-engineer (+ core-engineer for `AppConfig`) · deps: WP-25 · status: `done`
- Rename hide mode to mini mode in code, UI and docs: `hideMode` → `miniMode`, menu "Mini Mode", Settings checkbox; `AppConfig` reads the legacy `hideMode` key as a fallback (test).
- Fix the launch tilt: embed the pet before applying the persisted mini mode (`AppDelegate`), so `IslandView.setPetPlacement` finds it; launching with `miniMode` on shows a tilted pet from the first frame.
- Right-click menu: [server error], Mini Mode, Mark All Read, Settings…, Quit. Remove the Hooks and Launch at Login items.
- Settings: a hooks row ("Installed / Not installed" + Install / Uninstall button, `HookInstaller`, errors shown) next to Launch at login; re-measure the Settings RSS exception.
- AC: REQ-05 AC5–AC6, REQ-09 AC4. Installer tested only against scratch files (`CLAWD_SETTINGS_PATH` / `CLAWD_CONFIG_PATH`).

### WP-28 — Rename to ClawdIsland · owner: integration-engineer · deps: WP-25, WP-26, WP-27 · status: `done`
- Package, executable target and `Sources/ClawdNotch` → `ClawdIsland`; `ClawdCore`, `clawd-bridge` and `X-Clawd-Token` keep their names (ADR-0009).
- Bundle `dist/ClawdIsland.app`, id `dev.clawdisland.app`, usage strings, menu and window titles; version 1.1.0 and a CHANGELOG entry.
- Application Support `ClawdNotch/` → `ClawdIsland/`, moved once at launch if the new folder is missing (keeps token, port, `originalStatusLine`); test with a temp home.
- Signing "ClawdIsland Dev" (`make-signing-cert.sh`, `bundle.sh`); scripts, `.claude/` agents and skills, README, CLAUDE.md and docs 03–08 use the new name; `uninstall.sh` also removes a leftover `ClawdNotch` folder.
- AC: REQ-15 (v5 name); `grep -rI ClawdNotch` leaves only the migration code, ADR-0009 and CHANGELOG history; `install.sh --dest <tmp>` works; `codesign -dv` shows the new identifier.

### WP-29 — README GIFs on a scratch port · owner: macos-ui-engineer + orchestrator · deps: WP-28 · status: `done`
- `record-gif.sh` sets a scratch port in the backed-up config while recording (a scratch port and random token, also in `perf-suite.sh`: real Claude Code hooks and the bridge cannot reach the app, so no live session or real WK/HP leaks in); `simulate.sh` reads the port from the config. The scene becomes `mini-mode`; `docs/media/mini-mode.gif` replaces `hide-mode.gif` (deleted), README links updated.
- Re-record `island.gif` and `mini-mode.gif`; check extracted frames: the first frame tilted, no foreign sessions, the wave visible in `done`.
- AC: both GIFs < 600 KB, show motion and nothing outside the app window.

## v6 — Public 1.0.0
First public release on GitHub (Apple silicon, signed with a stable self-signed identity, no notarization). Nothing here is implemented yet. Order: (WP-30 ∥ WP-32 ∥ WP-34) → WP-31 → WP-33 → WP-35 → the user publishes. Every WP runs `swift build`, `scripts/test.sh` and, when it touches the app, the release `scripts/perf-suite.sh` within the `08` budget, then `reviewer`, then one local commit.

### WP-30 — Signing identity "ClawdIsland" · owner: integration-engineer · deps: none · status: `todo`
- `make-signing-cert.sh` and `bundle.sh` use the name "ClawdIsland" (renamed from "ClawdIsland Dev"; the user re-runs the script once). Releases are always signed with that identity, so friends' TCC grants survive updates (ADR-0008).
- `package.sh` refuses to package an ad-hoc build unless `--adhoc` is given.
- AC: REQ-15 AC1, AC4; `codesign -dv` shows the identity; the zip has a `.sha256`.

### WP-31 — First-run onboarding · owner: macos-ui-engineer · deps: WP-30 · status: `todo`
- On the first launch (no `onboarded` flag in config) and while the hooks are not installed, open Settings with a one-line welcome ("Install the Claude Code hooks to connect Clawd"); Install is the default button. Set the flag after the window has been shown once. No new window type.
- AC: REQ-09 AC5; a fresh config opens Settings once, a second launch does not. Tested only with `CLAWD_CONFIG_PATH` / `CLAWD_SETTINGS_PATH` scratch files.

### WP-32 — GitHub CI · owner: integration-engineer · deps: none · status: `todo`
- `.github/workflows/ci.yml` on a `macos` runner for push and pull request: `swift build`, `scripts/test.sh` (it must also work with full Xcode on the runner), `swift build -c release`. No secrets, no signing. Pushing stays the user's action.
- AC: REQ-15 AC6; the workflow file is valid YAML and `scripts/test.sh` works with and without Xcode.

### WP-33 — Settings window memory (timeboxed) · owner: macos-ui-engineer · deps: WP-31 · status: `todo`
- Try lighter construction and releasing everything on close; measure with `perf-suite.sh`. Target: closed returns to <= 45 MB RSS and `footprint` stays < 20 MB.
- If it does not work, record the attempt in `08`, keep the current exception (60 / 55 MB) and mark the WP done.
- AC: REQ-08 AC1; before → after table in `08`.

### WP-34 — Mini-mode pop-out triggers · owner: macos-ui-engineer · deps: none · status: `todo`
- Pop out only on a `popToken` advance or on entering `talking`, `done` or `needsInput`. `juggling` only re-poses the peeking pet. Update the trigger set in `AppDelegate`.
- AC: REQ-05 AC1; `simulate.sh subagents` causes no pop-out.

### WP-35 — Release 1.0.0 and README · owner: orchestrator + integration-engineer · deps: WP-30…WP-34 · status: `todo`
- Version 1.0.0 everywhere (`bundle.sh`, CHANGELOG, README, docs). The CHANGELOG becomes one **1.0.0** "first public release" entry summarising the features.
- Remove the ClawdNotch legacy: the support-folder migration code and its tests, and the leftover cleanup in `uninstall.sh` (nobody else ran ClawdNotch; this Mac is already migrated). ADR-0009 keeps the history.
- README for release: intro and GIFs, **Install from a release** (download the zip, check the sha256, move to Applications, macOS 15+ first launch: Privacy & Security → Open Anyway, or `xattr -dr com.apple.quarantine`), Settings → Install hooks, permissions, uninstall, privacy, license. Building from source becomes a short "Build from source" section. No ClawdNotch mentions, no "Share a build", no doc-table bloat.
- AC: REQ-15 AC2, AC5, AC7; `grep -rI ClawdNotch` leaves only ADR-0009 and CHANGELOG history.

**Release checklist (the user runs it):** `scripts/test.sh` → `scripts/bundle.sh release` (must say it signed with "ClawdIsland") → `scripts/package.sh` → `gh release create v1.0.0 dist/ClawdIsland-1.0.0.zip*`.

## Deferred
- Developer ID + notarization (ADR-0008 upgrade path).
- Ghostty and Warp stay app-level (no scripting API; Ghostty tab precision dropped unless it ships one).
- Universal binary / Intel: not needed (Apple silicon only, REQ-07).
- Update-check button: not wanted (no network calls from the app, no polling).
- Paid Developer ID, hardened runtime and notarization: only if the app goes beyond friends.
