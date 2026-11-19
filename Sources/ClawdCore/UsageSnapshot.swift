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

/// The HP bar's value: what is left of the 5-hour window (REQ-04).
public struct HitPoints: Equatable, Sendable {
    /// Colour band of the bar: 50 and above, 20–49, below 20 (REQ-04, docs/07 `hp.*` tokens).
    public enum Level: Sendable {
        case high, mid, low
    }

    /// Remaining percentage, 0–100.
    public let percent: Double
    /// The window has reset since the last report, so `percent` is an assumed 100 until fresh data arrives.
    public let isStale: Bool

    /// The band `percent` falls in; exactly 50 is still green and exactly 20 still yellow (REQ-04).
    public var level: Level {
        percent >= 50 ? .high : percent >= 20 ? .mid : .low
    }
}

extension UsageSnapshot {
    /// HP at `now`, or nil when usage is unknown (REQ-04 AC2). After `resetsAt` it is full and stale (AC3).
    public func hitPoints(now: Date) -> HitPoints? {
        guard let used = fiveHourUsedPercent else { return nil }
        if let resetsAt, resetsAt <= now { return HitPoints(percent: 100, isStale: true) }
        return HitPoints(percent: min(max(100 - used, 0), 100), isStale: false)
    }
}
