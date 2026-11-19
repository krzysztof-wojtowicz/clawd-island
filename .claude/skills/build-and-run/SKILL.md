---
name: build-and-run
description: Build, bundle, launch, and visually verify the ClawdNotch app (including screenshots of the notch area). Use whenever you need to see a UI or pet change running for real, or to restart the app after changes.
---

# Build and run ClawdNotch

> `scripts/*` are created in WP-0. If they are missing, the skeleton is not built yet: do WP-0 first.

1. `swift build` must pass. Fix any compiler errors before continuing.
2. `scripts/run.sh` kills any running `ClawdNotch`, bundles a debug `dist/ClawdNotch.app`, and launches it with `open`.
   - Pet demo mode: `scripts/run.sh --pet-demo` cycles through all pet states every 3 s.
3. Confirm that it is running: `pgrep -x ClawdNotch`.
4. Screenshot the notch region into the session scratchpad. The rectangle is `x,y,w,h` in points, from the top-left of the main display:
   `screencapture -x -R "$(( W/2 - 300 )),0,600,220" <scratchpad>/notch.png`, where `W` is the screen width in points.
   Open the image with the Read tool. Check the alignment with the notch, legibility at actual size, and colours.
5. Drive states with the `simulate-claude-events` skill. Measure with `perf-check`.
6. Stop the app when you are done: `pkill -x ClawdNotch`.

Notes:
- The app has no Dock icon. Quit it from its right-click menu or with `pkill`.
- If the window does not show over a full-screen app, see `docs/06-window-and-notch.md` (level and collection behaviour).
