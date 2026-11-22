// LoginItem.swift
// Launch at login through SMAppService (REQ-05 AC3).

import ServiceManagement
import os

/// Thin wrapper over `SMAppService.mainApp`. The status is always read back, never cached, because registration
/// can fail (for example for an ad-hoc signed bundle outside /Applications) or be changed in System Settings.
enum LoginItem {
    private static let logger = Logger(subsystem: "dev.clawdisland", category: "login")

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Registers or unregisters the app; failures are only logged.
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            // shortcut: no UI feedback on failure; the menu checkmark and Settings just stay as the real status says.
            logger.error("login item change failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
