// NewSessionCommand.swift
// Safe quoting for the "New session" launcher (REQ-V2-03): shell first, then AppleScript.

import Foundation

/// Builds the shell command a new terminal runs, quoted so a directory name can never change its meaning.
public enum NewSessionCommand {
    /// `path` in single quotes for a POSIX shell; each `'` becomes `'\''`.
    public static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// `text` escaped for the inside of an AppleScript string literal (`\` and `"`).
    public static func appleScriptEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// `cd '<dir>' && claude`, escaped and ready to sit between the quotes of an AppleScript string.
    public static func scriptText(directory: String) -> String {
        appleScriptEscape("cd \(shellQuote(directory)) && claude")
    }
}
