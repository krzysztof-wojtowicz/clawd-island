---
name: orchestrate-wp
description: How the main (orchestrator) agent executes ClawdNotch work packages from docs/09-roadmap.md using the specialist subagents, review, and local commits. Use when the user says "do the next WP", "continue the roadmap", "implement WP-x", or similar.
---

# Orchestrating work packages

1. **Pick:** open `docs/09-roadmap.md`. Take the WPs whose status is `todo` and whose dependencies are all `done`. If the user named a WP, take that one.
2. **Plan parallelism:** WPs (or the halves of a WP) whose owned directories do not overlap can run in parallel. See the ownership map in `CLAUDE.md`. Launch the specialists in **one message** with several Agent calls. Use `isolation: "worktree"` when two agents might touch shared files such as `Package.swift`. Otherwise work in the main tree.
3. **Brief each agent.** It starts cold, so give it:
   - the WP ID and its acceptance criteria (quoted from `09`) and the REQ IDs,
   - the exact files and directories it owns for this task,
   - any public APIs it must consume or expose (from `03`),
   - "Invoke the `ponytail` skill first. Follow `docs/10-code-style.md`. Do not commit.",
   - the expected report format: files, REQ/WP, verification, and the ponytail closing line.
4. **Integrate:** apply any cross-boundary requests that agents reported (for example a Core API addition) by delegating to the owner. Then run `swift build && swift test` yourself.
5. **Review:** launch `reviewer` on the diff. Fix the `blocker` and `should-fix` findings through the owning agent, and re-review until the verdict is `approve`. Nits are optional.
6. **Verify for real** when there is UI: use the `build-and-run`, `simulate-claude-events`, and `perf-check` skills.
7. **Commit locally:**
   - Set the WP status to `done` in `09`, and record spike results or measurements in the docs.
   - Make one commit per WP: `feat(<area>): <summary> (WP-x, REQ-yy)`, followed by the attribution trailer.
   - **Never `git push`.**
8. **Report to the user** in Polish and briefly: what was done, what was verified and how, what was skipped, any risks, and the next ready WPs.

Stop and ask the user when:
- a spike result contradicts an ADR,
- a requirement turns out to be infeasible,
- an action would touch the real `~/.claude/settings.json`,
- something needs sudo or a system permission.
