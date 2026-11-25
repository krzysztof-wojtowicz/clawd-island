// SessionStats.swift
// Per-session context use and cost read from the statusline payload (REQ-26, docs/05 "Context and cost").

import Foundation

/// One session's context use and cost as Claude Code reported them in its latest statusline payload.
/// Values are never estimated: a missing, null or mistyped field stays nil (REQ-26 AC2, AC3).
public struct SessionStats: Equatable, Sendable {
    public let sessionID: String
    /// Only used to name a session the store does not know yet.
    public let cwd: String?
    /// `context_window.used_percentage`, 0–100; null early in a session.
    public let contextUsedPercent: Double?
    /// `cost.total_cost_usd`, Claude Code's list-price estimate; resets on `/clear`.
    public let costUSD: Double?
}

extension SessionStats {
    /// Reads `session_id`, `context_window.used_percentage` and `cost.total_cost_usd` from a raw statusline body.
    /// Returns nil without a `session_id`, even when the numbers are present.
    public init?(statusline data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionID = object["session_id"] as? String, !sessionID.isEmpty
        else { return nil }
        let workspace = object["workspace"] as? [String: Any]
        self.init(
            sessionID: sessionID,
            cwd: workspace?["current_dir"] as? String ?? object["cwd"] as? String,
            // Clamped so a malformed value can never trap when the tooltip rounds it to an Int.
            contextUsedPercent: ((object["context_window"] as? [String: Any])?["used_percentage"] as? Double).map { min(max($0, 0), 100) },
            costUSD: ((object["cost"] as? [String: Any])?["total_cost_usd"] as? Double).map { max($0, 0) }
        )
    }
}
