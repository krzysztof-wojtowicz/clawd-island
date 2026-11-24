// Session.swift
// One Claude Code session and its per-session transition table (docs/04-state-machine.md).

import Foundation

/// The inferred phase of a single session. The pet shows the aggregate of these, not each one.
public enum SessionState: Equatable, Sendable {
    case idle
    case thinking
    /// Between `PreToolUse` and its result. Never decays: a long tool run sends no events.
    case usingTools
    /// Streaming text, set by a `MessageDisplay` that finds the talking streak at least `SessionStore.talkingStreak` old; decays to `thinking`
    /// after `SessionStore.talkingDecay`.
    case talking
    /// Context compaction from `PreCompact`. Never decays; the next state-setting event or `SessionStart(compact)` ends it.
    case compacting
    /// Derived, never stored: `SessionStore.snapshot` shows a session with `activeSubagents > 0` (and not
    /// `needsInput` or `done`) as `juggling`.
    case juggling
    case needsInput
    case done
}

/// A live Claude Code session as the UI sees it.
public struct Session: Equatable, Sendable, Identifiable {
    public let id: String
    /// The last path component of the session's `cwd`.
    public internal(set) var projectName: String
    /// Assigning it ends the talking streak, so every state-setting event resets the streak (REQ-03 AC8).
    public internal(set) var state: SessionState {
        didSet { talkingStreakStart = nil }
    }
    public internal(set) var unread = false
    /// The last turn ended with `StopFailure` (API error).
    public internal(set) var failed = false
    public internal(set) var meta: SessionMeta?
    /// The tool of the last `PreToolUse`, for the tooltip only.
    public internal(set) var toolName: String?
    public internal(set) var lastEventAt: Date
    public internal(set) var activeSubagents = 0
    /// When the last `MessageDisplay` arrived; extends the talking streak and drives talking decay.
    var lastTalkingAt: Date?
    /// When the current run of `MessageDisplay` events began; nil after any state-setting event.
    var talkingStreakStart: Date?

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

    /// Sort key for the panel, lower first: `needsInput`, unread `done`, `juggling`, `compacting`, `usingTools`, `talking`, `thinking`, then everything else.
    /// Read `done` ranks as idle, matching the status buckets.
    var panelRank: Int {
        switch state {
        case .needsInput: 0
        case .done where unread: 1
        case .juggling: 2
        case .compacting: 3
        case .usingTools: 4
        case .talking: 5
        case .thinking: 6
        case .idle, .done: 7
        }
    }

    /// `state` with talking decay applied at `now`: `talking` becomes `thinking` once `talkingDecay` has passed
    /// since the last `MessageDisplay`.
    func talkingState(at now: Date) -> SessionState {
        guard state == .talking, let last = lastTalkingAt,
              now.timeIntervalSince(last) >= SessionStore.talkingDecay else { return state }
        return .thinking
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
            activeSubagents = 0
        case .preToolUse:
            state = .usingTools
            toolName = event.toolName
        case .messageDisplay:
            var start = now
            if let current = talkingStreakStart, let last = lastTalkingAt,
               now.timeIntervalSince(last) < SessionStore.talkingDecay { start = current }
            // Only a MessageDisplay promotes, so one sentence then silence never shows talking (REQ-03 AC8).
            // Stores the decayed state first so a new streak never inherits a stale `talking`; `didSet` clears the streak.
            state = now.timeIntervalSince(start) >= SessionStore.talkingStreak ? .talking : talkingState(at: now)
            talkingStreakStart = start
            lastTalkingAt = now
        case .postToolUse, .postToolBatch, .postToolUseFailure:
            state = .thinking
        case .preCompact:
            state = .compacting
        case .permissionRequest:
            state = .needsInput
        case .notification:
            if let type = event.notificationType, Self.inputNotifications.contains(type) { state = .needsInput }
        case .permissionDenied:
            if state == .needsInput { state = .thinking }
        case .subagentStart:
            // A late start after `Stop` would otherwise resurface as a stale juggling count once the session is read.
            if state != .done { activeSubagents += 1 }
        case .subagentStop:
            activeSubagents = max(0, activeSubagents - 1)
        case .stop, .stopFailure:
            // Subagents finishing must never mark the parent session done.
            guard event.agentID == nil else { return }
            state = .done
            unread = true
            activeSubagents = 0
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
