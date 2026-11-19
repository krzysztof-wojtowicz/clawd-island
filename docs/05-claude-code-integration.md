# 05 — Claude Code integration

Verified against Claude Code 2.1.329 docs (hooks, statusline). Re-check field names if Claude Code changes.

## Transports (ADR-0002)
1. **HTTP hooks** (`"type": "http"`). Claude Code POSTs the event JSON directly to the app. No process is spawned per event, so this is the cheapest option.
2. **One command hook on `SessionStart`** (`"async": true`) runs `clawd-bridge hook session-start`. This captures what HTTP hooks cannot provide: the Claude Code PID, the tty, and the terminal app.
3. **The statusLine command** `clawd-bridge statusline` forwards the statusline JSON (which carries `rate_limits`) to the app and prints a status line.

## Hook config written by the installer
The installer recognises its own entries by their URL (`127.0.0.1:<port>/hook`) or by the `clawd-bridge` path. This keeps install idempotent and makes uninstall remove exactly what was added.

```jsonc
{
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "http", "url": "http://127.0.0.1:47474/hook",
                                        "headers": { "X-Clawd-Token": "<token>" }, "timeout": 2 }] }],
    // Same http entry for: SessionStart, PreToolUse, PostToolUse, PostToolBatch, PostToolUseFailure,
    // PermissionRequest, PermissionDenied, Notification, MessageDisplay, SubagentStart, SubagentStop,
    // Stop, StopFailure, PreCompact, SessionEnd
    "SessionStart": [{ "hooks": [
      { "type": "http", "url": "http://127.0.0.1:47474/hook", "headers": { "X-Clawd-Token": "<token>" }, "timeout": 2 },
      { "type": "command", "command": "'/Applications/ClawdNotch.app/Contents/MacOS/clawd-bridge' hook session-start", "async": true }
    ]}]
  },
  "statusLine": { "type": "command", "command": "'/Applications/ClawdNotch.app/Contents/MacOS/clawd-bridge' statusline" }
}
```

### Hard rules
- **The response body must be empty with status 200** for every hook. A JSON body on `PreToolUse` or `PermissionRequest` could be read as a decision (allow, deny, or block). In v1 we never decide anything.
- `timeout: 2` (seconds). If the app is not running, the connection is refused immediately. WP-0 must **verify** that Claude Code treats this as a silent, non-blocking error and does not print anything noisy to the user. If it does, fall back to: http for high-frequency events, and document the tradeoff in ADR-0002.
- Port `47474` is the default and can be changed in the config. If the port is busy, the app shows an error in its menu and does not silently move to another port, because hooks are written with a fixed URL.

## Endpoints (EventServer)
| Method / path | Body | Effect |
|---|---|---|
| `POST /hook` | raw hook JSON | `SessionStore.apply(event)` |
| `POST /session-meta` | `SessionMeta` JSON from the bridge | `SessionStore.apply(meta:)` |
| `POST /statusline` | raw statusline JSON | `UsageModel.update` (reads `rate_limits.five_hour.*` only) |
| anything else | — | 404 |
Every endpoint requires `X-Clawd-Token`. Bodies are limited to 64 KiB, with a 2 s read timeout and `Connection: close`.

## clawd-bridge
Startup must stay under 20 ms. It uses only Foundation and Darwin.

### `hook session-start`
1. Reads the hook JSON from stdin and takes `session_id` and `cwd` from it.
2. Walks the parent process chain (`proc_pidinfo` / `sysctl KERN_PROC_PID`):
   - **CC pid** is the nearest ancestor whose executable name is `claude`. `shortcut: name match, upgrade if CC renames its binary or runs under node`
   - **tty** comes from that process's controlling terminal (`e_tdev` → `devname`).
   - **terminal app** is the nearest ancestor whose executable path is inside a `.app` bundle. The bridge reads `CFBundleIdentifier` from its Info.plist.
   - Env: `TERM_PROGRAM`, `ITERM_SESSION_ID`, `TMUX` (tmux makes tab focus imprecise; fall back to app-level focus).
3. POSTs `SessionMeta` to `/session-meta` with a 300 ms timeout, then exits with code 0. **It always exits 0, even on error.**

### `statusline`
1. Reads stdin fully.
2. Fires a POST of the raw JSON to `/statusline` with a 300 ms timeout, without waiting on the app beyond that.
3. If the config holds an `originalStatusLine` command, the bridge runs it through `/bin/sh -c`, pipes the same stdin, and prints its stdout. Otherwise it prints a minimal line, for example `◆ <model> · HP 63%`.
4. It exits 0.

## Usage / HP (ADR-0004)
- Source: `rate_limits.five_hour.used_percentage` (0–100) and `rate_limits.five_hour.resets_at` (Unix seconds).
- These are present only for Pro and Max subscribers, after the first API response. Each window can be absent. If they are missing, `UsageSnapshot` stays nil and the HP bar is hidden.
- The statusline refreshes on assistant messages, so the data is as fresh as the last active session.
- **Forbidden:** the undocumented OAuth usage endpoint, and any Keychain or credentials access.

## Installer (`HookInstaller`, App/Integration)
- **Install:**
  1. Read `~/.claude/settings.json` (create it if missing).
  2. Write a backup.
  3. Remove any of our old entries, then add the current ones.
  4. If there is a foreign `statusLine`, save it as `originalStatusLine` in our config.
  5. Write atomically, preserving unknown keys.
- **Uninstall:** remove our entries, then restore `originalStatusLine` if one was saved.
- If the JSON is invalid, abort without writing and show an error. Never overwrite a file we failed to parse.
- `JSONSerialization` with sorted keys and pretty printing is acceptable. Comments are not supported, and CC settings are plain JSON.
- Tests: the install and uninstall round-trip leaves the file semantically equal to the original. Install is idempotent (installing twice gives the same result).

## Terminal focus → read (REQ-10)
- `TerminalFocusWatcher` observes `NSWorkspace.didActivateApplicationNotification`.
- **Terminal.app and iTerm2:** run AppleScript to get the selected tab's tty (`tty of selected tab of front window` / `tty of current session of current window`) and mark sessions with a matching `meta.tty` as read. This needs the Automation permission, requested on first use. If it is denied, fall back to app level.
- **Other terminals:** if the app stays frontmost for ≥ 2 s, mark all `done` sessions whose `terminalBundleID` matches as read.
- **Panel click on a session:** activate the terminal app. In Terminal.app or iTerm2, also select the tab with that tty.
- AppleScript runs only on an activation event, never on a timer.
