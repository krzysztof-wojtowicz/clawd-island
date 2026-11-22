// WindowTitle.swift
// Matching editor window titles to project names (REQ-V2-02).

import Foundation

/// Matches editor window titles against a project name. The title shape depends on the editor family.
public enum WindowTitle {
    /// Title conventions: VS Code is "file - project - Visual Studio Code", JetBrains is "project – file".
    public enum Family: Sendable {
        case vscode, jetbrains

        /// The family of an editor bundle ID: the `com.jetbrains.` prefix is JetBrains, anything else VS Code.
        public init(bundleID: String) {
            self = bundleID.hasPrefix("com.jetbrains.") ? .jetbrains : .vscode
        }
    }

    /// The index of the best window for `project`: the first title whose project segment equals it, else the
    /// first title containing it. Nil for an empty project or no match.
    public static func bestMatch(project: String, in titles: [String], family: Family = .vscode) -> Int? {
        guard !project.isEmpty else { return nil }
        if let exact = titles.firstIndex(where: { candidates(of: $0, family).contains(project) }) { return exact }
        return titles.firstIndex { $0.contains(project) }
    }

    /// Whether one title matches `project`, by the same rule.
    public static func matches(_ title: String, project: String, family: Family = .vscode) -> Bool {
        bestMatch(project: project, in: [title], family: family) != nil
    }

    /// The segments that may name the project: all but the app name for VS Code, only the first for JetBrains.
    private static func candidates(of title: String, _ family: Family) -> [String] {
        let parts = title.replacingOccurrences(of: " — ", with: "\u{0}")
            .replacingOccurrences(of: " – ", with: "\u{0}")
            .replacingOccurrences(of: " - ", with: "\u{0}")
            .split(separator: "\u{0}", omittingEmptySubsequences: false).map(String.init)
        switch family {
        case .vscode: return Array(parts.dropLast())
        case .jetbrains: return Array(parts.prefix(1))
        }
    }
}
