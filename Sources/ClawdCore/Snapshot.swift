// Snapshot.swift
// The immutable view model the UI renders, and the aggregate rule that picks the pet's state.

import Foundation

/// Everything the UI shows at one instant. The UI renders only this; an equal snapshot means no re-render.
public struct Snapshot: Equatable, Sendable {
    public let aggregate: PetState
    /// Live sessions.
    public let activeCount: Int
    /// Sessions that are `needsInput`, or `done` and unread.
    public let attentionCount: Int
    public let hasNeedsInput: Bool
    /// Sessions in arrival order, with talking decay already applied.
    public let sessions: [Session]
    public let usage: UsageSnapshot?
    /// Increments once per pop-out edge; the UI pops the pet when it sees a new value.
    public let popToken: Int
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
