# 09 — Roadmap and work packages

**How to use this file:** the orchestrator (`orchestrate-wp` skill) picks every WP whose status is `todo` and whose dependencies are `done`, delegates it to the owner agent (in parallel only when file ownership is disjoint; use a worktree when files may overlap), has `reviewer` check it, makes one local commit per WP, and updates the status here in the same commit. Every WP that touches the app also runs the release `scripts/perf-suite.sh` within the `08` budget.

Status values: `proposed` (in `11-proposals.md`, not accepted yet; the orchestrator skips it) · `todo` · `in-progress` · `done` · `blocked(<reason>)`

WP format:
```
### WP-<n> — <title> · owner: <agent> · deps: <WPs or none> · status: `todo`
- What to build (cite REQ / ADR / doc sections).
- AC: the REQ acceptance criteria it satisfies, plus how it is verified.
```
WP-0…WP-35 built 1.0.0 and appear in git history. 1.1.0 is WP-36 plus the accepted proposal WPs (numbers kept from `11`), plus WP-50…WP-52. New work packages continue from **WP-53**.

## 1.0.0 — released
Everything in `02` is implemented, reviewed, measured (`08`) and checked by hand on real hardware.

| Area | What shipped | Where |
|---|---|---|
| Core | Lenient hook decoding, per-session state machine, aggregate and panel order, talking decay, derived `juggling`, liveness, `popToken` edges, usage/HP rules, pending permissions | `Sources/ClawdCore/`, `04` |
| Transport | HTTP hooks to `EventServer` (loopback, token, 64 KiB cap, held `PermissionRequest`), `clawd-bridge` session-start + statusline wrapper | `Server/`, `clawd-bridge`, `05`, ADR-0002/0004/0006 |
| Window | Notch / virtual-notch island, SkyLight Space pinning, hover expand with glow, mini mode with 3 s pop-out, right-click menu | `Window/`, `06`, ADR-0005 |
| Pet | Nine Core Animation poses, waving paw, pop-out spring, placement moves, pause, Reduce Motion | `Pet/`, `07`, ADR-0003 |
| HUD | Session counter, three expanded counters, vertical HP bar, session panel, WK/HP footer, permission cards, "+ New" menu | `HUD/` |
| Integration | Tab-precise focus and read for Terminal.app / iTerm2, window focus for VS Code and JetBrains, new-session launcher, sound cues | `Integration/`, `05` |
| App | Settings window (hooks row, first-run welcome, toggles), launch at login, JetBrains Mono | `App/` |
| Distribution | `bundle` / `install` / `uninstall` / `package` scripts, self-signed "ClawdIsland" identity, GitHub Actions CI, README GIFs, release zip + sha256 | `scripts/`, `.github/`, ADR-0001/0008 |

## 1.1.0
Accepted scope (`11` P1 styles only, P2 without Agents, P4a, P4b, P4d, plus WP-50..52). The requirements are the ACs marked "(1.1.0)" in `02`. Claude Code stays the only agent. Run in this order; WPs with disjoint owners may run in parallel (WP-36 and WP-52 both touch Core: use a worktree or run them back to back). Each WP also marks itself `done` here and adds a `CHANGELOG.md` line under "Unreleased (1.1.0)".

### WP-36 — Pet styles Roundy / Sharpy · owner: pet-animator (`AppConfig` through core-engineer) · deps: none · status: `done`
- Reuse commit `6ff6829` from `pet-variants` (not the plush commits `6a85832`, `0864b24`, nor the README commit `f203f40`). Drop Cute; rename Classic → `roundy` and Sharp → `sharpy`. `petStyle` in config (default `roundy`, an unknown value decodes to `roundy`); `PetRig` per style; `PetView` rebuilds the rig live; `--render-poses <dir> --pet-style <style>` (REQ-06 AC2, `07` "Styles"). The Settings popup is temporary and moves to the Pet tab in WP-42.
- AC: REQ-06 AC1–AC2; `AppConfigTests` covers the default, an unknown value (including the old `classic` / `sharp` / `cute`) and the round-trip; every pose rendered in both styles and checked at notch size; `perf-suite.sh` within `08`.

### WP-52 — Talking streak · owner: core-engineer · deps: none · status: `done`
- `Session.talkingStreakStart`, set on `.messageDisplay`; the session keeps its previous state until a `MessageDisplay` finds the streak ≥ 1.5 s old (no timed promotion); any other state-setting event resets it; the 2 s decay and its one-shot `nextDecayDeadline` are unchanged (`04` "Talking streak", REQ-03 AC8). No new timer (`08` rule 1).
- AC: REQ-03 AC8; `TransitionTests` / `SessionStoreTests` for 1.49 s vs 1.5 s, a single `MessageDisplay` plus silence never promoting, a new streak after a 2 s gap, a decayed streak not revived by one message, a reset by `PreToolUse`, and the 2 s decay unchanged; `simulate.sh text` (talking) and `blip` (no change).

### WP-50 — Pose rework · owner: pet-animator · deps: WP-36 · status: `done`
- In `PetRig` / `PetAnimations`: drop the Zzz layer and its rise; restyle the speech bubble to the pet's look (rounded, pet tokens); scale the hammer and broom about 1.3× and re-check clipping in the right wing and in mini mode; juggling paws toss and catch in turn, in sync with the ball orbit; `done` and `needsInput` get an entry burst plus a stronger loop, keeping the wave (`07` "Poses and animations", REQ-03 AC7, AC9).
- AC: REQ-03 AC1, AC7, AC9 and REQ-04 AC4; every pose rendered in both styles (`--render-poses docs/media --pet-style roundy|sharpy`) and the README GIFs re-rendered; Reduce Motion checked; `perf-suite.sh` within `08`.

### WP-51 — Mini-mode hold until read · owner: macos-ui-engineer · deps: WP-52 · status: `done`
- In `AppDelegate` / `NotchWindowController`: the pop-out holds while the aggregate is `done` or `needsInput`; the 3 s countdown starts when it leaves both; `talking` keeps the plain 3 s; turning mini mode on while `done` also holds (REQ-05 AC1–AC2, `06` "Mini mode").
- AC: REQ-05 AC1, AC2, AC4; checked with `simulate.sh`: done stays out until mark-read or terminal focus, needsInput until resolved, talking retracts after 3 s; `perf-suite.sh` mini-mode scenarios within `08`.

### WP-42 — Settings tabs General / Pet / Advanced · owner: macos-ui-engineer · deps: WP-36 · status: `done`
- Rewrite `SettingsWindow.swift` as an `NSTabViewController` (`.toolbar` style, SF Symbols): General (welcome, hooks row, notch permissions, mini mode, focus-read, sound cues, launch at login; DND joins with WP-45), Pet (3× `PetView` preview with a pose picker, Style popup), Advanced (read-only port, version, GitHub link). Built on open, released on close; always opens on General at one fixed size for every tab (REQ-21, `06` "Settings window"). No Agents tab: it is deferred to WP-38+ and would be added to this window then.
- AC: REQ-21 AC1–AC6, REQ-09 AC5 (first run opens General with Install as default); scratch `CLAWD_SETTINGS_PATH` / `CLAWD_CONFIG_PATH` for the hooks row and first run; `perf-suite.sh --open-settings` within the `08` Settings exception.

### WP-45 — Do Not Disturb · owner: core-engineer (`dnd` key) → macos-ui-engineer · deps: WP-42, WP-51 · status: `done`
- `dnd` in `AppConfig` (default false); a right-click menu item and a General checkbox; while on, no pop-out and no sound cue, but state and counters update; turning it off while `needsInput` or an unread `done` is pending pops out once, held (REQ-05 AC2); turning it on retracts at once; the pet's pop-out spring is muted too (REQ-23, `06`).
- Investigation item: a screen-sharing or Focus-mode signal only if an event-driven public API exists; otherwise document it as dropped (`08` rule 1, REQ-23 AC3). Result: dropped, as screen sharing has no change notification and Focus status needs an entitlement and user permission.
- AC: REQ-23 AC1–AC3; `AppConfigTests` for `dnd`; checked with `simulate.sh`; no new repeating timer.

### WP-48 — Context and cost per session row · owner: core-engineer → macos-ui-engineer · deps: WP-42 · status: `done`
- Decode `context_window.used_percentage` and `cost.total_cost_usd` from `/statusline` into `Session` fields for the payload's `session_id` (included in `==`); the `SessionPanelView` row shows `ctx 64% · $1.20` at its right edge, omitting a missing part (REQ-26, `05` "Context and cost"). The dependency on WP-42 is file order only.
- AC: REQ-26 AC1–AC3; decoder tests with both fields, one, none, and a null context; `rate_limits` handling unchanged (existing tests pass); checked with a `simulate.sh` statusline POST.

### WP-46 — Poke · owner: pet-animator + macos-ui-engineer (hit-test pass-through) · deps: WP-50 · status: `done`
- `PetView` gets `mouseUp` and `acceptsFirstMouse`; `IslandView.hitTest` asks the pet slot first, so a click inside it reaches `PetView` although the counters slot sits above it (a tucked pet's slot includes the notch corner); a 0.6 s one-shot group (squash and blink, a `badge.alert` heart about 1 in 4 times) (REQ-24, `07` "Poke", `06` "Pet click").
- AC: REQ-24 AC1–AC3 and REQ-02 AC2 (the frontmost app stays active); no state change, no read, no panel; Reduce Motion gives a blink only; `perf-suite.sh` within `08`.

## Release checklist (the user runs it)
1. Bump `version=` in `scripts/bundle.sh` and add a `CHANGELOG.md` entry.
2. `scripts/test.sh`
3. `scripts/package.sh`: it bundles a release build and must sign it with "ClawdIsland" (it refuses an ad-hoc build).
4. `gh release create v<version> dist/ClawdIsland-<version>.zip dist/ClawdIsland-<version>.zip.sha256`

## Later (proposed)
These WPs stay `proposed` (`11-proposals.md`). Accepting one means moving its draft REQ into `02`, setting its ADR to `accepted`, and setting the WP to `todo`. The Agents tab of P2 is deferred to WP-38+: it would be added to the 1.1.0 Settings window then.

### WP-37 — Core: agent-aware sessions · owner: core-engineer · deps: none · status: `proposed`
- `Session.agent` (`claude` default, `codex`, `gemini`, `junie`), included in `==`; the store keys sessions by agent + `session_id`; `ClawdEvent` / `SessionMeta` decode an optional `agent` field leniently (`11` P3, ADR-0009, draft REQ-22 AC2).
- AC: tests cover two agents with the same `session_id`, a missing `agent` (Claude Code), and an unknown value; the `04` state machine is unchanged.

### WP-38 — Bridge adapter + Codex CLI · owner: integration-engineer · deps: WP-37 · status: `proposed`
- `clawd-bridge hook <agent> <event>`: mapping table for Codex (`11` P3 "Event mapping"), POST to `/hook` with a 300 ms timeout; the process walk gets a per-agent executable list; a pure Core `CodexHookSettings` merge plus a `~/.codex/hooks.json` installer (backup, idempotent, reversible; `config.toml` untouched); held `PermissionRequest` (Allow / Deny only) once a parallel terminal prompt is verified (ADR-0006, ADR-0009).
- AC: draft REQ-22 AC1–AC4 for Codex; install / uninstall round-trip tests; `simulate.sh --agent codex`; a real `codex` run against a scratch `CODEX_HOME`; bridge start < 20 ms (`08`).

### WP-39 — Junie CLI · owner: integration-engineer · deps: WP-38 · status: `proposed`
- Junie mapping and the `~/.junie/config.json` installer; `PermissionRequest` exits **1** for "no decision" and 0 only after an explicit Allow (ADR-0009).
- AC: draft REQ-22 AC1–AC4 for Junie; a test for every bridge exit path on `PermissionRequest` (app down, timeout, Deny, Allow, setting off); a real Junie run with `--config-location <scratch>`.

### WP-40 — Gemini CLI / Antigravity CLI · owner: integration-engineer · deps: WP-38 · status: `proposed`
- Mapping (`BeforeAgent`, `AfterAgent`, `Before/AfterTool`, `PreCompress`, `Notification`) and the installer for `~/.gemini/settings.json`, plus the Antigravity CLI `hooks.json` (verify the path and event names first; timeouts in ms). No permission cards.
- AC: draft REQ-22 AC1–AC3 for Gemini / Antigravity; `Notification` (ToolPermission) gives `needsInput`; round-trip tests.

### WP-41 — Panel agent tag and "+ New" per agent · owner: macos-ui-engineer · deps: WP-37 · status: `proposed`
- A 2-letter tag (`CC`, `CX`, `GM`, `JN`) before the project name, hidden while every session is Claude Code; a "+ New" submenu per installed agent with the REQ-18 quoting rules (`11` P3 "UI").
- AC: draft REQ-22 AC2; the REQ-18 AC2 quoting test extended to the other commands; the panel still truncates (REQ-14 AC3).

### WP-43 — Pet species: rig contract + Byte, Nib, Wisp, Mochi · owner: pet-animator · deps: WP-36 done · status: `proposed`
- The ADR-0010 role contract in `PetRig`, one builder per species, and `petSpecies` in config (Core change through core-engineer); `--render-poses <dir> --pet-species <s>` (next to `--pet-style`); the `add-pet-state` skill gains a per-species render step (`11` P1a, draft REQ-19).
- AC: draft REQ-19 AC1–AC4; the nine poses rendered per species and checked at notch size; mini mode and Reduce Motion per species; `perf-suite.sh` within budget.

### WP-44 — Pet colour, accessory, name · owner: pet-animator · deps: WP-43, WP-42 done · status: `proposed`
- `petColor` (presets plus `NSColorWell`, derived shade, eye-contrast rule), `petAccessory` on `hatAnchor`, and `petName` in the footer and tooltip (`11` P1b, draft REQ-20).
- AC: draft REQ-20 AC1–AC3; `AppConfigTests` for each key; badge and HP colours unchanged.

### WP-47 — Global hotkeys · owner: macos-ui-engineer · deps: WP-42 done · status: `proposed`
- Optional Carbon `RegisterEventHotKey` shortcuts: toggle the panel, Allow the top card (`11` P4c, draft REQ-25).
- AC: draft REQ-25; REQ-02 AC2 still holds; no Accessibility permission requested.

### WP-49 — Sound choice per cue · owner: macos-ui-engineer · deps: WP-42 done · status: `proposed`
- Per-cue system sound pickers, played through `afplay` (`11` P4e, REQ-12 AC4).
- AC: REQ-12 AC1–AC4 still hold with the defaults (Funk / Glass); config round-trip.

## Deferred
- Developer ID, hardened runtime and notarization (ADR-0008 upgrade path): only if Gatekeeper friction becomes a problem for users.
- Ghostty and Warp stay app-level focus (no scripting API).
- Universal binary / Intel: not planned (REQ-07).
- Update check: not wanted (no network calls, no polling).
- Plain-socket event server instead of `NWListener` (would trim the post-burst RSS, `08`).
