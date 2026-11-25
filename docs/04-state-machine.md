# 04 — State machine

Claude Code hooks give no explicit "thinking" signal, so the phases are **inferred** from the event sequence.

## Per-session states
`idle` · `thinking` · `usingTools` · `talking` · `compacting` · `needsInput` · `done` (plus `unread: Bool` and `failed: Bool` flags). `juggling` is **derived**, not stored (below).

## Transitions
| Hook event (`hook_event_name`) | Condition | New state | Side effects |
|---|---|---|---|
| `/session-meta` with `source: "statusline"` | — | unchanged | Attach or refresh `meta` (and the project name). Create the session as `idle` if unknown. |
| `/statusline` with `session_id` (1.1.0) | — | unchanged | Replace `contextUsedPercent` and `costUSD` with the payload's values (nil when absent or null; REQ-26). Create the session as `idle` if unknown, named after `workspace.current_dir` (or `cwd`). |
| `SessionStart` (via bridge `/session-meta`) | `source != compact` | `idle` | Create the session if unknown. The `source` may be startup, resume, clear, compact, or fork. Arrives through the bridge, because `SessionStart` has no http hooks. |
| `SessionStart` (via bridge) | `source == compact` | `idle` | Ends `compacting`. |
| `UserPromptSubmit` | — | `thinking` | `unread = false`, `failed = false`, `activeSubagents = 0` |
| `PreToolUse` | — | `usingTools` | Store `tool_name` (shown in the panel, for example "using Bash"; panel text for the new states: "compacting", "N subagents"). |
| `MessageDisplay` | — | `talking` if this event finds the talking streak ≥ 1.5 s old, else unchanged (1.1.0, below) | High-frequency event; the aggregate is debounced. Starts or extends the talking streak. |
| `PostToolUse`, `PostToolBatch`, `PostToolUseFailure` | — | `thinking` | |
| `PreCompact` | — | `compacting` | Left by the next state-setting event or `SessionStart(compact)`. |
| `PermissionRequest` | — | `needsInput` | If the app holds the request (REQ-16), add a `PendingPermission` with the input summary and `suggestion` (first `permission_suggestions` entry as raw JSON, at most 2 KiB, else nil). The card is removed by: a `PostToolUse` / `PostToolUseFailure` of the same session with the same `tool_name` and input summary (a `PermissionDenied` likewise, or for the whole session when it has no summary); `UserPromptSubmit`, `Stop`, `StopFailure` or `SessionEnd` of the session; the reply, a hang-up, the 110 s cap or session removal. `PreToolUse`, `MessageDisplay`, `PreCompact`, `Notification` and `Subagent*` leave it, because tools run in parallel. |
| `Notification` | `notification_type` ∈ {`permission_prompt`, `elicitation_dialog`, `agent_needs_input`} | `needsInput` | |
| `Notification` | `idle_prompt` | unchanged | If the session is `done`, it stays `done`. |
| `PermissionDenied` | state == `needsInput` | `thinking` | |
| `SubagentStart` / `SubagentStop` | — | unchanged | `activeSubagents ± 1` (floored at 0); drives the derived `juggling` |
| `Stop` | event has no `agent_id` | `done` | `unread = true`, `activeSubagents = 0` |
| `StopFailure` | — | `done` | `unread = true`, `failed = true`, `activeSubagents = 0` |
| `SessionEnd` | — | (removed) | |
| any unknown event | — | unchanged | Update `lastEventAt` only. Never crash on unknown input. |

Notes:
- A `needsInput` session leaves that state on the next event whose row sets a new state (in practice `PostToolUse`, `PreToolUse`, `UserPromptSubmit`, `PermissionDenied`, or `Stop`). `Notification` of other types, `Subagent*` and unknown events leave it in place.
- **Talking decay:** if a session has been in `talking` (text) for 2 s with no new talking event, it returns to `thinking`. `usingTools` **never decays**: a long Bash run sends no events, so it stays until `PostToolUse`/`PostToolBatch`/`PostToolUseFailure` (→ `thinking`), `PermissionRequest` (→ `needsInput`), `Stop` or `UserPromptSubmit`. Implement this as a computed check against `lastTalkingAt` when building the snapshot. The app schedules a single one-shot re-evaluation 2 s after the last talking event. This is not a periodic timer.
- **Talking streak (1.1.0, REQ-03 AC8):** a single `MessageDisplay` no longer makes a session `talking`. Each `MessageDisplay` starts or extends a streak: it starts a new one (`talkingStreakStart = now`) when the previous `MessageDisplay` is 2 s or more ago, or when any other state-setting event came after it; otherwise it extends the current one. The session is **promoted** to `talking` only when a `MessageDisplay` arrives while the streak is at least 1.5 s old (`now − talkingStreakStart ≥ 1.5 s`) and the previous `MessageDisplay` is less than 2 s ago: promotion needs evidence of continued writing, so there is no timed promotion and a single sentence followed by silence (for example a slow tool start) never shows `talking`. Until then the session keeps its previous state (`thinking`, `usingTools`, …). Any other state-setting event (`PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `Stop`, …) resets the streak. The 2 s talking decay and its one-shot `nextDecayDeadline` (set only once `talking`) are unchanged; there is no new timer. So a sentence between tool calls or subagent runs neither shows `talking` nor pops out mini mode.
- Events from subagents (`agent_id` present) update `lastEventAt` and the subagent counter. They never move the parent to `done`: `Stop` and `StopFailure` with an `agent_id` change nothing else.
- **Derived `juggling`:** a session whose `activeSubagents > 0` and whose state is not `needsInput` or `done` shows as `juggling` (computed in the snapshot, like talking decay). The counter resets on `Stop`, `StopFailure` and `UserPromptSubmit`, so a missed `SubagentStop` cannot stick.
- **`compacting`** does not decay; it ends on the next row that sets a state, or on `SessionStart(compact)` → `idle`.
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
any juggling (derived)                        → juggling
any compacting                                → compacting
any usingTools                                → usingTools
any talking                                   → talking
any thinking                                  → thinking
otherwise                                     → idle
```
- **What the pet shows:** never one particular session, always this aggregate. The most important state across all live sessions wins.
- `activeCount` = the number of live sessions (the number in the counter, REQ-04).
- The counter colour uses `hasNeedsInput` → red, `attentionCount > 0` → orange, `activeCount > 0` → blue, otherwise grey.
- `attentionCount` = the number of sessions that are `needsInput`, or `done && unread`. It is no longer displayed, but it still drives the counter colour, the pop-out, and "Mark all read".
- **Status counts** (`Snapshot.statusCounts`, shown as the three expanded counters; the UI adds idle + working into the first one) put each live session in exactly one bucket: `needsInput` → needsInput, `done && unread` → done, `thinking | usingTools | talking | compacting | juggling` → working, and everything else (`idle`, read `done`) → idle. The buckets add up to `activeCount`.
- **Pop-out trigger:** fires when `attentionCount` increases, or when the aggregate enters `done` or `needsInput`. The UI sees this as a `Snapshot.popToken` counter that increments, so the trigger is edge-based and the same transition never fires twice. In mini mode the window controller pops the island out on a `popToken` advance or when the aggregate enters `talking`, `done` or `needsInput` (REQ-05 AC1); `popToken` itself is unchanged. **(1.1.0)** The pop-out holds while the aggregate is `done` or `needsInput`, and the 3 s countdown starts only when it leaves both (REQ-05 AC2); a `talking` pop-out keeps the plain 3 s. Do Not Disturb suppresses the pop-out and the sound but not the snapshot (REQ-23).

## Panel order
`Snapshot.sessions` is sorted in Core by rank, the same order as the aggregate:
`needsInput` → `done && unread` → `juggling` → `compacting` → `usingTools` → `talking` → `thinking` → `idle` (a read `done` counts as `idle`).
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
- Talking streak (1.1.0): a `MessageDisplay` that finds the streak 1.49 s old keeps the previous state and one at 1.5 s promotes to `talking` (`MessageDisplay` at 0, 0.8 and 1.5 s promotes on the third); a single `MessageDisplay` followed by 3 s of silence never becomes `talking` and sets no `nextDecayDeadline`; a gap of 2 s starts a new streak; a `PreToolUse` in the middle resets it; the 2 s decay after promotion is unchanged.
- Panel order: rank first, then the newest `lastEventAt`.
- Status counts: one session per bucket state, and the sum equals `activeCount`.
- Subagent `Stop` does not mark the parent done.
- `PreCompact` → `compacting`; `SessionStart(compact)` → `idle`; another state-setting event also leaves `compacting`.
- `juggling`: derived when `activeSubagents > 0`; suppressed in `needsInput` and `done`; counter reset on `Stop`, `StopFailure`, `UserPromptSubmit`; never negative.
- Priority table includes `juggling` and `compacting`; panel order and status buckets match.
- `PendingPermission.suggestion`: kept when present and at most 2 KiB, nil otherwise.
- Liveness expiry, using an injected `isAlive` closure.
- `popToken` increments exactly once per qualifying edge.
