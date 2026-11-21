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
    var serverError: String?
    /// Called after `snapshot` changes, with the previous and the new value.
    @ObservationIgnored var onSnapshotChange: ((_ old: Snapshot, _ new: Snapshot) -> Void)?
    /// Recently used project directories, newest first, at most 5 (REQ-V2-03). Feeds the "+ New" menu.
    private(set) var recentProjects: [String] = AppConfig.load()?.recentProjects ?? []
    /// Persists one directory as the newest recent project and returns the stored list (empty on failure).
    @ObservationIgnored var recordProject: ((String) -> [String])?
    @ObservationIgnored private var seenSessionIDs: Set<String> = []

    @ObservationIgnored private var store: SessionStore
    @ObservationIgnored private var publishPending = false
    @ObservationIgnored private var decayTimer: Timer?
    @ObservationIgnored private var livenessTimer: Timer?
    @ObservationIgnored private var paused = false
    /// Held `PermissionRequest` connections by `PendingPermission.id`; an entry exists exactly while its card does.
    @ObservationIgnored private var responders: [UUID: PermissionResponder] = [:]
    @ObservationIgnored private var permissionTimer: Timer?

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

    /// Applies a held `PermissionRequest`: the event moves the session to `needsInput` and a card appears.
    func receive(permission event: ClawdEvent, responder: PermissionResponder) {
        store.apply(event, now: .now)
        store.addPermission(id: responder.id, for: event)
        responders[responder.id] = responder
        publish()
    }

    /// Answers a card from the notch (REQ-V2-01): allow or deny, once. Unknown or already closed ids are ignored.
    func decide(permissionID: UUID, allow: Bool) {
        guard let responder = responders.removeValue(forKey: permissionID) else { return }
        responder.reply(allow ? .allow : .deny)
        store.resolvePermission(permissionID)
        publish()
    }

    /// Replies empty to every held request and drops its card, so Claude Code falls back to its terminal dialog
    /// (the setting was switched off, docs/05).
    func releaseAllPermissions() {
        let held = responders
        guard !held.isEmpty else { return }
        responders.removeAll()
        for (id, responder) in held {
            responder.reply(.none)
            store.resolvePermission(id)
        }
        publish()
    }

    /// The client of a held request hung up, so its card is stale.
    func permissionClosed(_ id: UUID) {
        guard responders.removeValue(forKey: id) != nil else { return }
        store.resolvePermission(id)
        publish()
    }

    /// Starts a new Claude Code session in `directory` (REQ-V2-03), in the terminal of the most recently
    /// active session when that is Terminal.app or iTerm2, else Terminal.app.
    func newSession(at directory: URL) {
        let latest = snapshot.sessions.max { $0.lastEventAt < $1.lastEventAt }
        NewSessionLauncher.launch(directory: directory, preferredTerminal: latest?.meta?.terminalBundleID)
        noteProject(directory.path)
    }

    /// Asks the user for a folder and starts a session there; does nothing if cancelled.
    func chooseFolderAndStartSession() {
        if let url = NewSessionLauncher.chooseFolder() { newSession(at: url) }
    }

    private func noteProject(_ directory: String) {
        let stored = recordProject?(directory) ?? []
        if !stored.isEmpty { recentProjects = stored }
    }

    /// Records the `cwd` of each session the first time its metadata is seen.
    private func recordNewProjects(in sessions: [Session]) {
        for session in sessions where !seenSessionIDs.contains(session.id) {
            guard let cwd = session.meta?.cwd else { continue }
            seenSessionIDs.insert(session.id)
            noteProject(cwd)
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
        store.expirePermissions(now: now)
        let next = store.snapshot(now: now)
        releaseStaleResponders(keeping: next.pendingPermissions)
        schedulePermissionExpiry(now: now)
        recordNewProjects(in: next.sessions)
        if next != snapshot {
            let old = snapshot
            snapshot = next
            Self.logger.debug("snapshot \(next.aggregate.rawValue, privacy: .public) active=\(next.activeCount) attention=\(next.attentionCount) pop=\(next.popToken)")
            onSnapshotChange?(old, next)
        }
        scheduleDecay(now: now)
        updateLivenessTimer()
    }

    /// Replies empty to held requests whose card the store dropped (session moved on, ended, or the 110 s cap).
    private func releaseStaleResponders(keeping pending: [PendingPermission]) {
        guard !responders.isEmpty else { return }
        let live = Set(pending.map(\.id))
        for id in responders.keys where !live.contains(id) {
            responders.removeValue(forKey: id)?.reply(.none)
        }
    }

    /// One shared one-shot timer for the oldest pending permission's cap; no polling.
    private func schedulePermissionExpiry(now: Date) {
        permissionTimer?.invalidate()
        permissionTimer = store.nextPermissionDeadline().map { deadline in
            Self.schedule(after: max(0, deadline.timeIntervalSince(now)), repeats: false) { [weak self] in self?.publish() }
        }
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
