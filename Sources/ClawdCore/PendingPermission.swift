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
    public let receivedAt: Date
}
