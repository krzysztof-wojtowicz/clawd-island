// PermissionSuggestionTests.swift
// The first `permission_suggestions` entry kept for "Always allow" (WP-12, REQ-V2-01 AC7-AC9).

import Foundation
import Testing
@testable import ClawdCore

private func request(suggestions: String?) -> ClawdEvent {
    let extra = suggestions.map { #","permission_suggestions":\#($0)"# } ?? ""
    let json = #"{"hook_event_name":"PermissionRequest","session_id":"s","tool_name":"Bash","tool_input":{"command":"ls"}\#(extra)}"#
    return ClawdEvent(json: Data(json.utf8), receivedAt: Date(timeIntervalSince1970: 1))!
}

@Suite("Permission suggestion")
struct PermissionSuggestionTests {
    private let addRules = #"{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"rm -rf node_modules"}],"behavior":"allow","destination":"localSettings"}"#

    @Test("The first entry is kept as JSON with a readable rule")
    func present() throws {
        let suggestion = try #require(request(suggestions: "[\(addRules),{\"type\":\"setMode\",\"mode\":\"acceptEdits\"}]").suggestion)
        #expect(suggestion.rule == "Bash(rm -rf node_modules)")
        let object = try #require(JSONSerialization.jsonObject(with: Data(suggestion.json.utf8)) as? [String: Any])
        #expect(object["destination"] as? String == "localSettings")
        #expect(object["type"] as? String == "addRules")
    }

    @Test("A rule without content shows the tool name; other kinds show type and mode")
    func ruleText() {
        #expect(request(suggestions: #"[{"type":"addRules","rules":[{"toolName":"Read"}]}]"#).suggestion?.rule == "Read")
        #expect(request(suggestions: #"[{"type":"addDirectories","directories":["/a/b"],"destination":"session"}]"#).suggestion?.rule == "access to /a/b")
        #expect(request(suggestions: #"[{"type":"setMode","mode":"acceptEdits"}]"#).suggestion?.rule == "setMode acceptEdits")
    }

    @Test("Absent, empty, or malformed suggestions give nil", arguments: [nil, "[]", "{}", #"["x"]"#, "7", "null"])
    func absent(raw: String?) {
        #expect(request(suggestions: raw).suggestion == nil)
    }

    @Test("An entry over 2 KiB is dropped")
    func oversized() {
        let big = String(repeating: "x", count: 3000)
        #expect(request(suggestions: #"[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"\#(big)"}]}]"#).suggestion == nil)
    }

    @Test("The pending card carries the suggestion; other events never do")
    func pending() throws {
        var store = SessionStore()
        let event = request(suggestions: "[\(addRules)]")
        store.apply(event, now: .now)
        store.addPermission(id: UUID(), for: event)
        #expect(store.permissions.first?.suggestion == event.suggestion)
        let other = #"{"hook_event_name":"PreToolUse","session_id":"s","permission_suggestions":[\#(addRules)]}"#
        #expect(ClawdEvent(json: Data(other.utf8), receivedAt: .now)?.suggestion == nil)
    }
}
