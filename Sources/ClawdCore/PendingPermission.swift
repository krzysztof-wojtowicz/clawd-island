// PendingPermission.swift
// A PermissionRequest hook held open so the notch can answer it (REQ-V2-01, ADR-0006).

import Foundation

/// One permission prompt waiting for an allow or deny from the notch.
public struct PendingPermission: Equatable, Sendable, Identifiable {
    /// Identifies the held connection in the app; assigned by the event server.
    public let id: UUID
    public let sessionID: String
    public let projectName: String
    public let toolName: String?
    /// What the tool wants to do, at most `ClawdEvent.maxSummaryLength` characters.
    public let summary: String
    /// What "Always allow" would save; nil hides that button.
    public var suggestion: PermissionSuggestion? = nil
    public let receivedAt: Date
}

/// The first `permission_suggestions` entry of a `PermissionRequest`, kept verbatim so it can be echoed back
/// in `updatedPermissions` (REQ-V2-01 AC7, AC9). The app never builds or edits a rule.
public struct PermissionSuggestion: Equatable, Sendable {
    /// Largest accepted entry, in bytes; a bigger one is dropped.
    public static let maxBytes = 2048

    /// The entry as a JSON object.
    public let json: String
    /// A short human description of the rule, for the tooltip, for example `Bash(rm -rf node_modules)`.
    public let rule: String

    /// Decodes the first element of the raw `permission_suggestions` value. Nil when absent, malformed or oversized.
    init?(suggestions: Any?) {
        guard let entry = (suggestions as? [Any])?.first as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: entry, options: [.withoutEscapingSlashes]),
              data.count <= Self.maxBytes, let json = String(data: data, encoding: .utf8) else { return nil }
        self.json = json
        rule = Self.describe(entry)
    }

    private static func describe(_ entry: [String: Any]) -> String {
        if let rules = entry["rules"] as? [[String: Any]], let first = rules.first, let tool = first["toolName"] as? String {
            let content = first["ruleContent"] as? String
            return content.map { "\(tool)(\($0))" } ?? tool
        }
        if let directories = entry["directories"] as? [String], !directories.isEmpty {
            return "access to " + directories.joined(separator: ", ")
        }
        let parts = ["type", "mode"].compactMap { entry[$0] as? String }
        return parts.isEmpty ? "permission rule" : parts.joined(separator: " ")
    }
}
