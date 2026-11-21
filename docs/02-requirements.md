# 02 — Requirements

Each requirement has acceptance criteria (AC). WPs in `09-roadmap.md` reference these IDs.

## REQ-01 Lives in the notch
The pet always lives on the **main display** (the one with the menu bar, as set in System Settings → Displays). If that display has a notch, the pet anchors to it. Otherwise it uses the top centre of the display as a virtual notch. This is the user's decision: with an external monitor set as main, the pet goes there even when the MacBook lid is open.
- AC1: When the main display is a notched MacBook screen, the island has two asymmetric wings, each only as wide as its content: a **left wing** (the session counter) flush against the notch's left edge, and a **right wing** (HP bar and pet) flush against its right edge (±1 pt).
- AC2: When the main display is an external monitor, the virtual notch is centred at its top and the wings sit on either side of it, whether the lid is open or closed.
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
| `usingTools` | Claude Code is running a tool (Bash, Edit, …) | swings a hammer |
| `talking` | writing text | speech bubble with animated dots, mouth/body bounce |
| `done` | a session finished and is unread | one paw raised, with a pop-out on transition |
| `needsInput` | a permission or question is pending | paw raised, red "!" badge, stronger pop-out |
The pet shows no single session: it shows the **aggregate**, the most important state across all live sessions (AC3, `04`). One session waiting for permission raises the paw even while others are busy.
- AC1: Each state is distinguishable at a glance, at actual notch size.
- AC2: State changes render within 150 ms of the event reaching the app.
- AC3: The highest-priority state across sessions wins: `needsInput > done > usingTools > talking > thinking > idle > sleeping`.

## REQ-04 Session counter and HP bar
The collapsed island is laid out as `counter | notch | HP bar · pet` (see the sketch in `06`). Everything is vertically centred in the top row:
- an **HP bar** = `100 − rate_limits.five_hour.used_percentage`. It is **vertical**, sits left of the pet, is as tall as the pet, and fills bottom-up. It is coloured green, then yellow below 50, then red below 20. Hovering shows the exact percentage and the time until reset.
- one **session counter**: the number of live sessions, centred inside a circle that is always shown (including 0). The circle's colour shows the most urgent session. The first rule that matches wins:
  1. red (`badge.alert`): any session is `needsInput`,
  2. orange (`clawd.body`): any session is `done` and unread,
  3. blue (`badge.active`): sessions exist, and they are idle or working (the pet shows what they do),
  4. grey (`badge.empty`): no sessions.
- **expanded counters**: when the island expands (hover), the single counter morphs into three circles in the top row (at notch / menu-bar height), left of the notch. They replace the old status-count row in the panel, which frees vertical space. Always shown, in this order, together they split the live sessions:
  1. idle + working (`idle`, read `done`, `thinking`, `usingTools`, `talking`): grey (`badge.empty`) when the number is 0, blue (`badge.active`) when it is 1 or more,
  2. orange (`clawd.body`): `done` and unread,
  3. red (`badge.alert`): `needsInput`.
- a **usage line** in the panel footer: `WK 81% · HP 63% · resets in 1h 12m`.
- AC1: The counter equals the number of sessions in the panel and its colour follows the rule above. The three expanded counters add up to the collapsed counter.
- AC2: If usage is unknown (API plan, or no data yet), the HP bar is hidden or greyed. It is never fabricated.
- AC3: When `resets_at` passes, HP shows full and is marked stale until fresh data arrives.
- AC4: The wings are asymmetric and sized to their content: the left wing (counter) is about 28 pt or less, the right wing (HP bar and pet) about 56 pt or less, with enough room on the right that the `usingTools` hammer swing is never clipped (tuned by eye). There is a visible gap between the HP bar and the pet.
- AC5: `WK xx%` = `100 − rate_limits.seven_day.used_percentage`. It shows what is left, the same as HP. No weekly reset time is shown, because only HP has a countdown. The WK part is omitted when the window is absent, and after `seven_day.resets_at` passes it shows 100 % as stale (the same rule as AC3). Each percentage is tinted with the `hp.*` level colours.

## REQ-05 Hide mode
A toggle (right-click menu or Settings) hides the wings and tucks the pet into the notch's **bottom-right corner, upside down**: it is turned 180° and then a further 30° (about 150° clockwise in total), so its legs and lower body stay hidden behind the notch while its head, eyes and arms stick out down and to the right. Its state animations (blinking, hammer, bubbles, the "!" badge) stay visible.
- AC1: In hide mode, any aggregate state change makes the pet pop out (wings shown) for about 4 s, then retract.
- AC2: `needsInput` stays popped out until it is resolved.
- AC3: Hovering over the peeking pet expands the island temporarily.
- AC4: Every transition (hidden ↔ popped ↔ expanded, and switching hide mode on or off in any of them) moves the pet continuously: its position and tilt animate together with the island resize, with no jumps.

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
- (b) the user clicks "mark all read",
- (c) the user focuses the terminal hosting that session.
- AC1: (c) works at **tab precision** for Terminal.app and iTerm2, and at **app precision** for other terminals (focus held ≥ 2 s). It also covers a session that finishes while you are already looking at its tab: when a session becomes `done` and its terminal is frontmost, the selected tab is checked once (event-driven, no polling) and a match marks it read.
- AC1a: Focus and read tracking also work for sessions that started before the app launched (or relaunched): the terminal, tty and pid of a session are learned from its statusline updates as well as from `SessionStart` (`05`).
- AC2: Clicking a session in the panel focuses its terminal app (and tab where supported); it does not mark the session read by itself. The session becomes read through (c), because its tab is now focused. That is applied right after a successful focus (selecting a tab in a terminal that is already frontmost fires no activation event), and it follows the focus-read mode (with `off`, the click only focuses). If the terminal is unknown or has quit, the click does nothing.
  - Why focus rather than "open/resume the session": the session is already running in that tab; resuming it elsewhere would start a second Claude Code process on the same session.
- AC3: The panel lists sessions by importance (`04`, "Panel order"), so sessions that need you are never hidden behind "+n more".

## REQ-11 Hover glow
While the session panel is expanded (on hover), a soft orange (`clawd.body`) glow sits under and around it. It fades in and out with the expand and collapse. It is a nice-to-have: it ships only if it costs nothing measurable.
- AC1: No extra CPU at rest. The glow is a static layer, and only its opacity is animated (see `06` and `08`).
- AC2: The REQ-08 budgets still hold, measured with `perf.sh` with the panel collapsed and expanded. If they do not, the glow is removed and this REQ is marked *dropped*, with the measured numbers recorded in `08`.

## v2 (in scope since WP-9)
- **REQ-V2-01**: Allow/Deny permission prompts from the notch (ADR-0006). The `PermissionRequest` HTTP hook is held open while the notch shows the request; the terminal dialog appears at the same time, and whichever is answered first wins.
  - AC1: When Claude Code asks for a tool permission, the expanded panel shows a **permission card** at the top (project, tool name, a one-line summary of the input such as the Bash command or the file path, truncated) with **Allow** and **Deny** buttons. The pet is `needsInput` and pops out as before.
  - AC2: Allow or Deny from the notch resolves the request in Claude Code within 1 s, and the terminal dialog closes.
  - AC3: The terminal dialog still appears immediately and answering it works as before. The card disappears when the session moves on (any event that changes its state), when Claude Code closes the hook connection, or after 110 s (the app then replies with no decision).
  - AC4: When the app is not running, or the setting "Approve permissions from the notch" is off, behaviour is exactly as without the app: no decision and no delay.
  - AC5: The app never decides on its own; only an explicit click sends a decision. Deny sends the message "Denied from ClawdNotch".
- **REQ-V2-02**: Better focus for Ghostty, Warp and VS Code. **Tab precision is not possible**: none of them offers a scripting API to select a tab (Ghostty and Warp have no AppleScript tab dictionary; VS Code's terminal panel is internal). Best effort instead:
  - AC1: For the VS Code family (VS Code, VS Code Insiders, VSCodium, Cursor, Windsurf), a panel click raises the **window** whose title contains the session's project name, through the Accessibility API, then activates the app. On activation of such an app, a focused window whose title contains a session's project name marks that session read at once (window precision); otherwise the 2 s app-level rule applies.
  - AC2: The Accessibility permission is requested once, on first use. Without it, everything falls back to app level silently.
  - AC3: Ghostty and Warp stay at app level (click activates the app; reading uses the 2 s dwell).
- **REQ-V2-03**: Start a new Claude Code session from the expanded panel. A "New session" button in the footer opens a menu of up to 5 recent project directories (the `cwd`s of sessions seen, most recent first, persisted as `recentProjects` in config.json) plus "Choose Folder…". The chosen directory opens in a new window of the preferred terminal (the terminal of the most recently seen session if it is Terminal.app or iTerm2, otherwise Terminal.app) and runs `claude` there. It reuses the AppleScript mechanism from WP-6, quotes the path safely for both the shell and AppleScript, and never edits Claude Code settings.
  - AC1: The new session appears in the panel within a few seconds (through its hooks), in the chosen directory.
  - AC2: A path with spaces, quotes or `$` opens correctly and runs nothing but `cd <dir> && claude`.
