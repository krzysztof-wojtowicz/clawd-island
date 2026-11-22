---
name: simulate-claude-events
description: Send fake Claude Code hook / statusline events to the running ClawdNotch app to exercise pet states, counters, HP bar and pop-outs without running real Claude Code sessions. Use when testing or demoing any state-related behaviour.
---

# Simulate Claude Code events

`scripts/simulate.sh <scenario> [session_id]` reads the port and token from `~/Library/Application Support/ClawdNotch/config.json` and POSTs JSON with `curl` to `/hook`, `/session-meta`, and `/statusline`.

Scenarios. Implement all of these in WP-0/WP-4 and keep this list in sync with the script:
| Scenario | Sends | Expected pet state |
|---|---|---|
| `start` | `/session-meta` (how SessionStart arrives in production) | idle |
| `think` | UserPromptSubmit | thinking |
| `tool` | PreToolUse(Bash) | usingTools (hammer strike; never decays, ends on PostToolUse/Stop) |
| `tools` | think → PreToolUse(Bash) → hold 4 s → PostToolUse → Stop | thinking → usingTools (hammer) → done |
| `text` | MessageDisplay ×5, 200 ms apart | talking |
| `permission` | PermissionRequest | needsInput (red !) |
| `done` | Stop | done (paw raised) + pop-out |
| `fail` | StopFailure | done (failed) |
| `compact` | think → PreCompact → hold 6 s → `/session-meta` with `source: compact` | thinking → compacting (broom, dust) → idle |
| `subagents` | SubagentStart ×2, hold, SubagentStop ×2 | juggling (3 balls) → previous state. Planned, added in WP-17 |
| `end` | SessionEnd | session removed |
| `usage <pct>` | statusline with `rate_limits.five_hour.used_percentage=<pct>` | HP = 100 − pct |
| `turn` | think → tool → text → done, with realistic delays | full cycle |
| `multi` | 3 sessions in different states | counters 3 active / correct attention |
| `burst` | 50 events/s for 10 s | for perf-check |

The default `session_id` is `sim-1`. Pass a different one to simulate parallel sessions.

Manual one-off example:
```bash
curl -s -X POST "http://127.0.0.1:$PORT/hook" -H "X-Clawd-Token: $TOKEN" \
  -d '{"hook_event_name":"Stop","session_id":"sim-1","cwd":"/tmp/demo"}'
```
The Claude Code sandbox blocks localhost, so run this script with the sandbox disabled.

After sending events, verify with a screenshot (the `build-and-run` skill). For logic, prefer unit tests in `ClawdCoreTests`.
