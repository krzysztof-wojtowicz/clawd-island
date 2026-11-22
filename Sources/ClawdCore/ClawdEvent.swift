// ClawdEvent.swift
// A Claude Code hook event, decoded leniently from the raw hook JSON (docs/04, docs/05).

import Foundation

/// One hook event from Claude Code, reduced to the fields the state machine needs.
/// Large fields (`tool_input`, `prompt`, `last_assistant_message`) are never stored.
public struct ClawdEvent: Equatable, Sendable {
    /// The hook events ClawdIsland reacts to. Anything else decodes as `.unknown`.
    public enum Kind: String, Sendable {
        case userPromptSubmit = "UserPromptSubmit"
        case preToolUse = "PreToolUse"
        case messageDisplay = "MessageDisplay"
        case postToolUse = "PostToolUse"
        case postToolBatch = "PostToolBatch"
        case postToolUseFailure = "PostToolUseFailure"
        case preCompact = "PreCompact"
        case permissionRequest = "PermissionRequest"
        case permissionDenied = "PermissionDenied"
        case notification = "Notification"
        case subagentStart = "SubagentStart"
        case subagentStop = "SubagentStop"
        case stop = "Stop"
        case stopFailure = "StopFailure"
        case sessionEnd = "SessionEnd"
        case unknown
    }

    public let sessionID: String
    public let kind: Kind
    public let cwd: String?
    public let toolName: String?
    public let notificationType: String?
    /// Present when the event comes from a subagent rather than the main session.
    public let agentID: String?
    /// For `PermissionRequest`, `PostToolUse`, `PostToolUseFailure` and `PermissionDenied`: a short description of what the tool wants to do. Never the full `tool_input`.
    public var inputSummary: String? = nil
    /// For `PermissionRequest`: the first `permission_suggestions` entry, when present and small enough.
    public var suggestion: PermissionSuggestion? = nil
    public let receivedAt: Date

    /// Kinds that carry an `inputSummary`, so a finished tool can be matched to its pending permission card.
    static let summarisedKinds: Set<Kind> = [.permissionRequest, .postToolUse, .postToolUseFailure, .permissionDenied]

    /// Longest `inputSummary`, in characters.
    public static let maxSummaryLength = 120
}

extension ClawdEvent {
    /// Decodes a raw hook body. Returns nil only when the body is not a JSON object or lacks
    /// `hook_event_name` / `session_id`; unknown events and mistyped optional fields are tolerated.
    public init?(json data: Data, receivedAt: Date) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = object["hook_event_name"] as? String,
              let sessionID = object["session_id"] as? String, !sessionID.isEmpty
        else { return nil }
        let kind = Kind(rawValue: name) ?? .unknown
        let toolName = object["tool_name"] as? String
        self.init(
            sessionID: sessionID,
            kind: kind,
            cwd: object["cwd"] as? String,
            toolName: toolName,
            notificationType: object["notification_type"] as? String,
            agentID: object["agent_id"] as? String,
            inputSummary: Self.summarisedKinds.contains(kind)
                ? Self.summary(of: object["tool_input"] as? [String: Any], toolName: toolName) : nil,
            suggestion: kind == .permissionRequest ? PermissionSuggestion(suggestions: object["permission_suggestions"]) : nil,
            receivedAt: receivedAt
        )
    }

    /// The first of `command`, `file_path`, `url`, `pattern` that is a non-empty string (newlines flattened,
    /// cut to `maxSummaryLength`), else the tool name.
    private static func summary(of input: [String: Any]?, toolName: String?) -> String? {
        for key in ["command", "file_path", "url", "pattern"] {
            guard let text = input?[key] as? String, !text.isEmpty else { continue }
            let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            return String(flat.prefix(maxSummaryLength))
        }
        return toolName.map { String($0.prefix(maxSummaryLength)) }
    }
}
