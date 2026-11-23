// NewSessionCommand.swift
// Safe quoting for the "New session" launcher (REQ-18): shell first, then AppleScript.

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
    /// Nil unless `directory` is absolute and free of control characters: terminals receive the text as
    /// keystrokes, so a newline, ^U, ^C or ESC inside the quotes could change what runs.
    public static func scriptText(directory: String) -> String? {
        guard directory.hasPrefix("/"),
              !directory.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }) else { return nil }
        return appleScriptEscape("cd \(shellQuote(directory)) && claude")
    }
}
