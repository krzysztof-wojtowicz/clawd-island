# 04 — State machine

Claude Code hooks give no explicit "thinking" signal, so the phases are **inferred** from the event sequence.

## Per-session states
`idle` · `thinking` · `usingTools` · `talking` · `needsInput` · `done` (plus `unread: Bool` and `failed: Bool` flags)

## Transitions
| Hook event (`hook_event_name`) | Condition | New state | Side effects |
|---|---|---|---|
| `SessionStart` (via bridge `/session-meta`) | — | `idle` | Create the session if unknown. The `source` may be startup, resume, clear, compact, or fork. Arrives through the bridge, because `SessionStart` has no http hooks. |
| `UserPromptSubmit` | — | `thinking` | `unread = false`, `failed = false` |
| `PreToolUse` | — | `usingTools` | Store `tool_name` (shown in the panel, for example "using Bash"). |
| `MessageDisplay` | — | `talking` | High-frequency event; the aggregate is debounced. |
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
- A `needsInput` session leaves that state on the next event whose row sets a new state (in practice `PostToolUse`, `PreToolUse`, `UserPromptSubmit`, `PermissionDenied`, or `Stop`). `Notification` of other types, `Subagent*` and unknown events leave it in place.
- **Talking decay:** if a session has been in `talking` (text) for 2 s with no new talking event, it returns to `thinking`. `usingTools` **never decays**: a long Bash run sends no events, so it stays until `PostToolUse`/`PostToolBatch`/`PostToolUseFailure` (→ `thinking`), `PermissionRequest` (→ `needsInput`), `Stop` or `UserPromptSubmit`. Implement this as a computed check against `lastTalkingAt` when building the snapshot. The app schedules a single one-shot re-evaluation 2 s after the last talking event. This is not a periodic timer.
- Events from subagents (`agent_id` present) update `lastEventAt` and the subagent counter. They never move the parent to `done`: `Stop` and `StopFailure` with an `agent_id` change nothing else.
- **Unknown sessions:** any event for an unknown `session_id` creates the session (the app may have started mid-session).

## Read tracking (REQ-10)
`unread` is cleared by `UserPromptSubmit`, by `markAllRead()`, or by `TerminalFocusWatcher` (see `05`), including right after a panel click has focused the session's tab (REQ-10 AC2). A panel click alone does not mark read. Clearing `unread` on a `done` session makes it `idle`.

## Liveness
- The bridge supplies `pid` (the Claude Code process). Every 30 s the app calls `kill(pid, 0)`. If that returns `ESRCH`, the session is removed.
- Sessions without a pid are removed after **6 h** with no events.

## Aggregate (what the pet shows)
```
no sessions                                   → sleeping
any needsInput                                → needsInput
any done && unread                            → done
any usingTools                                → usingTools
any talking                                   → talking
any thinking                                  → thinking
otherwise                                     → idle
```
- **What the pet shows:** never one particular session, always this aggregate. The most important state across all live sessions wins.
- `activeCount` = the number of live sessions (the number in the counter, REQ-04).
- The counter colour uses `hasNeedsInput` → red, `attentionCount > 0` → orange, `activeCount > 0` → blue, otherwise grey.
- `attentionCount` = the number of sessions that are `needsInput`, or `done && unread`. It is no longer displayed, but it still drives the counter colour, the pop-out, and "Mark all read".
- **Status counts** (`Snapshot.statusCounts`, shown as the three expanded counters; the UI adds idle + working into the first one) put each live session in exactly one bucket: `needsInput` → needsInput, `done && unread` → done, `thinking | usingTools | talking` → working, and everything else (`idle`, read `done`) → idle. The buckets add up to `activeCount`.
- **Pop-out trigger:** fires when `attentionCount` increases, or when the aggregate enters `done` or `needsInput`. The UI sees this as a `Snapshot.popToken` counter that increments, so the trigger is edge-based and the same transition never fires twice.

## Panel order
`Snapshot.sessions` is sorted in Core by rank, the same order as the aggregate:
`needsInput` → `done && unread` → `usingTools` → `talking` → `thinking` → `idle` (a read `done` counts as `idle`).
Within a rank, the newest `lastEventAt` comes first. The panel shows the first 5 and then "+n more", so only the least important sessions are hidden.

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
- The talking decay boundary (1.99 s vs 2.0 s), and `usingTools` not decaying.
- Panel order: rank first, then the newest `lastEventAt`.
- Status counts: one session per bucket state, and the sum equals `activeCount`.
- Subagent `Stop` does not mark the parent done.
- Liveness expiry, using an injected `isAlive` closure.
- `popToken` increments exactly once per qualifying edge.
