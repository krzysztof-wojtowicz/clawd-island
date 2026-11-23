# ADR-0002 — Claude Code → app transport: HTTP hooks

**Status:** accepted

**Context:** Many hook events fire per turn (PreToolUse, PostToolUse, MessageDisplay). A command hook spawns a process per event. Claude Code supports `type: "http"` hooks, which POST the event JSON directly.

**Decision:**
- HTTP hooks go to `127.0.0.1:47474/hook` with `X-Clawd-Token` and `timeout: 2` (`PermissionRequest`: 120, ADR-0006).
- An empty 200 is always returned (except a decided `PermissionRequest`).
- `SessionStart` does not support http hooks ("Only `type: "command"` and `type: "mcp_tool"`"), so one async command hook (`clawd-bridge hook session-start`) delivers it, together with the pid, tty and terminal app that HTTP hooks cannot provide.

**Evidence** (Claude Code 2.1.329, `claude -p --settings <scratch>`):
- App not running (connection refused): no delay (5.2 s vs 5.4 s baseline). Every event fails silently except `SessionEnd`, which prints one `SessionEnd hook [...] failed: connect ECONNREFUSED` line. Accepted.
- App running: all events delivered, run stays fast. Headers: `Content-Type: application/json`, `Content-Length`, `X-Clawd-Token`, `Connection: keep-alive` (axios).
- The Claude Code Bash sandbox blocks localhost: hooks from a sandboxed `claude` hang until their timeout, so test unsandboxed.

**Consequences:** zero process spawns per event; Network.framework on our side.

**Rejected:** a Unix domain socket (HTTP hooks cannot target one), a file or FSEvents queue (latency, disk churn).
