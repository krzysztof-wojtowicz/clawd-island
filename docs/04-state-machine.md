# 04 — State machine

Claude Code hooks give no explicit "thinking" signal, so the phases are **inferred** from the event sequence.

## Per-session states
`idle` · `thinking` · `talking(.tool | .text)` · `needsInput` · `done` (plus `unread: Bool` and `failed: Bool` flags)

## Transitions
| Hook event (`hook_event_name`) | Condition | New state | Side effects |
|---|---|---|---|
| `SessionStart` (via bridge `/session-meta`) | — | `idle` | Create the session if unknown. The `source` may be startup, resume, clear, compact, or fork. Arrives through the bridge, because `SessionStart` has no http hooks. |
| `UserPromptSubmit` | — | `thinking` | `unread = false`, `failed = false` |
| `PreToolUse` | — | `talking(.tool)` | Store `tool_name` (used for the tooltip only). |
| `MessageDisplay` | — | `talking(.text)` | High-frequency event; the aggregate is debounced. |
| `PostToolUse`, `PostToolBatch`, `PostToolUseFailure` | — | `thinking` | |
| `PreCompact` | — | `thinking` | |
| `PermissionRequest` | — | `needsInput` | |
| `Notification` | `notification_type` ∈ {`permission_prompt`, `elicitation_dialog`, `agent_needs_input`} | `needsInput` | |
| `Notification` | `idle_prompt` | unchanged | If the session is `done`, it stays `done`. |
| `PermissionDenied` | state == `needsInput` | `thinking` | |
| `SubagentStart` / `SubagentStop` | — | unchanged | `activeSubagents ± 1` (floored at 0) |
| `Stop` | event has no `agent_id` | `done` | `unread = true` |
| `StopFailure` | — | `done` | `unread = true`, `failed = true` |
| `SessionEnd` | — | (removed) | |
| any unknown event | — | unchanged | Update `lastEventAt` only. Never crash on unknown input. |

Notes:
- A `needsInput` session leaves that state on the next `PostToolUse`, `PreToolUse`, `UserPromptSubmit`, `PermissionDenied`, or `Stop`.
- **Talking decay:** if a session has been in `talking` for 2 s with no new talking event, it returns to `thinking`. Implement this as a computed check against `lastTalkingAt` when building the snapshot. The app schedules a single one-shot re-evaluation 2 s after the last talking event. This is not a periodic timer.
- Events from subagents (`agent_id` present) update `lastEventAt` and the subagent counter. They never move the parent to `done`.
- **Unknown sessions:** any event for an unknown `session_id` creates the session (the app may have started mid-session).

## Read tracking (REQ-10)
`unread` is cleared by `UserPromptSubmit`, by `markRead(id)` (a panel click), by `markAllRead()`, or by `TerminalFocusWatcher` (see `05`). Clearing `unread` on a `done` session makes it `idle`.

## Liveness
- The bridge supplies `pid` (the Claude Code process). Every 30 s the app calls `kill(pid, 0)`. If that returns `ESRCH`, the session is removed.
- Sessions without a pid are removed after **6 h** with no events.

## Aggregate (what the pet shows)
```
no sessions                                   → sleeping
any needsInput                                → needsInput
any done && unread                            → done
any talking                                   → talking
any thinking                                  → thinking
otherwise                                     → idle
```
- `activeCount` = the number of live sessions.
- `attentionCount` = the number of sessions that are `needsInput`, or `done && unread`.
- **Pop-out trigger:** fires when `attentionCount` increases, or when the aggregate enters `done` or `needsInput`. The UI sees this as a `Snapshot.popToken` counter that increments, so the trigger is edge-based and the same transition never fires twice.

## Sample payloads (trimmed)
```json
{"hook_event_name":"UserPromptSubmit","session_id":"abc","cwd":"/Users/me/proj","prompt":"..."}
{"hook_event_name":"PreToolUse","session_id":"abc","tool_name":"Bash","tool_input":{},"tool_use_id":"t1"}
{"hook_event_name":"Notification","session_id":"abc","notification_type":"permission_prompt","message":"..."}
{"hook_event_name":"Stop","session_id":"abc","stop_hook_active":false,"last_assistant_message":"..."}
{"hook_event_name":"SessionEnd","session_id":"abc","reason":"prompt_input_exit"}
```
Decode leniently. Read only the fields we need, ignore extra fields, and drop large fields such as `tool_input`, `prompt`, and `last_assistant_message` without storing them.

## Tests (required, `Tests/ClawdCoreTests`)
- One test per transition-table row.
- Aggregate priority, using a table-driven test.
- The talking decay boundary (1.99 s vs 2.0 s).
- Subagent `Stop` does not mark the parent done.
- Liveness expiry, using an injected `isAlive` closure.
- `popToken` increments exactly once per qualifying edge.
