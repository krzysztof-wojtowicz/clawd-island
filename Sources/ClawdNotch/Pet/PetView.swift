// PetView.swift
// AppKit host for the Core Animation Clawd and its state, pop-out and pause API (docs/03, docs/07).

import AppKit
import ClawdCore

/// Clawd drawn as a layer tree (ADR-0003, REQ-03, REQ-06). Shows one `PetState` at a time; every loop
/// runs in the render server, so the app does no per-frame work. The pet is scaled to fit the view's bounds.
@MainActor
final class PetView: NSView {
    private let rig = PetRig()
    private var state: PetState = .sleeping
    private var isPaused = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(rig.root)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rig.applyPose(state)
        rig.showAccessories(for: state)
        CATransaction.commit()
        startLoops()
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

    /// Plays the pop-out spring (used on `done` / `needsInput` and when un-hiding). No-op under Reduce Motion.
    func popOut() {
        guard !Self.reduceMotion else { return }
        rig.popOut()
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
        rig.root.position = CGPoint(x: bounds.midX, y: bounds.midY)
        rig.root.transform = CATransform3DMakeScale(scale, scale, 1)
        // Text and path layers rasterise at contentsScale, so the unit-box scale must be folded in to stay sharp (REQ-06).
        let pixelScale = (window?.backingScaleFactor ?? 2) * scale
        for layer in rig.allLayers { layer.contentsScale = pixelScale }
        CATransaction.commit()
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
