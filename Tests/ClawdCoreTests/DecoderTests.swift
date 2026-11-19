// DecoderTests.swift
// Lenient decoding of hook, session-meta and statusline payloads (WP-1, docs/04 sample payloads, docs/05).

import Foundation
import Testing
@testable import ClawdCore

private let received = Date(timeIntervalSince1970: 7)

private func decode(_ json: String) -> ClawdEvent? {
    ClawdEvent(json: Data(json.utf8), receivedAt: received)
}

@Suite("Decoders")
struct DecoderTests {
    @Test("Sample payloads from docs/04 decode to the right kind", arguments: [
        (#"{"hook_event_name":"UserPromptSubmit","session_id":"abc","cwd":"/Users/me/proj","prompt":"..."}"#,
         ClawdEvent.Kind.userPromptSubmit),
        (#"{"hook_event_name":"PreToolUse","session_id":"abc","tool_name":"Bash","tool_input":{},"tool_use_id":"t1"}"#,
         .preToolUse),
        (#"{"hook_event_name":"Notification","session_id":"abc","notification_type":"permission_prompt","message":"..."}"#,
         .notification),
        (#"{"hook_event_name":"Stop","session_id":"abc","stop_hook_active":false,"last_assistant_message":"..."}"#,
         .stop),
        (#"{"hook_event_name":"SessionEnd","session_id":"abc","reason":"prompt_input_exit"}"#, .sessionEnd),
    ])
    func samplePayloads(json: String, kind: ClawdEvent.Kind) {
        let decoded = decode(json)
        #expect(decoded?.kind == kind)
        #expect(decoded?.sessionID == "abc")
        #expect(decoded?.receivedAt == received)
    }

    @Test("Only the needed fields are kept")
    func fields() {
        let full = decode(#"""
            {"hook_event_name":"PreToolUse","session_id":"abc","cwd":"/Users/me/proj","tool_name":"Bash",
             "agent_id":"ag","tool_input":{"command":"ls"}}
            """#)
        #expect(full == ClawdEvent(sessionID: "abc", kind: .preToolUse, cwd: "/Users/me/proj", toolName: "Bash",
                                   notificationType: nil, agentID: "ag", receivedAt: received))
        #expect(decode(#"{"hook_event_name":"Notification","session_id":"abc","notification_type":"idle_prompt"}"#)?
            .notificationType == "idle_prompt")
    }

    @Test("Unknown events and mistyped optional fields are tolerated")
    func lenient() {
        #expect(decode(#"{"hook_event_name":"BrandNewEvent","session_id":"abc","x":1}"#)?.kind == .unknown)
        let mistyped = decode(#"{"hook_event_name":"PreToolUse","session_id":"abc","tool_name":42,"cwd":null}"#)
        #expect(mistyped?.kind == .preToolUse)
        #expect(mistyped?.toolName == nil)
        #expect(mistyped?.cwd == nil)
    }

    @Test("Bodies without an event name or session id are rejected", arguments: [
        "", "not json", "[]", #"{"session_id":"abc"}"#, #"{"hook_event_name":"Stop"}"#,
        #"{"hook_event_name":"Stop","session_id":""}"#, #"{"hook_event_name":"Stop","session_id":5}"#,
    ])
    func rejected(json: String) {
        #expect(decode(json) == nil)
    }

    @Test("Session meta decodes all fields, and only session_id and cwd are required")
    func sessionMeta() {
        let full = SessionMeta(json: Data(#"""
            {"session_id":"abc","cwd":"/p","source":"resume","pid":4242,"tty":"/dev/ttys003",
             "terminal_bundle_id":"com.googlecode.iterm2","term_program":"iTerm.app","extra":true}
            """#.utf8))
        #expect(full == SessionMeta(sessionID: "abc", cwd: "/p", source: "resume", pid: 4242, tty: "/dev/ttys003",
                                    terminalBundleID: "com.googlecode.iterm2", termProgram: "iTerm.app"))
        let minimal = SessionMeta(json: Data(#"{"session_id":"abc","cwd":"/p","pid":"oops"}"#.utf8))
        #expect(minimal?.pid == nil)
        #expect(minimal?.source == nil)
        #expect(SessionMeta(json: Data(#"{"session_id":"abc"}"#.utf8)) == nil)
    }

    @Test("Statusline rate_limits.five_hour becomes a UsageSnapshot")
    func statusline() {
        let usage = UsageSnapshot(statusline: Data(#"""
            {"model":{"display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":37.5,"resets_at":1750000000},
             "seven_day":{"used_percentage":10}}}
            """#.utf8))
        #expect(usage == UsageSnapshot(fiveHourUsedPercent: 37.5, resetsAt: Date(timeIntervalSince1970: 1_750_000_000)))
        #expect(UsageSnapshot(statusline: Data(#"{"rate_limits":{"five_hour":{"used_percentage":12}}}"#.utf8))?
            .fiveHourUsedPercent == 12)
    }

    @Test("Missing usage stays nil and is never fabricated (REQ-04 AC2)", arguments: [
        #"{"model":{"display_name":"Opus"}}"#, #"{"rate_limits":{}}"#,
        #"{"rate_limits":{"seven_day":{"used_percentage":5}}}"#, #"{"rate_limits":{"five_hour":{}}}"#, "garbage",
    ])
    func statuslineMissing(json: String) {
        #expect(UsageSnapshot(statusline: Data(json.utf8)) == nil)
    }
}
