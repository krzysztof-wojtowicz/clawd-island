// EditorWindows.swift
// Window-level lookup and raise for the VS Code family through the Accessibility API (REQ-V2-02).

import AppKit
import ApplicationServices

/// Finds and raises editor windows by project name. Without the Accessibility grant every call returns
/// nil/false, so callers fall back to app level.
@MainActor
enum EditorWindows {
    /// VS Code, Insiders, VSCodium, Cursor and Windsurf.
    static let bundleIDs: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium",
        "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf",
    ]

    private static var asked = false

    /// Whether Accessibility is granted. The system prompt is shown at most once per launch, on the first call.
    static func isTrusted() -> Bool {
        if asked { return AXIsProcessTrusted() }
        asked = true
        // The literal is `kAXTrustedCheckOptionPrompt`, which Swift 6 rejects as a mutable global.
        return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Raises the first window of `app` whose title contains `project`. Returns whether one was found.
    static func raise(project: String, in app: NSRunningApplication) -> Bool {
        guard isTrusted() else { return false }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.5)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement],
              let match = windows.first(where: { title(of: $0)?.contains(project) == true }) else { return false }
        return AXUIElementPerformAction(match, kAXRaiseAction as CFString) == .success
    }

    /// The title of the app's focused window, or nil without trust or a focused window.
    static func focusedWindowTitle(of app: NSRunningApplication) -> String? {
        guard isTrusted() else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.5)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let window = value, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        return title(of: window as! AXUIElement)
    }

    private static func title(of window: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
