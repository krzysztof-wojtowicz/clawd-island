// CountersView.swift
// The right wing: active count, attention badge and the HP bar (REQ-04).

import AppKit
import ClawdCore

/// Renders the counters of one `Snapshot`. The HP bar is hidden while usage is unknown (REQ-04 AC2) and dimmed
/// when stale (AC3). The tooltip text is built when AppKit asks for it, so the reset countdown needs no timer.
final class CountersView: NSView, NSViewToolTipOwner {
    private static let barHeight: CGFloat = 3
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
        barTrack.cornerRadius = Self.barHeight / 2
        barFill.cornerRadius = Self.barHeight / 2
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
        attentionLabel.isHidden = snapshot.attentionCount == 0
        attentionLabel.layer?.backgroundColor = snapshot.hasNeedsInput ? PetTokens.badgeAlert : PetTokens.body
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
        let rowHeight = bounds.height - Self.barHeight - 3
        let badgeHeight: CGFloat = 14
        activeLabel.frame = CGRect(x: 0, y: bounds.maxY - rowHeight, width: bounds.width / 2, height: rowHeight)
        let badgeWidth = max(badgeHeight, attentionLabel.intrinsicContentSize.width + 6)
        attentionLabel.frame = CGRect(
            x: bounds.maxX - badgeWidth,
            y: bounds.maxY - rowHeight + (rowHeight - badgeHeight) / 2,
            width: badgeWidth,
            height: badgeHeight
        )
        attentionLabel.layer?.cornerRadius = badgeHeight / 2
        let track = CGRect(x: 0, y: 1, width: bounds.width, height: Self.barHeight)
        barTrack.frame = track
        barFill.frame = CGRect(x: track.minX, y: track.minY, width: track.width * hpFraction, height: track.height)
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
