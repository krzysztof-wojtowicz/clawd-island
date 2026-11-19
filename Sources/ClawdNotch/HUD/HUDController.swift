// HUDController.swift
// Binds each new Snapshot to the counters and the session panel, and re-renders once when the usage window resets.

import AppKit
import ClawdCore

/// Owns the HUD views. Both are drawn from the same `Snapshot`, so the counters always match the panel
/// (REQ-04 AC1). The only timer is a one-shot at `resetsAt`, which flips the HP bar to full and stale (AC3).
@MainActor
final class HUDController {
    let counters = CountersView()
    let panel = SessionPanelView()

    private var snapshot: Snapshot?
    private var resetTimer: Timer?

    init(model: AppModel) {
        panel.onSelect = { [model] id in
            model.markRead(id)
            // TODO(WP-6): focus the session's terminal (REQ-10 AC2).
        }
        panel.onMarkAllRead = { [model] in model.markAllRead() }
    }

    /// Draws `snapshot` into both views.
    func render(_ snapshot: Snapshot) {
        self.snapshot = snapshot
        let now = Date.now
        counters.render(snapshot, now: now)
        panel.render(snapshot)
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
