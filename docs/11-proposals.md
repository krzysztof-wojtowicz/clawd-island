# 11 — Proposals after 1.0.0

**Status:** proposed. Nothing here is implemented or accepted. When a proposal is accepted, its draft REQ moves into `02`, its ADR status becomes `accepted`, and the work packages in `09` go from `proposed` to `todo`. Draft requirements are numbered from **REQ-19**. Work packages start at **WP-37**, because WP-36 (pet styles Classic / Sharp / Cute) is pending on the `pet-variants` branch.

Every proposal must keep the CLAUDE.md invariants and the `08` budget. Each section says how it does.

| # | Proposal | Draft REQ | ADR | WPs |
|---|---|---|---|---|
| P1 | Pet customization: original species, colour, accessory, name | REQ-19, REQ-20 | ADR-0010 | WP-43, WP-44 |
| P2 | Settings window redesign (tabs, live preview) | REQ-21 | — | WP-42 |
| P3 | Other agents: Codex CLI, Gemini / Antigravity CLI, Junie CLI | REQ-22 | ADR-0009 | WP-37 … WP-41 |
| P4 | Smaller ideas: Do Not Disturb, poke, hotkey, context %, sound choice | REQ-23 … REQ-25 | — | WP-45 … WP-49 |

---

## P1 Pet customization

**Problem.** There is one pet. WP-36 adds styles, but they change only corner radii and the face. Users want to make the island feel their own. The vision rules out "themes" and "multiple pets". This proposal keeps **one pet on screen** and lets the user choose its species and dress.

### P1a Original species (draft REQ-19)
Every species is an **original design** made for this project (ADR-0010). No third-party mascots: Kodee, Ferris, the Go Gopher, Duke and Tux are all out.

| Species | Idea | Rig notes (unit box 32 × 24, `07`) |
|---|---|---|
| **Clawd** (default) | today's pet | unchanged |
| **Byte** | a round beetle or ladybug with a split shell and two antennae | body = shell (an ellipse with a centre seam); 6 legs (3 per side; the extra pair reuses the leg role); antennae bob with `thinking` |
| **Nib** | a boxy little robot with an antenna LED | body radius 1; eyes are rounded visor slits; the antenna LED is a 1 u circle that pulses in `usingTools` and `juggling` (opacity animation only) |
| **Wisp** | a small ghost | no legs (the leg layers are hidden); a wavy hem path on the body; it floats with the existing idle sway at 2× amplitude |
| **Mochi** | a soft blob or slime | body is a squircle with a flat bottom; legs are hidden; the `talking` bounce becomes a squash-and-stretch (scale y / x) |

- AC1: Settings → Pet offers a **Species** picker. `petSpecies` in config, default `clawd`; an unknown value falls back to `clawd`. Changes apply at once, without a restart, using the same live rig swap as WP-36.
- AC2: Every species implements all nine poses and every accessory (hammer, broom, balls, bubbles, "!" badge, Zzz), at notch size, and passes REQ-03 AC1 (distinguishable at a glance). Mini mode (REQ-05) and Reduce Motion work for every species.
- AC3: Vector only, built from `CAShapeLayer`s, with Core Animation only (ADR-0003, REQ-06 AC1). `--render-poses <dir> --pet-species <s>` renders the pose GIFs for each species.
- AC4: The app icon stays Clawd.

**Design.** ADR-0010 defines a **rig contract**: each species supplies the same named layer roles (`body`, `eyeL/R`, `armL/R`, `legs[]`, `accessoryAnchor`, `badgeAnchor`, `hatAnchor`) with frames and pivots. A role that a species lacks is an empty, hidden layer. `PoseRenderer` and the pose animations address roles, never a species, so a new pose (the `add-pet-state` skill) works for every species automatically. This is the WP-36 `PetRig` per-style builder taken one step further: one builder per species, and styles stay a Clawd-only option.

**Perf.** The rig is a few more `CAShapeLayer`s at most, built once per change. There is no runtime cost (`08` rules 1–2).

**Open questions.** Does Sharp / Cute apply to every species, or only to Clawd? Proposed: only to Clawd, and the style picker is hidden for other species. Should each species get its own idle tic (Byte's antenna twitch, Nib's LED blink)? Proposed: yes, as one extra repeating animation on the idle layer.

### P1b Colour, accessory, name (draft REQ-20)
- **Body colour.** Presets (Clawd orange `#D97757`, Ink, Mint, Lilac, Sky, Sand) plus "Custom…" through an `NSColorWell`. The shade (`clawd.bodyShade`) is derived by darkening the colour by about 12 %. Badge colours (`badge.*`, `hp.*`) never change, so the urgency colours of REQ-04 still mean the same. The orange "done" counter and the hover glow keep `clawd.body` as their token, so they follow the pet colour.
- **Accessory.** One slot: none, beanie, headphones, round glasses, party hat, or bow. Each is a small layer group on `hatAnchor` (or the eye group, for glasses), so it moves with the pose. Accessories are hidden in mini mode when they would poke out of the notch.
- **Name.** Default "Clawd". It is shown in the panel footer (`Clawd · WK 81% · HP 63%`) and in the pet tooltip. At most 12 characters.
- AC1: `petColor` (hex), `petAccessory` and `petName` in config, with lenient decoding (a bad value gives the default) and `AppConfigTests` round-trips.
- AC2: The colour contrast check: eyes stay readable. A preset or custom colour whose luminance is too close to `clawd.eye` switches the eyes to white.
- AC3: The Settings preview (P2) shows changes live; the island updates when the control changes.

---

## P2 Settings window redesign (draft REQ-21)

**Problem.** Settings is a single column of controls (`06` "Settings window"). P1 and P3 add a dozen more controls and need a pet preview. A flat list would turn into a wall.

**Design.** It stays plain AppKit (no SwiftUI, `08` rule 7). One `NSWindow` with an `NSTabView` in toolbar style (`NSTabViewController` with `.toolbar` tab style, the native macOS preferences look). It is built when opened and released on close, as today.

| Tab | Contents |
|---|---|
| **General** | first-run welcome line; Launch at login; Mini mode; Sound cues (and the per-cue sound, P4); Do Not Disturb (P4); focus-read mode |
| **Pet** | a live **preview** (`PetView` at 3× notch size, with a pose picker that cycles the nine poses); Species; Style (Clawd only); Colour; Accessory; Name |
| **Agents** | one row per agent: icon, name, "Installed / Not installed / Not found" (config dir missing), and Install / Uninstall; "Approve permissions from the notch" with a per-agent note when an agent cannot do it (Gemini) |
| **Advanced** | port (read-only) and token status; "Open config folder"; "Reset to defaults"; "Send test events" (runs the `simulate.sh` demo through the in-app store, debug-like but safe); version and links (GitHub, licence, third-party notices) |

- AC1: Every 1.0 control is still there, with the same config key and behaviour (REQ-05 AC6, REQ-09 AC4 / AC5, REQ-12 AC4, REQ-16 AC4).
- AC2: First run opens the **Agents** tab with the welcome, and Install for Claude Code is the default button (REQ-09 AC5 moves there).
- AC3: The window remembers the last tab during a run, not across launches (no new config key).
- AC4: The preview pet pauses (`setPaused`) when the window is not key, and it is released with the window. RSS with the window open stays within the existing Settings exception (`08` "Known limits": 60 MB open, 55 MB after close), measured with `perf-suite.sh --open-settings`.
- AC5: Every text is JetBrains Mono (REQ-14).

**Open question.** Should the tab bar use SF Symbols (`NSImage(systemSymbolName:)`)? Proposed: yes. They are system assets, not bundled bitmaps, so REQ-06 AC1 is not affected (that AC is about the pet).

---

## P3 Other agents (draft REQ-22)

**Problem.** Many people run Claude Code next to other terminal agents. Today the pet shows only Claude Code. The three agents picked first all have hook systems close to Claude Code's (researched 2026-11-23; re-verify field names when each WP starts, like `05` does for Claude Code):

| Agent | User hook config | Hook types | Events we'd use | Permission from the notch | Usage / HP |
|---|---|---|---|---|---|
| **Codex CLI** | `~/.codex/hooks.json` (also inline `[hooks]` in `~/.codex/config.toml`; project hooks only when the project is trusted) | `command`, `mcp_tool`; **no http** | `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `PreCompact`, `SubagentStart`, `SubagentStop`, `Stop` | yes: the same `hookSpecificOutput.decision.behavior` JSON as Claude Code; **no** `updatedPermissions` (it fails closed), so no Always allow | none (only per-request `token_usage`) |
| **Gemini CLI**, and its successor **Antigravity CLI** (Gemini CLI was replaced on 2026-06-18) | Gemini: `~/.gemini/settings.json` → `hooks`; Antigravity: a `hooks.json` under `~/.gemini/` (exact path to verify) | `command` only; `timeout` in **milliseconds** | `SessionStart`, `SessionEnd`, `BeforeAgent`, `AfterAgent`, `BeforeTool`, `AfterTool`, `Notification`, `PreCompress` | no: `Notification` (ToolPermission) is observe-only; `BeforeTool` could deny but never allow, so we only show `needsInput` | none |
| **Junie CLI** | `~/.junie/config.json` → `hooks` (project hooks are ignored by default) | `command` only (`sh -c`) | `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`, `StopFailure`, `PermissionRequest` | yes, but **by exit code**: 0 = approve, 2 or `"decision":"deny"` = deny, any other non-zero = show the normal dialog | none (`StopFailure` `error: rate_limit` only) |

### Design (ADR-0009)
- **Transport.** None of them supports http hooks, so each event is a command hook: `clawd-bridge hook <agent> <event>`. The bridge reads stdin, maps the payload to the existing `/hook` JSON shape (`hook_event_name` in Claude Code naming, `session_id`, `cwd`, `tool_name`, the tool-input summary) and adds `"agent": "<agent>"`. It POSTs with a 300 ms timeout and exits. The process costs a few ms per event (the bridge's < 20 ms start budget, `08`), which is fine for these agents but is why Claude Code keeps http hooks.
- **Event mapping (normalised name ← agent event).** `UserPromptSubmit` ← Codex / Junie `UserPromptSubmit`, Gemini `BeforeAgent`; `PreToolUse` / `PostToolUse` ← `PreToolUse` / `PostToolUse` or Gemini `BeforeTool` / `AfterTool`; `Stop` ← `Stop` or Gemini `AfterAgent`; `StopFailure` ← Junie `StopFailure`; `PreCompact` ← Codex `PreCompact`, Gemini `PreCompress`; `PermissionRequest` ← Codex / Junie `PermissionRequest`; `Notification` (permission) ← Gemini `Notification`; `SubagentStart` / `SubagentStop` ← Codex. `SessionStart` goes through `/session-meta` with the process walk, as for Claude Code. Thinking, talking, compacting and juggling then fall out of the existing state machine (`04`) with no new states.
- **Session identity.** `Session.agent` (`claude` default, `codex`, `gemini`, `junie`) is a new Core field (included in `==`). The store keys sessions by `agent + session_id`, so ids from different agents cannot collide.
- **Process walk.** The bridge's agent-process match (today: the path ends in `/claude` or contains `/claude/versions/`, `05`) becomes a per-agent list (`codex`, `gemini` / `agy`, `junie`; to verify per install method: Homebrew, npm, native). Terminal, tty and pid then work as today, so focus, read tracking (REQ-10) and editor window focus (REQ-17) need no change.
- **Permissions.** Codex: the bridge holds the request like the app holds Claude Code's (ADR-0006 exception). It waits for the app's decision (at most 110 s; the hook's `timeout` is 120). The terminal prompt runs in parallel, as with Claude Code. That must be **verified** for each agent before enabling. If an agent blocks its own dialog while the hook runs, notch permissions stay off for it. Junie: **"no decision" must exit 1, never 0**, because exit 0 auto-approves. Gemini: no cards; the session simply shows `needsInput`.
- **Installers.** One installer per agent, each following `05` "Installer" rules: backup next to the file, idempotent, fully reversible, entries recognised by a command containing `clawd-bridge`, abort without writing on invalid JSON. Codex `config.toml` is **not** edited (we write `hooks.json` only), so we never need a TOML writer. Pure merge logic lives in Core (`HookSettings`-like), and file IO is injected for tests, as today. The CLAUDE.md invariant "Editing `~/.claude/settings.json` is done only by the installer" is extended to every agent config file.
- **UI.** The panel row gets a 2-letter agent tag before the project name (`CC`, `CX`, `GM`, `JN`) in `badge.empty` grey; it is hidden while every session is Claude Code. "+ New" (REQ-18) gets one submenu per installed agent (`cd <dir> && codex` and so on, with the same quoting rules).
- **HP / WK.** They stay Claude Code only. They come from the statusline `rate_limits` (ADR-0004), and no other agent offers equivalent data. They are never estimated. The footer stays as today.

### Draft REQ-22 acceptance criteria
- AC1: Settings → Agents installs and uninstalls hooks for Codex CLI, Gemini / Antigravity CLI and Junie CLI, each with a backup, idempotently and reversibly; round-trip tests leave each file semantically equal.
- AC2: A session from any of them shows in the panel with its tag, counts in the counters, and drives the aggregate pet state with the same priority rules (REQ-03 AC3).
- AC3: Hooks never slow the agent: with the app not running, each bridge call exits within 300 ms with "no decision" semantics (Junie: exit 1 on `PermissionRequest`, 0 elsewhere).
- AC4: Notch permission cards work for Codex and Junie (Allow / Deny; no Always allow); Gemini sessions show `needsInput` only.
- AC5: The HP bar and WK are unchanged and still come only from Claude Code's statusline.
- AC6: `scripts/simulate.sh` gets `--agent <name>` to send the mapped events, for testing without the real CLIs.

**Out of scope (later):** Copilot CLI, Cursor, opencode, Qwen Code, Kiro (clawd-on-desk supports several of them). With ADR-0009's adapter in place, each is one mapping table plus one installer.

---

## P4 Smaller ideas

### P4a Do Not Disturb (draft REQ-23)
Mute pop-outs and sounds while a macOS Focus mode is on, or while the screen is being shared or recorded. The state still changes, and the counter still turns red.
- Detection is event-driven only: the `com.apple.donotdisturb` / Focus state is not public. Use `NSWorkspace` screen-sharing notifications and the user's own toggle (right-click menu "Do Not Disturb", `dnd` in config). Plain Focus detection is an open question; if it needs polling, it is dropped (`08` rule 1).
- AC: no pop-out and no sound while DND is on; `needsInput` still pops once when DND turns off.

### P4b Poke reaction (draft REQ-24)
A click on the pet (not on the HUD) plays a one-shot "boop": a squash, a blink and a small heart or spark, 0.6 s, as a Core Animation group. It never changes state, and it does not count as reading a session. Reduce Motion gives a blink only. clawd-on-desk has a similar interaction; ours is written from scratch.

### P4c Global hotkey (draft REQ-25)
An optional shortcut (default none; set in Settings → General) toggles the expanded panel. A second optional shortcut presses **Allow** on the top permission card. It is registered with Carbon `RegisterEventHotKey` (no event tap, no polling, no Accessibility permission). The app still never takes keyboard focus except for Settings (REQ-02 AC2).

### P4d Context and cost per session
The Claude Code statusline JSON carries per-session cost (`cost.total_cost_usd`) and context-window data. Show `ctx 64% · $1.20` on the session row tooltip. The field names must be verified against the current statusline docs first (`05`). Claude Code only; nothing is fabricated for other agents.

### P4e Sound choice
A per-cue system sound picker (needsInput / done) in Settings → General, from `/System/Library/Sounds`, played through `afplay` as today (REQ-12 AC4).

### Considered and rejected
- **Eyes that follow the cursor** (clawd-on-desk has it): needs a global mouse monitor that wakes the app on every mouse move, which breaks `08` rule 1.
- **Usage history or analytics:** a vision non-goal, and it would need storage per event (`08` rule 5).
- **Third-party mascots** (Kodee, Ferris, Gopher, Duke, Tux, Octocat): trademark and attribution burden. Original species instead (ADR-0010).
- **Several pets at once, one per agent:** a vision non-goal, and the island width (REQ-04 AC4) has no room. The agent tag in the panel covers it.
