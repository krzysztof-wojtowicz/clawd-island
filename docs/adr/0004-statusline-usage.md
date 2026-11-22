# ADR-0004 — Usage (HP bar) from the statusline `rate_limits`

**Status:** accepted (user decision)

**Context:** The HP bar shows the remaining 5-hour subscription window. The only documented, machine-readable source is the statusline stdin field `rate_limits.five_hour.{used_percentage,resets_at}`, which is present for Pro and Max subscribers after the first API response. An undocumented OAuth usage endpoint exists, but it would require reading credentials from the Keychain.

**Decision:** Install `clawd-bridge statusline` as the Claude Code `statusLine` command. It forwards the JSON to the app and prints a status line. If the user already had a statusline, its command is saved and wrapped (the same stdin is piped through, and its output is printed). Never touch the Keychain, OAuth tokens, or undocumented endpoints.

**Amendment (WP-5.3):** the weekly window `rate_limits.seven_day.{used_percentage,resets_at}` is read from the same payload, for the panel's `WK` value. It is the same field family and needs no new source.

**Consequences:**
- Data freshness is tied to active sessions. After `resets_at` passes, the HP bar shows full and is marked stale.
- The user's own statusline keeps working through the wrapper, and uninstall restores it.
- Rejected: the OAuth endpoint (undocumented, credential access, can break without notice).
