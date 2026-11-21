// Session.swift
// One Claude Code session and its per-session transition table (docs/04-state-machine.md).

import Foundation

/// The inferred phase of a single session. The pet shows the aggregate of these, not each one.
public enum SessionState: Equatable, Sendable {
    case idle
    case thinking
    /// Between `PreToolUse` and its result. Never decays: a long tool run sends no events.
    case usingTools
    /// Streaming text; decays to `thinking` after `SessionStore.talkingDecay`.
    case talking
    case needsInput
    case done
}

/// A live Claude Code session as the UI sees it.
public struct Session: Equatable, Sendable, Identifiable {
    public let id: String
    /// The last path component of the session's `cwd`.
    public internal(set) var projectName: String
    public internal(set) var state: SessionState
    public internal(set) var unread = false
    /// The last turn ended with `StopFailure` (API error).
    public internal(set) var failed = false
    public internal(set) var meta: SessionMeta?
    /// The tool of the last `PreToolUse`, for the tooltip only.
    public internal(set) var toolName: String?
    public internal(set) var lastEventAt: Date
    public internal(set) var activeSubagents = 0
    /// When the session last entered or refreshed `talking`; drives talking decay.
    var lastTalkingAt: Date?

    /// Waiting for the user, or finished and not yet seen; drives the pop-out, the orange counter and "Mark all read".
    public var needsAttention: Bool {
        state == .needsInput || (state == .done && unread)
    }

    init(id: String, cwd: String?, now: Date) {
        self.id = id
        self.projectName = cwd.map(Self.projectName(for:)) ?? id
        self.state = .idle
        self.lastEventAt = now
    }

    // Timestamps change on every event; comparing them would make each MessageDisplay a new snapshot.
    // Any new user-visible field must be added here, or the UI will not re-render for it.
    public static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.id == rhs.id && lhs.projectName == rhs.projectName && lhs.state == rhs.state
            && lhs.unread == rhs.unread && lhs.failed == rhs.failed && lhs.meta == rhs.meta
            && lhs.toolName == rhs.toolName && lhs.activeSubagents == rhs.activeSubagents
    }

    /// Sort key for the panel, lower first: `needsInput`, unread `done`, `usingTools`, `talking`, `thinking`, then everything else.
    /// Read `done` ranks as idle, matching the status buckets.
    var panelRank: Int {
        switch state {
        case .needsInput: 0
        case .done where unread: 1
        case .usingTools: 2
        case .talking: 3
        case .thinking: 4
        case .idle, .done: 5
        }
    }

    static func projectName(for cwd: String) -> String {
        (cwd as NSString).lastPathComponent
    }

    private static let inputNotifications: Set<String> = [
        "permission_prompt", "elicitation_dialog", "agent_needs_input",
    ]

    /// Applies one hook event per the transition table. `SessionEnd` is handled by the store.
    mutating func apply(_ event: ClawdEvent, now: Date) {
        lastEventAt = now
        if let cwd = event.cwd { projectName = Self.projectName(for: cwd) }
        switch event.kind {
        case .userPromptSubmit:
            state = .thinking
            unread = false
            failed = false
        case .preToolUse:
            state = .usingTools
            toolName = event.toolName
        case .messageDisplay:
            state = .talking
            lastTalkingAt = now
        case .postToolUse, .postToolBatch, .postToolUseFailure, .preCompact:
            state = .thinking
        case .permissionRequest:
            state = .needsInput
        case .notification:
            if let type = event.notificationType, Self.inputNotifications.contains(type) { state = .needsInput }
        case .permissionDenied:
            if state == .needsInput { state = .thinking }
        case .subagentStart:
            activeSubagents += 1
        case .subagentStop:
            activeSubagents = max(0, activeSubagents - 1)
        case .stop, .stopFailure:
            // Subagents finishing must never mark the parent session done.
            guard event.agentID == nil else { return }
            state = .done
            unread = true
            if event.kind == .stopFailure { failed = true }
        case .sessionEnd, .unknown:
            break
        }
    }

    /// Clears `unread`; a read `done` session becomes `idle` (REQ-10).
    mutating func markRead() {
        unread = false
        if state == .done { state = .idle }
    }
}
