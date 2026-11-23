# ADR-0009 — Other agents through clawd-bridge command adapters

**Status:** proposed (`11` P3)

**Context:** The P3 proposal adds Codex CLI, Gemini CLI (now Antigravity CLI) and Junie CLI. Claude Code reaches the app through HTTP hooks (ADR-0002). None of the three supports http hooks; they all run `command` hooks with the event JSON on stdin. Their event names and payloads are close to Claude Code's, but they differ in the details, and so do their permission semantics:
- Codex: the same decision JSON as Claude Code.
- Gemini: no permission hook at all.
- Junie: decides by exit code, and **exit 0 approves**.

None of them reports subscription usage the way Claude Code's statusline `rate_limits` does (ADR-0004).

**Decision:**
- Each agent's hooks run `clawd-bridge hook <agent> <event>`. The bridge maps the payload to the existing `/hook` shape with Claude Code event names, adds an `agent` field, POSTs it with a 300 ms timeout and exits. The app gets no new endpoint. `SessionStart` goes through `/session-meta` with the process walk, which gains a per-agent executable list.
- Core adds `Session.agent` and keys sessions by agent plus `session_id`. The state machine (`04`) is unchanged; agent events map onto existing transitions.
- Permissions: a held `PermissionRequest` keeps the ADR-0006 exception, and the bridge waits instead of the app's connection. This is enabled per agent only after it is verified that the agent's own prompt runs in parallel. "No decision" always means the agent's normal dialog: an empty stdout with exit 0 for Codex, **exit 1** for Junie (never 0). Gemini gets no cards.
- One installer per agent, with the same rules as `HookInstaller` (`05`): backup, idempotent, reversible, recognised by a command containing `clawd-bridge`, never writing a file it failed to parse. Codex hooks go into `~/.codex/hooks.json`, never into `config.toml`.
- HP / WK stay Claude Code only. Nothing is estimated for other agents.

**Consequences:**
- One process spawn per event for these agents (a few ms each, within the bridge's < 20 ms budget). This is acceptable for them, while Claude Code keeps the cheaper http path.
- Adding a further agent (Copilot CLI, Cursor, opencode, …) means one mapping table, one executable name and one installer.
- The Junie exit-code rule is a safety rule: a bug there would silently approve tool calls. It gets an explicit test for every bridge exit path.
- Rejected: a separate daemon per agent (more processes, more RSS); polling agent log files (`08` rule 1); editing TOML (needs a writer we do not want to own).
