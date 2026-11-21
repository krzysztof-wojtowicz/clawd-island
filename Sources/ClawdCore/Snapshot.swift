// Snapshot.swift
// The immutable view model the UI renders, and the aggregate rule that picks the pet's state.

import Foundation

/// Live sessions split into the four panel buckets (docs/04 "Status counts"); they add up to `activeCount`.
public struct StatusCounts: Equatable, Sendable {
    public let idle: Int
    public let working: Int
    public let done: Int
    public let needsInput: Int
}

extension StatusCounts {
    /// Buckets each session by its decayed state. A read `done` session counts as idle, so it leaves the done bucket.
    init(sessions: [Session]) {
        var idle = 0, working = 0, done = 0, needsInput = 0
        for session in sessions {
            switch session.state {
            case .needsInput: needsInput += 1
            case .done where session.unread: done += 1
            case .thinking, .usingTools, .talking: working += 1
            case .idle, .done: idle += 1
            }
        }
        self.init(idle: idle, working: working, done: done, needsInput: needsInput)
    }
}

/// Everything the UI shows at one instant. The UI renders only this; an equal snapshot means no re-render.
public struct Snapshot: Equatable, Sendable {
    public let aggregate: PetState
    /// Live sessions.
    public let activeCount: Int
    /// Live sessions per panel bucket; the panel status row reads these.
    public let statusCounts: StatusCounts
    /// Sessions that are `needsInput`, or `done` and unread.
    public let attentionCount: Int
    public let hasNeedsInput: Bool
    /// Sessions in panel order (rank, then newest `lastEventAt`), with talking decay already applied.
    public let sessions: [Session]
    public let usage: UsageSnapshot?
    /// Increments once per pop-out edge; the UI pops the pet when it sees a new value.
    public let popToken: Int
    /// Permission prompts held open for a notch decision, newest first (REQ-V2-01).
    public let pendingPermissions: [PendingPermission]
}

extension PetState {
    /// The highest-priority state across sessions (REQ-03 AC3):
    /// `needsInput > done (unread) > usingTools > talking > thinking > idle > sleeping`.
    init(aggregating sessions: [Session]) {
        if sessions.isEmpty {
            self = .sleeping
        } else if sessions.contains(where: { $0.state == .needsInput }) {
            self = .needsInput
        } else if sessions.contains(where: { $0.state == .done && $0.unread }) {
            self = .done
        } else if sessions.contains(where: { $0.state == .usingTools }) {
            self = .usingTools
        } else if sessions.contains(where: { $0.state == .talking }) {
            self = .talking
        } else if sessions.contains(where: { $0.state == .thinking }) {
            self = .thinking
        } else {
            self = .idle
        }
    }
}
