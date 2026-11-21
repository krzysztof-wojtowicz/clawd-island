// IslandView.swift
// The black island: the notch, a left wing (counter), a right wing (HP bar, pet), the expanded panel and the hover glow.

import AppKit

/// Content view of the notch panel (docs/06, "Layout" and "Hover glow").
///
/// The top row is the notch, at least `minRowHeight` tall, so on a short virtual notch it hangs a little below the
/// menu bar. The left wing holds the session counter and the right wing the HP bar and the pet, each flush with its
/// notch edge. The counters slot spans the whole row (so the expanded counters can slide out left of the notch); the
/// pet slot sits right of the HP bar, below the counters in z-order. Anything below the top row is the expanded
/// panel. While expanded, the view is `glowMargin` larger than the island on the sides and bottom so the glow is
/// not clipped. Hover is reported through `onHoverChange`; the right-click menu comes from `menuProvider`.
final class IslandView: NSView {
    /// Width of the wing left of the notch: the counter circle (REQ-04 AC4: wings at most 72 pt).
    static let leftWingWidth: CGFloat = 28
    /// Width of the wing right of the notch: HP bar, gap, pet, and room for the hammer, which reaches about 9 pt past
    /// the pet's right edge mid-swing (PetRig: arm pivot x 28 + hammer 8.5, unit box 32, scale 26/24).
    static let rightWingWidth = (CountersView.barInset + CountersView.barWidth + CountersView.barPetGap + petSize.width + 10)
        .rounded(.up)
    /// Room each side of the notch in the expanded island, enough for the three counters on the left.
    static let expandedWingWidth: CGFloat = 72
    /// Minimum top-row height: room for the pet slot plus 3 pt above and below.
    static let minRowHeight: CGFloat = 32
    /// How far the expanded panel reaches below the top row.
    static let expandedExtraHeight: CGFloat = 164
    /// Room for the glow beside and below the expanded island.
    static let glowMargin: CGFloat = 24
    /// How far the hidden window reaches below the notch; Clawd peeks out of this transparent strip (REQ-05, docs/06).
    static let peekHeight: CGFloat = 16
    /// Hidden Clawd's distance from the notch's right edge to its right edge.
    private static let hiddenPetInset: CGFloat = 12
    /// Hidden Clawd leans out toward the right wing (clockwise, so negative), in degrees.
    private static let hiddenTilt: CGFloat = -9
    /// The pet is 26 pt tall in the collapsed island (docs/07); its width follows the unit box.
    static let petSize = CGSize(
        width: PetTokens.collapsedHeight * PetTokens.unitBox.width / PetTokens.unitBox.height,
        height: PetTokens.collapsedHeight
    )
    private static let panelInset: CGFloat = 12
    private static let cornerRadius: CGFloat = 10
    private static let glowOpacity: Float = 0.35
    /// Small enough that the blur fades out well inside `glowMargin`; a clipped blur shows a hard edge.
    private static let glowRadius: CGFloat = 9

    /// Container for `PetView` (WP-3). Add the pet as a subview with `autoresizingMask = [.width, .height]`.
    let petSlot = NSView()
    /// Container for the counters and the HP bar (WP-5): it spans the whole row; `CountersView` places everything
    /// relative to the notch, and the pet shows through the gap right of the bar.
    let countersSlot = NSView()
    /// Where Clawd is, in screen coordinates (centre) and degrees of tilt. Set through `setPetPlacement`.
    private(set) var petPlacement: (center: CGPoint, tilt: CGFloat) = (.zero, 0)

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

    private var counters: CountersView? { countersSlot.subviews.first as? CountersView }

    /// Opaque black over the notch rect, above the pet: a hidden Clawd looks tucked behind the notch's bottom edge.
    /// A mask would do the same, but a full-window mask makes Core Animation render offscreen in-process (+45 MB).
    private let notchCover = CALayer()

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
        notchCover.backgroundColor = PetTokens.islandBackground
        notchCover.cornerRadius = Self.cornerRadius
        notchCover.cornerCurve = .continuous
        notchCover.maskedCorners = background.maskedCorners
        notchCover.zPosition = 1
        layer?.addSublayer(notchCover)
        // .activeAlways: the app is never active, so the default (.activeInKeyWindow) would never fire.
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Fades the glow in or out and morphs the counters; call it inside the expand/collapse animation group with the
    /// same duration.
    func setExpanded(_ expanded: Bool, duration: TimeInterval) {
        counters?.setExpanded(expanded, duration: duration)
        let visible = expanded
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        // A zero duration on a standalone layer would still get the implicit 0.25 s fade.
        CATransaction.setDisableActions(duration == 0)
        background.shadowOpacity = visible ? Self.glowOpacity : 0
        CATransaction.commit()
    }

    /// The pet's target for a mode, in screen coordinates (docs/06): `hidden` peeks under the right part of the notch,
    /// tilted; otherwise it sits in the right wing, upright. Expanded keeps the top row's right wing too.
    static func petPlacement(topRow: CGRect, hidden: Bool) -> (center: CGPoint, tilt: CGFloat) {
        if hidden {
            // One point under the notch's bottom edge puts about 55 % of the 26 pt pet in the 16 pt peek strip.
            return (CGPoint(x: topRow.maxX - hiddenPetInset - petSize.width / 2, y: topRow.minY - 1), hiddenTilt)
        }
        let x = topRow.maxX + CountersView.barInset + CountersView.barWidth + CountersView.barPetGap + petSize.width / 2
        return (CGPoint(x: x, y: topRow.midY), 0)
    }

    /// Moves and tilts the pet to `placement`. The slot's frame is recomputed from screen coordinates on every
    /// layout, so it stays put while the window frame interpolates; `PetView` animates only the offset from the old
    /// placement.
    func setPetPlacement(_ placement: (center: CGPoint, tilt: CGFloat), animated: Bool) {
        let old = petPlacement
        petPlacement = placement
        needsLayout = true
        let offset = CGSize(width: old.center.x - placement.center.x, height: old.center.y - placement.center.y)
        (petSlot.subviews.first as? PetView)?
            .setPlacement(tilt: placement.tilt, from: offset, tiltChange: old.tilt - placement.tilt, animated: animated)
    }

    override func layout() {
        super.layout()
        let origin = window?.frame.origin ?? .zero
        let row = topRow.offsetBy(dx: -origin.x, dy: -origin.y)
        // The window frame interpolates linearly while it resizes, so growing the margin with the height keeps
        // the island edges moving in step with the frame instead of jumping at either end.
        let progress = min(max((bounds.height - row.height) / (Self.expandedExtraHeight + Self.glowMargin), 0), 1)
        let margin = Self.glowMargin * progress
        // Hidden, the panel is notch-wide and reaches `peekHeight` below the black row, where only the pet shows.
        // The same width-driven progress fades the counters and the HP bar in with the wings.
        let wingProgress = min(max((bounds.width - row.width) / (Self.leftWingWidth + Self.rightWingWidth), 0), 1)
        let sliver = Self.peekHeight * (1 - wingProgress)
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
        layoutWing(row)
        countersSlot.alphaValue = wingProgress
        let size = Self.petSize
        petSlot.frame = CGRect(
            x: petPlacement.center.x - origin.x - size.width / 2,
            y: petPlacement.center.y - origin.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        notchCover.frame = row
        CATransaction.commit()
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

    /// Spans the counters across the row.
    private func layoutWing(_ row: CGRect) {
        let y = row.minY + (row.height - Self.petSize.height) / 2
        countersSlot.frame = CGRect(x: 0, y: y, width: bounds.width, height: Self.petSize.height)
        counters?.notch = row.minX...row.maxX
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
