# ClawdNotch — agent guide

Native macOS app: a Clawd-inspired pet living in the MacBook notch (or a virtual notch at the top of the main display) that mirrors Claude Code state, shows session counters and a 5-hour-usage "HP bar". Read `docs/01-vision.md` first if you are new.

## Golden rules
1. **Use the `ponytail` skill (level `full`) before every coding task.** Smallest complete change, no speculative abstractions.
2. **Follow `docs/10-code-style.md`.** Clean Swift 6, English `///` doc comments on types and non-trivial members, inline comments only for the *why*.
3. **Docs are the spec.** Requirements are `REQ-xx` (`docs/02`), work packages `WP-x` (`docs/09`), decisions `ADR-xxxx` (`docs/adr/`). Cite IDs in commits and reports. If code must diverge from a doc, update the doc in the same commit.
4. **Commit locally, never push.** No `git push`, no remotes. One logical change per commit.
5. **Never copy code from `rullerzhou-afk/clawd-on-desk`** (AGPL-3.0). Reading it for ideas is fine.

## Invariants (reviewer blocks on these)
- `ClawdCore` imports only Foundation and CoreGraphics (geometry types). No AppKit/SwiftUI/Network there — it must stay unit-testable.
- Hooks **never block or slow Claude Code**: HTTP hooks have a short timeout, the bridge never waits on the app, failures are silent.
- No reading Keychain, OAuth tokens or `~/.claude/.credentials*`. Usage comes only from the statusline `rate_limits` payload (ADR-0004).
- Event server binds to `127.0.0.1` only and checks the `X-Clawd-Token` header.
- Performance budget in `docs/08-performance.md` (idle CPU < 0.3 %, RSS < 40 MB, no polling except 30 s liveness, pet animated with Core Animation only).
- Editing `~/.claude/settings.json` is done only by the installer: backup first, idempotent, fully reversible.

## Toolchain
Swift 6.2 + **Command Line Tools only (no Xcode)**. Swift Package Manager, swift-testing (`import Testing`; XCTest is unavailable). No third-party dependencies.

## Commands

| Command | Purpose |
|---|---|
| `swift build` | Build all targets (debug) |
| `scripts/test.sh` | Run `ClawdCoreTests` (wraps `swift test`; with Command Line Tools only, plain `swift test` silently runs nothing) |
| `scripts/bundle.sh [debug\|release]` | Assemble + ad-hoc sign `dist/ClawdNotch.app` |
| `scripts/run.sh` | Kill running instance, bundle debug, launch |
| `scripts/simulate.sh <scenario>` | POST fake Claude Code hook events to the running app |
| `scripts/perf.sh [seconds]` | Sample CPU/RSS of the running app against the budget |
| `swift scripts/window-info.swift` | Print screens and the app's window level and bounds (no Screen Recording permission needed) |

### Environment gotchas
- The Claude Code Bash sandbox blocks localhost connections. Anything that talks to the app's event server (`simulate.sh`, `curl 127.0.0.1:…`, a real `claude` run with test hooks) must run with the sandbox disabled.
- `screencapture` fails unless the terminal has the Screen Recording permission. Use `window-info.swift` for geometry, and ask the user to look when visuals matter.
- Never test hooks against the real `~/.claude/settings.json`. Use `claude -p … --settings <scratch file>` instead.

## Repo map
```
Package.swift
Sources/ClawdCore/      pure logic: events, SessionStore, state machine, aggregator, usage   (owner: core-engineer)
Sources/ClawdNotch/     app: App/, Server/ (EventServer), Window/, Pet/, HUD/, Integration/
  Server/               NWListener HTTP endpoint                                            (owner: core-engineer)
  Window/, HUD/         NSPanel, notch geometry, SwiftUI HUD/panel/settings                 (owner: macos-ui-engineer)
  Pet/                  Core Animation Clawd, poses                                         (owner: pet-animator)
  Integration/          hook installer, terminal focus watcher                              (owner: integration-engineer)
Sources/clawd-bridge/   CLI: `hook session-start`, `statusline`                              (owner: integration-engineer)
Tests/ClawdCoreTests/   swift-testing
scripts/                bundle/run/simulate/perf
docs/                   spec (01–10) + adr/
.claude/agents|skills   multi-agent setup
```

## Working as an agent
- Orchestrator: follow the `orchestrate-wp` skill. Pick ready WPs from `docs/09-roadmap.md`, delegate by owner, review with `reviewer`, then commit.
- Specialist: stay inside the directories you own. If you need a change elsewhere (for example a new `ClawdCore` API), describe it in your report instead of editing it.
- Report back with: what changed (files), which `REQ`/`WP` it satisfies, how it was verified, and the ponytail closing line (what was skipped, and any risk).
- Useful skills: `build-and-run`, `simulate-claude-events`, `perf-check`, `add-pet-state`.
