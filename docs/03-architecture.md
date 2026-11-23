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
            │ SessionStore ── Session.apply ── PetState(aggregating:) ── apply(usage:)    │
            └──────────────────────────────────┬──────────────────────────────────────────┘
                                               ▼  AppModel (publishes only on change)
     NotchWindowController (NSPanel) ── PetView (CALayer Clawd) ── HUDController ── CountersView + SessionPanelView (AppKit)
                                               ▲
                         TerminalFocusWatcher (NSWorkspace activation + AppleScript tty)  → SessionStore.markRead
                         EditorWindows (Accessibility: VS Code family + JetBrains windows) → focus / markRead
                         SoundCues (popToken edges → afplay)                           (REQ-12)
                         LivenessTimer (30 s, kill(pid, 0))                               → SessionStore.expire
```

## SPM targets
| Target | Kind | Depends on | Notes |
|---|---|---|---|
| `ClawdCore` | library | Foundation, CoreGraphics | Pure, deterministic and testable. Time is injected (`now: Date` parameters), never read from a global clock. |
| `ClawdIsland` | executable (app) | ClawdCore, AppKit, QuartzCore, Network, ServiceManagement | The `.app` main binary. No SwiftUI: a hosting view would break the RSS budget (`08`). |
| `clawd-bridge` | executable (CLI) | Foundation | Bundled into `ClawdIsland.app/Contents/MacOS/`. It must start and exit in < 20 ms. |
| `ClawdCoreTests` | test | ClawdCore, Testing | swift-testing. |

## Key types (contracts)
- `ClawdEvent` (Core) is a decoded hook event: `sessionID`, `kind` (an enum mirroring the hook events we use), `cwd`, `toolName?`, `notificationType?`, `agentID?`, `receivedAt`.
- `SessionMeta` (Core) comes from the bridge on SessionStart: `sessionID`, `cwd`, `source` (startup, resume, clear, compact, or fork), `pid?`, `tty?`, `terminalBundleID?`, `termProgram?`. The process fields are optional because the bridge never fails, even when the process walk fails.
- `UsageSnapshot` (Core) holds `fiveHourUsedPercent?`, `resetsAt?`, `sevenDayUsedPercent?`, and `sevenDayResetsAt?`, taken from the statusline payload's `rate_limits.five_hour` and `rate_limits.seven_day`.
- `Session` (Core) holds `id`, `projectName` (the last path component of `cwd`), `state: SessionState` (`idle · thinking · usingTools · talking · compacting · needsInput · done`; `juggling` is derived from `activeSubagents`, `04`), `unread: Bool`, `failed: Bool`, `meta?`, `toolName?`, `lastEventAt`, `activeSubagents`, and the computed `needsAttention` (the panel badge rule that `attentionCount` also uses).
- `SessionStore` (Core) is a plain struct owned by AppModel. It has `apply(_:now:)`, `apply(meta:now:)`, `apply(usage:)`, `markRead(_:)`, `markAllRead()`, `expire(now:isAlive:)` (removes dead pids, and pid-less sessions silent for 6 h), `nextDecayDeadline(now:)` (when to schedule the one-shot talking-decay re-evaluation), and `snapshot(now:) -> Snapshot` (mutating: it advances `popToken` against the previous snapshot).
- `Snapshot` (Core, `Equatable`) holds `aggregate: PetState`, `activeCount`, `attentionCount`, `hasNeedsInput`, `statusCounts` (idle, working, done, needsInput; see `04`; the UI shows idle + working as one counter), `sessions: [Session]` (sorted by importance, see `04` "Panel order"; talking decay applied), `usage: UsageSnapshot?`, `pendingPermissions: [PendingPermission]` (id, sessionID, project, tool name, input summary, `suggestion?` raw JSON for Always allow, received time; REQ-16) and `popToken: Int`. **The UI renders only Snapshot.** An unchanged snapshot does not trigger a re-render.
- `PetState` (Core) is one of `sleeping`, `idle`, `thinking`, `usingTools`, `talking`, `compacting`, `juggling`, `done`, or `needsInput` (see `04-state-machine.md`).
- `PetView` (App/Pet) is an `NSView` with a layer tree. Its API is `setState(_:)`, `popOut()`, `setPlacement(tilt:from:tiltChange:animated:)` (mini-mode peek) and `setPaused(_:)`.
- `HUDController` (App/HUD) renders each new `Snapshot` into `CountersView` (the left wing's session counter, which morphs into the three expanded counters on hover), the right wing's vertical HP bar (next to the pet), and `SessionPanelView` (expanded panel: the sorted session list and the usage footer). Both are plain AppKit views. `UsageSnapshot.hitPoints(now:)` (Core) is the single HP rule both views use.
- `SettingsWindowController` (App, `SettingsWindow.swift`) owns the plain AppKit Settings window (mini mode, focus-read, notch permissions, sound cues, hooks row via `HookInstaller`, Launch at login, first-run welcome); the right-click menu has no hooks or login items (`06`).
- `TerminalFocusWatcher`, `EditorWindows` (VS Code family and JetBrains window focus via Accessibility) and `NewSessionLauncher` live in App/Integration; `SoundCues` lives in App. All are event-driven.
- `EventServer` (App/Server) is an `NWListener` that accepts `POST /hook`, `/session-meta`, and `/statusline`. It reads at most 64 KiB per body and requires the `X-Clawd-Token` header.

## Threading
- `EventServer` runs on its own serial `DispatchQueue`. It decodes there, then hops to `@MainActor` with a value type.
- Everything in the UI and all store mutation happen on the main actor. The only cross-queue state, `Preferences.notchPermissions` (read per request on the server queue) and `PermissionResponder`'s once-flag, uses `OSAllocatedUnfairLock`.
- Swift 6 strict concurrency must be on, with no `@unchecked Sendable` unless there is a `shortcut:` comment justifying it.

## Config and runtime files
- `~/Library/Application Support/ClawdIsland/config.json` holds the port, token, mini mode (`miniMode`), focus-read mode, `notchPermissions`, `soundCues`, `recentProjects`, `onboarded` (first-run welcome shown, REQ-09 AC5), and the original statusline command (for uninstall and wrapping).
- `~/.claude/settings.json` is edited only by `HookInstaller` (see `05`). The backup goes to `~/.claude/settings.json.clawdisland-backup-<timestamp>`.
- The bridge reads the port and token from the config file. If the file is missing, it exits silently.
- `CLAWD_CONFIG_PATH` and `CLAWD_SETTINGS_PATH` redirect the app (and `--uninstall-hooks`) to scratch files for testing; set both together.

## Holding a request (REQ-16)
`EventServer` handles each connection independently and keeps a `PermissionRequest` connection open until the user decides, the 110 s cap, or a hang-up (ADR-0006). Nothing may assume that requests complete immediately.
