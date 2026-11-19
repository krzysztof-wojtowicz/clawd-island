# 10 — Code style

Clean, small, and readable code. Apply the `ponytail` skill (level `full`) on every coding task. This document adds Swift-specific rules on top of it.

## Swift
- Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/): clarity at the point of use, and names that read as English phrases.
- Use Swift 6 language mode with strict concurrency. UI and store code is `@MainActor`. Values that cross actors are `Sendable` structs or enums.
- Prefer `struct` and `enum`. Use `final class` only where reference identity or AppKit requires it.
- Each type and function has one responsibility. Functions are ideally under 30 lines, and files under 300 lines. Split files by responsibility, not by mechanical size.
- No force unwraps (`!`) or `try!` outside tests, except for compile-time-safe constants. Any such constant gets a `// safe:` comment.
- Use `let` by default. Keep access control minimal: everything is `internal` unless another target needs it.
- No dead code, commented-out code, or TODOs without a WP reference (`// TODO(WP-6): …`).
- Errors at trust boundaries (HTTP bodies, the settings file, stdin) are handled explicitly and never crash the app.
- Use `os.Logger` with subsystem `dev.clawdnotch` and one category per module. Never use `print` in the app target. The bridge may print only its statusline output.

## Comments (English only)
- **File header:** 1–2 lines on the file's role.
  ```swift
  // SessionStore.swift
  // Tracks per-session Claude Code state and derives the pet's aggregate snapshot.
  ```
- **`///` doc comments** go on every type and every non-trivial method or property. They say *what* it does and *why* it exists, along with its contract (preconditions, threading, units), but not *how*.
  ```swift
  /// Applies a hook event and returns whether the visible snapshot may have changed.
  /// - Parameter now: Injected clock so transitions stay deterministic in tests.
  mutating func apply(_ event: ClawdEvent, now: Date) -> Bool
  ```
- **Inline comments explain only the why** that the code cannot show, in one line, for example: `// CC may start before the app; unknown sessions are created lazily.`
- **Known limits** use the Ponytail form: `// shortcut: <the limit>, <when to upgrade>`.
- Do not write comments that restate the code, banner comments, or changelog comments.

## Tests
- Use swift-testing (`@Test`, `#expect`) in `Tests/ClawdCoreTests`. Name tests after the behaviour: `@Test("Stop from a subagent does not finish the parent")`.
- Prefer table-driven `@Test(arguments:)` for transition tables.
- Any new non-trivial logic (a branch, a parser, a loop) ships with at least one test. AppKit glue that cannot run headless is verified manually through `build-and-run` and screenshots.

## Commits
- Use Conventional-ish messages: `feat(core): session state machine (WP-1, REQ-03)`. The body explains the why. End with the attribution trailer that the harness requires.
- Commit only after `swift build && swift test` pass. Never push.
