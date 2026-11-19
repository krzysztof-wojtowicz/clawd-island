# 03 — Architecture

## Overview
```
Claude Code ──(http hooks, POST JSON)──────────────▶ EventServer  127.0.0.1:47474 /hook
            ──(SessionStart command hook, async)──▶ clawd-bridge hook session-start ─▶ POST /session-meta
            ──(statusLine command)────────────────▶ clawd-bridge statusline ─────────▶ POST /statusline
                                                          └─ optionally runs the user's original statusline and prints its output
                                         │
                                         ▼  (decode → ClawdEvent, hop to MainActor)
            ┌──────────────────────── ClawdCore (Foundation + CG) ────────────────────────┐
            │ SessionStore  ── per-session StateMachine ── Aggregator ── UsageModel        │
            └──────────────────────────────────┬──────────────────────────────────────────┘
                                               ▼  @Observable AppModel (publishes only on change)
     NotchWindowController (NSPanel) ── PetView (CALayer Clawd) ── HUDView (SwiftUI) ── SessionPanel (SwiftUI)
                                               ▲
                         TerminalFocusWatcher (NSWorkspace activation + AppleScript tty)  → SessionStore.markRead
                         LivenessTimer (30 s, kill(pid, 0))                               → SessionStore.remove
```

## SPM targets
| Target | Kind | Depends on | Notes |
|---|---|---|---|
| `ClawdCore` | library | Foundation, CoreGraphics | Pure, deterministic and testable. Time is injected (`now: Date` parameters), never read from a global clock. |
| `ClawdNotch` | executable (app) | ClawdCore, AppKit, SwiftUI, QuartzCore, Network, ServiceManagement | The `.app` main binary. |
| `clawd-bridge` | executable (CLI) | Foundation | Bundled into `ClawdNotch.app/Contents/MacOS/`. It must start and exit in < 20 ms. |
| `ClawdCoreTests` | test | ClawdCore, Testing | swift-testing. |

## Key types (contracts)
- `ClawdEvent` (Core) is a decoded hook event: `sessionID`, `kind` (an enum mirroring the hook events we use), `cwd`, `toolName?`, `notificationType?`, `agentID?`, `receivedAt`.
- `SessionMeta` (Core) comes from the bridge on SessionStart: `sessionID`, `cwd`, `source` (startup, resume, clear, compact, or fork), `pid?`, `tty?`, `terminalBundleID?`, `termProgram?`. The process fields are optional because the bridge never fails, even when the process walk fails.
- `UsageSnapshot` (Core) holds `fiveHourUsedPercent?` and `resetsAt?`, taken from the statusline payload.
- `Session` (Core) holds `id`, `projectName` (the last path component of `cwd`), `state: SessionState`, `unread: Bool`, `meta?`, `lastEventAt`, `activeSubagents`.
- `SessionStore` (Core, `@MainActor` class or a plain struct owned by AppModel) has `apply(_:now:)`, `apply(meta:)`, `markRead(_:)`, `markAllRead()`, `expire(now:isAlive:)`, and returns `Snapshot`.
- `Snapshot` (Core, `Equatable`) holds `aggregate: PetState`, `activeCount`, `attentionCount`, `hasNeedsInput`, `sessions: [Session]`, and `usage: UsageSnapshot?`. **The UI renders only Snapshot.** An unchanged snapshot does not trigger a re-render.
- `PetState` (Core) is one of `sleeping`, `idle`, `thinking`, `talking`, `done`, or `needsInput` (see `04-state-machine.md`).
- `PetView` (App/Pet) is an `NSView` with a layer tree. Its API is `setState(_:)`, `popOut()`, and `setPaused(_:)`.
- `EventServer` (App/Server) is an `NWListener` that accepts `POST /hook`, `/session-meta`, and `/statusline`. It reads at most 64 KiB per body and requires the `X-Clawd-Token` header.

## Threading
- `EventServer` runs on its own serial `DispatchQueue`. It decodes there, then hops to `@MainActor` with a value type.
- Everything in the UI and all store mutation happen on the main actor. No locks are needed.
- Swift 6 strict concurrency must be on, with no `@unchecked Sendable` unless there is a `shortcut:` comment justifying it.

## Config and runtime files
- `~/Library/Application Support/ClawdNotch/config.json` holds the port, token, hide mode, focus-read mode, and the original statusline command (for uninstall and wrapping).
- `~/.claude/settings.json` is edited only by `HookInstaller` (see `05`). The backup goes to `~/.claude/settings.json.clawdnotch-backup-<timestamp>`.
- The bridge reads the port and token from the config file. If the file is missing, it exits silently.

## Extensibility for v2 (REQ-V2-01)
`EventServer` handles each connection independently, so a future `/permission` endpoint can keep a connection open until the user decides, or until a timeout. Nothing in v1 may assume that requests complete immediately.
