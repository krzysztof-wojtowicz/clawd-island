// IslandView.swift
// The black island: the notch plus one right wing (HP bar, pet, counts), the expanded panel and its hover glow.

import AppKit

/// Content view of the notch panel (docs/06, "Layout" and "Hover glow").
///
/// The top row is the notch, at least `minRowHeight` tall, so on a short virtual notch it hangs a little below the
/// menu bar. One wing sits flush with the notch's right edge: the counters slot spans it, and the pet slot sits
/// between the HP bar and the counts column, below the counters in z-order. Anything below the top row is the
/// expanded panel. While expanded, the view is `glowMargin` larger than the island on the sides and bottom so the
/// glow is not clipped. Hover is reported through `onHoverChange`; the right-click menu comes from `menuProvider`.
final class IslandView: NSView {
    /// Width of the wing right of the notch (REQ-04 AC4: at most 72 pt).
    static let wingWidth: CGFloat = 72
    /// Minimum top-row height: room for the pet slot plus 3 pt above and below.
    static let minRowHeight: CGFloat = 32
    /// How far the expanded panel reaches below the top row.
    static let expandedExtraHeight: CGFloat = 182
    /// Room for the glow beside and below the expanded island.
    static let glowMargin: CGFloat = 24
    /// How far Clawd peeks out below the notch in hide mode (REQ-05, docs/07).
    static let sliverHeight: CGFloat = 7
    /// Hidden Clawd's distance from the notch's right edge to its right edge.
    private static let hiddenPetInset: CGFloat = 12
    /// The pet is 26 pt tall in the collapsed island (docs/07); its width follows the unit box.
    private static let petSize = CGSize(
        width: PetTokens.collapsedHeight * PetTokens.unitBox.width / PetTokens.unitBox.height,
        height: PetTokens.collapsedHeight
    )
    private static let wingInset: CGFloat = 4
    private static let panelInset: CGFloat = 12
    private static let cornerRadius: CGFloat = 10
    private static let glowOpacity: Float = 0.35
    /// Small enough that the blur fades out well inside `glowMargin`; a clipped blur shows a hard edge.
    private static let glowRadius: CGFloat = 9

    /// Container for `PetView` (WP-3). Add the pet as a subview with `autoresizingMask = [.width, .height]`.
    let petSlot = NSView()
    /// Container for the HP bar and the counts (WP-5): it spans the wing, with the bar at its left edge and the counts
    /// column (`CountersView.columnWidth`) at its right edge; the pet shows through the gap.
    let countersSlot = NSView()
    /// Container for the expanded session panel (WP-5). Hidden while the island is collapsed.
    let panelSlot = NSView()

    /// The top row (notch x and width, row height) in screen coordinates. Set by the window controller.
    var topRow: CGRect = .zero {
        didSet { needsLayout = true }
    }

    /// Called with `true` when the mouse enters the island and `false` when it leaves.
    var onHoverChange: ((Bool) -> Void)?

    /// Builds the session panel on the first expand, so it costs nothing at launch.
    var panelProvider: (() -> NSView)?

    /// Builds the right-click menu on demand; building it at launch costs about 4 MB of peak RSS.
    var menuProvider: (() -> NSMenu)?

    /// The black island shape and the glow's shadow; a sublayer, so it can be smaller than the view.
    private let background = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        background.backgroundColor = PetTokens.islandBackground
        background.cornerRadius = Self.cornerRadius
        background.cornerCurve = .continuous
        // Layer coordinates are bottom-up here, so "MinY" corners are the bottom ones.
        background.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        background.shadowColor = PetTokens.body
        background.shadowRadius = Self.glowRadius
        background.shadowOffset = CGSize(width: 0, height: -2)
        background.shadowOpacity = 0
        layer?.addSublayer(background)
        for slot in [petSlot, countersSlot, panelSlot] {
            addSubview(slot)
        }
        // .activeAlways: the app is never active, so the default (.activeInKeyWindow) would never fire.
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Fades the glow in or out; call it inside the expand/collapse animation group with the same duration.
    func setGlowVisible(_ visible: Bool, duration: TimeInterval) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        // A zero duration on a standalone layer would still get the implicit 0.25 s fade.
        CATransaction.setDisableActions(duration == 0)
        background.shadowOpacity = visible ? Self.glowOpacity : 0
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        let origin = window?.frame.origin ?? .zero
        let row = topRow.offsetBy(dx: -origin.x, dy: -origin.y)
        // The window frame interpolates linearly while it resizes, so growing the margin with the height keeps
        // the island edges moving in step with the frame instead of jumping at either end.
        let progress = min(max((bounds.height - row.height) / (Self.expandedExtraHeight + Self.glowMargin), 0), 1)
        let margin = Self.glowMargin * progress
        // Hidden, the panel is notch-wide and reaches `sliverHeight` below the black row, where only the pet shows.
        // The same width-driven progress slides the pet between its hidden and wing positions.
        let wingProgress = min(max((bounds.width - row.width) / Self.wingWidth, 0), 1)
        let sliver = Self.sliverHeight * (1 - wingProgress)
        let island = CGRect(x: margin, y: margin + sliver, width: bounds.width - 2 * margin, height: bounds.height - margin - sliver)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        background.frame = island
        background.shadowPath = CGPath(
            roundedRect: CGRect(origin: .zero, size: island.size),
            cornerWidth: Self.cornerRadius,
            cornerHeight: Self.cornerRadius,
            transform: nil
        )
        CATransaction.commit()
        layoutWing(CGRect(x: row.maxX, y: row.minY, width: Self.wingWidth, height: row.height))
        let hiddenPet = CGPoint(x: row.maxX - Self.hiddenPetInset - Self.petSize.width, y: row.minY - Self.petSize.height)
        petSlot.frame.origin = CGPoint(
            x: hiddenPet.x + (petSlot.frame.minX - hiddenPet.x) * wingProgress,
            y: hiddenPet.y + (petSlot.frame.minY - hiddenPet.y) * wingProgress
        )
        let panelHeight = row.minY - island.minY
        panelSlot.isHidden = panelHeight <= 2 * Self.panelInset
        if !panelSlot.isHidden {
            if panelSlot.subviews.isEmpty, let view = panelProvider?() {
                view.frame = panelSlot.bounds
                view.autoresizingMask = [.width, .height]
                panelSlot.addSubview(view)
            }
            panelSlot.frame = CGRect(x: island.minX, y: island.minY, width: island.width, height: panelHeight)
                .insetBy(dx: Self.panelInset, dy: Self.panelInset)
        }
    }

    /// Places the counters across the wing and the pet centred between the HP bar and the counts column.
    private func layoutWing(_ wing: CGRect) {
        let content = wing.insetBy(dx: Self.wingInset, dy: (wing.height - Self.petSize.height) / 2)
        countersSlot.frame = content
        let gapMinX = content.minX + CountersView.barWidth
        let gapMaxX = content.maxX - CountersView.columnWidth
        petSlot.frame = CGRect(
            x: (gapMinX + gapMaxX - Self.petSize.width) / 2,
            y: content.minY,
            width: Self.petSize.width,
            height: Self.petSize.height
        )
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?()
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
    }
}
