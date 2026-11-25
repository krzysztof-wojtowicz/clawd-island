# ClawdIsland — agent guide

Native macOS app (Apple silicon, macOS 14+): a Clawd-inspired pet living in the MacBook notch (or a virtual notch at the top of the main display) that mirrors Claude Code state, shows a session counter and a 5-hour-usage "HP bar". Read `docs/01-vision.md` first if you are new.

**Status:** **1.1.0 is released on GitHub** (version set in `scripts/bundle.sh`): its work packages are in `docs/09-roadmap.md` "1.1.0" (WP-36, 42, 45, 46, 48, 50–52), and its requirements are the items marked "(1.1.0)" in `docs/02`. New work packages continue from WP-53. The remaining post-1.0 proposals, with draft REQs and ADR-0009/0010, live in `docs/11-proposals.md`.

## Golden rules
1. **Use the `ponytail` skill (level `full`) before every coding task.** Smallest complete change, no speculative abstractions.
2. **Follow `docs/10-code-style.md`.** Clean Swift 6, English `///` doc comments on types and non-trivial members, inline comments only for the *why*.
3. **Docs are the spec.** Requirements are `REQ-xx` (`docs/02`), work packages `WP-x` (`docs/09`), decisions `ADR-xxxx` (`docs/adr/`). Cite IDs in commits and reports. If code must diverge from a doc, update the doc in the same commit.
4. **Commit locally, never push.** Pushing and publishing releases are the user's steps. One logical change per commit.
5. **Never copy code from `rullerzhou-afk/clawd-on-desk`** (AGPL-3.0). Reading it for ideas is fine.

## Invariants (reviewer blocks on these)
- `ClawdCore` imports only Foundation and CoreGraphics (geometry types). No AppKit/SwiftUI/Network there — it must stay unit-testable.
- Hooks **never block or slow Claude Code**: HTTP hooks have a short timeout, the bridge never waits on the app, failures are silent. Sole exception: a `PermissionRequest` held while the notch shows Allow/Deny (ADR-0006); the terminal dialog runs in parallel, so the user is never blocked.
- No reading Keychain, OAuth tokens or `~/.claude/.credentials*`. Usage comes only from the statusline `rate_limits` payload (ADR-0004).
- Event server binds to `127.0.0.1` only and checks the `X-Clawd-Token` header.
- Performance budget in `docs/08-performance.md` (CPU < 0.1 % sleeping and < 1 % animating, footprint < 20 MB and RSS < 45 MB steady, no polling except 30 s liveness, pet animated with Core Animation only).
- Editing `~/.claude/settings.json` is done only by the installer: backup first, idempotent, fully reversible.

## Toolchain
Swift 6.2 + **Command Line Tools only (no Xcode)**. Swift Package Manager, swift-testing (`import Testing`; XCTest is unavailable). No third-party dependencies.

## Commands

| Command | Purpose |
|---|---|
| `swift build` | Build all targets (debug) |
| `scripts/test.sh` | Run `ClawdCoreTests` (wraps `swift test`; with Command Line Tools only, plain `swift test` silently runs nothing) |
| `scripts/bundle.sh [debug\|release]` | Assemble + sign `dist/ClawdIsland.app` ("ClawdIsland" identity if present, else ad-hoc; ADR-0008) |
| `scripts/run.sh` | Kill running instance, bundle debug, launch |
| `scripts/simulate.sh <scenario>` | POST fake Claude Code hook events to the running app |
| `scripts/perf.sh [seconds]` | Sample CPU/RSS of the running app against the budget |
| `scripts/perf-suite.sh` | Every `08` scenario on a release bundle on a scratch port and token, one table |
| `scripts/record-gif.sh <island\|mini-mode>` | Record the README GIF into `docs/media/` (release bundle, scratch port; needs Screen Recording, sandbox off) |
| `scripts/install.sh` / `uninstall.sh` / `package.sh` | Install, remove, zip + sha256 a release build (agents test only against temp destinations; `package.sh` needs the signing identity or `--adhoc`) |
| `scripts/make-signing-cert.sh` | One-time local "ClawdIsland" signing identity; **the user runs it** (asks for the login password) |
| `swift scripts/window-info.swift` | Print screens and the app's window level and bounds (no Screen Recording permission needed) |

### Environment gotchas
- The Claude Code Bash sandbox blocks localhost connections. Anything that talks to the app's event server (`simulate.sh`, `curl 127.0.0.1:…`, a real `claude` run with test hooks) must run with the sandbox disabled.
- `screencapture` fails unless the terminal has the Screen Recording permission. Use `window-info.swift` for geometry, and ask the user to look when visuals matter.
- Never test hooks against the real `~/.claude/settings.json`. Use `claude -p … --settings <scratch file>` instead.
- To try Install, onboarding or `--uninstall-hooks` on the app, set both `CLAWD_SETTINGS_PATH` and `CLAWD_CONFIG_PATH` to scratch files (the bridge ignores them and reads the real config).
- Launch flags: `--open-settings [--close-settings-after <s>]` (perf-suite), `--uninstall-hooks` (uninstall.sh). Debug builds only: `--pet-demo`, `--render-poses <dir> [--pet-style roundy|sharpy]` (README pose GIFs: `.build/debug/ClawdIsland --render-poses docs/media --pet-style roundy`, and `--render-poses docs/media/sharpy --pet-style sharpy`; delete the unused `hero.gif` from both; `--pet-style` from WP-36), `--render-icon <dir>`, `--debug-auto-allow|deny|always` (answer permission cards automatically for e2e tests).

## Repo map
```
Package.swift
Sources/ClawdCore/      pure logic: events, SessionStore, state machine, aggregator, usage   (owner: core-engineer)
Sources/ClawdIsland/    app: App/, Server/ (EventServer), Window/, Pet/, HUD/, Integration/
  Server/               NWListener HTTP endpoint                                            (owner: core-engineer)
  App/, Window/, HUD/   app delegate, Settings, NSPanel, notch geometry, AppKit HUD/panel   (owner: macos-ui-engineer)
  Pet/                  Core Animation Clawd, poses                                         (owner: pet-animator)
  Integration/          terminal focus watcher, new-session launcher,
                        editor window focus (VS Code, JetBrains)                            (owner: integration-engineer)
Sources/clawd-bridge/   CLI: `hook session-start`, `statusline`                              (owner: integration-engineer)
Tests/ClawdCoreTests/   swift-testing
scripts/                bundle, install, uninstall, package, make-signing-cert              (owner: integration-engineer)
                        run, test, simulate, perf, perf-suite, record-gif, window-info      (owner: orchestrator)
.github/workflows/      CI: build, test, release build on macos-26                         (owner: integration-engineer)
docs/                   spec (01–10), proposals (11) + adr/
.claude/agents|skills   multi-agent setup
```

## Working as an agent
- Orchestrator: follow the `orchestrate-wp` skill. Pick ready WPs from `docs/09-roadmap.md`, delegate by owner, review with `reviewer`, then commit.
- Specialist: stay inside the directories you own. If you need a change elsewhere (for example a new `ClawdCore` API), describe it in your report instead of editing it.
- Report back with: what changed (files), which `REQ`/`WP` it satisfies, how it was verified, and the ponytail closing line (what was skipped, and any risk).
- Useful skills: `build-and-run`, `simulate-claude-events`, `perf-check`, `add-pet-state`.
