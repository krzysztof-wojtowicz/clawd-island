// EditorWindows.swift
// Window-level lookup and raise for the VS Code family and JetBrains IDEs through the Accessibility API (REQ-17).

import AppKit
import ApplicationServices
import ClawdCore

/// Finds and raises editor windows by project name. Without the Accessibility grant every call returns
/// nil/false, so callers fall back to app level. The AX lookups can block on a busy editor, so they are
/// `nonisolated` and callers run them off the main thread.
enum EditorWindows {
    /// VS Code, Insiders, VSCodium, Cursor and Windsurf.
    static let bundleIDs: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium",
        "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf",
    ]

    /// Whether `bundleID` is a VS Code-family editor or any JetBrains IDE (`com.jetbrains.` prefix).
    static func handles(_ bundleID: String) -> Bool {
        bundleIDs.contains(bundleID) || bundleID.hasPrefix("com.jetbrains.")
    }

    private static let timeout: Float = 0.2

    /// Whether Accessibility is granted, without any prompt (the activation path).
    static func isTrusted() -> Bool { AXIsProcessTrusted() }

    /// Whether Accessibility is granted, showing the system prompt if not. Prompts at most once per launch,
    /// so call it only from a user click, never on a plain app switch.
    @MainActor
    static func requestTrust() -> Bool {
        if asked { return AXIsProcessTrusted() }
        asked = true
        // The literal is `kAXTrustedCheckOptionPrompt`, which Swift 6 rejects as a mutable global.
        return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    @MainActor private static var asked = false

    /// Raises the best window of `pid` for `project` (see `WindowTitle`). Returns whether one was raised.
    nonisolated static func raise(project: String, pid: pid_t, family: WindowTitle.Family) -> Bool {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, timeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return false }
        let titles = windows.map { title(of: $0) ?? "" }
        guard let index = WindowTitle.bestMatch(project: project, in: titles, family: family) else { return false }
        return AXUIElementPerformAction(windows[index], kAXRaiseAction as CFString) == .success
    }

    /// The title of the app's focused window, or nil without one.
    nonisolated static func focusedWindowTitle(pid: pid_t) -> String? {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, timeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let window = value, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        // safe: type id checked above
        return title(of: unsafeDowncast(window, to: AXUIElement.self))
    }

    nonisolated private static func title(of window: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
