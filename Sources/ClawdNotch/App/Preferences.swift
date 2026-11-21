// Preferences.swift
// Hide mode and focus-read mode, persisted in the shared config file (docs/03).

import ClawdCore
import os

/// The user's settings. The config file is re-read before every write, so a token or statusline saved by the
/// installer in the meantime is never overwritten with stale values.
@MainActor
final class Preferences {
    private static let logger = Logger(subsystem: "dev.clawdnotch", category: "prefs")

    private(set) var hideMode: Bool
    private(set) var focusReadMode: AppConfig.FocusReadMode
    /// Called after `hideMode` changes.
    var onHideModeChange: ((Bool) -> Void)?

    init() {
        let config = AppConfig.load()
        hideMode = config?.hideMode ?? false
        focusReadMode = config?.focusReadMode ?? .tab
    }

    /// Sets and persists hide mode.
    func setHideMode(_ value: Bool) {
        guard value != hideMode else { return }
        hideMode = value
        persist { $0.hideMode = value }
        onHideModeChange?(value)
    }

    /// Sets and persists the focus-read mode.
    func setFocusReadMode(_ value: AppConfig.FocusReadMode) {
        focusReadMode = value
        persist { $0.focusReadMode = value }
    }

    /// Records a directory as the most recent project (REQ-V2-03) and returns the updated list.
    /// The list comes from the file, so it is right even after another writer changed it.
    func noteRecentProject(_ directory: String) -> [String] {
        var recents: [String] = []
        persist { $0.noteRecentProject(directory); recents = $0.recentProjects }
        return recents
    }

    private func persist(_ change: (inout AppConfig) -> Void) {
        // An unreadable or missing file is left alone: it may hold the user's original statusline.
        guard var config = AppConfig.load() else {
            Self.logger.error("config.json unreadable; setting not saved")
            return
        }
        change(&config)
        do { try config.write() } catch { Self.logger.error("cannot save config: \(error.localizedDescription, privacy: .public)") }
    }
}
