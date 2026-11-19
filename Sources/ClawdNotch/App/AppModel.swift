// AppModel.swift
// Main-actor owner of the SessionStore: applies server messages and publishes snapshots only when they change.

import ClawdCore
import Foundation
import Observation
import os

/// The app's single source of truth for the UI. It owns the `SessionStore`, applies inbound messages,
/// and publishes `snapshot` only when it differs from the previous one (docs/08 rule 3).
/// Timers: one one-shot talking-decay re-evaluation, and the 30 s liveness check while sessions exist.
@MainActor @Observable
final class AppModel {
    private static let coalesceInterval: TimeInterval = 0.1
    private static let livenessInterval: TimeInterval = 30
    private static let logger = Logger(subsystem: "dev.clawdnotch", category: "model")

    /// What the UI renders.
    private(set) var snapshot: Snapshot
    /// Why the event server is not listening (for example, the port is busy). Nil while it works.
    // TODO(WP-7): show this in the menu.
    var serverError: String?
    /// Called after `snapshot` changes, with the previous and the new value.
    @ObservationIgnored var onSnapshotChange: ((_ old: Snapshot, _ new: Snapshot) -> Void)?

    @ObservationIgnored private var store: SessionStore
    @ObservationIgnored private var publishPending = false
    @ObservationIgnored private var decayTimer: Timer?
    @ObservationIgnored private var livenessTimer: Timer?
    @ObservationIgnored private var paused = false

    init() {
        var store = SessionStore()
        snapshot = store.snapshot(now: .now)
        self.store = store
    }

    /// Applies one decoded server message. `MessageDisplay` floods are coalesced to one snapshot per 100 ms.
    func receive(_ inbound: Inbound) {
        store.apply(inbound, now: .now)
        if case .event(let event) = inbound, event.kind == .messageDisplay {
            publishCoalesced()
        } else {
            publish()
        }
    }

    /// Marks one session read (a panel click or terminal focus).
    func markRead(_ id: String) {
        store.markRead(id)
        publish()
    }

    /// Marks every session read.
    func markAllRead() {
        store.markAllRead()
        publish()
    }

    /// Stops the liveness timer while nobody can see the app (docs/08 rule 4); resuming restarts it.
    func setPaused(_ paused: Bool) {
        self.paused = paused
        updateLivenessTimer()
    }

    private func publishCoalesced() {
        guard !publishPending else { return }
        publishPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.coalesceInterval) { [weak self] in
            MainActor.assumeIsolated {
                self?.publishPending = false
                self?.publish()
            }
        }
    }

    private func publish() {
        let now = Date.now
        let next = store.snapshot(now: now)
        if next != snapshot {
            let old = snapshot
            snapshot = next
            Self.logger.debug("snapshot \(next.aggregate.rawValue, privacy: .public) active=\(next.activeCount) attention=\(next.attentionCount) pop=\(next.popToken)")
            onSnapshotChange?(old, next)
        }
        scheduleDecay(now: now)
        updateLivenessTimer()
    }

    /// Replaces the single one-shot timer that re-evaluates the snapshot when talking decays to thinking.
    private func scheduleDecay(now: Date) {
        decayTimer?.invalidate()
        decayTimer = store.nextDecayDeadline(now: now).map { deadline in
            Self.schedule(after: deadline.timeIntervalSince(now), repeats: false) { [weak self] in self?.publish() }
        }
    }

    /// Runs the 30 s liveness check only while sessions exist and the app is not paused (docs/08 rule 1).
    private func updateLivenessTimer() {
        let wanted = !paused && !snapshot.sessions.isEmpty
        guard wanted != (livenessTimer != nil) else { return }
        livenessTimer?.invalidate()
        livenessTimer = wanted ? Self.schedule(after: Self.livenessInterval, repeats: true) { [weak self] in
            self?.expireDeadSessions()
        } : nil
        livenessTimer?.tolerance = 5
    }

    /// Adds a main-run-loop timer in `.common` modes, so it still fires while a menu is tracking.
    private static func schedule(
        after interval: TimeInterval,
        repeats: Bool,
        _ action: @escaping @MainActor () -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats) { _ in MainActor.assumeIsolated { action() } }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func expireDeadSessions() {
        // EPERM means the process exists but belongs to someone else; only ESRCH means it is gone.
        store.expire(now: .now) { pid in kill(pid, 0) == 0 || errno != ESRCH }
        publish()
    }
}
