// PetAnimations.swift
// Loop, entry and pop-out animations per pose (docs/07). All are CAAnimations run by the render server (ADR-0003).

import AppKit
import ClawdCore

extension PetRig {
    private static let loopPrefix = "loop."

    /// Adds `state`'s loop animations (docs/07 table), plus its one-shot entry effects (burst, shake) when `entering`
    /// is true, i.e. on a real state change rather than a rig rebuild or Reduce Motion toggle. Offsets are additive.
    func startLoops(for state: PetState, entering: Bool) {
        switch state {
        case .sleeping:
            torso.add(Self.keyframes("transform.scale.y", [1, 0.96, 1], period: 3.2), forKey: "loop.breath")
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
            // Every ball rides `ballLoop` a third of the 1.2 s period apart, so a ball reaches the right paw at
            // 0, 0.4, 0.8 s and the left paw 0.2 s later: each paw flicks up (toss) as a ball passes, every 0.4 s.
            for (index, ball) in balls.enumerated() {
                let arc = CAKeyframeAnimation(keyPath: "position")
                arc.path = Self.ballLoop
                arc.keyTimes = [0, 0.5, 1]
                arc.duration = 1.2
                arc.repeatCount = .infinity
                arc.timeOffset = Double(index) * 0.4
                ball.add(arc, forKey: "loop.arc")
            }
            // Flick up and lift as the ball passes (t = 0), settle, then dip to catch the next one.
            let beats: [NSNumber] = [0, 0.35, 0.8, 1]
            for (arm, side) in [(rightArm, 1.0), (leftArm, -1.0)] {
                let toss = Self.keyframes("transform.rotation.z", [28, 0, -18, 28].map { Self.radians($0 * side) }, period: 0.4, keyTimes: beats, additive: true)
                let lift = Self.keyframes("position.y", [0.9, 0, -0.5, 0.9], period: 0.4, keyTimes: beats, additive: true)
                // The left paw catches 0.2 s after the right.
                toss.timeOffset = side < 0 ? 0.2 : 0
                lift.timeOffset = toss.timeOffset
                arm.add(toss, forKey: "loop.toss")
                arm.add(lift, forKey: "loop.lift")
            }
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
            if entering { playBurst(color: PetTokens.body) }
            rightArm.add(Self.waveLoop(), forKey: "loop.wave")
            root.add(Self.waveHops(), forKey: "loop.hop")
        case .needsInput:
            rightArm.add(Self.waveLoop(), forKey: "loop.wave")
            root.add(Self.waveHops(), forKey: "loop.hop")
            let pulse = Self.keyframes("transform.scale", [1, 1.3, 1], period: 1.2)
            badge.add(pulse, forKey: "loop.badge")
            guard entering else { return }
            playBurst(color: PetTokens.badgeAlert)
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

    /// The 0.6 s poke (REQ-24, docs/07 "Poke"): a blink, plus a squash of the torso on its feet when `squash`, plus the
    /// heart floating up from the head when `heart`. `tilt` (radians) is the pet's tilt; the heart is counter-rotated so
    /// it stays upright on screen. Its "poke." keys leave the state's loops running, and a repeat poke restarts it.
    func poke(squash: Bool, heart showHeart: Bool, tilt: CGFloat) {
        let beats: [NSNumber] = [0, 0.25, 0.6, 1]
        let blink = Self.keyframes("transform.scale.y", [1, 0.1, 0.1, 1], period: 0.6, keyTimes: beats)
        blink.repeatCount = 1
        eyeGroup.add(blink, forKey: "poke.blink")
        if squash {
            let group = CAAnimationGroup()
            // Overrides the `sleeping` breath (4 %) for 0.6 s; the breath carries on afterwards.
            group.animations = [
                Self.keyframes("transform.scale.x", [1, 1.12, 0.96, 1], period: 0.6, keyTimes: beats),
                Self.keyframes("transform.scale.y", [1, 0.8, 1.05, 1], period: 0.6, keyTimes: beats),
            ]
            group.duration = 0.6
            torso.add(group, forKey: "poke.squash")
        }
        guard showHeart else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        heart.transform = CATransform3DMakeRotation(-tilt, 0, 0, 1)
        CATransaction.commit()
        // Floats rig-up, i.e. away from the head: in mini mode that is down and out of the notch, where it stays visible.
        let float = CAAnimationGroup()
        float.animations = [
            Self.keyframes("opacity", [0, 1, 1, 0], period: 0.6, keyTimes: [0, 0.15, 0.55, 1]),
            Self.keyframes("position.y", [0, 3.5], period: 0.6, additive: true),
        ]
        float.duration = 0.6
        heart.add(float, forKey: "poke.heart")
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

    /// Three ±20° paw swings in 0.9 s, then a 1.5 s rest, repeating (docs/07).
    private static func waveLoop() -> CAKeyframeAnimation {
        let period = 2.4
        let swing = 0.9 / period / 7
        return keyframes(
            "transform.rotation.z",
            [0, 20, -20, 20, -20, 20, -20, 0, 0].map(radians),
            period: period,
            keyTimes: (0...7).map { NSNumber(value: Double($0) * swing) } + [1],
            additive: true
        )
    }

    /// Two 1.2 u hops of the whole pet during the wave's swings, still during its rest; shares the wave's 2.4 s period.
    /// Animates the root's sublayer transform, so legs and accessories hop with the body and the units stay unit-box.
    private static func waveHops() -> CAKeyframeAnimation {
        let period = 2.4
        return keyframes(
            "sublayerTransform.translation.y",
            [0, 1.2, 0, 1.2, 0, 0],
            period: period,
            keyTimes: [0, 0.15, 0.3, 0.45, 0.6, period].map { NSNumber(value: $0 / period) }
        )
    }

    /// One-shot entry flash (REQ-03 AC7): the body outline in `color` grows from the body's edge and fades out.
    private func playBurst(color: CGColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        burst.strokeColor = color
        CATransaction.commit()
        let flash = CAAnimationGroup()
        flash.animations = [
            Self.keyframes("opacity", [0, 1, 0], period: 0.7, keyTimes: [0, 0.12, 1]),
            Self.keyframes("transform.scale", [1, 1.5], period: 0.7),
        ]
        flash.duration = 0.7
        burst.add(flash, forKey: "loop.burst")
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
