// CountersView.swift
// The right wing's HP bar and counts column (REQ-04); the pet shows through the gap between them.

import AppKit
import ClawdCore

/// Renders the counters of one `Snapshot`: a vertical HP bar at the left edge, filling bottom-up, and ONE session
/// counter (`activeCount`) at the right edge, centred in a circle that is always shown, also at 0 (REQ-04 AC1).
/// The circle colour comes from `HUDStyle.counterColor`. The HP bar is hidden while usage is unknown (AC2) and full
/// but dimmed when stale (AC3). The tooltip text is built when AppKit asks for it, so the reset countdown needs no timer.
final class CountersView: NSView, NSViewToolTipOwner {
    /// Width of the vertical HP bar at the left edge.
    static let barWidth: CGFloat = 3
    /// Width of the counter column at the right edge, equal to the circle diameter.
    static let columnWidth: CGFloat = 16
    private static let staleOpacity: Float = 0.4

    private let countLabel = HUDStyle.label(size: 10, weight: .bold, color: HUDStyle.color(PetTokens.badgeGlyph))
    private let barTrack = CALayer()
    private let barFill = CALayer()
    private var snapshot: Snapshot?
    private var hpFraction: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        countLabel.alignment = .center
        countLabel.wantsLayer = true
        countLabel.layer?.cornerCurve = .continuous
        // The container speaks for the counters as a whole.
        countLabel.setAccessibilityElement(false)
        addSubview(countLabel)
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
        countLabel.stringValue = "\(snapshot.activeCount)"
        countLabel.layer?.backgroundColor = HUDStyle.counterColor(snapshot)
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
        // A two-digit count widens the circle into a pill, growing evenly to the left and right of the column centre.
        let size = Self.columnWidth
        let width = max(size, countLabel.intrinsicContentSize.width + 6)
        countLabel.frame = CGRect(
            x: bounds.maxX - size / 2 - width / 2,
            y: (bounds.height - size) / 2,
            width: width,
            height: size
        )
        countLabel.layer?.cornerRadius = size / 2
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
