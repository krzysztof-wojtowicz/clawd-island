# ADR-0008 — Sign with a local self-signed identity

**Status:** accepted (implementation: WP-24)

**Context:** The app is ad-hoc signed, so its code identity changes on every build. macOS ties Automation (Terminal, iTerm2), Accessibility (editor window focus) and login-item grants to that identity, so every rebuild can silently drop them. A Developer ID costs a paid Apple Developer membership.

**Decision:** `scripts/make-signing-cert.sh` creates a "ClawdNotch Dev" code-signing certificate in the login keychain once (the user runs it, because trusting it asks for the login password). `bundle.sh` signs with it when present and falls back to ad-hoc otherwise, printing which.

**Consequences:**
- Grants survive rebuilds on this Mac.
- Other Macs see an unidentified-developer Gatekeeper warning (right-click → Open); there is no hardened runtime and no notarization yet.
- Upgrade path: a Developer ID identity plus hardened runtime (with the `com.apple.security.automation.apple-events` entitlement) and `notarytool` (`09`, Deferred).
- Rejected: staying ad-hoc (grants keep resetting).
