// EventRequestTests.swift
// Event server request checks: head parsing, token, route, size limits and body decoding (docs/05).

import Foundation
import Testing
@testable import ClawdCore

private func head(_ lines: String...) -> HTTPRequestHead? {
    HTTPRequestHead(Data(lines.joined(separator: "\r\n").utf8))
}

@Suite("Event requests")
struct EventRequestTests {
    @Test("Header names are case-insensitive and values are trimmed")
    func parsesHead() throws {
        let parsed = try #require(head("POST /hook HTTP/1.1", "x-CLAWD-token:  secret ", "Content-Length: 12"))
        #expect(parsed.method == "POST")
        #expect(parsed.path == "/hook")
        #expect(parsed.headers["x-clawd-token"] == "secret")
        #expect(parsed.headers["content-length"] == "12")
    }

    @Test("A malformed request line is rejected")
    func malformed() {
        #expect(head("GARBAGE") == nil)
    }

    @Test("Verdicts", arguments: [
        (["POST /hook HTTP/1.1", "X-Clawd-Token: t", "Content-Length: 5"], HeadVerdict.readBody(.hook, length: 5)),
        (["POST /session-meta HTTP/1.1", "X-Clawd-Token: t", "Content-Length: 0"], .readBody(.sessionMeta, length: 0)),
        (["POST /statusline HTTP/1.1", "X-Clawd-Token: t"], .readBody(.statusline, length: 0)),
        (["POST /hook HTTP/1.1", "X-Clawd-Token: wrong", "Content-Length: 5"], .reject(status: 401)),
        (["POST /hook HTTP/1.1", "Content-Length: 5"], .reject(status: 401)),
        (["POST /nope HTTP/1.1", "X-Clawd-Token: wrong"], .reject(status: 401)),
        (["POST /nope HTTP/1.1", "X-Clawd-Token: t"], .reject(status: 404)),
        (["GET /hook HTTP/1.1", "X-Clawd-Token: t"], .reject(status: 404)),
        (["POST /hook HTTP/1.1", "X-Clawd-Token: t", "Content-Length: 65536"], .readBody(.hook, length: 65536)),
        (["POST /hook HTTP/1.1", "X-Clawd-Token: t", "Content-Length: 65537"], .reject(status: 413)),
        (["POST /hook HTTP/1.1", "X-Clawd-Token: t", "Content-Length: -1"], .reject(status: 400)),
        (["POST /hook HTTP/1.1", "X-Clawd-Token: t", "Content-Length: x"], .reject(status: 400)),
    ])
    func verdicts(lines: [String], expected: HeadVerdict) throws {
        let parsed = try #require(HTTPRequestHead(Data(lines.joined(separator: "\r\n").utf8)))
        #expect(parsed.verdict(token: "t") == expected)
    }

    @Test("Each endpoint decodes its own payload")
    func decodesBodies() {
        let now = Date(timeIntervalSince1970: 1)
        let hook = EventEndpoint.hook.decode(Data(#"{"hook_event_name":"Stop","session_id":"a"}"#.utf8), receivedAt: now)
        #expect(hook == .event(ClawdEvent(sessionID: "a", kind: .stop, cwd: nil, toolName: nil,
                                          notificationType: nil, agentID: nil, receivedAt: now)))
        let meta = EventEndpoint.sessionMeta.decode(Data(#"{"session_id":"a","cwd":"/p"}"#.utf8), receivedAt: now)
        if case .meta(let decoded) = meta { #expect(decoded.sessionID == "a") } else { Issue.record("not meta") }
        let usage = EventEndpoint.statusline.decode(
            Data(#"{"rate_limits":{"five_hour":{"used_percentage":40}}}"#.utf8), receivedAt: now)
        #expect(usage == .statusline(
            usage: UsageSnapshot(fiveHourUsedPercent: 40, resetsAt: nil, sevenDayUsedPercent: nil, sevenDayResetsAt: nil),
            stats: nil))
    }

    @Test("Bodies with nothing to apply decode to nil", arguments: [EventEndpoint.hook, .sessionMeta, .statusline])
    func nothingToApply(endpoint: EventEndpoint) {
        #expect(endpoint.decode(Data("{}".utf8), receivedAt: .now) == nil)
        #expect(endpoint.decode(Data("not json".utf8), receivedAt: .now) == nil)
    }

    @Test("Inbound messages reach the store")
    func appliesInbound() {
        var store = SessionStore()
        let now = Date(timeIntervalSince1970: 1)
        store.apply(.event(ClawdEvent(sessionID: "a", kind: .userPromptSubmit, cwd: "/p", toolName: nil,
                                      notificationType: nil, agentID: nil, receivedAt: now)), now: now)
        store.apply(.statusline(
            usage: UsageSnapshot(fiveHourUsedPercent: 5, resetsAt: nil, sevenDayUsedPercent: nil, sevenDayResetsAt: nil),
            stats: nil), now: now)
        let snapshot = store.snapshot(now: now)
        #expect(snapshot.aggregate == .thinking)
        #expect(snapshot.usage?.fiveHourUsedPercent == 5)
    }
}
