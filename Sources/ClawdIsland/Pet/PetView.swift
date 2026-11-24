// PetView.swift
// AppKit host for the Core Animation Clawd and its state, pop-out and pause API (docs/03, docs/07).

import AppKit
import ClawdCore

/// Clawd drawn as a layer tree (ADR-0003, REQ-03, REQ-06). Shows one `PetState` at a time; every loop
/// runs in the render server, so the app does no per-frame work. The pet is scaled to fit the view's bounds.
@MainActor
final class PetView: NSView {
    private var rig = PetRig(style: .roundy)
    /// Plain layer between the view's backing layer and the rig: AppKit does not manage it, so its anchor, tilt and
    /// placement offset stay as set here.
    private let tiltLayer = CALayer()
    private var placementCount = 0
    private var state: PetState = .sleeping
    private var isPaused = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(tiltLayer)
        mountRig()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(reduceMotionDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        updateAccessibilityLabel()
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// Switches pose, accessories and loop. Setting the current state does nothing, so callers may
    /// forward every snapshot. While paused, the change appears when the pet resumes.
    func setState(_ newState: PetState) {
        guard newState != state else { return }
        state = newState
        rig.stopLoops()
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        rig.showAccessories(for: state)
        CATransaction.commit()
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        rig.applyPose(state)
        CATransaction.commit()
        startLoops()
        updateAccessibilityLabel()
    }

    /// Redraws the pet in `style` (REQ-06 AC2), keeping its state, tilt and pause. The current style does nothing.
    func setStyle(_ style: AppConfig.PetStyle) {
        guard style != rig.style else { return }
        let wasPaused = isPaused
        rig.root.removeFromSuperlayer()
        rig = PetRig(style: style)
        isPaused = false
        mountRig()
        fitPet()
        setPaused(wasPaused)
    }

    /// Plays the pop-out spring (used on `done` / `needsInput` and when un-hiding). No-op under Reduce Motion.
    func popOut() {
        guard !Self.reduceMotion else { return }
        rig.popOut()
    }

    /// Tilts the pet to `tilt` degrees about its centre (docs/06 mini mode, docs/07 "Placement moves"). When
    /// `animated`, the pet starts displaced by `offset` and rotated back by `tiltChange` and settles with the pop-out
    /// spring, or a straight 200 ms ease-out under Reduce Motion. The view itself is already at its target frame, so
    /// the move is an additive animation and stays correct while the window resizes. Each call adds its own
    /// animations, so an interrupted move continues and the new one sums with it.
    func setPlacement(tilt: CGFloat, from offset: CGSize, tiltChange: CGFloat, animated: Bool) {
        tiltLayer.transform = CATransform3DMakeRotation(tilt * CGFloat.pi / 180, 0, 0, 1)
        guard animated, offset != .zero || tiltChange != 0 else { return }
        placementCount += 1
        let reduceMotion = Self.reduceMotion
        let moves: [(String, Any)] = [
            ("position", NSValue(point: CGPoint(x: offset.width, y: offset.height))),
            ("transform.rotation.z", NSNumber(value: Double(tiltChange) * .pi / 180)),
        ]
        for (keyPath, from) in moves {
            let animation: CABasicAnimation
            if reduceMotion {
                animation = CABasicAnimation(keyPath: keyPath)
                animation.duration = 0.2
                animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            } else {
                // The pop-out spring from docs/07.
                let spring = CASpringAnimation(keyPath: keyPath)
                spring.mass = 1
                spring.stiffness = 180
                spring.damping = 12
                spring.duration = spring.settlingDuration
                animation = spring
            }
            animation.isAdditive = true
            animation.fromValue = from
            animation.toValue = keyPath == "position" ? NSValue(point: .zero) : NSNumber(value: 0)
            tiltLayer.add(animation, forKey: "\(keyPath)-\(placementCount)")
        }
    }

    /// Freezes (`true`) or resumes every pet animation in place, e.g. while the screen sleeps or the pet is hidden.
    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        let root = rig.root
        if paused {
            root.timeOffset = root.convertTime(CACurrentMediaTime(), from: nil)
            root.speed = 0
        } else {
            let pausedAt = root.timeOffset
            root.speed = 1
            root.timeOffset = 0
            root.beginTime = 0
            root.beginTime = root.convertTime(CACurrentMediaTime(), from: nil) - pausedAt
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        fitPet()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        fitPet()
    }

    /// Scales the unit box to the bounds and re-rasterises text and paths at the resulting pixel density.
    private func fitPet() {
        let box = PetTokens.unitBox
        let scale = min(bounds.width / box.width, bounds.height / box.height)
        guard scale > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tiltLayer.bounds = bounds
        tiltLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        rig.root.position = CGPoint(x: bounds.midX, y: bounds.midY)
        rig.root.transform = CATransform3DMakeScale(scale, scale, 1)
        // Text and path layers rasterise at contentsScale, so the unit-box scale must be folded in to stay sharp (REQ-06).
        let pixelScale = (window?.backingScaleFactor ?? 2) * scale
        for layer in rig.allLayers { layer.contentsScale = pixelScale }
        CATransaction.commit()
    }

    /// Puts the rig into the tilt layer in the current state's pose, without transition animations.
    private func mountRig() {
        tiltLayer.addSublayer(rig.root)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rig.applyPose(state)
        rig.showAccessories(for: state)
        CATransaction.commit()
        startLoops()
    }

    private func startLoops() {
        guard !Self.reduceMotion else { return }
        rig.startLoops(for: state)
    }

    @objc private func reduceMotionDidChange() {
        rig.stopLoops()
        startLoops()
    }

    private func updateAccessibilityLabel() {
        setAccessibilityLabel("Clawd: \(state.rawValue)")
    }

    private static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
