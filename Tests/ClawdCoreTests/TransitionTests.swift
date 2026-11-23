// TransitionTests.swift
// One case per row of the transition table in docs/04-state-machine.md (REQ-03).

import Foundation
import Testing
@testable import ClawdCore

/// Builds a hook event with only the fields a test cares about.
func event(
    _ kind: ClawdEvent.Kind, session: String = "s1", cwd: String? = nil, tool: String? = nil,
    notification: String? = nil, agent: String? = nil, at time: Date = .init(timeIntervalSince1970: 0)
) -> ClawdEvent {
    ClawdEvent(sessionID: session, kind: kind, cwd: cwd, toolName: tool, notificationType: notification,
               agentID: agent, receivedAt: time)
}

@Suite("Transition table")
struct TransitionTests {
    /// A session in `from` (with flags) receives `event` and must end in `to` (with flags).
    struct Row: Sendable, CustomTestStringConvertible {
        let name: String
        var from: SessionState = .idle
        var unread = false
        var failed = false
        let event: ClawdEvent
        let to: SessionState
        var unreadAfter = false
        var failedAfter = false
        var testDescription: String { name }
    }

    static let rows: [Row] = [
        Row(name: "UserPromptSubmit → thinking, clears unread and failed",
            from: .done, unread: true, failed: true, event: event(.userPromptSubmit), to: .thinking),
        Row(name: "PreToolUse → usingTools", from: .thinking, event: event(.preToolUse, tool: "Bash"),
            to: .usingTools),
        Row(name: "MessageDisplay → talking", from: .thinking, event: event(.messageDisplay),
            to: .talking),
        Row(name: "PostToolUse → thinking", from: .usingTools, event: event(.postToolUse), to: .thinking),
        Row(name: "PostToolBatch → thinking", from: .usingTools, event: event(.postToolBatch), to: .thinking),
        Row(name: "PostToolUseFailure → thinking", from: .usingTools, event: event(.postToolUseFailure),
            to: .thinking),
        Row(name: "PreCompact → compacting", from: .idle, event: event(.preCompact), to: .compacting),
        Row(name: "PostToolUse leaves compacting", from: .compacting, event: event(.postToolUse), to: .thinking),
        Row(name: "PreToolUse leaves compacting", from: .compacting, event: event(.preToolUse), to: .usingTools),
        Row(name: "MessageDisplay leaves compacting", from: .compacting, event: event(.messageDisplay), to: .talking),
        Row(name: "UserPromptSubmit leaves compacting", from: .compacting, event: event(.userPromptSubmit), to: .thinking),
        Row(name: "Stop leaves compacting", from: .compacting, event: event(.stop), to: .done, unreadAfter: true),
        Row(name: "Unknown event keeps compacting", from: .compacting, event: event(.unknown), to: .compacting),
        Row(name: "PermissionRequest → needsInput", from: .usingTools, event: event(.permissionRequest),
            to: .needsInput),
        Row(name: "Notification permission_prompt → needsInput", from: .thinking,
            event: event(.notification, notification: "permission_prompt"), to: .needsInput),
        Row(name: "Notification elicitation_dialog → needsInput", from: .thinking,
            event: event(.notification, notification: "elicitation_dialog"), to: .needsInput),
        Row(name: "Notification agent_needs_input → needsInput", from: .thinking,
            event: event(.notification, notification: "agent_needs_input"), to: .needsInput),
        Row(name: "Notification idle_prompt keeps done", from: .done, unread: true,
            event: event(.notification, notification: "idle_prompt"), to: .done, unreadAfter: true),
        Row(name: "Notification of an unknown type changes nothing", from: .thinking,
            event: event(.notification, notification: "something_new"), to: .thinking),
        Row(name: "PermissionDenied in needsInput → thinking", from: .needsInput,
            event: event(.permissionDenied), to: .thinking),
        Row(name: "PermissionDenied outside needsInput changes nothing", from: .usingTools,
            event: event(.permissionDenied), to: .usingTools),
        Row(name: "SubagentStart keeps the state", from: .thinking, event: event(.subagentStart, agent: "a1"),
            to: .thinking),
        Row(name: "SubagentStop keeps the state", from: .thinking, event: event(.subagentStop, agent: "a1"),
            to: .thinking),
        Row(name: "Stop without agent_id → done and unread", from: .thinking, event: event(.stop),
            to: .done, unreadAfter: true),
        Row(name: "Stop from a subagent does not finish the parent", from: .thinking,
            event: event(.stop, agent: "a1"), to: .thinking),
        Row(name: "StopFailure → done, unread and failed", from: .thinking, event: event(.stopFailure),
            to: .done, unreadAfter: true, failedAfter: true),
        Row(name: "Unknown event changes nothing", from: .talking, event: event(.unknown),
            to: .talking),
        Row(name: "Stop leaves needsInput", from: .needsInput, event: event(.stop), to: .done, unreadAfter: true),
        Row(name: "PreToolUse leaves needsInput", from: .needsInput, event: event(.preToolUse),
            to: .usingTools),
        Row(name: "PostToolUse leaves needsInput", from: .needsInput, event: event(.postToolUse), to: .thinking),
        Row(name: "UserPromptSubmit leaves needsInput", from: .needsInput, event: event(.userPromptSubmit),
            to: .thinking),
    ]

    @Test(arguments: rows)
    func transition(_ row: Row) {
        var session = Session(id: "s1", cwd: "/p", now: .init(timeIntervalSince1970: 0))
        session.state = row.from
        session.unread = row.unread
        session.failed = row.failed
        let now = Date(timeIntervalSince1970: 10)

        session.apply(row.event, now: now)

        #expect(session.state == row.to)
        #expect(session.unread == row.unreadAfter)
        #expect(session.failed == row.failedAfter)
        #expect(session.lastEventAt == now)
    }

    @Test("PreToolUse stores the tool name")
    func storesToolName() {
        var session = Session(id: "s1", cwd: nil, now: .init(timeIntervalSince1970: 0))
        session.apply(event(.preToolUse, tool: "Bash"), now: .init(timeIntervalSince1970: 1))
        #expect(session.toolName == "Bash")
    }

    @Test("Subagent counter goes up and down and is floored at zero")
    func subagentCounter() {
        var session = Session(id: "s1", cwd: nil, now: .init(timeIntervalSince1970: 0))
        session.apply(event(.subagentStart, agent: "a"), now: .now)
        session.apply(event(.subagentStart, agent: "b"), now: .now)
        #expect(session.activeSubagents == 2)
        session.apply(event(.subagentStop, agent: "a"), now: .now)
        session.apply(event(.subagentStop, agent: "b"), now: .now)
        session.apply(event(.subagentStop, agent: "c"), now: .now)
        #expect(session.activeSubagents == 0)
    }

    @Test("SessionStart metadata creates an idle session")
    func sessionStartCreates() {
        var store = SessionStore()
        let meta = SessionMeta(sessionID: "s1", cwd: "/Users/me/proj", source: "startup", pid: 42, tty: "/dev/ttys001",
                               terminalBundleID: "com.apple.Terminal", termProgram: "Apple_Terminal")
        store.apply(meta: meta, now: .init(timeIntervalSince1970: 5))
        let session = store.snapshot(now: .init(timeIntervalSince1970: 5)).sessions.first
        #expect(session?.state == .idle)
        #expect(session?.projectName == "proj")
        #expect(session?.meta == meta)
    }

    @Test("SessionStart metadata for a known session resets it to idle and clears its flags")
    func sessionStartKnown() {
        var store = SessionStore()
        store.apply(event(.stopFailure), now: .init(timeIntervalSince1970: 0))
        store.apply(meta: SessionMeta(sessionID: "s1", cwd: "/p", source: "clear", pid: nil, tty: nil,
                                      terminalBundleID: nil, termProgram: nil),
                    now: .init(timeIntervalSince1970: 1))
        #expect(store.sessions.map(\.state) == [.idle])
        #expect(store.sessions.first?.unread == false)
        #expect(store.sessions.first?.failed == false)
    }

    @Test("SessionEnd removes the session")
    func sessionEndRemoves() {
        var store = SessionStore()
        store.apply(event(.userPromptSubmit), now: .init(timeIntervalSince1970: 0))
        store.apply(event(.sessionEnd), now: .init(timeIntervalSince1970: 1))
        #expect(store.sessions.isEmpty)
    }

    @Test("Any event for an unknown session creates it, named after its cwd")
    func unknownSessionCreated() {
        var store = SessionStore()
        store.apply(event(.unknown, cwd: "/Users/me/proj"), now: .init(timeIntervalSince1970: 3))
        #expect(store.sessions.map(\.projectName) == ["proj"])
        #expect(store.sessions.first?.state == .idle)
        #expect(store.sessions.first?.lastEventAt == Date(timeIntervalSince1970: 3))
    }

    @Test("Reading a done session makes it idle")
    func markReadDone() {
        var store = SessionStore()
        store.apply(event(.stop, session: "a"), now: .init(timeIntervalSince1970: 0))
        store.apply(event(.stop, session: "b"), now: .init(timeIntervalSince1970: 0))
        store.markRead("a")
        #expect(store.sessions.map(\.state) == [.idle, .done])
        store.markAllRead()
        #expect(store.sessions.map(\.state) == [.idle, .idle])
        #expect(store.sessions.allSatisfy { !$0.unread })
    }
}
