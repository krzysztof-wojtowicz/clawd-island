// NowPlayingWatcher.swift
// Listens for Music and Spotify play-state notifications (REQ-13, ADR-0007). Event-driven: no polling, no AppleScript.

import AppKit
import ClawdCore

/// Observes the distributed notifications Apple Music and Spotify post themselves on every play, pause, stop and
/// track change, and forwards each decoded report. Needs no permission. Delivery is on the main thread.
@MainActor
final class NowPlayingWatcher: NSObject {
    private let onReport: (NowPlaying) -> Void

    init(onReport: @escaping (NowPlaying) -> Void) {
        self.onReport = onReport
    }

    func start() {
        for app in NowPlaying.App.allCases {
            DistributedNotificationCenter.default().addObserver(
                self, selector: #selector(received(_:)), name: Notification.Name(app.notificationName), object: nil)
        }
    }

    @objc private func received(_ notification: Notification) {
        guard let report = NowPlaying(notificationName: notification.name.rawValue, userInfo: notification.userInfo) else { return }
        onReport(report)
    }
}
