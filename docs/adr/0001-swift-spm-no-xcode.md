# ADR-0001 — Swift 6 + SwiftPM, no Xcode project

**Status:** accepted

**Context:** The app must be native, lightweight and simple to develop. The development machine has only the Command Line Tools, no Xcode. AI agents edit the code, so plain-text project files are preferable.

**Decision:** Swift 6 with AppKit and Core Animation, built with Swift Package Manager. `scripts/bundle.sh` assembles and signs the `.app` (Info.plist, binaries, fonts, icon; signing in ADR-0008). Tests use swift-testing through `scripts/test.sh`. No SwiftUI: a hosting view breaks the RSS budget (`08`).

**Consequences:**
- No `.xcodeproj` merge conflicts; everything builds from the CLI and in CI.
- No previews and no Instruments; performance is measured with `ps`, `footprint`, `vmmap` and `scripts/perf-suite.sh`.
- With Command Line Tools only, plain `swift test` cannot find swift-testing and silently runs nothing. `scripts/test.sh` adds the framework search path and rpath, disables the broken `_Testing_Foundation` cross-import overlay, and fails when no test ran. Under full Xcode (CI) it runs plain `swift test`.
- Rejected: Electron/Tauri (too heavy for REQ-08), an Xcode project (not installed, hard for agents to edit).
