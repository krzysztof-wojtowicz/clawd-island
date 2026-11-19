// PetRig.swift
// Builds Clawd's layer tree from the unit-box anatomy in docs/07 and applies each state's static pose.

import AppKit
import ClawdCore

/// Every layer of the pet. Geometry is in unit-box units (32 × 24, origin bottom-left);
/// `PetView` scales `root` to its bounds. Pose setters animate implicitly inside the caller's `CATransaction`.
@MainActor
struct PetRig {
    /// Container of the whole pet: scaled to the view, sprung by pop-out, and paused as a whole.
    let root = CALayer()
    /// Body, eyes and arms; moves as one for breathing, sway, bob and bounce. Anchored at the body's bottom edge.
    let torso = CALayer()
    let eyes: [CAShapeLayer]
    let leftArm: CAShapeLayer
    let rightArm: CAShapeLayer
    let zzz = CATextLayer()
    let cloud: [CAShapeLayer]
    let bubble = CAShapeLayer()
    let dots: [CAShapeLayer]
    let badge: CAShapeLayer

    private let eyeGroup = CALayer()
    private let fullBox = CGRect(origin: .zero, size: PetTokens.unitBox)
    private let bodyBottom: CGFloat = 6
    private let armPivot = CGPoint(x: 28, y: 13)
    // Raised from the shoulder rather than mid-height, so the paw clears the body's silhouette at notch size.
    private let raisedArmPivot = CGPoint(x: 28, y: 18.5)
    private let raisedArmAngle: CGFloat = 110 * .pi / 180

    init() {
        let body = Self.roundedRect(CGRect(x: 4, y: 6, width: 24, height: 14), radius: 3.5, color: PetTokens.body)
        eyes = [10.5, 19].map { Self.roundedRect(CGRect(x: $0, y: 12.5, width: 2.4, height: 4.2), radius: 1.2, color: PetTokens.eye) }
        // Arms pivot on their inner edge so they can rotate up into a raised paw.
        leftArm = Self.roundedRect(CGRect(x: 0.5, y: 11, width: 3.5, height: 4), radius: 1, color: PetTokens.body)
        leftArm.anchorPoint = CGPoint(x: 1, y: 0.5)
        leftArm.position = CGPoint(x: 4, y: 13)
        rightArm = Self.roundedRect(CGRect(x: 28, y: 11, width: 3.5, height: 4), radius: 1, color: PetTokens.body)
        rightArm.anchorPoint = CGPoint(x: 0, y: 0.5)
        rightArm.position = armPivot
        let legs = (1...4).map { index in
            let centerX = 4 + 24 * CGFloat(index) / 5
            return Self.roundedRect(CGRect(x: centerX - 1.1, y: 2, width: 2.2, height: 4), radius: 1, color: PetTokens.body)
        }
        cloud = [(26, 21, 0.8), (28.2, 22, 1.1), (30.5, 22.5, 1.5)].map { Self.circle(x: $0.0, y: $0.1, radius: $0.2, color: PetTokens.bubbleFill) }
        dots = [3.2, 5.75, 8.3].map { Self.circle(x: $0, y: 3, radius: 0.8, color: PetTokens.eye) }
        badge = Self.circle(x: 3.5, y: 21, radius: 2.8, color: PetTokens.badgeAlert)

        root.bounds = fullBox
        torso.bounds = fullBox
        torso.anchorPoint = CGPoint(x: 0.5, y: bodyBottom / fullBox.height)
        torso.position = CGPoint(x: fullBox.midX, y: bodyBottom)
        eyeGroup.frame = fullBox
        eyes.forEach(eyeGroup.addSublayer)
        // Arms sit behind the body so their inner ends merge into it.
        [leftArm, rightArm, body, eyeGroup].forEach(torso.addSublayer)

        configureBubble()
        configureText()
        legs.forEach(root.addSublayer)
        [torso, zzz, bubble, badge].forEach(root.addSublayer)
        cloud.forEach(root.addSublayer)
        for accessory in accessories { accessory.opacity = 0 }
    }

    /// Accessory layers that cross-fade between states.
    private var accessories: [CALayer] { [zzz, bubble, badge] + cloud }

    /// Sets the model values of the pose parts (eyes, torso height, right arm) for `state`.
    func applyPose(_ state: PetState) {
        let eyeScale: CGFloat = state == .sleeping ? 0.15 : 1
        for eye in eyes { eye.transform = CATransform3DMakeScale(1, eyeScale, 1) }
        eyeGroup.position = CGPoint(x: fullBox.midX, y: fullBox.midY + (state == .thinking ? 1 : 0))
        torso.position = CGPoint(x: fullBox.midX, y: bodyBottom - (state == .sleeping ? 1 : 0))
        let raised = state == .done || state == .needsInput
        rightArm.position = raised ? raisedArmPivot : armPivot
        rightArm.transform = raised ? CATransform3DMakeRotation(raisedArmAngle, 0, 0, 1) : CATransform3DIdentity
    }

    /// Shows only the accessories that belong to `state`.
    func showAccessories(for state: PetState) {
        zzz.opacity = state == .sleeping ? 1 : 0
        bubble.opacity = state == .talking ? 1 : 0
        badge.opacity = state == .needsInput ? 1 : 0
        for circle in cloud { circle.opacity = state == .thinking ? 1 : 0 }
    }

    /// Every layer in the tree, for bulk updates such as `contentsScale` or removing loops.
    var allLayers: [CALayer] {
        var result: [CALayer] = []
        var pending: [CALayer] = [root]
        while let layer = pending.popLast() {
            result.append(layer)
            pending += layer.sublayers ?? []
        }
        return result
    }

    private func configureBubble() {
        bubble.frame = CGRect(x: 20.5, y: 18, width: 11.5, height: 6)
        let path = CGMutablePath()
        path.addRoundedRect(in: bubble.bounds, cornerWidth: 2.5, cornerHeight: 2.5)
        // Tail pointing down-left at the head.
        path.addLines(between: [CGPoint(x: 2.2, y: 0.5), CGPoint(x: 0.3, y: -1.8), CGPoint(x: 4.6, y: 0.5)])
        path.closeSubpath()
        bubble.path = path
        bubble.fillColor = PetTokens.bubbleFill
        dots.forEach(bubble.addSublayer)
    }

    private func configureText() {
        zzz.frame = CGRect(x: 21, y: 17, width: 11, height: 6)
        zzz.string = "Zzz"
        zzz.font = NSFont.systemFont(ofSize: 0, weight: .heavy)
        zzz.fontSize = 4.4
        zzz.alignmentMode = .right
        zzz.foregroundColor = PetTokens.bubbleFill

        let glyph = CATextLayer()
        glyph.frame = badge.bounds.offsetBy(dx: 0, dy: -0.3)
        glyph.string = "!"
        glyph.font = NSFont.systemFont(ofSize: 0, weight: .black)
        glyph.fontSize = 4.4
        glyph.alignmentMode = .center
        glyph.foregroundColor = PetTokens.badgeGlyph
        badge.addSublayer(glyph)
    }

    private static func roundedRect(_ frame: CGRect, radius: CGFloat, color: CGColor) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.frame = frame
        layer.backgroundColor = color
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
        return layer
    }

    private static func circle(x: CGFloat, y: CGFloat, radius: CGFloat, color: CGColor) -> CAShapeLayer {
        let layer = roundedRect(CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius), radius: radius, color: color)
        layer.cornerCurve = .circular
        return layer
    }
}
