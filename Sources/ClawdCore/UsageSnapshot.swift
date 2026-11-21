// UsageSnapshot.swift
// The 5-hour usage window read from the statusline `rate_limits` payload (ADR-0004).

import Foundation

/// The latest known usage windows (5-hour and 7-day). A window exists only when Claude Code reported it;
/// it is never fabricated (REQ-04 AC2).
public struct UsageSnapshot: Equatable, Sendable {
    /// Percentage of the 5-hour window already used, 0–100.
    public let fiveHourUsedPercent: Double?
    public let resetsAt: Date?
    /// Percentage of the 7-day window already used, 0–100.
    public let sevenDayUsedPercent: Double?
    public let sevenDayResetsAt: Date?
}

extension UsageSnapshot {
    /// Reads `rate_limits.{five_hour,seven_day}.{used_percentage,resets_at}` from a raw statusline body.
    /// Returns nil only when neither window yields a value (API plans, or before the first API response).
    public init?(statusline data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = object["rate_limits"] as? [String: Any]
        else { return nil }
        let fiveHour = Self.window(limits["five_hour"])
        let sevenDay = Self.window(limits["seven_day"])
        guard fiveHour != nil || sevenDay != nil else { return nil }
        self.init(fiveHourUsedPercent: fiveHour?.used, resetsAt: fiveHour?.resetsAt,
                  sevenDayUsedPercent: sevenDay?.used, sevenDayResetsAt: sevenDay?.resetsAt)
    }

    /// Reads one window object; nil when it is missing or carries neither field.
    private static func window(_ value: Any?) -> (used: Double?, resetsAt: Date?)? {
        guard let window = value as? [String: Any] else { return nil }
        let used = window["used_percentage"] as? Double
        let resetsAt = (window["resets_at"] as? Double).map(Date.init(timeIntervalSince1970:))
        guard used != nil || resetsAt != nil else { return nil }
        return (used, resetsAt)
    }

    /// What is left of one window at `now`: nil when usage is unknown, full and stale after `resetsAt`.
    private static func remaining(used: Double?, resetsAt: Date?, now: Date) -> HitPoints? {
        guard let used else { return nil }
        if let resetsAt, resetsAt <= now { return HitPoints(percent: 100, isStale: true) }
        return HitPoints(percent: min(max(100 - used, 0), 100), isStale: false)
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
        Self.remaining(used: fiveHourUsedPercent, resetsAt: resetsAt, now: now)
    }

    /// What is left of the 7-day window at `now` (REQ-04 AC5), or nil when that window is absent.
    /// After `sevenDayResetsAt` it is 100 and stale, same rule as `hitPoints(now:)`.
    public func weekRemaining(now: Date) -> HitPoints? {
        Self.remaining(used: sevenDayUsedPercent, resetsAt: sevenDayResetsAt, now: now)
    }
}
