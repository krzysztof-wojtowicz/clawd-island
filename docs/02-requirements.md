# 02 — Requirements

Each requirement has acceptance criteria (AC). WPs in `09-roadmap.md` reference these IDs.

## REQ-01 Lives in the notch
The pet always lives on the **main display** (the one with the menu bar, as set in System Settings → Displays). If that display has a notch, the pet anchors to it. Otherwise it uses the top centre of the display as a virtual notch. This is the user's decision: with an external monitor set as main, the pet goes there even when the MacBook lid is open.
- AC1: When the main display is a notched MacBook screen, the island's single wing (pet, counters, HP bar) sits flush against the **right** edge of the physical notch (±1 pt). While collapsed, nothing extends left of the notch.
- AC2: When the main display is an external monitor, the virtual notch is centred at its top and the wing sits to its right, whether the lid is open or closed.
- AC3: A display change (plug, unplug, resolution change, or a different main display) moves the pet within 1 s, without a restart.

## REQ-02 Always on top
The pet stays visible above all apps, including full-screen apps, and on every Space.
- AC1: It is visible over a full-screen Safari or terminal, and over every Space in Mission Control.
- AC2: It never takes keyboard focus. Clicking it does not deactivate the frontmost app.
- AC3: It has no Dock icon and does not appear in the Cmd-Tab switcher.
- AC4: Switching Spaces (a three-finger swipe or Ctrl+←/→), or entering or leaving a full-screen app, does not move or re-animate the island. It stays fixed at the top, like the menu bar (ADR-0005).

## REQ-03 State is shown by appearance
| Aggregate state | Trigger (see `04-state-machine.md`) | Visual |
|---|---|---|
| `sleeping` | no live sessions | eyes closed, slow breathing, "Zzz" |
| `idle` | sessions exist, none busy or unread | blinking, small idle sway |
| `thinking` | a turn is in progress, no output yet | thought cloud or eyes up, gentle bob |
| `talking` | writing text or running tools | speech bubble with animated dots, mouth/body bounce |
| `done` | a session finished and is unread | one paw raised, with a pop-out on transition |
| `needsInput` | a permission or question is pending | paw raised, red "!" badge, stronger pop-out |
- AC1: Each state is distinguishable at a glance, at actual notch size.
- AC2: State changes render within 150 ms of the event reaching the app.
- AC3: The highest-priority state across sessions wins: `needsInput > done > talking > thinking > idle > sleeping`.

## REQ-04 Counters and HP bar
The compact right wing is laid out as `HP bar | pet | counts` (see the sketch in `06`):
- an **HP bar** = `100 − rate_limits.five_hour.used_percentage`. It is **vertical**, sits left of the pet, is as tall as the pet, and fills bottom-up. It is coloured green, then yellow below 50, then red below 20. Hovering shows the exact percentage and the time until reset.
- the number of **active** sessions, shown as a plain number at the top of the counts column, always visible (including 0),
- the number of **attention** sessions (`done` unread + `needsInput`), shown as a number in a circle badge below it, always visible. The badge is blue (`badge.calm`) at 0, orange (`clawd.body`) while only `done` sessions are unread, and red (`badge.alert`) when any session is `needsInput`.
- AC1: The counters match the session panel exactly.
- AC2: If usage is unknown (API plan, or no data yet), the HP bar is hidden or greyed. It is never fabricated.
- AC3: When `resets_at` passes, HP shows full and is marked stale until fresh data arrives.
- AC4: The wing is at most 64 pt wide (a target, tuned by eye), so the island sticks out from the notch noticeably less than the previous two 60 pt wings.

## REQ-05 Hide mode
A toggle (click or right-click menu) collapses the pet so that only a sliver (ears and eyes) peeks out from under the notch.
- AC1: In hide mode, any aggregate state change makes the pet pop out for about 4 s, then retract.
- AC2: `needsInput` stays popped out until it is resolved.
- AC3: Hovering over the sliver expands the pet temporarily.

## REQ-06 Clawd-inspired design
Orange (`#D97757` family), a rounded-rectangle body, two tall dark eyes, little side arms and four stubby legs, with smooth corners and richer animation than the pixel original.
- AC1: Vector-only, so it is sharp on every Retina scale. There are no bitmap assets.

## REQ-07 macOS only
macOS 14+ on Apple silicon, and also on Intel if the build allows it at no extra cost.

## REQ-08 Minimal resource usage
See `08-performance.md`.
- AC1: Idle CPU < 0.3 %. Animating < 1 %. RSS < 40 MB. 0 wakeups/s while sleeping, apart from the 30 s liveness timer.
- AC2: It adds no measurable latency to Claude Code (hooks are fire-and-forget).

## REQ-09 Claude Code subscription integration
- AC1: A one-click install adds hooks and the statusline to `~/.claude/settings.json` (with a backup, idempotently). Uninstall restores the previous state, including any original statusline.
- AC2: Multiple concurrent sessions (several terminals, subagents) are tracked independently.
- AC3: Usage data comes from the statusline `rate_limits` field only (ADR-0004).

## REQ-10 Attention / read tracking
A `done` session becomes *read* when any of the following happens:
- (a) a new prompt is submitted in that session,
- (b) the user clicks the session in the panel, or clicks "mark all read",
- (c) the user focuses the terminal hosting that session.
- AC1: (c) works at **tab precision** for Terminal.app and iTerm2, and at **app precision** for other terminals (focus held ≥ 2 s).
- AC2: Clicking a session in the panel activates its terminal (and tab where supported).

## REQ-11 Hover glow
While the session panel is expanded (on hover), a soft orange (`clawd.body`) glow sits under and around it. It fades in and out with the expand and collapse. It is a nice-to-have: it ships only if it costs nothing measurable.
- AC1: No extra CPU at rest. The glow is a static layer, and only its opacity is animated (see `06` and `08`).
- AC2: The REQ-08 budgets still hold, measured with `perf.sh` with the panel collapsed and expanded. If they do not, the glow is removed and this REQ is marked *dropped*, with the measured numbers recorded in `08`.

## Future (v2, not in scope)
- **REQ-V2-01**: Allow/Deny permission prompts from the notch, through a blocking `PermissionRequest` HTTP hook with a timeout and a fallback to the terminal. The architecture must not preclude this (the event server can hold a request open).
- **REQ-V2-02**: Tab-precise focus for Ghostty, Warp, and VS Code.
- **REQ-V2-03**: Start a new Claude Code session from the expanded panel. For example, a "New session" button opens the user's terminal in a chosen or recent project directory and runs `claude` there. It reuses the terminal-launch and focus mechanism from WP-6 (AppleScript or `open -a`), and it never edits Claude Code settings.
