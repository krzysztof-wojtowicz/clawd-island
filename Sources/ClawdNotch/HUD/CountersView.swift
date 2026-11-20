// CountersView.swift
// The right wing's HP bar and counts column (REQ-04); the pet shows through the gap between them.

import AppKit
import ClawdCore

/// Renders the counters of one `Snapshot`: a vertical HP bar at the left edge, filling bottom-up, and a counts column
/// at the right edge (active count on top, attention badge below; both always visible). The HP bar is hidden while
/// usage is unknown (REQ-04 AC2) and full but dimmed when stale (AC3). The tooltip text is built when AppKit asks
/// for it, so the reset countdown needs no timer.
final class CountersView: NSView, NSViewToolTipOwner {
    /// Width of the vertical HP bar at the left edge.
    static let barWidth: CGFloat = 3
    /// Width of the counts column at the right edge.
    static let columnWidth: CGFloat = 14
    private static let badgeSize: CGFloat = 14
    private static let staleOpacity: Float = 0.4

    private let activeLabel = HUDStyle.label(size: 11, weight: .semibold)
    private let attentionLabel = HUDStyle.label(size: 10, weight: .bold, color: HUDStyle.color(PetTokens.badgeGlyph))
    private let barTrack = CALayer()
    private let barFill = CALayer()
    private var snapshot: Snapshot?
    private var hpFraction: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        activeLabel.alignment = .center
        attentionLabel.alignment = .center
        attentionLabel.wantsLayer = true
        attentionLabel.layer?.cornerCurve = .continuous
        for label in [activeLabel, attentionLabel] {
            // The container speaks for the counters as a whole.
            label.setAccessibilityElement(false)
            addSubview(label)
        }
        barTrack.backgroundColor = PetTokens.bubbleFill
        barTrack.opacity = 0.2
        barTrack.cornerRadius = Self.barWidth / 2
        barFill.cornerRadius = Self.barWidth / 2
        layer?.addSublayer(barTrack)
        layer?.addSublayer(barFill)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows `snapshot`; `now` decides whether the usage window has already reset.
    func render(_ snapshot: Snapshot, now: Date) {
        self.snapshot = snapshot
        activeLabel.stringValue = "\(snapshot.activeCount)"
        attentionLabel.stringValue = "\(snapshot.attentionCount)"
        attentionLabel.layer?.backgroundColor = snapshot.hasNeedsInput ? PetTokens.badgeAlert
            : snapshot.attentionCount > 0 ? PetTokens.body : PetTokens.badgeCalm
        let hp = snapshot.usage?.hitPoints(now: now)
        barTrack.isHidden = hp == nil
        barFill.isHidden = hp == nil
        if let hp {
            hpFraction = hp.percent / 100
            barFill.backgroundColor = HUDStyle.token(for: hp.level)
            barFill.opacity = hp.isStale ? Self.staleOpacity : 1
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let columnMidX = bounds.maxX - Self.columnWidth / 2
        // Two-digit counts may be a little wider than the column; they spill evenly past both column edges.
        let activeWidth = max(Self.columnWidth, activeLabel.intrinsicContentSize.width)
        activeLabel.frame = CGRect(
            x: columnMidX - activeWidth / 2,
            y: Self.badgeSize,
            width: activeWidth,
            height: bounds.height - Self.badgeSize
        )
        let badgeWidth = max(Self.badgeSize, attentionLabel.intrinsicContentSize.width + 4)
        attentionLabel.frame = CGRect(x: columnMidX - badgeWidth / 2, y: 0, width: badgeWidth, height: Self.badgeSize)
        attentionLabel.layer?.cornerRadius = Self.badgeSize / 2
        let track = CGRect(x: 0, y: 0, width: Self.barWidth, height: bounds.height)
        barTrack.frame = track
        barFill.frame = CGRect(x: track.minX, y: track.minY, width: track.width, height: track.height * hpFraction)
        removeAllToolTips()
        addToolTip(bounds, owner: self, userData: nil)
    }

    /// Built on demand, like the tooltip, so the reset countdown is current when VoiceOver reads it.
    override func accessibilityLabel() -> String? {
        guard let snapshot else { return nil }
        return "\(HUDStyle.countsLine(snapshot)), \(HUDStyle.usageLine(snapshot.usage, now: .now))"
    }

    func view(
        _ view: NSView,
        stringForToolTip tag: NSView.ToolTipTag,
        point: NSPoint,
        userData data: UnsafeMutableRawPointer?
    ) -> String {
        guard let snapshot else { return "" }
        return "\(HUDStyle.usageLine(snapshot.usage, now: .now))\n\(HUDStyle.countsLine(snapshot))"
    }
}
