# Changelog

## 1.1.0

Renamed from ClawdNotch to ClawdIsland (ADR-0009). After updating, delete the old ClawdNotch app and click **Install Hooks** in Settings once (old hook entries are replaced). Your config, token and saved statusline move over automatically at first launch.

- Mini mode: Clawd tucks under the notch and pops out on state changes (replaces hide mode).
- Waving paw in done and needs-input; two-pair legs.
- Music headphones and now-playing removed.
- Hooks install/uninstall and Launch at login live in Settings only.
- Bundle id `dev.clawdisland.app`, signing identity "ClawdIsland Dev".

## 1.0.0

First release.

- Notch island with a session counter, an HP bar (5-hour usage) and the pet; a virtual notch on Macs without one.
- Usage read only from the Claude Code statusline `rate_limits` payload; HP and WK.
- Session panel on hover, focus on click (exact tab for Terminal.app and iTerm2, window for VS Code and JetBrains IDEs).
- Permission requests answered from the notch; "+ New" session launcher.
- Hide mode with a 3 s pop-out, sound cues, music headphones.
- One-click, reversible hook install and uninstall.
- JetBrains Mono bundled (used when not installed); app icon; version keys.
- `scripts/make-signing-cert.sh`, `install.sh`, `uninstall.sh` and `package.sh`; signing with a local certificate (ADR-0008).
