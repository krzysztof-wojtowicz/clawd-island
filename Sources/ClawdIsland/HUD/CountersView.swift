// CountersView.swift
// The right wing's HP bar and counts column (REQ-04); the pet shows through the gap between them.

import AppKit
import ClawdCore

/// Renders the counters of one `Snapshot`, laid out around the notch (REQ-01, REQ-04). Collapsed: ONE session counter
/// (`activeCount`) in a circle left of the notch, always shown, also at 0 (AC1), and a vertical HP bar right of it,
/// filling bottom-up. Expanded: the single counter morphs into three circles left of the notch (idle + working, done
/// unread, needs input; AC1), which slide out of its position. The single colour comes from `HUDStyle.counterColor`.
/// The HP bar is hidden while usage is unknown (AC2) and full but dimmed when stale (AC3). Tooltip text is built when
/// AppKit asks for it, so the reset countdown needs no timer.
final class CountersView: NSView, NSViewToolTipOwner {
    /// Width of the vertical HP bar.
    static let barWidth: CGFloat = 3
    /// Gap between the notch's right edge and the HP bar.
    static let barInset: CGFloat = 2
    /// Gap between the HP bar and the pet.
    static let barPetGap: CGFloat = 6
    /// Diameter of every counter circle.
    static let circleSize: CGFloat = 16
    private static let circleGap: CGFloat = 8
    /// Distance from the notch's left edge to the counters' right edge.
    private static let notchInset: CGFloat = 4
    private static let staleOpacity: Float = 0.4
    /// A zero in an alert colour is drawn dimmed so it does not read as a warning.
    private static let zeroOpacity: CGFloat = 0.35

    /// The notch's x range in this view's coordinates. Set by `IslandView`.
    var notch: ClosedRange<CGFloat> = 0...0 {
        didSet { if notch != oldValue { needsLayout = true } }
    }

    private let countLabel = CountersView.circle()
    /// Idle + working, done unread, needs input (REQ-04 AC1).
    private let statusCircles = [CountersView.circle(), CountersView.circle(), CountersView.circle()]
    private var isExpanded = false
    private let barTrack = CALayer()
    private let barFill = CALayer()
    private var snapshot: Snapshot?
    private var hpFraction: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for label in [countLabel] + statusCircles {
            addSubview(label)
        }
        for (circle, fill) in zip(statusCircles, [PetTokens.badgeEmpty, PetTokens.body, PetTokens.badgeAlert]) {
            circle.layer?.backgroundColor = fill
            circle.alphaValue = 0
        }
        applyExpanded(animatedFor: nil)
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

    /// A 16 pt round digit label; the container speaks for the counters as a whole until they are expanded.
    private static func circle() -> NSTextField {
        let label = CenteredLabel(labelWithString: "")
        label.font = HUDStyle.font(size: 10, weight: .bold)
        label.textColor = HUDStyle.color(PetTokens.badgeGlyph)
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.cornerCurve = .continuous
        label.setAccessibilityElement(false)
        return label
    }

    /// Morphs between the single counter and the three circles; call it inside the expand/collapse animation group
    /// with the same duration (0 jumps).
    func setExpanded(_ expanded: Bool, duration: TimeInterval) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        applyExpanded(animatedFor: duration)
    }

    /// Sets the model values for the current state and, given a duration, animates from what is on screen.
    private func applyExpanded(animatedFor duration: TimeInterval?) {
        let moving = [countLabel] + statusCircles
        let before = moving.map { label in
            let layer = label.layer
            let opacity = layer?.presentation()?.opacity ?? layer?.opacity ?? 0
            let x = Self.translation(layer?.presentation() ?? layer)
            return (opacity, x)
        }
        updateOpacities()
        applyOffsets()
        setAccessibilityElement(!isExpanded)
        describeCircles()
        registerToolTips()
        guard let duration, duration > 0 else { return }
        for (label, (opacity, x)) in zip(moving, before) {
            guard let layer = label.layer else { continue }
            layer.add(Self.animation("opacity", from: CGFloat(opacity), to: CGFloat(layer.opacity), duration: duration), forKey: "fade")
            layer.add(
                Self.animation("transform.translation.x", from: x, to: Self.translation(layer), duration: duration),
                forKey: "slide"
            )
        }
    }

    /// Tooltips and VoiceOver labels for the circles; only while expanded, since collapsed they are invisible.
    private func describeCircles() {
        for (circle, name) in zip(statusCircles, Self.circleNames) {
            circle.setAccessibilityElement(isExpanded)
            circle.setAccessibilityLabel("\(circle.stringValue) \(name)")
            circle.toolTip = isExpanded ? "\(circle.stringValue) \(name)" : nil
        }
    }

    private static let circleNames = ["idle or working", "done, unread", "need input"]

    private static func translation(_ layer: CALayer?) -> CGFloat {
        layer?.value(forKeyPath: "transform.translation.x") as? CGFloat ?? 0
    }

    private static func animation(_ keyPath: String, from: CGFloat, to: CGFloat, duration: TimeInterval) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = NSNumber(value: from)
        animation.toValue = NSNumber(value: to)
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return animation
    }

    /// The single counter shows collapsed, the three circles expanded; a zero in an alert colour is dimmed.
    private func updateOpacities() {
        countLabel.alphaValue = isExpanded ? 0 : 1
        let counts = snapshot?.statusCounts
        let values = [(counts?.idle ?? 0) + (counts?.working ?? 0), counts?.done ?? 0, counts?.needsInput ?? 0]
        for (index, (circle, value)) in zip(statusCircles, values).enumerated() {
            circle.alphaValue = !isExpanded ? 0 : (value == 0 && index > 0 ? Self.zeroOpacity : 1)
        }
    }

    /// Collapsed, circles 1 and 2 sit on circle 3 (the single counter's spot); expanded, they are where `layout` put them.
    private func applyOffsets() {
        for circle in statusCircles {
            let offset = isExpanded ? 0 : statusCircles[2].frame.maxX - circle.frame.maxX
            circle.layer?.transform = CATransform3DMakeTranslation(offset, 0, 0)
        }
    }

    /// Shows `snapshot`; `now` decides whether the usage window has already reset.
    func render(_ snapshot: Snapshot, now: Date) {
        self.snapshot = snapshot
        countLabel.stringValue = "\(snapshot.activeCount)"
        countLabel.layer?.backgroundColor = HUDStyle.counterColor(snapshot)
        let counts = snapshot.statusCounts
        let values = [counts.idle + counts.working, counts.done, counts.needsInput]
        for (circle, value) in zip(statusCircles, values) {
            circle.stringValue = "\(value)"
        }
        statusCircles[0].layer?.backgroundColor = values[0] > 0 ? PetTokens.badgeActive : PetTokens.badgeEmpty
        updateOpacities()
        describeCircles()
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
        // A two-digit count widens a circle into a pill, growing to the left, so the right edges stay put.
        let size = Self.circleSize
        var right = notch.lowerBound - Self.notchInset
        func place(_ label: NSTextField) {
            let width = max(size, label.intrinsicContentSize.width + 6)
            label.frame = CGRect(x: right - width, y: (bounds.height - size) / 2, width: width, height: size)
            label.layer?.cornerRadius = size / 2
        }
        place(countLabel)
        for circle in statusCircles.reversed() {
            place(circle)
            right = circle.frame.minX - Self.circleGap
        }
        applyOffsets()
        let track = CGRect(x: notch.upperBound + Self.barInset, y: 0, width: Self.barWidth, height: bounds.height)
        barTrack.frame = track
        barFill.frame = CGRect(x: track.minX, y: track.minY, width: track.width, height: track.height * hpFraction)
        registerToolTips()
    }

    /// The single counter's spot (collapsed only: expanded, circle 3 has its own tip) and the bar, with a target
    /// wider than the 3 pt bar itself.
    private func registerToolTips() {
        removeAllToolTips()
        if !isExpanded { addToolTip(countLabel.frame, owner: self, userData: nil) }
        addToolTip(barTrack.frame.insetBy(dx: -Self.barInset, dy: 0), owner: self, userData: nil)
    }

    /// Built on demand, like the tooltip, so the reset countdown is current when VoiceOver reads it.
    override func accessibilityLabel() -> String? {
        guard let snapshot else { return nil }
        return "\(HUDStyle.countsLine(snapshot)), \(HUDStyle.usageLine(snapshot.usage, now: .now).string)"
    }

    func view(
        _ view: NSView,
        stringForToolTip tag: NSView.ToolTipTag,
        point: NSPoint,
        userData data: UnsafeMutableRawPointer?
    ) -> String {
        guard let snapshot else { return "" }
        return "\(HUDStyle.usageLine(snapshot.usage, now: .now).string)\n\(HUDStyle.countsLine(snapshot))"
    }
}

/// A label whose digits sit in the vertical middle of its frame: AppKit draws label text from the top, which left
/// the counter digits high in their 16 pt circles.
private final class CenteredLabel: NSTextField {
    override class var cellClass: AnyClass? {
        get { CenteredCell.self }
        set {}
    }
}

/// Places the text line so the cap height is centred in the cell.
private final class CenteredCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var line = super.drawingRect(forBounds: rect)
        guard let font else { return line }
        line.origin.y = rect.midY + font.capHeight / 2 - font.ascender
        line.size.height = font.ascender - font.descender + font.leading
        return line
    }
}
