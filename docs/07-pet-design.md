# 07 — Pet design (Clawd-inspired)

## Design tokens
| Token | Value | Use |
|---|---|---|
| `clawd.body` | `#D97757` | body, arms, legs |
| `clawd.bodyShade` | `#C2643F` | bottom shading or the leg back row (optional) |
| `clawd.eye` | `#1F1A17` | eyes |
| `badge.alert` | `#FF3B30` | "!" badge; session counter while any session is `needsInput`; the poke heart (1.1.0) |
| `badge.active` | `#0A84FF` | session counter while sessions exist and none needs you; first expanded counter at ≥ 1 |
| `badge.empty` | `#8E8E93` | session counter at 0 sessions; first expanded counter at 0 |
| `badge.glyph` | `#FFFFFF` | the "!" on the badge |
| `bubble.fill` | `#FFFFFF` at 92 % | thought bubble, dust puffs |
| `bubble.speech` | `#F2C9B6` | speech bubble (`talking`, 1.1.0): a pale tint of `clawd.body`, so it reads as the pet's own |
| `tool.handle` / `tool.head` | `#8B5A2B` / `#8E8E93` | hammer handle and head (`usingTools`) |
| `broom.handle` / `broom.bristle` | `#8B5A2B` / `#C9A66B` | broom (`compacting`) |
| `ball.1` / `ball.2` / `ball.3` | `#FF9F0A` / `#64D2FF` / `#BF5AF2` | juggling balls (`juggling`) |
| `hp.high` / `hp.mid` / `hp.low` | `#34C759` / `#FFCC00` / `#FF3B30` | HP bar at ≥ 50 / 20–49 / < 20 (REQ-04) |
| `island.bg` | `#000000` | island |
Define these once, in `Sources/ClawdIsland/Pet/PetTokens.swift`. Any colour literal anywhere else is a review finding. The session counter is orange (`clawd.body`) while a `done` session is unread, and the hover glow (REQ-11) also reuses `clawd.body`, so neither needs a token of its own. `badge.empty` (grey) and `badge.active` (blue) are also used by the first expanded counter (idle + working).
HUD text has no token: it uses the system label colours (`labelColor`, `secondaryLabelColor`), which the panel's forced `.darkAqua` appearance resolves to light text on the black island.

## Anatomy
Every part is a separate `CAShapeLayer`. Coordinates are in a unit box of **32 × 24** (width × height), scaled to the actual size, with the origin at the bottom-left.
- **body:** a rounded rect of 24 × 14 at (4, 6), corner radius 3.5 with a continuous curve.
- **eyes:** 2 × rounded rects of 2.4 × 4.2, at x = 10.5 and x = 19, y = 12.5, corner radius 1.2.
- **arms:** 2 × rounded rects of 3.5 × 4, on the left and right sides at mid-height. The anchor point is the inner edge; the right arm pivots at (28, 15) when raised (both arms, mirrored at (4, 15), in `juggling`); the paw points up and out beside the head.
- **legs:** 4 × rounded rects of 2.2 × 4 below the body, corner radius 1, grouped as **two pairs with a visible middle gap** (as in the original Clawd): centres at about x 7.5 / 11 and 21 / 24.5, inside the body width.
- **accessories** (hidden by default): the **speech bubble** (a flat 11.5 × 5.4 u block in `bubble.speech` at (20.5, 18.5) with the body's style radius, 2.2 u Roundy and 0 Sharpy, and a stepped tail of two small squares down-left onto the head, right of the right eye, no outline; three 1.6 u square dots in `clawd.eye`, like tiny eyes), the thought cloud (3 circles), the "!" badge (a red circle with white text), placed top-left so it never covers the raised right arm, the **broom** (`compacting`: a handle of 1.3 × 11.7 u with a bristle head of 5.2 × 3.9 u, held by two pet-sized paws drawn on the handle, pivoting at its top at (24.5, 15) in front of the body, right of the eyes; two dust puffs of 0.9 u radius reuse `bubble.fill`, at the sweep ends (x 17.3 and 31.7, y 2), sublayers of the body), three **balls** (circles of 3.6 u, `ball.1–3`, for `juggling`; both arms are raised 50° up and out, and the balls ride a closed loop through the two catch points a ball's radius beyond the paw tips, (31.2, 19.2) and (0.8, 19.2): a high toss from the right paw to the left peaking at y 24.7, then a low toss back over the head peaking at y 22.8 so ball bottoms stay at or above y 20, the head top; the Reduce Motion pose has all three in flight on the high toss), the **hammer**: a handle of 1.3 × 6.5 u (`tool.handle`) with a head of 2.6 × 5.2 u (`tool.head`), in arm-local coordinates (handle along the arm, head across its tip), and the **burst** (a stroke-only outline of the body, 1.2 u wide, behind the pet, for the `done` / `needsInput` entry flash). The hammer is a sublayer of the right arm, so it moves with the arm, and cross-fades like the other accessories. The hammer and broom are 1.3× their 1.0.0 size (1.1.0): mid-swing the hammer head reaches about 7 u (7.7 pt) past the unit box's right edge and 2.1 u above it, inside the right wing's 10 pt hammer room and the top row's 3 pt margin (REQ-04 AC4).

## Styles (REQ-06 AC2, 1.1.0)
Every style uses the anatomy above, with the same frames, pivots, poses, animations and colours; only the corner radii differ. `PetRig` is built for one style, and `PetView` swaps in a new rig when `petStyle` changes (no animation; state, tilt and pause carry over). WP-36 reuses commit `6ff6829` from the unmerged `pet-variants` branch, renamed; its Cute and Plush styles are dropped (Plush must never ship).
- **Roundy** (`roundy`, default): today's pet, with the radii above.
- **Sharpy** (`sharpy`): the same pet with sharp corners: every pet part (body, eyes, arms, legs, broom paws) has corner radius 0, and so do the parts drawn in the pet's look (the speech bubble and its dots, the burst outline). Other accessories keep their shapes.
- `--render-poses <dir> --pet-style <style>` (debug builds) renders every pose for one style. Each pose must read at notch size in both styles.

## Poses and animations
All animations are `CABasicAnimation` / `CAKeyframeAnimation` added to layers. They are repeating where noted and run by the render server. **Never drive frames from Swift timers.**

| State | Pose | Loop animation | Period |
|---|---|---|---|
| `sleeping` | eyes scaled to y = 0.15 (closed), body lowered 1 u; no "Zzz" (dropped in 1.1.0) | body scale-y 1.0↔0.96 ("breathing") | 3.2 s |
| `idle` | neutral | blink (eyes scale-y → 0.1 for 120 ms) using keyframes with a long hold, gentle x-sway ±0.5 u | 4.5 s |
| `thinking` | eyes shifted up 1 u, thought cloud visible | cloud circles pulse in sequence, body bob ±0.6 u | 1.6 s |
| `usingTools` | right arm cocked at 65° (up and right) holding the hammer (1.3× in 1.1.0); no speech bubble | strike: additive arm rotation 0° → −40° at 20 % of the period (fast down-stroke) → 0° (slow lift), body dips 0.5 u on impact | 0.7 s |
| `talking` | speech bubble visible, in the pet's own look (1.1.0: `bubble.speech` block, style radius, stepped tail, square dots) | dots light up in sequence, body bounce ±0.8 u, arms wiggle ±8° | 0.9 s |
| `compacting` | sweeping: both arms hold the broom (1.3× in 1.1.0), which sweeps side to side | broom sweep loop (rotation ±18° plus 1.5 u slide), a small dust puff cycles at the bristles | 1.0 s |
| `juggling` | both arms raised 50° up and out, three balls visible | each ball rides the toss loop (anatomy), a third of the period apart, half the period per toss, so a ball passes the right paw at 0, 0.4, 0.8 s and the left paw 0.2 s later; each paw flicks up 28° and lifts 0.9 u as a ball passes (the toss), settles, and dips 18° and 0.5 u to catch the next (0.4 s, the left paw 0.2 s behind the right, both phase-locked to the balls) | 1.2 s (balls), 0.4 s (paws) |
| `done` | right arm raised 55° (counter-clockwise; +55° in macOS layer coordinates, y up) | entry (1.1.0): the burst outline in `clawd.body` grows from the body's edge to 1.5× and fades out in 0.7 s, once (opacity and scale only); wave loop: 3 swings of ±20° (about 0.9 s), rest about 1.5 s, repeat while the state holds; with each wave the whole pet hops 1.2 u twice (1.1.0, in the first 0.6 s) | 2.4 s |
| `needsInput` | right arm raised, "!" badge visible | entry (1.1.0): the same burst in `badge.alert`, and a slight body shake; the same wave and hops; badge scale pulse 1.0↔1.3 (1.15 in 1.0.0) | 1.2 s (pulse), 2.4 s (wave) |

- **Transitions:** cross-fade the accessories (150 ms), and move pose parts with an implicit `CATransaction`, 200 ms, ease-out.
- **Pop-out:** a spring on the container's position and scale (`CASpringAnimation`, damping 12, stiffness 180), with a small hop of 3 u on the body.
- **Placement moves** (mini mode peek ↔ right wing ↔ expanded, `06`): the container's position and rotation animate together with the same spring. The upside-down peek turns the pet through about 150°, always the short way round, so popping out reads as the pet flipping up into the wing. Reduce Motion: a straight 200 ms ease-out move.
- **Poke (REQ-24, 1.1.0):** a click on the pet plays a one-shot 0.6 s `CAAnimationGroup`: a squash (body scale-y down and scale-x up, then back) and a blink. About 1 in 4 pokes, chosen at random, also shows a small heart in `badge.alert` red that floats up from the head and fades out (a hidden `CAShapeLayer`, shown only during the poke). It plays on top of the current pose and changes nothing else; a second poke during one restarts it. No sound. Reduce Motion: a blink only, no squash and no heart.
- **Paused** (screen asleep, session locked, or the pet hidden off-screen): set `layer.speed = 0` on the root layer and restore the time offset when resuming.
- Respect **Reduce Motion** (`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`): keep the static poses but disable the loops and springs (`usingTools` shows a still, raised hammer; `compacting` a still broom; `juggling` still balls mid-arc; `done` / `needsInput` keep the paw raised without waving or hopping and skip the entry burst; the poke is a blink only).

## Size
The default height is 26 pt, in the island's right wing next to the HP bar (`06`), which is about 56 pt wide so the hammer swing fits (REQ-04 AC4). In mini mode the pet keeps its size and hangs upside down from the notch's bottom-right corner, rotated about 150° clockwise (180° − 30°), legs hidden behind the notch, head and arms out; its loops keep running. Verify legibility at 1× and 2× using the `build-and-run` skill with screenshots.

## Legal note
The look is *inspired by* Anthropic's Clawd mascot. Do not copy pixel art or assets from Anthropic or clawd-on-desk. Draw everything from the anatomy spec above.
