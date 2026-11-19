---
name: add-pet-state
description: Checklist for adding or changing a pet state (e.g. a new "sweeping" pose for compaction) consistently across docs, state machine, tests, animation and simulator. Use whenever PetState or its mapping changes.
---

# Add or change a pet state

Work through every step. Missing any step leaves the system inconsistent.

1. **Spec first:**
   - Update `docs/02-requirements.md` (the REQ-03 table).
   - Update `docs/04-state-machine.md`: the transition rows, the aggregate priority list, and the pop-out rule if it is affected.
   - Update `docs/07-pet-design.md`: the pose, the loop, and the period.
2. **Core** (core-engineer): `PetState` case, the transitions in the state machine, the aggregate priority, and a test for each new row and for the priority.
3. **Pet** (pet-animator): the pose and loop in `Sources/ClawdNotch/Pet/`, any new colours in `PetTokens`, and Reduce Motion behaviour.
4. **HUD** (macos-ui-engineer): add the state to the session panel's label or icon, if it is shown there.
5. **Simulator:** add a scenario to `scripts/simulate.sh` and to the table in the `simulate-claude-events` skill.
6. **Verify:** `scripts/test.sh`, a screenshot through `build-and-run`, and `perf-check` for the animating scenario.
7. Commit everything together: `feat(pet): <state> state (REQ-03)`.
