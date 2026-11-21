# ADR-0006 — Answer permission prompts from the notch

**Status:** accepted (implementation: WP-9)

**Context:** REQ-V2-01 asks for Allow/Deny in the notch. Claude Code's `PermissionRequest` hook can return a decision (`hookSpecificOutput.decision.behavior` = `allow` / `deny`). An HTTP hook that answers late must not cost the user anything in the terminal, and CLAUDE.md says hooks never block or slow Claude Code.

**Evidence** (2026-11-22, real `claude` 2.x in a pty, scratch `--settings`, a local hook server):
- The terminal permission dialog appeared 0.2 s after the hook request; it does **not** wait for the hook.
- A hook reply `allow` sent 8 s later was applied and closed the dialog.
- Answering in the terminal while the hook was still held worked normally.
- Docs: an empty 2xx body means "no decision"; timeouts, refused connections and non-2xx are non-blocking errors. `timeout` is in seconds (default 600).

**Decision:**
- Install the `PermissionRequest` hook with `timeout: 120`; every other hook keeps `timeout: 2`.
- `EventServer` holds a `PermissionRequest` connection while the notch shows a card, and replies with the decision JSON on an explicit click, or with an empty 200 after 110 s, when the session moves on, or when the feature is off.
- The app never decides automatically.

**Consequences:**
- The "hooks never block" invariant gets one documented exception: a held `PermissionRequest` does not block the user, because the terminal dialog runs in parallel and either answer wins.
- Sessions that cannot prompt (for example background subagents) wait for the notch for up to 120 s instead of being denied at once. That is the point of the feature.
- Existing installs keep `timeout: 2` until the hooks are reinstalled; then the app's hold is cut at 2 s (the card vanishes, nothing breaks).
- Rejected: a command hook through the bridge (the bridge must never wait on the app), and auto-expanding the panel on every request (too intrusive; the pet pops out and the card is one hover away).
