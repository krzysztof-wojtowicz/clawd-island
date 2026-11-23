# 09 — Roadmap and work packages

**How to use this file:** the orchestrator (`orchestrate-wp` skill) picks every WP whose status is `todo` and whose dependencies are `done`, delegates it to the owner agent (in parallel only when file ownership is disjoint; use a worktree when files may overlap), has `reviewer` check it, makes one local commit per WP, and updates the status here in the same commit. Every WP that touches the app also runs the release `scripts/perf-suite.sh` within the `08` budget.

Status values: `proposed` (in `11-proposals.md`, not accepted yet; the orchestrator skips it) · `todo` · `in-progress` · `done` · `blocked(<reason>)`

WP format:
```
### WP-<n> — <title> · owner: <agent> · deps: <WPs or none> · status: `todo`
- What to build (cite REQ / ADR / doc sections).
- AC: the REQ acceptance criteria it satisfies, plus how it is verified.
```
New work packages continue from **WP-36** (WP-0…WP-35 built 1.0.0 and appear in git history).

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

## Release checklist (the user runs it)
1. Bump `version=` in `scripts/bundle.sh` and add a `CHANGELOG.md` entry.
2. `scripts/test.sh`
3. `scripts/package.sh`: it bundles a release build and must sign it with "ClawdIsland" (it refuses an ad-hoc build).
4. `gh release create v<version> dist/ClawdIsland-<version>.zip dist/ClawdIsland-<version>.zip.sha256`

## Next
WP-36 (pet styles Classic / Sharp / Cute) is pending on the `pet-variants` branch. The WPs below are `proposed` (`11-proposals.md`). Accepting one means moving its draft REQ into `02`, setting its ADR to `accepted`, and setting the WP to `todo`.

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

### WP-42 — Settings window redesign · owner: macos-ui-engineer · deps: none (the Agents tab lists Claude Code only until WP-38..40) · status: `proposed`
- An `NSTabViewController` with toolbar tabs General / Pet / Agents / Advanced, with a live `PetView` preview and a pose picker (`11` P2, draft REQ-21).
- AC: draft REQ-21 AC1–AC5; every 1.0 control kept; first run opens Agents; `scripts/perf-suite.sh` with Settings open stays within the `08` Settings exception.

### WP-43 — Pet species: rig contract + Byte, Nib, Wisp, Mochi · owner: pet-animator · deps: WP-36 merged · status: `proposed`
- The ADR-0010 role contract in `PetRig`, one builder per species, and `petSpecies` in config (Core change through core-engineer); `--render-poses <dir> --pet-species <s>`; the `add-pet-state` skill gains a per-species render step (`11` P1a, draft REQ-19).
- AC: draft REQ-19 AC1–AC4; the nine poses rendered per species and checked at notch size; mini mode and Reduce Motion per species; `perf-suite.sh` within budget.

### WP-44 — Pet colour, accessory, name · owner: pet-animator · deps: WP-43, WP-42 · status: `proposed`
- `petColor` (presets plus `NSColorWell`, derived shade, eye-contrast rule), `petAccessory` on `hatAnchor`, and `petName` in the footer and tooltip (`11` P1b, draft REQ-20).
- AC: draft REQ-20 AC1–AC3; `AppConfigTests` for each key; badge and HP colours unchanged.

### WP-45 — Do Not Disturb · owner: macos-ui-engineer · deps: none · status: `proposed`
- A menu and Settings toggle `dnd`, plus a screen-sharing signal, mute pop-outs and sounds (`11` P4a, draft REQ-23). Focus-mode detection only if it can be done without polling.
- AC: draft REQ-23; no new repeating timer (`08` rule 1).

### WP-46 — Poke reaction · owner: pet-animator · deps: none · status: `proposed`
- A one-shot "boop" Core Animation group on a pet click (`11` P4b, draft REQ-24).
- AC: draft REQ-24; no state change and no read; a blink only under Reduce Motion.

### WP-47 — Global hotkeys · owner: macos-ui-engineer · deps: WP-42 · status: `proposed`
- Optional Carbon `RegisterEventHotKey` shortcuts: toggle the panel, Allow the top card (`11` P4c, draft REQ-25).
- AC: draft REQ-25; REQ-02 AC2 still holds; no Accessibility permission requested.

### WP-48 — Context and cost per session · owner: core-engineer · deps: none · status: `proposed`
- Verify the statusline cost and context fields, decode them per session, and show them in the row tooltip (`11` P4d, `05`).
- AC: decoder tests with and without the fields; nothing shown for other agents.

### WP-49 — Sound choice per cue · owner: macos-ui-engineer · deps: WP-42 · status: `proposed`
- Per-cue system sound pickers, played through `afplay` (`11` P4e, REQ-12 AC4).
- AC: REQ-12 AC1–AC4 still hold with the defaults (Funk / Glass); config round-trip.

## Deferred
- Developer ID, hardened runtime and notarization (ADR-0008 upgrade path): only if Gatekeeper friction becomes a problem for users.
- Ghostty and Warp stay app-level focus (no scripting API).
- Universal binary / Intel: not planned (REQ-07).
- Update check: not wanted (no network calls, no polling).
- Plain-socket event server instead of `NWListener` (would trim the post-burst RSS, `08`).
