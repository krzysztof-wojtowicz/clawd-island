// SessionStoreTests.swift
// Aggregate priority, counters, talking decay, liveness and pop-out edges (WP-1, REQ-03 AC3, REQ-04 AC1).

import Foundation
import Testing
@testable import ClawdCore

private let t0 = Date(timeIntervalSince1970: 1_000)

@Suite("SessionStore")
struct SessionStoreTests {
    /// Sessions given as (state, unread) and the aggregate the pet must show.
    struct AggregateCase: Sendable, CustomTestStringConvertible {
        let sessions: [(SessionState, Bool)]
        let expected: PetState
        var testDescription: String { "\(sessions.map { "\($0.0)\($0.1 ? "*" : "")" }) → \(expected)" }
    }

    static let aggregateCases: [AggregateCase] = [
        AggregateCase(sessions: [], expected: .sleeping),
        AggregateCase(sessions: [(.idle, false)], expected: .idle),
        AggregateCase(sessions: [(.idle, false), (.thinking, false)], expected: .thinking),
        AggregateCase(sessions: [(.thinking, false), (.talking, false)], expected: .talking),
        AggregateCase(sessions: [(.talking, false), (.usingTools, false)], expected: .usingTools),
        AggregateCase(sessions: [(.usingTools, false), (.thinking, false), (.idle, false)], expected: .usingTools),
        AggregateCase(sessions: [(.juggling, false), (.compacting, false), (.usingTools, false)], expected: .juggling),
        AggregateCase(sessions: [(.juggling, false), (.done, true)], expected: .done),
        AggregateCase(sessions: [(.juggling, false), (.needsInput, false)], expected: .needsInput),
        AggregateCase(sessions: [(.usingTools, false), (.compacting, false), (.talking, false)], expected: .compacting),
        AggregateCase(sessions: [(.compacting, false), (.thinking, false)], expected: .compacting),
        AggregateCase(sessions: [(.compacting, false), (.done, true)], expected: .done),
        AggregateCase(sessions: [(.compacting, false), (.needsInput, false)], expected: .needsInput),
        AggregateCase(sessions: [(.usingTools, false), (.done, true)], expected: .done),
        AggregateCase(sessions: [(.done, true), (.needsInput, false), (.usingTools, false)],
                      expected: .needsInput),
        AggregateCase(sessions: [(.done, false), (.idle, false)], expected: .idle),
    ]

    @Test("Highest-priority state wins across sessions (REQ-03 AC3)", arguments: aggregateCases)
    func aggregatePriority(_ testCase: AggregateCase) {
        let sessions = testCase.sessions.enumerated().map { index, pair in
            var session = Session(id: "s\(index)", cwd: nil, now: t0)
            session.state = pair.0
            session.unread = pair.1
            return session
        }
        #expect(PetState(aggregating: sessions) == testCase.expected)
    }

    @Test("Counters match the session list (REQ-04 AC1)")
    func countersMatchSessions() {
        var store = SessionStore()
        store.apply(event(.stop, session: "a"), now: t0)
        store.apply(event(.permissionRequest, session: "b"), now: t0)
        store.apply(event(.userPromptSubmit, session: "c"), now: t0)
        store.apply(event(.stop, session: "d"), now: t0)
        store.markRead("d")

        let snapshot = store.snapshot(now: t0)
        #expect(snapshot.activeCount == snapshot.sessions.count)
        #expect(snapshot.activeCount == 4)
        #expect(snapshot.attentionCount == snapshot.sessions.filter(\.needsAttention).count)
        #expect(snapshot.attentionCount == 2)
        #expect(snapshot.hasNeedsInput)
    }

    @Test("Talking decays to thinking at exactly 2 s, not at 1.99 s")
    func talkingDecayBoundary() {
        var store = SessionStore()
        store.apply(event(.messageDisplay), now: t0)
        #expect(store.snapshot(now: t0.addingTimeInterval(1.99)).aggregate == .talking)
        #expect(store.snapshot(now: t0.addingTimeInterval(2.0)).aggregate == .thinking)
        #expect(store.snapshot(now: t0.addingTimeInterval(2.0)).sessions.first?.state == .thinking)
    }

    @Test("SessionStart(compact) ends compacting; compacting counts as working and never decays")
    func compactingLifecycle() {
        var store = SessionStore()
        store.apply(event(.preCompact), now: t0)
        let later = store.snapshot(now: t0.addingTimeInterval(600))
        #expect(later.aggregate == .compacting)
        #expect(later.statusCounts.working == 1)
        store.apply(meta: SessionMeta(sessionID: "s1", cwd: "/p", source: "compact", pid: nil, tty: nil,
                                      terminalBundleID: nil, termProgram: nil), now: t0.addingTimeInterval(601))
        #expect(store.snapshot(now: t0.addingTimeInterval(602)).aggregate == .idle)
    }

    @Test("usingTools never decays and sets no decay deadline")
    func usingToolsDoesNotDecay() {
        var store = SessionStore()
        store.apply(event(.preToolUse), now: t0)
        #expect(store.nextDecayDeadline(now: t0) == nil)
        let later = store.snapshot(now: t0.addingTimeInterval(60))
        #expect(later.aggregate == .usingTools)
        #expect(later.sessions.first?.state == .usingTools)
    }

    @Test("A new talking event restarts the decay and moves the deadline")
    func decayDeadline() {
        var store = SessionStore()
        #expect(store.nextDecayDeadline(now: t0) == nil)
        store.apply(event(.messageDisplay), now: t0)
        store.apply(event(.messageDisplay), now: t0.addingTimeInterval(1.5))
        #expect(store.nextDecayDeadline(now: t0.addingTimeInterval(1.5)) == t0.addingTimeInterval(3.5))
        #expect(store.snapshot(now: t0.addingTimeInterval(3)).aggregate == .talking)
        #expect(store.nextDecayDeadline(now: t0.addingTimeInterval(3.5)) == nil)
    }

    @Test("A MessageDisplay flood does not change the snapshot (render only on change)")
    func messageFloodSnapshotsEqual() {
        var store = SessionStore()
        store.apply(event(.messageDisplay), now: t0)
        let first = store.snapshot(now: t0)
        store.apply(event(.messageDisplay), now: t0.addingTimeInterval(0.5))
        #expect(store.snapshot(now: t0.addingTimeInterval(0.5)) == first)
    }

    @Test("Running subagents derive juggling unless the session needs input or is done; counters reset (REQ-03 AC6)")
    func jugglingDerivation() {
        var store = SessionStore()
        store.apply(event(.userPromptSubmit), now: t0)
        store.apply(event(.subagentStart, agent: "a"), now: t0)
        store.apply(event(.subagentStart, agent: "b"), now: t0)
        var snapshot = store.snapshot(now: t0)
        #expect(snapshot.aggregate == .juggling)
        #expect(snapshot.sessions.first?.state == .juggling)
        #expect(snapshot.sessions.first?.activeSubagents == 2)
        #expect(snapshot.statusCounts.working == 1)
        store.apply(event(.preToolUse, tool: "Bash"), now: t0)
        #expect(store.snapshot(now: t0).aggregate == .juggling)
        store.apply(event(.permissionRequest), now: t0)
        #expect(store.snapshot(now: t0).aggregate == .needsInput)
        store.apply(event(.postToolUse), now: t0)
        store.apply(event(.stop, agent: "a"), now: t0)
        #expect(store.snapshot(now: t0).aggregate == .juggling)
        store.apply(event(.stop), now: t0)
        snapshot = store.snapshot(now: t0)
        #expect(snapshot.aggregate == .done)
        #expect(snapshot.sessions.first?.activeSubagents == 0)
    }

    @Test("A SubagentStart after Stop is ignored, so reading the session does not resurface juggling")
    func lateSubagentStart() {
        var store = SessionStore()
        store.apply(event(.userPromptSubmit), now: t0)
        store.apply(event(.stop), now: t0)
        store.apply(event(.subagentStart, agent: "late"), now: t0)
        store.markRead("s1")
        let snapshot = store.snapshot(now: t0)
        #expect(snapshot.aggregate == .idle)
        #expect(snapshot.sessions.first?.activeSubagents == 0)
    }

    @Test("UserPromptSubmit and StopFailure reset the subagent counter")
    func subagentCounterResets() {
        var store = SessionStore()
        store.apply(event(.subagentStart, agent: "a"), now: t0)
        store.apply(event(.userPromptSubmit), now: t0)
        #expect(store.snapshot(now: t0).aggregate == .thinking)
        store.apply(event(.subagentStart, agent: "a"), now: t0)
        store.apply(event(.stopFailure), now: t0)
        #expect(store.sessions.first?.activeSubagents == 0)
    }

    @Test("Subagent Stop does not mark the parent done")
    func subagentStop() {
        var store = SessionStore()
        store.apply(event(.userPromptSubmit), now: t0)
        store.apply(event(.stop, agent: "agent-1"), now: t0)
        let snapshot = store.snapshot(now: t0)
        #expect(snapshot.aggregate == .thinking)
        #expect(snapshot.attentionCount == 0)
    }

    @Test("Statusline meta attaches without touching state; unknown sessions are created idle (REQ-10 AC1a)")
    func statuslineMeta() {
        var store = SessionStore()
        store.apply(event(.userPromptSubmit, session: "busy"), now: t0)
        let later = t0.addingTimeInterval(5)
        for id in ["busy", "new"] {
            store.apply(meta: SessionMeta(sessionID: id, cwd: "/p/app", source: "statusline", pid: 7, tty: "/dev/ttys001",
                                          terminalBundleID: "com.googlecode.iterm2", termProgram: nil), now: later)
        }
        let busy = store.sessions.first { $0.id == "busy" }
        #expect(busy?.state == .thinking)
        #expect(busy?.lastEventAt == t0)
        #expect(busy?.meta?.tty == "/dev/ttys001")
        let new = store.sessions.first { $0.id == "new" }
        #expect(new?.state == .idle)
        #expect(new?.projectName == "app")
    }

    @Test("Liveness: dead pids are removed, live ones kept, pid-less sessions expire after 6 h")
    func livenessExpiry() {
        var store = SessionStore()
        for (id, pid) in [("dead", Int32(1)), ("alive", Int32(2))] {
            store.apply(meta: SessionMeta(sessionID: id, cwd: "/p", source: nil, pid: pid, tty: nil,
                                          terminalBundleID: nil, termProgram: nil), now: t0)
        }
        store.apply(event(.userPromptSubmit, session: "old"), now: t0)
        store.apply(event(.userPromptSubmit, session: "recent"), now: t0.addingTimeInterval(1))
        let sixHours = t0.addingTimeInterval(SessionStore.silentExpiry)

        store.expire(now: sixHours) { $0 == 2 }

        #expect(store.sessions.map(\.id) == ["alive", "recent"])
    }

    @Test("popToken increments exactly once per qualifying edge")
    func popTokenEdges() {
        var store = SessionStore()
        #expect(store.snapshot(now: t0).popToken == 0)

        store.apply(event(.userPromptSubmit, session: "a"), now: t0)
        #expect(store.snapshot(now: t0).popToken == 0)

        store.apply(event(.stop, session: "a"), now: t0)
        #expect(store.snapshot(now: t0).popToken == 1)
        #expect(store.snapshot(now: t0).popToken == 1)

        // A second finished session raises attentionCount while the aggregate stays done.
        store.apply(event(.stop, session: "b"), now: t0)
        #expect(store.snapshot(now: t0).popToken == 2)

        store.apply(event(.permissionRequest, session: "a"), now: t0)
        #expect(store.snapshot(now: t0).popToken == 3)

        store.markAllRead()
        #expect(store.snapshot(now: t0).popToken == 3)
        store.apply(event(.permissionDenied, session: "a"), now: t0)
        #expect(store.snapshot(now: t0).popToken == 3)
    }

    @Test("Usage is carried into the snapshot")
    func usageInSnapshot() {
        var store = SessionStore()
        #expect(store.snapshot(now: t0).usage == nil)
        let usage = UsageSnapshot(fiveHourUsedPercent: 37, resetsAt: t0, sevenDayUsedPercent: nil, sevenDayResetsAt: nil)
        store.apply(usage: usage)
        #expect(store.snapshot(now: t0).usage == usage)
    }
}
