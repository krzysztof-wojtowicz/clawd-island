# ADR-0003 — Pet rendered with Core Animation layers

**Status:** accepted

**Context:** The pet animates almost constantly. SwiftUI `repeatForever`, `TimelineView`, and timer-driven drawing all tick in-process every frame, costing CPU and wakeups (REQ-08). The user chose vector graphics over sprites.

**Decision:** Draw Clawd as a tree of `CAShapeLayer`s inside an `NSView`. Run all loops as `CAAnimation`s, which execute in the render server. SwiftUI is used only for mostly-static UI (counters, HP bar, panel), and it hosts `PetView` via `NSViewRepresentable`.

**Consequences:**
- Near-zero app CPU while animating, sharp at any scale, and no assets.
- Animations are declared in code (`07-pet-design.md` is the spec), which is easy for agents to modify.
- Rejected: sprite sheets (need hand-drawn assets, and blurry scaling), SwiftUI-only animation (in-process ticking), and Lottie/Rive (dependencies).
