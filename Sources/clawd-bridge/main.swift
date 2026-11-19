// main.swift (clawd-bridge)
// CLI invoked by Claude Code hooks and the statusline; it forwards data to the app (docs/05).
// Subcommands are implemented in WP-4. Until then it must already honour the contract: never fail Claude Code.

import Foundation

// Contract from docs/05: always exit 0, whatever happens.
exit(0)
