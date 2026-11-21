// HUDController.swift
// Binds each new Snapshot to the counters and the session panel, and re-renders once when the usage window resets.

import AppKit
import ClawdCore

/// Owns the HUD views. Both are drawn from the same `Snapshot`, so the counters always match the panel
/// (REQ-04 AC1). The only timer is a one-shot at `resetsAt`, which flips the HP bar to full and stale (AC3).
@MainActor
final class HUDController {
    let counters = CountersView()
    private let model: AppModel
    private let focus: (Session) -> Void
    /// Built on the first expand (docs/08); nil until then.
    private var panel: SessionPanelView?

    private var snapshot: Snapshot?
    private var resetTimer: Timer?

    init(model: AppModel, focus: @escaping (Session) -> Void) {
        self.model = model
        self.focus = focus
    }

    /// Builds the session panel, draws the latest snapshot into it and returns it. Called once, on the first expand.
    func makePanel() -> SessionPanelView {
        let panel = SessionPanelView()
        // A click only focuses; the watcher marks the session read once its tab is in front (REQ-10 AC2).
        panel.onSelect = { [model, focus] id in
            if let session = model.snapshot.sessions.first(where: { $0.id == id }) { focus(session) }
        }
        panel.onMarkAllRead = { [model] in model.markAllRead() }
        panel.recentProjects = { [model] in model.recentProjects }
        panel.onNewSession = { [model] url in model.newSession(at: url) }
        panel.onChooseFolder = { [model] in model.chooseFolderAndStartSession() }
        panel.onDecide = { [model] id, allow in model.decide(permissionID: id, allow: allow) }
        if let snapshot { panel.render(snapshot) }
        self.panel = panel
        return panel
    }

    /// Draws `snapshot` into both views.
    func render(_ snapshot: Snapshot) {
        self.snapshot = snapshot
        let now = Date.now
        counters.render(snapshot, now: now)
        panel?.render(snapshot)
        scheduleResetRender(at: snapshot.usage?.resetsAt, now: now)
    }

    /// Keeps one one-shot timer at `resetsAt` that re-renders the HP bar as stale; reuses it while `resetsAt` is unchanged.
    private func scheduleResetRender(at resetsAt: Date?, now: Date) {
        if let resetTimer, resetTimer.isValid, resetTimer.fireDate == resetsAt { return }
        resetTimer?.invalidate()
        resetTimer = nil
        guard let resetsAt, resetsAt > now else { return }
        let timer = Timer(fire: resetsAt, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let snapshot = self.snapshot else { return }
                self.render(snapshot)
            }
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        resetTimer = timer
    }
}
