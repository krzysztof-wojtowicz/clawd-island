# ADR-0001 — Swift 6 + SwiftPM, no Xcode project

**Status:** accepted

**Context:** The app must be native and lightweight, and simple to develop. The development machine has only the Command Line Tools installed, with no Xcode. Multiple AI agents will edit the code, so plain-text project files are preferable.

**Decision:** Use Swift 6 with AppKit (window and layers) and SwiftUI (HUD, panel, settings), built with Swift Package Manager. `scripts/bundle.sh` assembles the `.app` (Info.plist, binaries, ad-hoc `codesign`). Tests use swift-testing.

**Consequences:**
- Pro: no `.xcodeproj` merge conflicts, and everything builds from the CLI.
- Con: no SwiftUI previews and no Instruments. We measure performance with `ps` and `powermetrics`.
- Con (found in WP-0): with Command Line Tools only, `swift test` cannot find swift-testing and silently runs nothing. Always use `scripts/test.sh`, which adds the framework search path and rpath and disables the broken `_Testing_Foundation` cross-import overlay.
- Rejected: Electron/Tauri (too heavy for REQ-08), and a plain Xcode project (not installed, and hard for agents to edit).
