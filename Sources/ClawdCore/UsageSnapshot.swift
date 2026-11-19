// UsageSnapshot.swift
// The 5-hour usage window read from the statusline `rate_limits` payload (ADR-0004).

import Foundation

/// The latest known 5-hour usage window. It exists only when Claude Code reported one;
/// it is never fabricated (REQ-04 AC2).
public struct UsageSnapshot: Equatable, Sendable {
    /// Percentage of the 5-hour window already used, 0–100.
    public let fiveHourUsedPercent: Double?
    public let resetsAt: Date?
}

extension UsageSnapshot {
    /// Reads `rate_limits.five_hour.{used_percentage,resets_at}` from a raw statusline body.
    /// Returns nil when the window is absent (API plans, or before the first API response).
    public init?(statusline data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = object["rate_limits"] as? [String: Any],
              let window = limits["five_hour"] as? [String: Any]
        else { return nil }
        let used = window["used_percentage"] as? Double
        let resetsAt = (window["resets_at"] as? Double).map(Date.init(timeIntervalSince1970:))
        guard used != nil || resetsAt != nil else { return nil }
        self.init(fiveHourUsedPercent: used, resetsAt: resetsAt)
    }
}
