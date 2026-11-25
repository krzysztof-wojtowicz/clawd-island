# 02 — Requirements

Each requirement has acceptance criteria (AC); work packages in `09-roadmap.md` and code comments cite these IDs. Everything below is implemented. Requirements and ACs marked **(1.1.0)** were added or changed in 1.1.0 (work packages in `09` "1.1.0"); the rest dates from 1.0.0.

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
| `sleeping` | no live sessions | eyes closed, slow breathing; no "Zzz" (1.1.0) |
| `idle` | sessions exist, none busy or unread | blinking, small idle sway |
| `thinking` | a turn is in progress, no output yet | thought cloud or eyes up, gentle bob |
| `usingTools` | Claude Code is running a tool (Bash, Edit, …) | swings a hammer (about 1.3× bigger, 1.1.0) |
| `compacting` | context compaction (`PreCompact`) | sweeps with a broom (about 1.3× bigger, 1.1.0), dust puffs |
| `juggling` | subagents are running (`activeSubagents > 0`) | juggles 3 balls; both paws toss and catch in turn, in sync with the balls (1.1.0) |
| `talking` | writing text for at least 1.5 s (a talking streak, 1.1.0) | speech bubble in the pet's own look (rounded, pet palette, 1.1.0) with animated dots, mouth/body bounce |
| `done` | a session finished and is unread | entry burst (1.1.0), one paw raised, then waving in a loop; pop-out on transition |
| `needsInput` | a permission or question is pending | entry burst (1.1.0), paw raised, then waving in a loop; red "!" badge, stronger pop-out |
The pet shows no single session: it shows the **aggregate**, the most important state across all live sessions (AC3, `04`). One session waiting for permission raises the paw even while others are busy.
- AC1: Each state is distinguishable at a glance, at actual notch size.
- AC2: State changes render within 150 ms of the event reaching the app.
- AC3: The highest-priority state across sessions wins: `needsInput > done > juggling > compacting > usingTools > talking > thinking > idle > sleeping`.
- AC4: `compacting` starts on `PreCompact` and ends on the next state-setting event or on `SessionStart(source: compact)` (`04`).
- AC5: The panel text reads "compacting" and "N subagents"; both states count as working in the status buckets.
- AC6: `juggling` is derived per session from `activeSubagents > 0` unless the session is `needsInput` or `done`. The counter resets on `Stop`, `StopFailure` and `UserPromptSubmit`, so a missed `SubagentStop` cannot leave the pet juggling.
- AC7: In `done` and `needsInput` the paw raises, then waves in a loop: three ±20° swings (about 0.9 s), a rest of about 1.5 s, repeating while the state holds. No wave under Reduce Motion (the paw stays raised). **(1.1.0)** Entering either state also plays a one-shot burst or flash around the pet, and the loop is stronger (`07`), so it is clear at a glance that something ended or needs you. The wave semantics above are unchanged; Reduce Motion skips the burst.
- AC8 **(1.1.0)**: A session becomes `talking` only when a `MessageDisplay` arrives after a **talking streak** of `MessageDisplay` events has lasted 1.5 s (`04` "Talking streak"); a single sentence followed by silence never shows `talking`. A short sentence between tool calls or subagent runs keeps the previous state, so it neither shows `talking` nor pops out mini mode. The 2 s talking decay is unchanged.
- AC9 **(1.1.0)**: The reworked poses (`07`): `sleeping` has no "Zzz"; the speech bubble matches the pet's look; the hammer and broom are about 1.3× bigger and are still never clipped (REQ-04 AC4); in `juggling` both paws visibly toss and catch, alternating in sync with the ball orbit. Every pose works in both styles (REQ-06 AC2), in mini mode and under Reduce Motion.

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

## REQ-05 Mini mode
A toggle (right-click menu "Mini Mode", or Settings) hides the wings and tucks the pet into the notch's **bottom-right corner, upside down**: it is turned 180° and then a further 30° (about 150° clockwise in total), so its legs and lower body stay hidden behind the notch while its head, eyes and arms stick out down and to the right. Its state animations (blinking, hammer, bubbles, the "!" badge) stay visible.
- AC1: In mini mode, the pet pops out (wings shown) only when the aggregate **enters** `talking`, `done` or `needsInput`, or when `popToken` advances (a new attention edge). Other state changes (`thinking`, `usingTools`, `compacting`, `juggling`, `idle`, `sleeping`) only change the peeking pet's pose and animation in the corner. A `talking` pop-out lasts about **3 s**, then retracts; a new trigger during a pop-out restarts the 3 s.
- AC2 **(1.1.0)**: `done` and `needsInput` stay popped out until the session is read (`done`) or resolved (`needsInput`): the pop-out holds while the aggregate is `done` or `needsInput`. When the aggregate leaves both, the usual 3 s countdown runs, then the pet retracts. Do Not Disturb suppresses every pop-out (REQ-23).
- AC3: Hovering over the peeking pet expands the island temporarily.
- AC4: Every transition (hidden ↔ popped ↔ expanded, and switching mini mode on or off in any of them) moves the pet continuously: its position and tilt animate together with the island resize, with no jumps.
- AC5: Launching with mini mode already on shows the pet tilted from the first frame (the pet is embedded before the persisted mode is applied).
- AC6: Launch at login is a Settings checkbox only; it is not in the right-click menu.

## REQ-06 Clawd-inspired design
Orange (`#D97757` family), a rounded-rectangle body, two tall dark eyes, little side arms and four stubby legs in two pairs with a gap between them, with smooth corners and richer animation than the pixel original.
- AC1: Vector-only, so it is sharp on every Retina scale. There are no bitmap assets.
- AC2 **(1.1.0)**: Settings → Pet offers a **Style**: **Roundy** (default, the look above) and **Sharpy** (the same pet with sharp corners on every pet part). It is `petStyle` in config (`roundy` / `sharpy`; an unknown value gives `roundy`). A change rebuilds the rig live, without a restart, and every style keeps the same anatomy, poses, animations and colours (`07` "Styles"). `--render-poses <dir> --pet-style <style>` renders the pose GIFs for one style.

## REQ-07 macOS only
macOS 14+ on Apple silicon only (no universal binary, no Intel build).

## REQ-08 Minimal resource usage
See `08-performance.md`.
- AC1: Sleeping CPU < 0.1 %, idle or animating < 1 % (averaged after settling). Memory: `footprint` (phys_footprint, what the app really owns) < 20 MB, and RSS < 45 MB steady (RSS includes shared AppKit/system pages: an empty accessory AppKit app already sits near 30 MB). 0 wakeups/s while sleeping, apart from the 30 s liveness timer.
- AC2: It adds no measurable latency to Claude Code (hooks are fire-and-forget).

## REQ-09 Claude Code subscription integration
- AC1: A one-click install adds hooks and the statusline to `~/.claude/settings.json` (with a backup, idempotently). Uninstall restores the previous state, including any original statusline.
- AC2: Multiple concurrent sessions (several terminals, subagents) are tracked independently.
- AC3: Usage data comes from the statusline `rate_limits` field only (ADR-0004).
- AC4: Install Hooks / Uninstall Hooks live in Settings only (a status row "Claude Code hooks: Installed / Not installed" plus one button), not in the right-click menu.
- AC5: On the first launch (no `onboarded` flag in config) while the hooks are not installed, Settings opens once with a one-line welcome ("Install the Claude Code hooks to connect Clawd") and Install as the default button; the flag is then set, so later launches do not open it. **(1.1.0)** The hooks row and the welcome live in the **General** tab, and the first run opens that tab (REQ-21).

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
While the session panel is expanded (on hover), a soft orange (`clawd.body`) glow sits under and around it, fading in and out with the expand and collapse.
- AC1: No extra CPU at rest. The glow is a static layer shadow; only its opacity animates (`06`, `08`).
- AC2: The REQ-08 budgets hold with the panel expanded (`08`, "expanded hover").

## REQ-12 Sound cues
A short system sound on the edge into attention.
- AC1: Entering `needsInput` plays "Funk"; a session becoming `done` and unread plays "Glass".
- AC2: Once per edge, using the `popToken` edge logic; no repeat while the state persists.
- AC3: No sound for changes the user causes (mark read, focus-read, session removal).
- AC4: Settings toggle "Sound cues" (`soundCues` in config), default on. Sounds play through a short-lived `afplay` process (an in-process `NSSound` costs +7 MB RSS); no timer, no polling.

## REQ-14 Typography
All HUD and panel text (counters, footer, session rows, cards, Settings) uses **JetBrains Mono**.
- AC1: Looked up with `NSFont(name:size:)`; fallback `NSFont.monospacedSystemFont`. No crash, no layout break.
- AC2: The font is bundled in `Contents/Resources/Fonts/` and registered for the process at launch only when JetBrains Mono is not installed (a process-registered face costs ~3 MB RSS per face used). OFL 1.1 text in `THIRD_PARTY_NOTICES.md`.
- AC3: Text fits: footer, cards and panel rows truncate rather than overflow.

## REQ-15 Distribution
The app is **ClawdIsland**, bundle id `dev.clawdisland.app`, released on GitHub.
- AC1: Signed with the stable self-signed "ClawdIsland" identity (ADR-0008) when present, otherwise ad-hoc; `bundle.sh` says which. Releases are always signed with it (`package.sh` refuses an ad-hoc build unless `--adhoc`), so Automation, Accessibility and login-item grants survive updates.
- AC2: Info.plist carries `CFBundleShortVersionString` (semantic version, kept in `bundle.sh` and `CHANGELOG.md`), `CFBundleVersion` (git commit count), `LSMinimumSystemVersion` 14.0, `NSHumanReadableCopyright`, and an `AppIcon.icns` drawn from the pet.
- AC3: `scripts/install.sh` installs a release build to `~/Applications` or `/Applications`; `scripts/uninstall.sh` uninstalls the hooks through the app's reversible uninstaller (`--uninstall-hooks`), then removes the app and its config; `scripts/package.sh` makes the zip and its `.sha256`. None of them touches `~/.claude/settings.json` except through `HookInstaller`.
- AC4: `LICENSE` is MIT; `THIRD_PARTY_NOTICES.md` lists JetBrains Mono; README leads with "Install from a release" (sha256 check, Gatekeeper Open Anyway) and covers Settings → Install, permissions, uninstall and privacy; `CHANGELOG.md` has one entry per release.
- AC5: GitHub Actions builds and tests every push and pull request (`swift build`, `scripts/test.sh`, `swift build -c release`; no secrets, no signing).
- AC6: Releases are Apple silicon zips with a `.sha256`; there is no update-check button and the app makes no network calls beyond `127.0.0.1`.

## REQ-16 Permissions from the notch
Allow / Deny / Always allow permission prompts from the notch (ADR-0006). The `PermissionRequest` HTTP hook is held open while the notch shows the request; the terminal dialog appears at the same time, and whichever is answered first wins.
- AC1: When Claude Code asks for a tool permission, the expanded panel shows a **permission card** at the top (project, tool name, a one-line truncated summary of the input such as the Bash command or file path) with action buttons. The pet is `needsInput` and pops out as before.
- AC2: Allow or Deny from the notch resolves the request in Claude Code within 1 s, and the terminal dialog closes.
- AC3: The terminal dialog still appears immediately and answering it works as before. The card disappears when the session moves on, when Claude Code closes the hook connection, or after 110 s (the app then replies with no decision).
- AC4: When the app is not running, or "Approve permissions from the notch" is off, behaviour is exactly as without the app: no decision and no delay.
- AC5: The app never decides on its own; only an explicit click sends a decision. Deny sends the message "Denied from ClawdIsland".
- AC6: The card has three **equal-width pills with centred labels**: Deny, Allow, Always allow (layout in `06`).
- AC7: Always allow replies `allow` with the request's first `permission_suggestions` entry, as received, in `decision.updatedPermissions` (`05`). The suggestion carries its own destination.
- AC8: Always allow is hidden when the request has no suggestion. Its tooltip shows the rule that would be saved.
- AC9: Core keeps the suggestion as raw JSON of at most 2 KiB in `PendingPermission`; a larger one hides the button.

## REQ-17 Editor window focus
Better focus for the VS Code family, JetBrains IDEs, Ghostty and Warp. **Tab precision is not possible**: none offers a scripting API to select a tab (VS Code's and the IDEs' terminal panels are internal). Best effort:
- AC1: For the VS Code family (VS Code, Insiders, VSCodium, Cursor, Windsurf), a panel click raises the **window** whose title has a segment equal to the session's project name (else contains it), through the Accessibility API, then activates the app. On activation, a focused window matching a session's project name marks that session read at once (window precision); otherwise the 2 s app-level rule applies.
- AC2: The Accessibility permission is requested once, on first use. Without it, everything falls back to app level silently.
- AC3: Ghostty and Warp stay at app level (click activates the app; reading uses the 2 s dwell).
- AC4: JetBrains IDEs (`com.jetbrains.` bundle-ID family, `05`) get the same window-level click and read behaviour as AC1.
- AC5: The project name is matched per family: JetBrains titles are `project – file`, so the **first** segment is the project; VS Code drops the last segment (the app name). Segments split on ` — `, ` – ` and ` - `.
- AC6: State tracking already works in any IDE terminal (hooks do not depend on the terminal); only focus precision is limited to the window.

## REQ-18 New session
Start a new Claude Code session from the expanded panel. A "+ New" footer button opens a menu of up to 5 recent project directories (`cwd`s seen, most recent first, `recentProjects` in config.json) plus "Choose Folder…". The directory opens in a new window of the preferred terminal (Terminal.app or iTerm2, from the most recent session, else Terminal.app) running `claude`. It quotes the path safely for shell and AppleScript and never edits Claude Code settings.
- AC1: The new session appears in the panel within a few seconds (through its hooks), in the chosen directory.
- AC2: A path with spaces, quotes or `$` opens correctly and runs nothing but `cd <dir> && claude`.

## REQ-21 Settings tabs (1.1.0)
Settings becomes a window with three toolbar tabs: **General**, **Pet** and **Advanced** (`06` "Settings window"). It stays plain AppKit: an `NSTabViewController` with the `.toolbar` tab style and SF Symbols icons. Claude Code is the only agent, so there is no Agents tab.
- AC1: **General** holds the first-run welcome line, the Claude Code hooks row (Install / Uninstall), "Approve permissions from the notch", Mini mode, the focus-read mode, Sound cues, Do Not Disturb (REQ-23) and Launch at login. Every 1.0 control keeps its config key and behaviour (REQ-05 AC6, REQ-09 AC4 / AC5, REQ-12 AC4, REQ-16 AC4).
- AC2: First run opens **General** with the welcome, and Install is the default button (REQ-09 AC5).
- AC3: **Pet** holds a live preview (`PetView` at 3× notch size, with a pose picker that cycles the nine poses) and the Style popup, Roundy / Sharpy (REQ-06 AC2). The preview pauses (`setPaused`) while the window is not key, and it is released with the window.
- AC4: **Advanced** holds only the port (read-only), the app version (`CFBundleShortVersionString`) and a link to the GitHub repository (https://github.com/krzysztof-wojtowicz/clawd-island).
- AC5: The window always opens on **General** and has one fixed size for every tab (the largest tab's), so switching tabs never resizes it. It is built when opened and released on close, and its memory is measured with `perf-suite.sh` against the Settings exception (`08` "Known limits"; 1.1.0 accepts 66 MB open and 61 MB after close).
- AC6: Control text is JetBrains Mono (REQ-14); the window title and toolbar tab labels are AppKit system text.

## REQ-23 Do Not Disturb (1.1.0)
A user toggle that mutes the pet's interruptions: right-click menu "Do Not Disturb" and a General checkbox, `dnd` in config, default off.
- AC1: While DND is on, there is no pop-out (REQ-05) and no sound (REQ-12). State, counters and the panel still update; the counter still turns red.
- AC2: When DND is turned off while a `needsInput` is pending, the pet pops out once. The pop-out is held like any `needsInput` pop-out (REQ-05 AC2), and an unread `done` does the same. Turning DND on retracts a pop-out at once.
- AC3: Screen-sharing or Focus-mode detection is added only if an event-driven public API exists. Otherwise it is dropped (`08` rule 1). There is no new repeating timer. **Dropped (WP-45):** no public API posts screen-sharing changes (`CGSessionCopyCurrentDictionary` must be polled), and `INFocusStatusCenter` needs the Communication Notifications entitlement, a provisioning profile and user authorization.

## REQ-24 Poke (1.1.0)
A click on the pet (not on the HUD) plays a one-shot "poke": a 0.6 s squash and blink as a Core Animation group (`07` "Poke"). About 1 in 4 pokes, chosen at random, also shows a small red heart floating up. Written from scratch.
- AC1: No sound and no state change. A poke does not mark a session read and never opens the panel.
- AC2: The click never takes keyboard focus and does not deactivate the frontmost app (REQ-02 AC2).
- AC3: Under Reduce Motion a poke is a blink only.

## REQ-26 Context and cost per session (1.1.0)
Each session row shows the session's context use and cost at its right edge, for example `ctx 64% · $1.20`, from the Claude Code statusline payload (`05` "Context and cost").
- AC1: The values come from the statusline fields `context_window.used_percentage` and `cost.total_cost_usd`, attached to the session named by the payload's `session_id`. The global `rate_limits` usage handling (REQ-04, ADR-0004) is unchanged.
- AC2: A part is omitted when its field is absent or null (context is null early in a session); with both absent, nothing is shown. The project name truncates before the stats do (REQ-14 AC3).
- AC3: Claude Code only, and never estimated or fabricated. The cost is Claude Code's own estimate at list price and resets on `/clear`.
