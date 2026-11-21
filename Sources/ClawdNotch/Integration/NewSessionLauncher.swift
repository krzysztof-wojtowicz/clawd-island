// NewSessionLauncher.swift
// Opens a terminal window running `claude` in a chosen directory (REQ-V2-03).

import AppKit
import ClawdCore
import os

/// Starts new Claude Code sessions in Terminal.app or iTerm2 through AppleScript. Scripts run only in
/// response to a user action, never on a timer.
@MainActor
enum NewSessionLauncher {
    nonisolated private static let logger = Logger(subsystem: "dev.clawdnotch", category: "launcher")
    static let terminalApp = "com.apple.Terminal"
    static let iTerm = "com.googlecode.iterm2"
    private static let queue = DispatchQueue(label: "dev.clawdnotch.launcher", qos: .userInitiated)

    /// Opens a new window in the preferred terminal and runs `claude` in `directory`.
    /// - Parameter preferredTerminal: A terminal bundle ID; anything but iTerm2 means Terminal.app.
    static func launch(directory: URL, preferredTerminal: String?) {
        // Paths from hook payloads are untrusted: refuse anything that is not a plain absolute path.
        guard let text = NewSessionCommand.scriptText(directory: directory.path) else {
            logger.info("launch refused: unsafe directory")
            return
        }
        let source: String
        if preferredTerminal == iTerm {
            source = """
            tell application "iTerm2"
                activate
                set w to (create window with default profile)
                tell current session of w to write text "\(text)"
            end tell
            """
        } else {
            source = """
            tell application "Terminal"
                do script "\(text)"
                activate
            end tell
            """
        }
        // The script can block on the Automation prompt, so keep it off the main thread.
        queue.async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error { logger.info("launch failed: \(error[NSAppleScript.errorNumber] as? Int ?? 0)") }
        }
    }

    /// Shows a folder picker (activating the app so it is visible) and returns the choice, or nil if cancelled.
    static func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Start Session"
        NSApp.activate()
        return panel.runModal() == .OK ? panel.url : nil
    }
}
