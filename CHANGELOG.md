# Changelog

## 1.0.0

First public release. Apple silicon, macOS 14+, signed with a self-signed "ClawdIsland" identity (not notarized).

- Notch island with a session counter, an HP bar (5-hour usage) and the pet; a virtual notch on Macs without one.
- Usage read only from the Claude Code statusline `rate_limits` payload (HP and WK); no credentials are touched.
- Clawd in nine Core Animation poses, including a waving paw in done and needs-input, juggling for subagents and sweeping for compaction.
- Session panel on hover; focus on click (exact tab for Terminal.app and iTerm2, window for VS Code and JetBrains IDEs, app for others).
- Permission requests answered from the notch (Deny, Allow, Always allow); "+ New" session launcher.
- Mini mode: Clawd hangs from the notch corner and pops out for 3 s when Claude writes, finishes or needs you.
- Sound cues for needs-input and done.
- Settings: one-click, reversible hook install and uninstall, launch at login, focus-read mode; the first launch opens Settings once with a welcome when the hooks are not installed.
- JetBrains Mono bundled (used when not installed); app icon.
- Scripts to install, uninstall and package; GitHub Actions CI.
