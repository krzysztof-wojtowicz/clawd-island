// PermissionResponder.swift
// The one-shot handle for a held PermissionRequest connection (REQ-V2-01, ADR-0006).

import Foundation
import os

/// Answers one held `PermissionRequest` hook. `reply` takes effect exactly once; later calls are ignored,
/// so the user's click, the 110 s cap, and a closed connection can race safely.
// shortcut: the exactly-once and release logic is verified manually only, because the app target has no tests.
final class PermissionResponder: Sendable {
    /// What goes back to Claude Code.
    enum Decision: Sendable {
        case allow, deny
        /// Allow and save the given `permission_suggestions` entry (raw JSON object) as received.
        case alwaysAllow(suggestion: String)
        /// An empty 200: no decision, Claude Code falls back to the terminal dialog.
        case none

        /// The response body.
        var body: Data {
            switch self {
            case .allow:
                Data(#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#.utf8)
            case .deny:
                Data(#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied from ClawdIsland"}}}"#.utf8)
            case .alwaysAllow(let suggestion):
                Data(#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","updatedPermissions":[\#(suggestion)]}}}"#.utf8)
            case .none:
                Data()
            }
        }
    }

    /// Identifies this request in `PendingPermission.id`.
    let id = UUID()
    private let send: @Sendable (Decision) -> Void
    private let finished = OSAllocatedUnfairLock(initialState: false)

    init(send: @escaping @Sendable (Decision) -> Void) {
        self.send = send
    }

    /// Sends `decision` unless a reply was already sent. Safe from any thread.
    func reply(_ decision: Decision) {
        let first = finished.withLock { done -> Bool in
            defer { done = true }
            return !done
        }
        if first { send(decision) }
    }
}
