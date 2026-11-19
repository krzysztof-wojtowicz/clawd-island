# 06 — Window and notch

## Panel setup
- The window is an `NSPanel` subclass with `styleMask: [.borderless, .nonactivatingPanel]`, `isFloatingPanel = true`, `hidesOnDeactivate = false`, `backgroundColor = .clear`, `isOpaque = false`, and `hasShadow = false`.
- `level`: `.mainMenu + 3` (window server layer 27, above the menu bar at 24). **Spike A (WP-0):** the panel sits exactly over the built-in notch (verified with `window-info.swift`). Visibility over full-screen apps and other Spaces needs a visual check by the user, because the Screen Recording permission is missing. If it is hidden there, try `CGShieldingWindowLevel()`.
- `constrainFrameRect(_:to:)` is overridden to return the frame unchanged. Otherwise AppKit pushes the panel below the menu bar.
- `collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`.
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
          ┌──────────── black island (extends the notch) ────────────┐
 collapsed│ [Clawd 28pt] │        physical notch        │ 2 ● 1 ▮▮▮▮▯ │
          └───────────────────────────────────────────────────────────┘
 expanded (hover): island grows down by ~ 120–200 pt into a panel:
          │  proj-a   ● talking   Bash          12s                     │
          │  proj-b   ✋ done (unread)           2m     [mark read]     │
          │  HP 63%  · resets in 1h 12m                    [⚙] [hide]   │
```
- Left wing: Clawd, 28–32 pt tall, vertically centred in the notch height.
- Right wing: active count, attention count (the badge turns red on `needsInput`), and the HP bar (5 segments or continuous, 3 pt tall).
- The island is black (`#000`), so it merges with the physical notch. Corners use a continuous (squircle) curve.
- **Click-through:** the panel frame equals the island's frame. Resize the panel when the island changes, rather than using a full-width transparent window. Animate the resize with `NSAnimationContext` together with SwiftUI.
- Hover uses `NSTrackingArea` and expands after 150 ms of hover. It collapses 300 ms after the mouse leaves.
- **Right-click** opens an `NSMenu` with: Hide mode toggle, Mark all read, Install/Uninstall hooks, Launch at login, Settings…, Quit.

## Hide mode (REQ-05)
- **Hidden:** the island is the width of the notch only, and Clawd is positioned so that only the top 6–8 pt (ear tips and eyes) peek out below the notch edge. On a virtual notch, the sliver hangs below the black pill.
- **Pop-out:** on `Snapshot.popToken` change, or on any aggregate change, the island expands to its collapsed-visible form with a spring (response 0.35, damping 0.7). It stays for 4 s and then retracts. While the state is `needsInput`, it stays out.

## Settings window (SwiftUI)
These settings are not in scope for WP-2. The full set:
- Port.
- Hide mode default.
- Focus-read mode: tab, app, or off.
- Launch at login (`SMAppService.mainApp`).
- Install/Uninstall hooks.
- Hook status (whether the last event was received and when).
