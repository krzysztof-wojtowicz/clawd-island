// PanelOrderTests.swift
// Snapshot.sessions order: rank first, then newest lastEventAt, applied after talking decay (REQ-04 AC1, REQ-10 AC3).

import Foundation
import Testing
@testable import ClawdCore

@Suite("Panel order")
struct PanelOrderTests {
    @Test("Sessions are ranked needsInput > unread done > compacting > usingTools > talking > thinking > idle, decay applied first")
    func mixedStatesRankInOrder() {
        var store = SessionStore()
        let base = Date(timeIntervalSince1970: 1_000)
        store.apply(event(.unknown, session: "idleOld"), now: base)
        store.apply(event(.userPromptSubmit, session: "thinkNew"), now: base.addingTimeInterval(5))
        store.apply(event(.permissionRequest, session: "needs"), now: base.addingTimeInterval(1))
        store.apply(event(.stop, session: "doneUnread"), now: base.addingTimeInterval(2))
        store.apply(event(.preToolUse, session: "tools"), now: base.addingTimeInterval(3))
        store.apply(event(.preCompact, session: "compact"), now: base.addingTimeInterval(0.5))
        store.apply(event(.messageDisplay, session: "talkDecayed"), now: base.addingTimeInterval(4))
        store.apply(event(.messageDisplay, session: "talkFresh"), now: base.addingTimeInterval(9))
        store.apply(event(.stop, session: "doneRead"), now: base.addingTimeInterval(7))
        store.markRead("doneRead")

        let now = base.addingTimeInterval(10)
        let order = store.snapshot(now: now).sessions.map(\.id)
        #expect(order == ["needs", "doneUnread", "compact", "tools", "talkFresh", "thinkNew", "talkDecayed", "doneRead", "idleOld"])
    }

    @Test("Equal rank: newest lastEventAt first, regardless of arrival order")
    func equalRankNewestFirst() {
        var store = SessionStore()
        let base = Date(timeIntervalSince1970: 1_000)
        store.apply(event(.userPromptSubmit, session: "early"), now: base.addingTimeInterval(1))
        store.apply(event(.userPromptSubmit, session: "late"), now: base.addingTimeInterval(3))

        let order = store.snapshot(now: base.addingTimeInterval(3)).sessions.map(\.id)
        #expect(order == ["late", "early"])
    }
}
