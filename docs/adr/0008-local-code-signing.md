# ADR-0008 — Sign with a local self-signed identity

**Status:** accepted

**Context:** The app is ad-hoc signed, so its code identity changes on every build. macOS ties Automation (Terminal, iTerm2), Accessibility (editor window focus) and login-item grants to that identity, so every rebuild can silently drop them. A Developer ID costs a paid Apple Developer membership.

**Decision:** `scripts/make-signing-cert.sh` creates a "ClawdIsland" code-signing certificate in the login keychain once (the user runs it, because trusting it asks for the login password). `bundle.sh` signs with it when present and falls back to ad-hoc otherwise, printing which. Every release is signed with it, and `package.sh` refuses an ad-hoc build unless `--adhoc` is given.

**Consequences:**
- Grants survive rebuilds on this Mac.
- Other Macs see a Gatekeeper warning on each downloaded copy: macOS 15+ needs Privacy & Security → Open Anyway once per download (or `xattr -dr com.apple.quarantine`). There is no hardened runtime and no notarization yet.
- Users' Automation / Accessibility grants are stable across updates only when every release is signed with the same certificate.
- The private key lives only in the user's login keychain: back it up (export the identity), or after a lost key every user must re-grant permissions.
- Upgrade path: a Developer ID identity plus hardened runtime (with the `com.apple.security.automation.apple-events` entitlement) and `notarytool` (`09`, Deferred).
- Rejected: staying ad-hoc (grants keep resetting).
