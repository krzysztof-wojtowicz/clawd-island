# ADR-0010 — Original pet species on a shared rig contract

**Status:** proposed (`11` P1)

**Context:** Users want more than one look for the pet. The obvious candidates are well-known programming mascots (Kotlin's Kodee, Rust's Ferris, the Go Gopher, Java's Duke, Tux). They are trademarks, or come with attribution and usage guidelines; Kodee's guidelines, for example, forbid altering its proportions, which a 32 × 24 u notch rig must do. The pet itself is already a fan design (`01`). Each extra species also multiplies the pose work: nine poses, accessories, mini mode, Reduce Motion.

**Decision:**
- Ship **original species only**, designed for this project (Byte, Nib, Wisp, Mochi; `11` P1a). No third-party mascots in the app, the README or the release.
- Every species implements one **rig contract**: named layer roles (`body`, `eyeL/R`, `armL/R`, `legs[]`, `accessoryAnchor`, `badgeAnchor`, `hatAnchor`) with frames and pivots in the 32 × 24 u box. A missing role is an empty, hidden layer. Pose animations address roles only.
- `PetRig` gets one builder per species. WP-36 styles stay a Clawd-only variation inside the Clawd builder.
- The `add-pet-state` checklist gains a step: render the new pose for every species (`--render-poses <dir> --pet-species <s>`).

**Consequences:**
- No licensing or trademark work, and no `THIRD_PARTY_NOTICES` entries for art.
- A new pose costs one animation, not one per species, as long as it stays within the roles. A species-specific tic is one optional extra animation.
- Species must fit the existing frames (the hammer swing room of REQ-04 AC4, the mini-mode peek of REQ-05), which limits very tall or wide designs.
- Rejected: bitmap or sprite skins (REQ-06 AC1, ADR-0003); user-loaded SVG skins (a parser we would own, and no way to guarantee the nine poses).
