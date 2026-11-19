# ADR-0002 — Claude Code → app transport: HTTP hooks

**Status:** accepted (verified in WP-0)

**Context:** Many hook events fire per turn (PreToolUse, PostToolUse, MessageDisplay). A command hook spawns a process per event. Claude Code supports `type: "http"` hooks, which POST the event JSON directly.

**Decision:**
- HTTP hooks go to `127.0.0.1:47474/hook` with `X-Clawd-Token` and `timeout: 2`.
- An empty 200 response is always returned.
- One extra async command hook on `SessionStart` (`clawd-bridge`) collects the pid, tty, and terminal app, which HTTP hooks cannot provide.

**Consequences:**
- Zero process spawns per event, and Network.framework on our side.
- Risk: the behaviour when the app is not running. Spike B must confirm a silent, fast failure. Fallback: keep http, document any visible noise, and consider an "app not running" uninstall prompt.
- Rejected: Unix domain socket (HTTP hooks cannot target one), and a file or FSEvents queue (latency, disk churn).

**Spike B result (2026-11-19, Claude Code 2.1.329, `claude -p --settings <scratch>`):**
- **App not running (connection refused):** total run time was 5.2 s, versus a 5.4 s baseline with no hooks, so there is no delay. Every event fails silently except `SessionEnd`, which prints one line: `SessionEnd hook [http://127.0.0.1:…/hook] failed: connect ECONNREFUSED`. Accepted.
- **App running (listener returns an empty 200):** UserPromptSubmit, PreToolUse, PostToolUse, MessageDisplay, Stop, and SessionEnd were all delivered, and the run stayed fast (2.9 s). The headers were `Content-Type: application/json`, `Content-Length`, `X-Clawd-Token`, and `Connection: keep-alive` (axios).
- **`SessionStart` does not support http hooks** (the docs say: "Only `type: "command"` and `type: "mcp_tool"` hooks are supported"). The command hook fires, including in `-p` mode. The `clawd-bridge` SessionStart hook is therefore also the transport for the start event.
- **Caveat for testing:** the Claude Code Bash sandbox blocks localhost. Hooks from a sandboxed `claude` hang until their timeout, so run such tests unsandboxed.
