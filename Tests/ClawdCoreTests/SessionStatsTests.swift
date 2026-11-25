// SessionStatsTests.swift
// Per-session context and cost from the statusline: decoding, store application and the tooltip (REQ-26, WP-48).

import Foundation
import Testing
@testable import ClawdCore

private let t0 = Date(timeIntervalSince1970: 1_000)

private func stats(_ json: String) -> SessionStats? {
    SessionStats(statusline: Data(json.utf8))
}

@Suite("Session stats")
struct SessionStatsTests {
    @Test("Decodes context and cost for the payload's session", arguments: [
        (#"{"session_id":"a","context_window":{"used_percentage":64.4},"cost":{"total_cost_usd":1.2}}"#, 64.4, 1.2),
        (#"{"session_id":"a","context_window":{"used_percentage":64},"cost":{"total_cost_usd":3}}"#, 64, 3),
        (#"{"session_id":"a","cost":{"total_cost_usd":1.2}}"#, nil, 1.2),
        (#"{"session_id":"a","context_window":{"used_percentage":null},"cost":{"total_cost_usd":1.2}}"#, nil, 1.2),
        (#"{"session_id":"a","context_window":{"used_percentage":64}}"#, 64, nil),
        (#"{"session_id":"a"}"#, nil, nil),
        (#"{"session_id":"a","context_window":{"used_percentage":"64"},"cost":{"total_cost_usd":"1.2"}}"#, nil, nil),
        (#"{"session_id":"a","context_window":64,"cost":[1.2]}"#, nil, nil),
        (#"{"session_id":"a","context_window":{"used_percentage":1e300},"cost":{"total_cost_usd":-0.5}}"#, 100, 0),
    ] as [(String, Double?, Double?)])
    func decodes(json: String, context: Double?, cost: Double?) throws {
        let decoded = try #require(stats(json))
        #expect(decoded.sessionID == "a")
        #expect(decoded.contextUsedPercent == context)
        #expect(decoded.costUSD == cost)
    }

    @Test("No session_id gives nothing to attach")
    func needsSessionID() {
        #expect(stats(#"{"context_window":{"used_percentage":64},"cost":{"total_cost_usd":1.2}}"#) == nil)
        #expect(stats(#"{"session_id":"","cost":{"total_cost_usd":1.2}}"#) == nil)
        #expect(stats("not json") == nil)
    }

    @Test("The working directory comes from workspace.current_dir, else cwd")
    func workingDirectory() {
        #expect(stats(#"{"session_id":"a","workspace":{"current_dir":"/w/app"},"cwd":"/c"}"#)?.cwd == "/w/app")
        #expect(stats(#"{"session_id":"a","cwd":"/c"}"#)?.cwd == "/c")
    }

    @Test("A statusline body carries usage and stats together; rate_limits alone still decodes")
    func endpointDecoding() {
        let body = #"{"session_id":"a","rate_limits":{"five_hour":{"used_percentage":40}},"cost":{"total_cost_usd":2}}"#
        let usage = UsageSnapshot(fiveHourUsedPercent: 40, resetsAt: nil, sevenDayUsedPercent: nil, sevenDayResetsAt: nil)
        #expect(EventEndpoint.statusline.decode(Data(body.utf8), receivedAt: t0) == .statusline(
            usage: usage, stats: SessionStats(sessionID: "a", cwd: nil, contextUsedPercent: nil, costUSD: 2)))
        #expect(EventEndpoint.statusline.decode(Data(#"{"session_id":"a"}"#.utf8), receivedAt: t0) == .statusline(
            usage: nil, stats: SessionStats(sessionID: "a", cwd: nil, contextUsedPercent: nil, costUSD: nil)))
    }

    @Test("Stats land on their session without changing its state")
    func appliesToSession() throws {
        var store = SessionStore()
        store.apply(ClawdEvent(sessionID: "a", kind: .preToolUse, cwd: "/p/a", toolName: "Bash",
                               notificationType: nil, agentID: nil, receivedAt: t0), now: t0)
        store.apply(ClawdEvent(sessionID: "b", kind: .stop, cwd: "/p/b", toolName: nil,
                               notificationType: nil, agentID: nil, receivedAt: t0), now: t0)
        let before = store.snapshot(now: t0)
        store.apply(.statusline(usage: nil, stats: SessionStats(
            sessionID: "a", cwd: "/elsewhere", contextUsedPercent: 64, costUSD: 1.2)), now: t0)
        let after = store.snapshot(now: t0)
        let a = try #require(after.sessions.first { $0.id == "a" })
        #expect(a.state == .usingTools)
        #expect(a.projectName == "a")
        #expect(a.contextUsedPercent == 64 && a.costUSD == 1.2)
        #expect(after.sessions.first { $0.id == "b" } == before.sessions.first { $0.id == "b" })
        #expect(after.sessions != before.sessions, "new fields are part of ==, so the UI re-renders")
        #expect(after.aggregate == before.aggregate && after.popToken == before.popToken)
    }

    @Test("A later payload replaces both values, including with nil")
    func latestWins() {
        var store = SessionStore()
        store.apply(stats: SessionStats(sessionID: "a", cwd: nil, contextUsedPercent: 64, costUSD: 1.2), now: t0)
        store.apply(stats: SessionStats(sessionID: "a", cwd: nil, contextUsedPercent: nil, costUSD: 0.1), now: t0)
        let session = store.snapshot(now: t0).sessions.first
        #expect(session?.contextUsedPercent == nil)
        #expect(session?.costUSD == 0.1)
    }

    @Test("An unknown session is created idle, named after its directory")
    func createsUnknownSession() {
        var store = SessionStore()
        store.apply(stats: SessionStats(sessionID: "a", cwd: "/p/app", contextUsedPercent: 10, costUSD: nil), now: t0)
        let session = store.snapshot(now: t0).sessions.first
        #expect(session?.state == .idle)
        #expect(session?.projectName == "app")
        #expect(session?.unread == false)
    }

    @Test("Statusline without rate_limits keeps the last usage")
    func keepsUsage() {
        var store = SessionStore()
        let usage = UsageSnapshot(fiveHourUsedPercent: 30, resetsAt: nil, sevenDayUsedPercent: nil, sevenDayResetsAt: nil)
        store.apply(.statusline(usage: usage, stats: nil), now: t0)
        store.apply(.statusline(usage: nil, stats: SessionStats(
            sessionID: "a", cwd: nil, contextUsedPercent: nil, costUSD: 1)), now: t0)
        #expect(store.snapshot(now: t0).usage == usage)
    }

    @Test("Tooltip rounds percent to an integer and cost to cents, omitting missing parts", arguments: [
        (64.4, 1.2, "ctx 64% · $1.20"),
        (64.5, 1.234, "ctx 65% · $1.23"),
        (0.2, 0, "ctx 0% · $0.00"),
        (99.6, nil, "ctx 100%"),
        (nil, 12.345, "$12.35"),
        (nil, nil, nil),
    ] as [(Double?, Double?, String?)])
    func tooltip(context: Double?, cost: Double?, expected: String?) {
        var session = Session(id: "a", cwd: nil, now: t0)
        session.contextUsedPercent = context
        session.costUSD = cost
        #expect(session.statsText == expected)
    }
}
