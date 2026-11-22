// NowPlayingWatcher.swift
// Listens for Music and Spotify play-state notifications (REQ-13, ADR-0007). Event-driven: no polling, no AppleScript.

import AppKit
import ClawdCore

/// Observes the distributed notifications Apple Music and Spotify post themselves on every play, pause, stop and
/// track change, and forwards each decoded report. Needs no permission. Delivery is on the main queue.
@MainActor
final class NowPlayingWatcher {
    private let onReport: (NowPlaying) -> Void
    private var tokens: [any NSObjectProtocol] = []

    init(onReport: @escaping (NowPlaying) -> Void) {
        self.onReport = onReport
    }

    // shortcut: the apps post only on change, so after launch the state is unknown until the next play, pause or
    // track change (REQ-13 AC5). Upgrade: ask the player once at start, which needs Automation permission.
    func start() {
        guard tokens.isEmpty else { return }
        for app in NowPlaying.App.allCases {
            let token = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(app.notificationName), object: nil, queue: .main
            ) { [weak self] notification in
                // Decoded first: `Notification` is not Sendable, the `NowPlaying` report is.
                guard let report = NowPlaying(
                    notificationName: notification.name.rawValue, userInfo: notification.userInfo) else { return }
                MainActor.assumeIsolated { self?.onReport(report) }
            }
            tokens.append(token)
        }
    }

    /// Removes the observers; `start()` may be called again.
    func stop() {
        tokens.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        tokens = []
    }
}
