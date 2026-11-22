# 06 — Window and notch

## Panel setup
- The window is an `NSPanel` subclass with `styleMask: [.borderless, .nonactivatingPanel]`, `isFloatingPanel = true`, `hidesOnDeactivate = false`, `backgroundColor = .clear`, `isOpaque = false`, and `hasShadow = false`.
- `level`: `.mainMenu + 3` (window server layer 27, above the menu bar at 24). Verified with `window-info.swift`: the panel sits exactly over the built-in notch, and it is visible over full-screen apps (confirmed by the user).
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
              ┌──── black island: two asymmetric wings around the notch ────┐
 collapsed    │ (3) │        physical notch        │ ▮ ┌─────┐               │  (3) = session counter, circle colour =
              │     │                              │ ▮ │Clawd│               │        red / orange / blue / grey
              └─────┘                              └─▯─└─────┘───────────────┘  ▮ = vertical HP bar
 expanded (hover): the top row keeps the notch height; the counter morphs into three counters, and the island
 grows down into a panel, centred under the notch, with a soft orange glow beneath it (REQ-11):
       │ (2)(1)(1) │        physical notch        │ ▮ Clawd  │   = idle+working · done · needs input
       │  proj-b   ● done (unread)                                        │
       │  proj-a     using Bash                                           │
       │  WK 81% · HP 63% · resets in 1h 12m   [+ New] [Mark all read]     │
```
- Top row: the notch plus **two wings**, `max(notch height, 32 pt)` tall, so on a short virtual notch (24 pt menu bar) the island hangs a little below the menu bar. The wings are asymmetric and only as wide as their content (REQ-04 AC4): the **left wing** (about 28 pt) is flush with the notch's left edge, the **right wing** (about 56 pt, room for the hammer swing) with its right edge.
- **Left wing: session counter.** The number of live sessions, centred inside a 16 pt circle that is always shown and vertically centred in the top row. A two-digit count widens the circle into a pill. Colour, first match wins: `badge.alert` (red) if any session is `needsInput`, `clawd.body` (orange) if any is `done` and unread, `badge.active` (blue) if any sessions exist, otherwise `badge.empty` (grey).
- **Right wing: HP bar, then Clawd**, vertically centred in the top row.
  - **HP bar:** vertical and continuous, 3 pt wide, as tall as the pet, filling bottom-up in `hp.*` colours. It is hidden while usage is unknown, and full and dimmed while stale. The hover tooltip shows the same line as the panel footer, computed when it is shown.
  - **Clawd:** 26 pt tall (`07`). It may shrink to about 22 pt if that is needed to meet the width target.
- **Expanded counters (REQ-04):** on expand, three 16 pt circles slide out of the single counter's position into the top row, left of the notch, in the order: idle + working (`badge.empty` at 0, otherwise `badge.active`), done and unread (`clawd.body`), needs input (`badge.alert`). Position and opacity animate in the same `NSAnimationContext` group as the expand; on collapse they merge back into the single circle. All three are always shown, so the layout never jumps; a 0 in the orange or red circle is drawn at 35 % opacity. There are no captions; each circle has a tooltip and an accessibility label ("2 idle or working", "1 done", …).
- The expanded panel stays centred under the notch, at least 360 pt wide (`expandedMinWidth`). It lists up to 5 sessions, sorted by importance (`04`, "Panel order"), then "+n more", with the usage line and "Mark all read" in the footer. The panel reaches about 164 pt below the top row (`expandedExtraHeight`).
  - **Usage footer:** `WK 81% · HP 63% · resets in 1h 12m`. Each percentage is tinted with its `hp.*` level colour, and the rest is secondary text. If the line does not fit beside the buttons, "resets in" shortens to "resets". WK has no countdown and is omitted when unknown (the line then starts at HP). The HP-bar tooltip shows the same line.
  - **State dot** before each session name: red (`badge.alert`) for `needsInput`, orange (`clawd.body`) for `done` and unread, blue (`badge.active`) for working (`thinking`, `usingTools`, `talking`); idle and read sessions have no dot.
  - **"+ New"** (REQ-V2-03) opens the recent-projects menu (`05`).
  - **Permission cards** (REQ-V2-01): while requests are pending, up to 2 cards sit above the session list, newest first. Each card is about 40 pt (44 pt overflowed the 164 pt panel): on the left, `proj-a · Bash` and below it the input summary (secondary text, one line, truncated in the middle); on the right, **three equal-width pills in one row — Deny / Allow / Always**, each label centred in its pill. "Always" is omitted (the other two keep their size) when the request has no suggestion; its tooltip shows the rule. With 2 cards the list shows 1 session row plus "+n more" (the panel height does not change). The buttons work without activating the app (non-activating panel).
  - **Clicking a session row** focuses its terminal and tab (REQ-10 AC2, `05`); it does not mark the session read by itself.
- **Font (REQ-14):** all HUD and panel text uses JetBrains Mono via `NSFont(name:size:)`, falling back to `NSFont.monospacedSystemFont`; one helper owns the lookup. Text truncates rather than overflowing. Colours stay system label colours.
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
- **Hidden:** both wings are gone and the island is exactly the notch. The window extends past the notch's bottom-right corner (about 24 pt to the right and 22 pt below, tuned by eye); that extra area is transparent, so the pet hangs over whatever is there. Clawd is **upside down and tilted**: rotated about 150° clockwise (180° minus 30°), with its legs and lower body behind the notch's bottom-right corner (the opaque notch-cover layer hides them) and its head, eyes and arms sticking out down and to the right. All state animations keep running and stay visible. On a virtual notch, it hangs from the pill's bottom-right corner the same way.
- **Pop-out (v3.1):** on a `Snapshot.popToken` advance, or when the aggregate **enters** `talking`, `done`, `needsInput` or `juggling`, the wings appear and Clawd moves from its peek spot into the right wing, upright. It stays for **3 s** (one-shot task, no polling, restarted by a new trigger) and then retracts. Every other state change only switches the peeking pet's pose and animation, with no pop-out. `talking` re-enters often during a turn (the 2 s decay back to `thinking`), so a busy turn may pop out repeatedly; that is accepted. While the state is `needsInput`, it stays out. Hovering the peeking pet expands the island as usual (counters morph, panel opens), and collapsing goes back to the peek.
- **Transitions (REQ-05 AC4):** the pet has a target frame and tilt per mode (hidden / wing / expanded). On every mode change, including hide mode switched on or off while popped or expanded, the pet's position and rotation animate with Core Animation (the pop-out spring from `07`), with the spring, which may settle after the panel resize has finished (Reduce Motion: a straight 200 ms move). The pet is placed in screen-stable coordinates, so it does not jitter while the window frame interpolates.
- The setting is `hideMode` in config.json; it is toggled from the right-click menu or Settings.

## Settings window (AppKit)
A plain AppKit window, built when opened and released on close (SwiftUI would cost too much RSS, `08`). It activates the app while open. Current items: hide mode, focus-read mode (`tab` / `app` / `off`), "Approve permissions from the notch" (`notchPermissions`, default on), **"Sound cues"** (`soundCues`, default on, REQ-12, WP-15), **"Show headphones when music plays"** (`headphones`, default on, REQ-13 AC7) and launch at login. Port and hook status are not built yet (Install/Uninstall hooks is in the right-click menu).
