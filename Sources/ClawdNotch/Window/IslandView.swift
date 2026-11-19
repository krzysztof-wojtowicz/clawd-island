// IslandView.swift
// The black island around the notch, with slot containers for the pet, the counters and the expanded panel.

import AppKit

/// Content view of the notch panel (docs/06, "Layout").
///
/// The top row spans the notch width and is at least `minRowHeight` tall, so on a short virtual notch it hangs a little
/// below the menu bar. The pet slot sits in the left wing and the counters slot in the right wing, both flush with the
/// notch edges and vertically centred in the row. Anything below the top row is the expanded panel. Hover is reported through
/// `onHoverChange`; the right-click menu comes from `menuProvider`.
final class IslandView: NSView {
    /// Width of each black wing beside the notch.
    static let wingWidth: CGFloat = 60
    /// Minimum top-row height: room for the pet slot plus 3 pt above and below.
    static let minRowHeight: CGFloat = 32
    /// Height of the pet and counters slots; the pet is 26 pt tall in the collapsed island (docs/07).
    private static let slotHeight = PetTokens.collapsedHeight
    private static let slotHorizontalInset: CGFloat = 6
    private static let panelInset: CGFloat = 12
    private static let cornerRadius: CGFloat = 10

    /// Container for `PetView` (WP-3). Add the pet as a subview with `autoresizingMask = [.width, .height]`.
    let petSlot = NSView()
    /// Container for the active/attention counters and the HP bar (WP-5).
    let countersSlot = NSView()
    /// Container for the expanded session panel (WP-5). Hidden while the island is collapsed.
    let panelSlot = NSView()

    /// Size of the top row: the notch width by `max(notch height, minRowHeight)`. Set by the window controller.
    var topRowSize: CGSize = .zero {
        didSet { needsLayout = true }
    }

    /// Called with `true` when the mouse enters the island and `false` when it leaves.
    var onHoverChange: ((Bool) -> Void)?

    /// Builds the right-click menu on demand; building it at launch costs about 4 MB of peak RSS.
    var menuProvider: (() -> NSMenu)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        if let layer {
            layer.backgroundColor = PetTokens.islandBackground
            layer.cornerRadius = Self.cornerRadius
            layer.cornerCurve = .continuous
            // Layer coordinates are bottom-up here, so "MinY" corners are the bottom ones.
            layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        }
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

    override func layout() {
        super.layout()
        let rowY = bounds.maxY - topRowSize.height
        let leftWing = CGRect(
            x: bounds.midX - topRowSize.width / 2 - Self.wingWidth,
            y: rowY,
            width: Self.wingWidth,
            height: topRowSize.height
        )
        let rightWing = leftWing.offsetBy(dx: Self.wingWidth + topRowSize.width, dy: 0)
        let verticalInset = (topRowSize.height - Self.slotHeight) / 2
        petSlot.frame = leftWing.insetBy(dx: Self.slotHorizontalInset, dy: verticalInset)
        countersSlot.frame = rightWing.insetBy(dx: Self.slotHorizontalInset, dy: verticalInset)
        panelSlot.isHidden = rowY <= 2 * Self.panelInset
        if !panelSlot.isHidden {
            panelSlot.frame = CGRect(x: 0, y: 0, width: bounds.width, height: rowY)
                .insetBy(dx: Self.panelInset, dy: Self.panelInset)
        }
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
