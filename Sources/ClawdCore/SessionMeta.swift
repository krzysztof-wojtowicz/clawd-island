// SessionMeta.swift
// Session metadata the bridge sends on SessionStart: the Claude Code process and its terminal (docs/05).

import Foundation

/// Metadata for one Claude Code session, posted by `clawd-bridge hook session-start` to `/session-meta`.
/// Process fields are optional because the bridge never fails, even when its process walk does.
public struct SessionMeta: Equatable, Sendable {
    public let sessionID: String
    public let cwd: String
    /// `startup`, `resume`, `clear`, `compact` or `fork`, kept as sent so new values never break decoding.
    public let source: String?
    /// The Claude Code process, used for liveness checks.
    public let pid: Int32?
    public let tty: String?
    public let terminalBundleID: String?
    public let termProgram: String?
}

extension SessionMeta {
    /// Decodes the bridge's snake_case JSON. Returns nil without `session_id` or `cwd`;
    /// missing or mistyped optional fields become nil.
    public init?(json data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionID = object["session_id"] as? String, !sessionID.isEmpty,
              let cwd = object["cwd"] as? String
        else { return nil }
        self.init(
            sessionID: sessionID,
            cwd: cwd,
            source: object["source"] as? String,
            pid: (object["pid"] as? Int).flatMap(Int32.init(exactly:)),
            tty: object["tty"] as? String,
            terminalBundleID: object["terminal_bundle_id"] as? String,
            termProgram: object["term_program"] as? String
        )
    }
}
