// ClawdEvent.swift
// A Claude Code hook event, decoded leniently from the raw hook JSON (docs/04, docs/05).

import Foundation

/// One hook event from Claude Code, reduced to the fields the state machine needs.
/// Large fields (`tool_input`, `prompt`, `last_assistant_message`) are never stored.
public struct ClawdEvent: Equatable, Sendable {
    /// The hook events ClawdNotch reacts to. Anything else decodes as `.unknown`.
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
    public let receivedAt: Date
}

extension ClawdEvent {
    /// Decodes a raw hook body. Returns nil only when the body is not a JSON object or lacks
    /// `hook_event_name` / `session_id`; unknown events and mistyped optional fields are tolerated.
    public init?(json data: Data, receivedAt: Date) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = object["hook_event_name"] as? String,
              let sessionID = object["session_id"] as? String, !sessionID.isEmpty
        else { return nil }
        self.init(
            sessionID: sessionID,
            kind: Kind(rawValue: name) ?? .unknown,
            cwd: object["cwd"] as? String,
            toolName: object["tool_name"] as? String,
            notificationType: object["notification_type"] as? String,
            agentID: object["agent_id"] as? String,
            receivedAt: receivedAt
        )
    }
}
