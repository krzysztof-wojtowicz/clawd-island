# ADR-0003 — Pet rendered with Core Animation layers

**Status:** accepted

**Context:** The pet animates almost constantly. SwiftUI `repeatForever`, `TimelineView` and timer-driven drawing all tick in-process every frame, costing CPU and wakeups (REQ-08). Vector graphics were chosen over sprites.

**Decision:** Draw Clawd as a tree of `CAShapeLayer`s inside an AppKit `NSView` (`PetView`). Run every loop as a `CAAnimation`, which executes in the render server. `07-pet-design.md` is the spec.

**Consequences:**
- Near-zero app CPU while animating, sharp at any scale, no assets.
- Animations are declared in code, which is easy for agents to modify.
- Rejected: sprite sheets (hand-drawn assets, blurry scaling), SwiftUI animation (in-process ticking), Lottie/Rive (dependencies).
