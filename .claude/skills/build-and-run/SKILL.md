---
name: build-and-run
description: Build, bundle, launch, and visually verify the ClawdIsland app (including screenshots of the notch area). Use whenever you need to see a UI or pet change running for real, or to restart the app after changes.
---

# Build and run ClawdIsland

1. `swift build` must pass. Fix any compiler errors before continuing.
2. `scripts/run.sh` kills any running `ClawdIsland`, bundles a debug `dist/ClawdIsland.app`, and launches it with `open`.
   - Pet demo mode: `scripts/run.sh --pet-demo` cycles through all pet states every 3 s.
3. Confirm that it is running: `pgrep -x ClawdIsland`.
4. Screenshot the notch region into the session scratchpad. The rectangle is `x,y,w,h` in points, from the top-left of the main display:
   `screencapture -x -R "$(( W/2 - 300 )),0,600,220" <scratchpad>/notch.png`, where `W` is the screen width in points.
   Open the image with the Read tool. Check the alignment with the notch, legibility at actual size, and colours.
   If `screencapture` fails ("could not create image"), the terminal lacks the Screen Recording permission. Run `swift scripts/window-info.swift` to check geometry and window level, and ask the user to check the visuals.
5. Drive states with the `simulate-claude-events` skill. Measure with `perf-check`.
6. Stop the app when you are done: `pkill -x ClawdIsland`.

Notes:
- The app has no Dock icon. Quit it from its right-click menu or with `pkill`.
- If the window does not show over a full-screen app, see `docs/06-window-and-notch.md` (level and collection behaviour).
