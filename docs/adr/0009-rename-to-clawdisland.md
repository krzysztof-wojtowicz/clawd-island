# ADR-0009 — Rename to ClawdIsland

**Status:** accepted (implementation: WP-28, REQ-15)

**Context:** The app is not only a notch decoration: the island grows wings, expands into a panel and shrinks to a mini peek, much like the iPhone's Dynamic Island. "ClawdNotch" also fits badly on Macs with a virtual notch.

**Decision:** The product, bundle and executable target are named **ClawdIsland**, with bundle id `dev.clawdisland.app`. `ClawdCore`, `clawd-bridge` and the `X-Clawd-Token` header keep their names (they say "Clawd", not "Notch"). The Application Support folder moves from `ClawdNotch/` to `ClawdIsland/` once at launch, only when the new folder is missing, so the token, port and `originalStatusLine` survive and uninstall can still restore the user's statusline. The signing certificate becomes "ClawdIsland Dev" (renamed to "ClawdIsland" in v6, WP-30; none exists yet, so there is nothing to migrate; ADR-0008 otherwise unchanged).

**Consequences:**
- The new bundle id is a new app to macOS: Automation, Accessibility and login-item grants are asked for again.
- Hooks are re-installed from Settings. `HookSettings` recognises the app's entries by shape, so the re-install replaces the old ones instead of duplicating them.
- Docs 03–08, scripts, `.claude/` and CLAUDE.md are renamed in WP-28; history (CHANGELOG, ADR-0007/0008 bodies) keeps the old name.

**Rejected:** keeping the old bundle id for permission continuity (the name and the identifier would disagree, and no signed build has shipped yet, so little is lost).
