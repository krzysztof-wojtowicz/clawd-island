// SessionStore.swift
// Tracks per-session Claude Code state and derives the pet's aggregate snapshot.

import Foundation

/// All live sessions plus the latest usage window. Owned by the app on the main actor;
/// every time-dependent method takes an injected `now` so behaviour stays deterministic in tests.
public struct SessionStore: Sendable {
    /// How long `talking` survives without a new talking event before it decays to `thinking`.
    public static let talkingDecay: TimeInterval = 2
    /// Sessions without a pid are dropped after this long with no events.
    public static let silentExpiry: TimeInterval = 6 * 60 * 60

    var sessions: [Session] = []
    var usage: UsageSnapshot?
    private var popToken = 0
    private var lastAggregate = PetState.sleeping
    private var lastAttentionCount = 0

    public init() {}

    /// Applies a hook event. Unknown sessions are created; `SessionEnd` removes the session.
    public mutating func apply(_ event: ClawdEvent, now: Date) {
        if event.kind == .sessionEnd {
            sessions.removeAll { $0.id == event.sessionID }
            return
        }
        let index = indexCreatingIfNeeded(event.sessionID, cwd: event.cwd, now: now)
        sessions[index].apply(event, now: now)
    }

    /// Applies the bridge's SessionStart metadata: the session becomes (or is created) `idle`.
    public mutating func apply(meta: SessionMeta, now: Date) {
        let index = indexCreatingIfNeeded(meta.sessionID, cwd: meta.cwd, now: now)
        sessions[index].meta = meta
        sessions[index].projectName = Session.projectName(for: meta.cwd)
        sessions[index].state = .idle
        sessions[index].unread = false
        sessions[index].failed = false
        sessions[index].lastEventAt = now
    }

    /// Stores the latest usage window from the statusline.
    public mutating func apply(usage: UsageSnapshot) {
        self.usage = usage
    }

    /// Marks one session read (a panel click or terminal focus).
    public mutating func markRead(_ id: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].markRead()
    }

    /// Marks every session read.
    public mutating func markAllRead() {
        for index in sessions.indices { sessions[index].markRead() }
    }

    /// Removes sessions whose Claude Code process is gone, or that have no pid and were silent for 6 h.
    /// - Parameter isAlive: Injected liveness check, `kill(pid, 0) != ESRCH` in the app.
    public mutating func expire(now: Date, isAlive: (Int32) -> Bool) {
        sessions.removeAll { session in
            if let pid = session.meta?.pid { return !isAlive(pid) }
            return now.timeIntervalSince(session.lastEventAt) >= Self.silentExpiry
        }
    }

    /// The earliest future moment a talking session decays, so the app can schedule one one-shot
    /// re-evaluation instead of a periodic timer. Nil when nothing is talking.
    public func nextDecayDeadline(now: Date) -> Date? {
        sessions
            .compactMap { session -> Date? in
                guard session.state == .talking, let talkedAt = session.lastTalkingAt else { return nil }
                return talkedAt.addingTimeInterval(Self.talkingDecay)
            }
            .filter { $0 > now }
            .min()
    }

    /// Builds the snapshot at `now`, applying talking decay and advancing `popToken` on a pop-out edge.
    /// Mutating because pop-out edges are measured against the previously built snapshot.
    public mutating func snapshot(now: Date) -> Snapshot {
        let visible = sessions.map { decayed($0, now: now) }
        let aggregate = PetState(aggregating: visible)
        let attentionCount = visible.filter(\.needsAttention).count
        let enteredUrgent = aggregate != lastAggregate && (aggregate == .done || aggregate == .needsInput)
        if attentionCount > lastAttentionCount || enteredUrgent { popToken += 1 }
        lastAggregate = aggregate
        lastAttentionCount = attentionCount
        return Snapshot(
            aggregate: aggregate,
            activeCount: visible.count,
            attentionCount: attentionCount,
            hasNeedsInput: visible.contains { $0.state == .needsInput },
            sessions: visible,
            usage: usage,
            popToken: popToken
        )
    }

    private func decayed(_ session: Session, now: Date) -> Session {
        guard session.state == .talking, let talkedAt = session.lastTalkingAt,
              now.timeIntervalSince(talkedAt) >= Self.talkingDecay
        else { return session }
        var copy = session
        copy.state = .thinking
        return copy
    }

    // CC may start before the app; unknown sessions are created lazily from any event.
    // shortcut: a late event arriving after SessionEnd re-creates a ghost session that lives until expiry,
    // upgrade to a short-lived tombstone set if ghosts show up in practice.
    private mutating func indexCreatingIfNeeded(_ id: String, cwd: String?, now: Date) -> Int {
        if let index = sessions.firstIndex(where: { $0.id == id }) { return index }
        sessions.append(Session(id: id, cwd: cwd, now: now))
        return sessions.endIndex - 1
    }
}
