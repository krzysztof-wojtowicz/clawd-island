// PermissionTests.swift
// PermissionRequest summaries and the pending-permission lifecycle in SessionStore (REQ-16).

import Foundation
import Testing
@testable import ClawdCore

private let t0 = Date(timeIntervalSince1970: 1_000)

private func request(_ session: String = "s1", tool: String = "Bash", input: String = #""tool_input":{"command":"ls"}"#,
                     at time: Date = t0) -> ClawdEvent {
    let json = #"{"hook_event_name":"PermissionRequest","session_id":"\#(session)","cwd":"/p/proj","tool_name":"\#(tool)",\#(input)}"#
    return ClawdEvent(json: Data(json.utf8), receivedAt: time)!
}

private func event(_ kind: ClawdEvent.Kind, session: String = "s1") -> ClawdEvent {
    ClawdEvent(sessionID: session, kind: kind, cwd: nil, toolName: nil, notificationType: nil, agentID: nil,
               inputSummary: nil, receivedAt: t0)
}

@Suite("Permissions")
struct PermissionTests {
    @Test("Summary comes from command, file_path, url or pattern, else the tool name", arguments: [
        (#""tool_input":{"command":"rm -rf x"}"#, "rm -rf x"),
        (#""tool_input":{"file_path":"/a/b.swift","command":"c"}"#, "c"),
        (#""tool_input":{"file_path":"/a/b.swift"}"#, "/a/b.swift"),
        (#""tool_input":{"url":"https://x.dev"}"#, "https://x.dev"),
        (#""tool_input":{"pattern":"TODO"}"#, "TODO"),
        (#""tool_input":{"command":"a\nb"}"#, "a b"),
        (#""tool_input":{"command":7,"other":"x"}"#, "Bash"),
        (#""tool_input":{}"#, "Bash"),
        (#""tool_input":"str""#, "Bash"),
        (#""x":1"#, "Bash"),
    ])
    func summary(input: String, expected: String) {
        #expect(request(input: input).inputSummary == expected)
    }

    @Test("A huge command is cut to 120 characters")
    func hugeInput() {
        let big = String(repeating: "x", count: 100_000)
        #expect(request(input: #""tool_input":{"command":"\#(big)"}"#).inputSummary?.count == 120)
    }

    @Test("Other events never carry a summary")
    func otherEvents() {
        let json = #"{"hook_event_name":"PreToolUse","session_id":"s","tool_name":"Bash","tool_input":{"command":"ls"}}"#
        #expect(ClawdEvent(json: Data(json.utf8), receivedAt: t0)?.inputSummary == nil)
    }

    @Test("A request is listed newest first and puts the session in needsInput")
    func addAndOrder() {
        var store = SessionStore()
        let a = UUID(), b = UUID()
        for (id, event) in [(a, request("s1", at: t0)), (b, request("s2", tool: "Edit", at: t0 + 1))] {
            store.apply(event, now: event.receivedAt)
            store.addPermission(id: id, for: event)
        }
        let snapshot = store.snapshot(now: t0 + 1)
        #expect(snapshot.pendingPermissions.map(\.id) == [b, a])
        #expect(snapshot.pendingPermissions.first?.projectName == "proj")
        #expect(snapshot.pendingPermissions.first?.summary == "ls")
        #expect(snapshot.aggregate == .needsInput)
    }

    @Test("Only PermissionRequest events can be added")
    func addIgnoresOthers() {
        var store = SessionStore()
        store.apply(event(.preToolUse), now: t0)
        store.addPermission(id: UUID(), for: event(.preToolUse))
        #expect(store.snapshot(now: t0).pendingPermissions.isEmpty)
    }

    @Test("resolvePermission removes only that one")
    func resolve() {
        var store = SessionStore()
        let a = UUID(), b = UUID()
        for (id, session) in [(a, "s1"), (b, "s2")] {
            store.apply(request(session), now: t0)
            store.addPermission(id: id, for: request(session))
        }
        store.resolvePermission(a)
        #expect(store.snapshot(now: t0).pendingPermissions.map(\.id) == [b])
    }

    @Test("Turn-level events drop the session's cards; tool-level and other events leave them", arguments: [
        (ClawdEvent.Kind.userPromptSubmit, true), (.stop, true), (.stopFailure, true), (.sessionEnd, true),
        (.preToolUse, false), (.messageDisplay, false), (.preCompact, false), (.postToolBatch, false),
        (.subagentStart, false), (.notification, false), (.unknown, false),
    ])
    func removal(kind: ClawdEvent.Kind, removes: Bool) {
        var store = SessionStore()
        store.apply(request(), now: t0)
        store.addPermission(id: UUID(), for: request())
        store.apply(request("s2"), now: t0)
        store.addPermission(id: UUID(), for: request("s2"))
        store.apply(event(kind), now: t0 + 1)
        let remaining = store.snapshot(now: t0 + 1).pendingPermissions.map(\.sessionID)
        // Newest first: s2 was added after s1.
        #expect(remaining == (removes ? ["s2"] : ["s2", "s1"]))
    }

    private func finished(_ kind: String, tool: String, command: String?) -> ClawdEvent {
        let input = command.map { #","tool_input":{"command":"\#($0)"}"# } ?? ""
        let json = #"{"hook_event_name":"\#(kind)","session_id":"s1","tool_name":"\#(tool)"\#(input)}"#
        return ClawdEvent(json: Data(json.utf8), receivedAt: t0 + 1)!
    }

    @Test("Parallel tools: another tool's PostToolUse keeps the card, the matching one drops it")
    func parallel() {
        var store = SessionStore()
        store.apply(request(input: #""tool_input":{"command":"rm x"}"#), now: t0)
        store.addPermission(id: UUID(), for: request(input: #""tool_input":{"command":"rm x"}"#))
        for other in [finished("PostToolUse", tool: "Bash", command: "ls"),
                      finished("PostToolUse", tool: "Edit", command: "rm x"),
                      finished("PostToolUseFailure", tool: "Read", command: nil)] {
            store.apply(other, now: t0 + 1)
        }
        #expect(store.snapshot(now: t0 + 1).pendingPermissions.count == 1)
        store.apply(finished("PostToolUse", tool: "Bash", command: "rm x"), now: t0 + 2)
        #expect(store.snapshot(now: t0 + 2).pendingPermissions.isEmpty)
    }

    @Test("PostToolUseFailure and PermissionDenied for the same tool and input drop the card")
    func failureAndDenied() {
        for kind in ["PostToolUseFailure", "PermissionDenied"] {
            var store = SessionStore()
            store.apply(request(), now: t0)
            store.addPermission(id: UUID(), for: request())
            store.apply(finished(kind, tool: "Bash", command: "pwd"), now: t0 + 1)
            #expect(store.snapshot(now: t0 + 1).pendingPermissions.count == 1)
            store.apply(finished(kind, tool: "Bash", command: "ls"), now: t0 + 2)
            #expect(store.snapshot(now: t0 + 2).pendingPermissions.isEmpty)
        }
    }

    @Test("A PermissionDenied without a tool drops the session's cards")
    func deniedWithoutSummary() {
        var store = SessionStore()
        store.apply(request(), now: t0)
        store.addPermission(id: UUID(), for: request())
        store.apply(event(.permissionDenied), now: t0 + 1)
        #expect(store.snapshot(now: t0 + 1).pendingPermissions.isEmpty)
    }

    @Test("Expiry drops requests at 110 s and reports the next deadline")
    func expiry() {
        var store = SessionStore()
        for (session, time) in [("s1", t0), ("s2", t0 + 50)] {
            store.apply(request(session, at: time), now: time)
            store.addPermission(id: UUID(), for: request(session, at: time))
        }
        #expect(store.nextPermissionDeadline() == t0 + SessionStore.permissionCap)
        store.expirePermissions(now: t0 + 109.9)
        #expect(store.snapshot(now: t0 + 110).pendingPermissions.count == 2)
        store.expirePermissions(now: t0 + 110)
        #expect(store.snapshot(now: t0 + 110).pendingPermissions.map(\.sessionID) == ["s2"])
        #expect(store.nextPermissionDeadline() == t0 + 50 + SessionStore.permissionCap)
        store.expirePermissions(now: t0 + 200)
        #expect(store.nextPermissionDeadline() == nil)
    }

    @Test("A session removed by liveness expiry takes its cards with it")
    func livenessRemoval() {
        var store = SessionStore()
        store.apply(request(), now: t0)
        store.addPermission(id: UUID(), for: request())
        store.expire(now: t0 + SessionStore.silentExpiry, isAlive: { _ in true })
        #expect(store.snapshot(now: t0).pendingPermissions.isEmpty)
    }
}
