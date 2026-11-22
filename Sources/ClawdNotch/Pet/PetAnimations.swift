// PetAnimations.swift
// Loop, entry and pop-out animations per pose (docs/07). All are CAAnimations run by the render server (ADR-0003).

import AppKit
import ClawdCore

extension PetRig {
    private static let loopPrefix = "loop."

    /// Adds `state`'s loop and entry animations (docs/07 table). Offsets are additive, so they ride on the pose.
    func startLoops(for state: PetState) {
        switch state {
        case .sleeping:
            torso.add(Self.keyframes("transform.scale.y", [1, 0.96, 1], period: 3.2), forKey: "loop.breath")
            zzz.add(Self.zzzRise(period: 3.2), forKey: "loop.zzz")
        case .idle:
            // 120 ms blink at the end of a long hold.
            let blink = Self.keyframes("transform.scale.y", [1, 1, 0.1, 1], period: 4.5, keyTimes: [0, 0.9733, 0.9867, 1])
            for eye in eyes { eye.add(blink, forKey: "loop.blink") }
            torso.add(Self.keyframes("position.x", [0, 0.5, 0, -0.5, 0], period: 4.5, additive: true), forKey: "loop.sway")
        case .thinking:
            for (index, circle) in cloud.enumerated() {
                let pulse = Self.keyframes("transform.scale", [1, 1.3, 1, 1], period: 1.6, keyTimes: [0, 0.17, 0.33, 1])
                pulse.timeOffset = 1.6 - Double(index) * 1.6 / 3
                circle.add(pulse, forKey: "loop.pulse")
            }
            torso.add(Self.keyframes("position.y", [0, 0.6, 0, -0.6, 0], period: 1.6, additive: true), forKey: "loop.bob")
        case .usingTools:
            // Fast down-stroke (0.14 s), slow lift; the body dips on impact. One 0.7 s loop, all in the render server.
            let strike = Self.keyframes("transform.rotation.z", [0, -40, 0].map(Self.radians), period: 0.7, keyTimes: [0, 0.2, 1], additive: true)
            rightArm.add(strike, forKey: "loop.strike")
            let dip = Self.keyframes("position.y", [0, -0.5, 0], period: 0.7, keyTimes: [0, 0.2, 1], additive: true)
            torso.add(dip, forKey: "loop.dip")
        case .compacting:
            // Sweeps between two extremes (t = 0 and 0.5 s); a dust puff bursts at each end as the bristles turn.
            let sweep = Self.keyframes("transform.rotation.z", [-18, 18, -18].map(Self.radians), period: 1)
            broom.add(sweep, forKey: "loop.sweep")
            broom.add(Self.keyframes("position.x", [-1.5, 1.5, -1.5], period: 1, additive: true), forKey: "loop.slide")
            for (index, puff) in dust.enumerated() {
                let burst = CAAnimationGroup()
                burst.animations = [
                    Self.keyframes("opacity", [0, 0.9, 0, 0], period: 1, keyTimes: [0, 0.1, 0.45, 1]),
                    Self.keyframes("transform.scale", [0.4, 1.4, 1.4, 1.4], period: 1, keyTimes: [0, 0.45, 0.5, 1]),
                    Self.keyframes("position.y", [0, 2, 2, 2], period: 1, keyTimes: [0, 0.45, 0.5, 1], additive: true),
                ]
                burst.duration = 1
                burst.repeatCount = .infinity
                burst.timeOffset = index == 0 ? 0 : 0.5
                puff.add(burst, forKey: "loop.puff")
            }
        case .juggling:
            // A cascade: every ball rides the same orbit, a third of the period apart.
            let orbit = CGPath(ellipseIn: Self.ballOrbit, transform: nil)
            for (index, ball) in balls.enumerated() {
                let arc = CAKeyframeAnimation(keyPath: "position")
                arc.path = orbit
                arc.duration = 1.2
                arc.repeatCount = .infinity
                arc.calculationMode = .paced
                arc.timeOffset = Double(index) * 0.4
                ball.add(arc, forKey: "loop.arc")
            }
            let bob = Self.keyframes("transform.rotation.z", [0, 6, 0, -6, 0].map(Self.radians), period: 1.2, additive: true)
            rightArm.add(bob, forKey: "loop.bob")
            bob.timeOffset = 0.6
            leftArm.add(bob, forKey: "loop.bob")
        case .talking:
            for (index, dot) in dots.enumerated() {
                let light = Self.keyframes("opacity", [0.3, 1, 0.3, 0.3], period: 0.9, keyTimes: [0, 0.17, 0.33, 1])
                light.timeOffset = 0.9 - Double(index) * 0.3
                dot.add(light, forKey: "loop.dots")
            }
            torso.add(Self.keyframes("position.y", [0, 0.8, 0, -0.8, 0], period: 0.9, additive: true), forKey: "loop.bounce")
            let wiggle = Self.keyframes("transform.rotation.z", [0, 8, 0, -8, 0].map(Self.radians), period: 0.9, additive: true)
            leftArm.add(wiggle, forKey: "loop.wiggle")
            wiggle.timeOffset = 0.45
            rightArm.add(wiggle, forKey: "loop.wiggle")
        case .done:
            let wave = Self.keyframes("transform.rotation.z", [0, 15, 0, -15, 0].map(Self.radians), period: 0.6, additive: true)
            wave.repeatCount = 2
            rightArm.add(wave, forKey: "loop.wave")
        case .needsInput:
            let pulse = Self.keyframes("transform.scale", [1, 1.15, 1], period: 1.2)
            badge.add(pulse, forKey: "loop.badge")
            let shake = Self.keyframes("position.x", [0, -0.6, 0.6, -0.6, 0.6, 0], period: 0.35, additive: true)
            shake.repeatCount = 1
            torso.add(shake, forKey: "loop.shake")
        }
    }

    /// Removes every loop and entry animation, leaving pop-out springs alone.
    func stopLoops() {
        for layer in allLayers {
            for key in layer.animationKeys() ?? [] where key.hasPrefix(Self.loopPrefix) {
                layer.removeAnimation(forKey: key)
            }
        }
    }

    /// Springs the whole pet in from slightly above and smaller, with a 3 u hop of the torso.
    func popOut() {
        let fitted = root.transform
        let scale = fitted.m11
        let grow = Self.spring("transform")
        grow.fromValue = CATransform3DScale(fitted, 0.8, 0.8, 1)
        grow.toValue = fitted
        root.add(grow, forKey: "pop.scale")
        // Root position is in view points, so the 4 u drop is converted with the fitted scale.
        let drop = Self.spring("position.y")
        drop.fromValue = 4 * scale
        drop.toValue = 0
        drop.isAdditive = true
        root.add(drop, forKey: "pop.drop")
        let hop = Self.keyframes("position.y", [0, 3, 0], period: 0.3, additive: true)
        hop.repeatCount = 1
        torso.add(hop, forKey: "pop.hop")
    }

    private static func keyframes(
        _ keyPath: String,
        _ values: [CGFloat],
        period: CFTimeInterval,
        keyTimes: [NSNumber]? = nil,
        additive: Bool = false
    ) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = keyTimes
        animation.duration = period
        animation.repeatCount = .infinity
        animation.isAdditive = additive
        animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: values.count - 1)
        return animation
    }

    /// "Zzz" fades in, rises 2 u and fades out once per breath.
    private static func zzzRise(period: CFTimeInterval) -> CAAnimationGroup {
        let group = CAAnimationGroup()
        group.animations = [
            keyframes("opacity", [0, 1, 1, 0], period: period, keyTimes: [0, 0.2, 0.7, 1]),
            keyframes("position.y", [-1, 1], period: period, additive: true),
        ]
        group.duration = period
        group.repeatCount = .infinity
        return group
    }

    private static func spring(_ keyPath: String) -> CASpringAnimation {
        let spring = CASpringAnimation(keyPath: keyPath)
        spring.damping = 12
        spring.stiffness = 180
        spring.duration = spring.settlingDuration
        return spring
    }

    private static func radians(_ degrees: CGFloat) -> CGFloat {
        degrees * .pi / 180
    }
}
