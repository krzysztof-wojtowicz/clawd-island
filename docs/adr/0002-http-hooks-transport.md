# ADR-0002 — Claude Code → app transport: HTTP hooks

**Status:** accepted (pending WP-0 Spike B verification)

**Context:** Many hook events fire per turn (PreToolUse, PostToolUse, MessageDisplay). A command hook spawns a process per event. Claude Code supports `type: "http"` hooks, which POST the event JSON directly.

**Decision:**
- HTTP hooks go to `127.0.0.1:47474/hook` with `X-Clawd-Token` and `timeout: 2`.
- An empty 200 response is always returned.
- One extra async command hook on `SessionStart` (`clawd-bridge`) collects the pid, tty, and terminal app, which HTTP hooks cannot provide.

**Consequences:**
- Zero process spawns per event, and Network.framework on our side.
- Risk: the behaviour when the app is not running. Spike B must confirm a silent, fast failure. Fallback: keep http, document any visible noise, and consider an "app not running" uninstall prompt.
- Rejected: Unix domain socket (HTTP hooks cannot target one), and a file or FSEvents queue (latency, disk churn).

**Spike B result:** _to be filled in WP-0_
