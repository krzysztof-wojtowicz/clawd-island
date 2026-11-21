// HUDStyle.swift
// Shared text and colour helpers for the counters and the session panel, so both describe a Snapshot identically.

import AppKit
import ClawdCore

/// Labels, colours and wording used by every HUD view (REQ-04 AC1: counters and panel share one vocabulary).
@MainActor
enum HUDStyle {
    /// A non-editable label; the island is always dark, so the semantic label colours resolve to light text.
    static func label(size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    /// Bridges a `PetTokens` colour to AppKit.
    static func color(_ token: CGColor) -> NSColor {
        // The tokens are sRGB, which NSColor always accepts; the fallback is unreachable.
        NSColor(cgColor: token) ?? .labelColor
    }

    /// The bar colour for an HP band (docs/07 `hp.high` / `hp.mid` / `hp.low`).
    static func token(for level: HitPoints.Level) -> CGColor {
        switch level {
        case .high: PetTokens.hpHigh
        case .mid: PetTokens.hpMid
        case .low: PetTokens.hpLow
        }
    }

    /// One line on the 5-hour window, e.g. "HP 63% · resets in 1h 12m". Computed at `now`, never ticking.
    static func usageLine(_ usage: UsageSnapshot?, now: Date) -> String {
        guard let usage, let hp = usage.hitPoints(now: now) else { return "Usage unknown" }
        if hp.isStale { return "HP 100% · window reset, waiting for fresh data" }
        let percent = "HP \(hp.percent.formatted(.number.precision(.fractionLength(0...1))))%"
        guard let resetsAt = usage.resetsAt else { return percent }
        let left = Duration.seconds(max(resetsAt.timeIntervalSince(now), 60))
        return "\(percent) · resets in \(left.formatted(.units(allowed: [.hours, .minutes], width: .narrow)))"
    }

    /// The counters in words, for the tooltip and VoiceOver.
    static func countsLine(_ snapshot: Snapshot) -> String {
        "\(snapshot.activeCount) active · \(snapshot.attentionCount) need\(snapshot.attentionCount == 1 ? "s" : "") attention"
    }

    /// A session's state as shown in the panel.
    static func stateText(_ session: Session) -> String {
        switch session.state {
        case .idle: "idle"
        case .thinking: "thinking"
        case .usingTools: "using \(session.toolName ?? "a tool")"
        case .talking: "writing"
        case .needsInput: "needs input"
        case .done: session.failed ? "failed" : "done"
        }
    }
}
