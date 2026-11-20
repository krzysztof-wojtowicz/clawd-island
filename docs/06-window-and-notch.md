# 06 — Window and notch

## Panel setup
- The window is an `NSPanel` subclass with `styleMask: [.borderless, .nonactivatingPanel]`, `isFloatingPanel = true`, `hidesOnDeactivate = false`, `backgroundColor = .clear`, `isOpaque = false`, and `hasShadow = false`.
- `level`: `.mainMenu + 3` (window server layer 27, above the menu bar at 24). **Spike A (WP-0):** the panel sits exactly over the built-in notch (verified with `window-info.swift`). Visibility over full-screen apps and other Spaces needs a visual check by the user, because the Screen Recording permission is missing. If it is hidden there, try `CGShieldingWindowLevel()`.
- `constrainFrameRect(_:to:)` is overridden to return the frame unchanged. Otherwise AppKit pushes the panel below the menu bar.
- `collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`. On its own, this still lets the island slide during a Space switch, so it serves only as the fallback.
- **Space pinning (REQ-02 AC4, ADR-0005, WP-2.1):** right after the first `orderFrontRegardless()`, `SpaceAnchor.pin(panel)` adds the panel to its own SkyLight Space at a high absolute level. It loads the calls with `dlopen`/`dlsym` and skips silently if any are missing. The island then stays fixed during swipes, Ctrl+arrow and full-screen transitions.
- `canBecomeKey` and `canBecomeMain` return `false`. The Settings window is a separate, normal window.
- The app sets `LSUIElement = true` in Info.plist, so it has no Dock icon and does not appear in Cmd-Tab.

## Choosing the screen
- Always use `NSScreen.screens.first`, which is the main display with the menu bar (REQ-01). Do not use `NSScreen.main`, which follows the key window.
- `NotchGeometry` decides between a physical and a virtual notch from that screen's metrics.
- Re-layout on `NSApplication.didChangeScreenParametersNotification`.

## Notch geometry
- Physical notch: `notchWidth = screen.frame.width − auxiliaryTopLeftArea.width − auxiliaryTopRightArea.width` and `notchHeight = safeAreaInsets.top`.
- Virtual notch: width 200 pt, height equal to the menu bar height (`screen.frame.maxY − screen.visibleFrame.maxY`, at least 24 pt), drawn as a black shape with bottom corners rounded to 10 pt.
- Put this calculation in a pure function: `NotchGeometry.compute(screenFrame:visibleFrame:safeTop:auxLeft:auxRight:) -> NotchRect`. Test it in Core if it can be expressed with plain `CGRect`. `CGRect` is in CoreGraphics/Foundation, which is allowed.

## Layout ("island")
```
            ┌──── black island (extends the notch to the right) ────┐
            │     physical notch     │ ▮ ┌─────┐                    │  ▮ = vertical HP bar
 collapsed  │                        │ ▮ │Clawd│ (3)                │ (3) = session counter, circle colour =
            │                        │ ▯ └─────┘                    │       red / orange / blue / grey
            └───────────────────────────────────────────────────────┘
 expanded (hover): the island grows down by ~ 120–200 pt into a panel, centred under the notch,
 with a soft orange glow beneath it (REQ-11):
       │  proj-b   ● done (unread)                                        │
       │  proj-a     using Bash                                           │
       │  HP 63%  · resets in 1h 12m                    [Mark all read]   │
```
- Top row: the notch plus **one wing on the right**, `max(notch height, 32 pt)` tall, so on a short virtual notch (24 pt menu bar) the island hangs a little below the menu bar. There is no left wing. The wing is flush with the notch's right edge and 72 pt wide (REQ-04 AC4).
- Wing contents, left to right, all vertically centred in the top row:
  - **HP bar:** vertical and continuous, 3 pt wide, as tall as the pet, filling bottom-up in `hp.*` colours. It is hidden while usage is unknown, and full and dimmed while stale. The hover tooltip shows the exact HP and the reset countdown, computed when it is shown.
  - **Clawd:** 26 pt tall (`07`). It may shrink to about 22 pt if that is needed to meet the width target.
  - **Session counter:** the number of live sessions, centred inside a 14–16 pt circle that is always shown. The circle is vertically centred on the pet and the HP bar. A two-digit count widens the circle into a pill. Colour, first match wins: `badge.alert` (red) if any session is `needsInput`, `clawd.body` (orange) if any is `done` and unread, `badge.active` (blue) if any sessions exist, otherwise `badge.empty` (grey).
- The expanded panel stays centred under the notch, at least 360 pt wide (`expandedMinWidth`), so while expanded it may extend left of the notch. Only the collapsed island is one-sided. It lists up to 5 sessions, sorted by importance (`04`, "Panel order"), then "+n more", with the usage line and "Mark all read" in the footer. Settings and hide live in the right-click menu (WP-7).
- The island is black (`#000`), so it merges with the physical notch. Corners use a continuous (squircle) curve.
- **Click-through:** the panel frame equals the island's frame. Resize the panel when the island changes, rather than using a full-width transparent window. Animate the resize with `NSAnimationContext`.
- Hover uses `NSTrackingArea` and expands after 150 ms of hover. It collapses 300 ms after the mouse leaves.
- **Right-click** opens an `NSMenu` with: Hide mode toggle, Mark all read, Install/Uninstall hooks, Launch at login, Settings…, Quit.

## Hover glow (REQ-11)
- The glow is a `CALayer` shadow on the island's background layer: colour `clawd.body`, radius 9 pt, offset 2 pt downward, with an explicit `shadowPath` equal to the island shape. Because the path is given, there is no offscreen pass and no blur filter.
- Only `shadowOpacity` animates (0 ↔ 0.35), in the same `NSAnimationContext` group as the expand and collapse. At rest, the glow is static and costs no CPU.
- While expanded, the panel frame grows by the glow margin on the sides and bottom, so the shadow is not clipped. Beyond the shadow's blur, the margin is fully transparent, so clicks there probably pass through to the window below (to be confirmed by eye). It exists only while the panel is expanded. When collapsed, the frame equals the island again. The blur radius must stay well below the 24 pt margin. Otherwise the clipped blur shows a hard edge, which was the case at radius 16.
- `NotchPanel` keeps `hasShadow = false`: the glow is our layer, not the window shadow.
- If `perf.sh` shows that the glow breaks the budget, remove it and mark REQ-11 as dropped (`08`).

## Hide mode (REQ-05)
- **Hidden:** the wing collapses, the island is the width of the notch only, and Clawd slides under the right part of the notch so that only the top 6–8 pt (ear tips and eyes) peek out below the notch edge. On a virtual notch, the sliver hangs below the right part of the black pill.
- **Pop-out:** on `Snapshot.popToken` change, or on any aggregate change, the island expands to its collapsed-visible form with a spring (response 0.35, damping 0.7). It stays for 4 s and then retracts. While the state is `needsInput`, it stays out.

## Settings window (SwiftUI)
These settings are not in scope for WP-2. The full set:
- Port.
- Hide mode default.
- Focus-read mode: tab, app, or off.
- Launch at login (`SMAppService.mainApp`).
- Install/Uninstall hooks.
- Hook status (whether the last event was received and when).
