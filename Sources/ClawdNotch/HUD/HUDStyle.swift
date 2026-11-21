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

    /// The session counter circle (docs/06, first match wins): red for needs-input, orange for an unread `done`,
    /// blue while sessions exist, grey otherwise.
    static func counterColor(_ snapshot: Snapshot) -> CGColor {
        if snapshot.hasNeedsInput { return PetTokens.badgeAlert }
        if snapshot.attentionCount > 0 { return PetTokens.body }
        return snapshot.activeCount > 0 ? PetTokens.badgeActive : PetTokens.badgeEmpty
    }

    /// One line on the usage windows, e.g. "HP 63% · resets in 1h 12m · WEEK 81%", each percentage tinted with its
    /// HP band colour. The WEEK part is omitted while the weekly window is unknown. Computed at `now`, never ticking.
    static func usageLine(_ usage: UsageSnapshot?, now: Date) -> NSAttributedString {
        guard let usage, let hp = usage.hitPoints(now: now) else { return NSAttributedString(string: "Usage unknown") }
        let line = NSMutableAttributedString()
        // Attributed strings ignore the label's textColor, so untinted runs carry the secondary colour themselves.
        func plain(_ text: String) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [.foregroundColor: NSColor.secondaryLabelColor])
        }
        func percent(_ hp: HitPoints) -> NSAttributedString {
            let text = "\(hp.percent.formatted(.number.precision(.fractionLength(0...1))))%"
            return NSAttributedString(string: text, attributes: [.foregroundColor: color(token(for: hp.level))])
        }
        line.append(plain("HP "))
        line.append(percent(hp))
        if hp.isStale {
            line.append(plain(" · window reset, waiting for fresh data"))
        } else if let resetsAt = usage.resetsAt {
            let left = Duration.seconds(max(resetsAt.timeIntervalSince(now), 60))
            line.append(plain(" · resets in \(left.formatted(.units(allowed: [.hours, .minutes], width: .narrow)))"))
        }
        if let week = usage.weekRemaining(now: now) {
            line.append(plain(" · WEEK "))
            line.append(percent(week))
        }
        return line
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
