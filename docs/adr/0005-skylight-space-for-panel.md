# ADR-0005 — Pin the island to its own SkyLight Space

**Status:** accepted

**Context:** The panel uses `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`. A window that joins all Spaces still belongs to each Space, so a Space transition carries it along. This happens on a three-finger swipe, on Ctrl+←/→, and when entering or leaving a full-screen app: the island slides off with the old Space and slides back in with the new one. The menu bar does not move, and the island should behave the same way (REQ-02 AC4). No public window level or collection behaviour prevents the slide.

**Decision:** Put the panel into a dedicated Space that sits above every user Space. Several notch apps use this technique. Only the idea is taken from them; no code is copied.
- Load `/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight` at runtime with `dlopen`, and resolve the following with `dlsym`: `SLSMainConnectionID`, `SLSSpaceCreate`, `SLSSpaceSetAbsoluteLevel`, `SLSShowSpaces`, and `SLSAddWindowsToSpaces`. Call them through `@convention(c)` function types. There is no linker flag and no bridging header, so the toolchain stays the same (ADR-0001).
- Run this once, right after the panel's first `orderFrontRegardless()`: create a Space, set a high absolute level, show it, and add the panel's `windowNumber`. The Space lives as long as the process, and the OS reclaims it on exit.
- **Fallback:** if the framework or any symbol is missing, skip silently. The existing `collectionBehavior` keeps the island visible on every Space (it just slides again).

**Consequences:**
- The island stays fixed during Space switches and full-screen transitions, like the menu bar.
- It uses private API: a macOS update may change or remove these symbols. The dlsym fallback turns that into a cosmetic regression, not a crash. Re-check after every major macOS update.
- The app is not App Store-safe. That is acceptable: it ships as GitHub release zips only (`01`).
- It has no runtime cost: these are one-time calls with no timers and no extra windows.
- Rejected:
  - Higher window levels (for example `CGShieldingWindowLevel`). The window still belongs to a Space and slides.
  - Re-showing the window on `activeSpaceDidChangeNotification`. That fires after the animation, so the island still visibly jumps.
