// StatusCountsTests.swift
// Panel bucket counts: each live session lands in exactly one bucket (docs/04 "Status counts", REQ-04 AC1).

import Foundation
import Testing
@testable import ClawdCore

private let t0 = Date(timeIntervalSince1970: 1_000)

@Suite("Status counts")
struct StatusCountsTests {
    /// Builds a store from (event that sets the state, whether the session is then marked read).
    private func snapshot(_ sessions: [(ClawdEvent.Kind, read: Bool)]) -> Snapshot {
        var store = SessionStore()
        for (index, item) in sessions.enumerated() {
            let id = "s\(index)"
            store.apply(event(item.0, session: id), now: t0)
            if item.read { store.markRead(id) }
        }
        return store.snapshot(now: t0)
    }

    @Test("One session per state lands in the expected bucket", arguments: [
        (ClawdEvent.Kind.unknown, false, StatusCounts(idle: 1, working: 0, done: 0, needsInput: 0)),
        (.stop, true, StatusCounts(idle: 1, working: 0, done: 0, needsInput: 0)),
        (.stop, false, StatusCounts(idle: 0, working: 0, done: 1, needsInput: 0)),
        (.userPromptSubmit, false, StatusCounts(idle: 0, working: 1, done: 0, needsInput: 0)),
        (.preToolUse, false, StatusCounts(idle: 0, working: 1, done: 0, needsInput: 0)),
        // A single MessageDisplay is too short a talking streak, so a new session stays idle.
        (.messageDisplay, false, StatusCounts(idle: 1, working: 0, done: 0, needsInput: 0)),
        (.permissionRequest, false, StatusCounts(idle: 0, working: 0, done: 0, needsInput: 1)),
    ])
    func bucket(kind: ClawdEvent.Kind, read: Bool, expected: StatusCounts) {
        let snap = snapshot([(kind, read: read)])
        #expect(snap.statusCounts == expected)
        #expect(snap.activeCount == 1)
    }

    @Test("Mixed sessions split across buckets and add up to activeCount")
    func mixedSumsToActive() {
        let snap = snapshot([
            (.unknown, read: false), (.stop, read: true), (.stop, read: false), (.userPromptSubmit, read: false),
            (.preToolUse, read: false), (.messageDisplay, read: false), (.permissionRequest, read: false),
        ])
        #expect(snap.statusCounts == StatusCounts(idle: 3, working: 2, done: 1, needsInput: 1))
        let counts = snap.statusCounts
        #expect(counts.idle + counts.working + counts.done + counts.needsInput == snap.activeCount)
    }

    @Test("An empty store has all-zero buckets")
    func empty() {
        #expect(snapshot([]).statusCounts == StatusCounts(idle: 0, working: 0, done: 0, needsInput: 0))
    }
}
