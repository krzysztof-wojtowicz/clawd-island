// WindowTitle.swift
// Matching editor window titles to project names (REQ-V2-02).

import Foundation

/// Matches VS Code-style window titles ("file — project — Visual Studio Code") against a project name.
public enum WindowTitle {
    /// The index of the best window for `project`: the first title with a segment equal to it, else the first
    /// title containing it. Nil for an empty project or no match.
    public static func bestMatch(project: String, in titles: [String]) -> Int? {
        guard !project.isEmpty else { return nil }
        if let exact = titles.firstIndex(where: { segments(of: $0).contains(project) }) { return exact }
        return titles.firstIndex { $0.contains(project) }
    }

    /// Whether one title matches `project`, by the same rule.
    public static func matches(_ title: String, project: String) -> Bool {
        bestMatch(project: project, in: [title]) != nil
    }

    /// The title split on " — " and " - " without its last segment, which is the app name.
    private static func segments(of title: String) -> [String] {
        let parts = title.replacingOccurrences(of: " — ", with: "\u{0}")
            .replacingOccurrences(of: " - ", with: "\u{0}")
            .split(separator: "\u{0}", omittingEmptySubsequences: false).map(String.init)
        return Array(parts.dropLast())
    }
}
