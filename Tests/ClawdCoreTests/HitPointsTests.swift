// HitPointsTests.swift
// HP bar value, colour bands and the unknown/stale rules (WP-5, REQ-04 AC2–3).

import Foundation
import Testing
@testable import ClawdCore

private let t0 = Date(timeIntervalSince1970: 1_000)

@Suite("HitPoints")
struct HitPointsTests {
    @Test("HP is 100 minus used, clamped, banded at 50 and 20", arguments: [
        (37.0, 63.0, HitPoints.Level.high),
        (50.0, 50.0, .high),
        (51.0, 49.0, .mid),
        (80.0, 20.0, .mid),
        (81.0, 19.0, .low),
        (120.0, 0.0, .low),
        (-5.0, 100.0, .high),
    ])
    func value(used: Double, percent: Double, level: HitPoints.Level) {
        let hp = UsageSnapshot(fiveHourUsedPercent: used, resetsAt: t0 + 60).hitPoints(now: t0)
        #expect(hp == HitPoints(percent: percent, isStale: false))
        #expect(hp?.level == level)
    }

    @Test("Unknown usage yields no HP (REQ-04 AC2)")
    func unknown() {
        #expect(UsageSnapshot(fiveHourUsedPercent: nil, resetsAt: t0 + 60).hitPoints(now: t0) == nil)
    }

    @Test("Without resetsAt, HP is never stale")
    func noReset() {
        let usage = UsageSnapshot(fiveHourUsedPercent: 30, resetsAt: nil)
        #expect(usage.hitPoints(now: .distantFuture) == HitPoints(percent: 70, isStale: false))
    }

    @Test("After resetsAt, HP is full and stale (REQ-04 AC3)")
    func stale() {
        let usage = UsageSnapshot(fiveHourUsedPercent: 90, resetsAt: t0)
        #expect(usage.hitPoints(now: t0) == HitPoints(percent: 100, isStale: true))
    }
}
