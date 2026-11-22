# 07 — Pet design (Clawd-inspired)

## Design tokens
| Token | Value | Use |
|---|---|---|
| `clawd.body` | `#D97757` | body, arms, legs |
| `clawd.bodyShade` | `#C2643F` | bottom shading or the leg back row (optional) |
| `clawd.eye` | `#1F1A17` | eyes |
| `badge.alert` | `#FF3B30` | "!" badge; session counter while any session is `needsInput` |
| `badge.active` | `#0A84FF` | session counter while sessions exist and none needs you; first expanded counter at ≥ 1 |
| `badge.empty` | `#8E8E93` | session counter at 0 sessions; first expanded counter at 0 |
| `badge.glyph` | `#FFFFFF` | the "!" on the badge |
| `bubble.fill` | `#FFFFFF` at 92 % | speech and thought bubbles |
| `tool.handle` / `tool.head` | `#8B5A2B` / `#8E8E93` | hammer handle and head (`usingTools`) |
| `broom.handle` / `broom.bristle` | `#8B5A2B` / `#C9A66B` | broom (`compacting`) |
| `ball.1` / `ball.2` / `ball.3` | `#FF9F0A` / `#64D2FF` / `#BF5AF2` | juggling balls (`juggling`) |
| `headphones.band` / `headphones.cup` | `#3A3A3C` / `#D1D1D6` | headphones overlay (REQ-13) |
| `hp.high` / `hp.mid` / `hp.low` | `#34C759` / `#FFCC00` / `#FF3B30` | HP bar at ≥ 50 / 20–49 / < 20 (REQ-04) |
| `island.bg` | `#000000` | island |
Define these once, in `Sources/ClawdNotch/Pet/PetTokens.swift`. Any colour literal anywhere else is a review finding. The session counter is orange (`clawd.body`) while a `done` session is unread, and the hover glow (REQ-11) also reuses `clawd.body`, so neither needs a token of its own. `badge.empty` (grey) and `badge.active` (blue) are also used by the first expanded counter (idle + working).
HUD text has no token: it uses the system label colours (`labelColor`, `secondaryLabelColor`), which the panel's forced `.darkAqua` appearance resolves to light text on the black island.

## Anatomy
Every part is a separate `CAShapeLayer`. Coordinates are in a unit box of **32 × 24** (width × height), scaled to the actual size, with the origin at the bottom-left.
- **body:** a rounded rect of 24 × 14 at (4, 6), corner radius 3.5 with a continuous curve.
- **eyes:** 2 × rounded rects of 2.4 × 4.2, at x = 10.5 and x = 19, y = 12.5, corner radius 1.2.
- **arms:** 2 × rounded rects of 3.5 × 4, on the left and right sides at mid-height. The anchor point is the inner edge; the right arm pivots at the shoulder (28, 18.5) when raised, because a mid-height pivot keeps the paw inside the body outline at notch size.
- **legs:** 4 × rounded rects of 2.2 × 4, spaced evenly below the body, corner radius 1.
- **accessories** (hidden by default): the speech bubble (with a 3-dot layer), the thought cloud (3 circles), the "Zzz" text layer, the "!" badge (a red circle with white text), placed top-left so it never covers the raised right arm, the **broom** (`compacting`: a handle of 1 × 9 u with a bristle head of 4 × 3 u, held by two paws drawn on the handle, pivoting at its top at (24.5, 15) in front of the body, right of the eyes; two dust puffs of 0.9 u radius reuse `bubble.fill`, at the sweep ends, sublayers of the body), three **balls** (circles of 2.6 u, `ball.1–3`, for `juggling`; they ride a flattened ellipse of 20 × 2.4 u above the head, spanning x 6–26, y 20.6–23, and stay on it at 120° apart as the Reduce Motion pose; the arms tilt up and out by 35°), and the **hammer**: a handle of 1 × 5 u (`tool.handle`) with a head of 2 × 4 u (`tool.head`), in arm-local coordinates (handle along the arm, head across its tip). The hammer is a sublayer of the right arm, so it moves with the arm, and cross-fades like the other accessories.
- **headphones** (REQ-13, a separate overlay, not an accessory of a pose): a band arc over the top of the head (`headphones.band`) and two cups (rounded rects of 3 × 5 u, `headphones.cup`) at the body's upper sides, drawn above the body and below the eyes so the face stays visible. Hidden unless music plays.

## Poses and animations
All animations are `CABasicAnimation` / `CAKeyframeAnimation` added to layers. They are repeating where noted and run by the render server. **Never drive frames from Swift timers.**

| State | Pose | Loop animation | Period |
|---|---|---|---|
| `sleeping` | eyes scaled to y = 0.15 (closed), body lowered 1 u | body scale-y 1.0↔0.96 ("breathing"), Zzz fade and rise | 3.2 s |
| `idle` | neutral | blink (eyes scale-y → 0.1 for 120 ms) using keyframes with a long hold, gentle x-sway ±0.5 u | 4.5 s |
| `thinking` | eyes shifted up 1 u, thought cloud visible | cloud circles pulse in sequence, body bob ±0.6 u | 1.6 s |
| `usingTools` | right arm cocked at 65° (up and right) holding the hammer; no speech bubble | strike: additive arm rotation 0° → −40° at 20 % of the period (fast down-stroke) → 0° (slow lift), body dips 0.5 u on impact | 0.7 s |
| `talking` | speech bubble visible | dots light up in sequence, body bounce ±0.8 u, arms wiggle ±8° | 0.9 s |
| `compacting` | sweeping: both arms hold the broom, which sweeps side to side | broom sweep loop (rotation ±18° plus 1.5 u slide), a small dust puff cycles at the bristles | 1.0 s |
| `juggling` | arms up and slightly out, three balls visible | balls follow keyframed arcs (a cascade, each offset by a third of the period), arms bob ±6° | 1.2 s |
| `done` | right arm raised 110° (counter-clockwise; +110° in macOS layer coordinates, y up) | arm wave ±15° for 2 cycles after the pop, then hold | — |
| `needsInput` | right arm raised, "!" badge visible | badge scale pulse 1.0↔1.15, slight body shake on entry | 1.2 s |

- **Transitions:** cross-fade the accessories (150 ms), and move pose parts with an implicit `CATransaction`, 200 ms, ease-out.
- **Pop-out:** a spring on the container's position and scale (`CASpringAnimation`, damping 12, stiffness 180), with a small hop of 3 u on the body.
- **Placement moves** (hide mode peek ↔ right wing ↔ expanded, `06`): the container's position and rotation animate together with the same spring. The upside-down peek turns the pet through about 150°, always the short way round, so popping out reads as the pet flipping up into the wing. Reduce Motion: a straight 200 ms ease-out move.
- **Headphones overlay (REQ-13):** orthogonal to every pose, including hide mode (it rotates with the pet). Cross-fade 150 ms on play/pause. Only in `idle` and `sleeping` may the whole head bob about ±0.4 u (period 0.6 s) while playing; other loops are not disturbed. One overlay serves all states: do not add states x2.
- **Paused** (screen asleep, session locked, or the pet hidden off-screen): set `layer.speed = 0` on the root layer and restore the time offset when resuming.
- Respect **Reduce Motion** (`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`): keep the static poses but disable the loops and springs (`usingTools` shows a still, raised hammer; `compacting` a still broom; `juggling` still balls mid-arc; headphones appear without bob).

## Size
The default height is 26 pt, in the island's right wing next to the HP bar (`06`), which is about 56 pt wide so the hammer swing fits (REQ-04 AC4). In hide mode the pet keeps its size and hangs upside down from the notch's bottom-right corner, rotated about 150° clockwise (180° − 30°), legs hidden behind the notch, head and arms out; its loops keep running. Verify legibility at 1× and 2× using the `build-and-run` skill with screenshots.

## Legal note
The look is *inspired by* Anthropic's Clawd mascot. Do not copy pixel art or assets from Anthropic or clawd-on-desk. Draw everything from the anatomy spec above.
