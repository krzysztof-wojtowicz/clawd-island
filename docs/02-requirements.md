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
| `compacting` | context compaction (`PreCompact`) | sweeps with a broom, dust puffs |
| `juggling` | subagents are running (`activeSubagents > 0`) | juggles 3 balls |
| `talking` | writing text | speech bubble with animated dots, mouth/body bounce |
| `done` | a session finished and is unread | one paw raised, with a pop-out on transition |
| `needsInput` | a permission or question is pending | paw raised, red "!" badge, stronger pop-out |
The pet shows no single session: it shows the **aggregate**, the most important state across all live sessions (AC3, `04`). One session waiting for permission raises the paw even while others are busy.
- AC1: Each state is distinguishable at a glance, at actual notch size.
- AC2: State changes render within 150 ms of the event reaching the app.
- AC3: The highest-priority state across sessions wins: `needsInput > done > juggling > compacting > usingTools > talking > thinking > idle > sleeping`.
- AC4: `compacting` starts on `PreCompact` and ends on the next state-setting event or on `SessionStart(source: compact)` (`04`).
- AC5: The panel text reads "compacting" and "N subagents"; both states count as working in the status buckets.
- AC6: `juggling` is derived per session from `activeSubagents > 0` unless the session is `needsInput` or `done`. The counter resets on `Stop`, `StopFailure` and `UserPromptSubmit`, so a missed `SubagentStop` cannot leave the pet juggling.

## REQ-04 Session counter and HP bar
The collapsed island is laid out as `counter | notch | HP bar · pet` (see the sketch in `06`). Everything is vertically centred in the top row:
- an **HP bar** = `100 − rate_limits.five_hour.used_percentage`. It is **vertical**, sits left of the pet, is as tall as the pet, and fills bottom-up. It is coloured green, then yellow below 50, then red below 20. Hovering shows the exact percentage and the time until reset.
- one **session counter**: the number of live sessions, centred inside a circle that is always shown (including 0). The circle's colour shows the most urgent session. The first rule that matches wins:
  1. red (`badge.alert`): any session is `needsInput`,
  2. orange (`clawd.body`): any session is `done` and unread,
  3. blue (`badge.active`): sessions exist, and they are idle or working (the pet shows what they do),
  4. grey (`badge.empty`): no sessions.
- **expanded counters**: when the island expands (hover), the single counter morphs into three circles in the top row (at notch / menu-bar height), left of the notch. Always shown, in this order, together they split the live sessions:
  1. idle + working (`idle`, read `done`, `thinking`, `usingTools`, `talking`, `compacting`, `juggling`): grey (`badge.empty`) when the number is 0, blue (`badge.active`) when it is 1 or more,
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
- AC1: In hide mode, the pet pops out (wings shown) for about **3 s**, then retracts, only when the aggregate **enters** `talking`, `done`, `needsInput` or `juggling`, or when `popToken` advances (a new attention edge). Other state changes (`thinking`, `usingTools`, `compacting`, `idle`, `sleeping`) only change the peeking pet's pose and animation in the corner. A new trigger during a pop-out restarts the 3 s (v3.1).
- AC2: `needsInput` stays popped out until it is resolved (it does not retract after 3 s).
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

## v2 (done in WP-9, WP-10, WP-11; extended in v3)
- **REQ-V2-01**: Allow / Deny / Always allow permission prompts from the notch (ADR-0006). The `PermissionRequest` HTTP hook is held open while the notch shows the request; the terminal dialog appears at the same time, and whichever is answered first wins.
  - AC1: When Claude Code asks for a tool permission, the expanded panel shows a **permission card** at the top (project, tool name, a one-line truncated summary of the input such as the Bash command or file path) with action buttons. The pet is `needsInput` and pops out as before.
  - AC2: Allow or Deny from the notch resolves the request in Claude Code within 1 s, and the terminal dialog closes.
  - AC3: The terminal dialog still appears immediately and answering it works as before. The card disappears when the session moves on, when Claude Code closes the hook connection, or after 110 s (the app then replies with no decision).
  - AC4: When the app is not running, or "Approve permissions from the notch" is off, behaviour is exactly as without the app: no decision and no delay.
  - AC5: The app never decides on its own; only an explicit click sends a decision. Deny sends the message "Denied from ClawdNotch".
  - AC6 (v3): The card has three **equal-width pills with centred labels**: Allow, Deny, Always allow (layout in `06`).
  - AC7 (v3): Always allow replies `allow` with the request's first `permission_suggestions` entry, as received, in `decision.updatedPermissions` (`05`). The suggestion carries its own destination.
  - AC8 (v3): Always allow is hidden when the request has no suggestion. Its tooltip shows the rule that would be saved.
  - AC9 (v3): Core keeps the suggestion as raw JSON of at most 2 KiB in `PendingPermission`; a larger one hides the button.
- **REQ-V2-02**: Better focus for the VS Code family, JetBrains IDEs, Ghostty and Warp. **Tab precision is not possible**: none offers a scripting API to select a tab (VS Code's and the IDEs' terminal panels are internal). Best effort:
  - AC1: For the VS Code family (VS Code, Insiders, VSCodium, Cursor, Windsurf), a panel click raises the **window** whose title has a segment equal to the session's project name (else contains it), through the Accessibility API, then activates the app. On activation, a focused window matching a session's project name marks that session read at once (window precision); otherwise the 2 s app-level rule applies.
  - AC2: The Accessibility permission is requested once, on first use. Without it, everything falls back to app level silently.
  - AC3: Ghostty and Warp stay at app level (click activates the app; reading uses the 2 s dwell).
  - AC4 (v3): JetBrains IDEs (`com.jetbrains.` bundle-ID family, `05`) get the same window-level click and read behaviour as AC1.
  - AC5 (v3): The project name is matched per family: JetBrains titles are `project – file`, so the **first** segment is the project; VS Code drops the last segment (the app name). Segments split on ` — `, ` – ` and ` - `.
  - AC6 (v3): State tracking already works in any IDE terminal (hooks do not depend on the terminal); only focus precision is limited to the window.
- **REQ-V2-03**: Start a new Claude Code session from the expanded panel. A "+ New" footer button opens a menu of up to 5 recent project directories (`cwd`s seen, most recent first, `recentProjects` in config.json) plus "Choose Folder…". The directory opens in a new window of the preferred terminal (Terminal.app or iTerm2, from the most recent session, else Terminal.app) running `claude`. It quotes the path safely for shell and AppleScript and never edits Claude Code settings.
  - AC1: The new session appears in the panel within a few seconds (through its hooks), in the chosen directory.
  - AC2: A path with spaces, quotes or `$` opens correctly and runs nothing but `cd <dir> && claude`.

## v3
- **REQ-12 Sound cues**: a short system sound on the edge into attention.
  - AC1: Entering `needsInput` plays one system sound (default "Funk"); a session becoming `done` and unread plays another ("Glass").
  - AC2: Once per edge, using the `popToken` edge logic; no repeat while the state persists.
  - AC3: No sound for changes the user causes (mark read, focus-read, session removal).
  - AC4: Settings toggle "Sound cues" (`soundCues` in config), default **on**. Sounds are cached `NSSound`s; no timer, no polling.
- **REQ-13 Music headphones**: while Apple Music or Spotify plays, the pet wears headphones.
  - AC1: Driven only by the apps' play-state notifications (`05`, ADR-0007): no login, no private API, no polling, no AppleScript.
  - AC2: `Playing` shows the headphones (150 ms cross-fade); `Paused` / `Stopped` hides them.
  - AC3: The headphones are an overlay orthogonal to every pose, including hide mode. Only in `idle` and `sleeping` may the head bob slightly.
  - AC6 (v3.1): The band and cups read clearly on the black island (light colours, `07`), and in every pose — the raised arm in `done` / `needsInput`, the hammer, the broom, the balls — nothing hides them, and they never cover the eyes.
  - AC7 (v3.1): Settings has "Show headphones when music plays" (`headphones` in config.json, default on). Off: the watcher stops observing and the headphones hide at once. On: they appear at the next play / pause / track change (AC5).
  - AC4: Title, artist and album are stored in `Snapshot.nowPlaying` for later features and are not displayed.
  - AC5: Known limit: after launching the app, the headphones appear at the next play, pause or track change. Reduce Motion: no bob.
- **REQ-14 Typography**: all HUD and panel text (counters, footer, session rows, cards, Settings) uses **JetBrains Mono**.
  - AC1: Looked up with `NSFont(name:size:)`; fallback `NSFont.monospacedSystemFont` when it is not installed. No crash, no layout break.
  - AC2: The font is not bundled yet (OFL 1.1 license obligations, deferred to the production phase, `09`).
  - AC3: Text still fits: footer, cards and panel rows truncate rather than overflow.
