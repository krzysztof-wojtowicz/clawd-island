# 09 — Roadmap and work packages

**How to use this file:** the orchestrator (`orchestrate-wp` skill) picks every WP whose status is `todo` and whose dependencies are `done`, delegates it to the owner agent (in parallel only when file ownership is disjoint; use a worktree when files may overlap), has `reviewer` check it, makes one local commit per WP, and updates the status here in the same commit. Every WP that touches the app also runs the release `scripts/perf-suite.sh` within the `08` budget.

Status values: `todo` · `in-progress` · `done` · `blocked(<reason>)`

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
No work packages are planned yet.

## Deferred
- Developer ID, hardened runtime and notarization (ADR-0008 upgrade path): only if Gatekeeper friction becomes a problem for users.
- Ghostty and Warp stay app-level focus (no scripting API).
- Universal binary / Intel: not planned (REQ-07).
- Update check: not wanted (no network calls, no polling).
- Plain-socket event server instead of `NWListener` (would trim the post-burst RSS, `08`).
