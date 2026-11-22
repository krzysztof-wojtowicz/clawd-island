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
    private(set) var soundCues: Bool
    private(set) var headphones: Bool
    private(set) var focusReadMode: AppConfig.FocusReadMode
    /// "Approve permissions from the notch" (REQ-V2-01). Read per request on the server queue, hence a lock.
    nonisolated let notchPermissions: OSAllocatedUnfairLock<Bool>
    /// Called when "approve from the notch" is switched off, so held requests can be released.
    var onNotchPermissionsOff: (() -> Void)?
    /// Called after `hideMode` changes.
    var onHideModeChange: ((Bool) -> Void)?

    /// Called after `headphones` changes.
    var onHeadphonesChange: ((Bool) -> Void)?

    init() {
        let config = AppConfig.load()
        hideMode = config?.hideMode ?? false
        focusReadMode = config?.focusReadMode ?? .tab
        soundCues = config?.soundCues ?? true
        headphones = config?.headphones ?? true
        notchPermissions = OSAllocatedUnfairLock(initialState: config?.notchPermissions ?? true)
    }

    /// Sets and persists "approve permissions from the notch"; the event server picks it up on the next request.
    func setNotchPermissions(_ value: Bool) {
        notchPermissions.withLock { $0 = value }
        persist { $0.notchPermissions = value }
        if !value { onNotchPermissionsOff?() }
    }

    /// Sets and persists "Sound cues".
    func setSoundCues(_ value: Bool) {
        soundCues = value
        persist { $0.soundCues = value }
    }

    /// Sets and persists "Show headphones when music plays" (REQ-13 AC7).
    func setHeadphones(_ value: Bool) {
        guard value != headphones else { return }
        headphones = value
        persist { $0.headphones = value }
        onHeadphonesChange?(value)
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
        // Already first (the common case: every new session of the same project): no write.
        if let config = AppConfig.load(), config.recentProjects.first == directory { return config.recentProjects }
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
