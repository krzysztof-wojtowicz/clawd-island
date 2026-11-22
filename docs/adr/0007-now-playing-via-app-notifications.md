# ADR-0007 — Now playing via the music apps' own notifications

**Status:** Superseded — feature removed in v5 (WP-25). Kept for history.

**Context:** The pet should wear headphones while music plays, and keep title, artist and album for later features. Constraints: no login, no private API, no polling, and the CPU/RSS budget (`docs/08`). The user listens through Apple Music and Spotify, including over AirPlay.

**Decision:** `NowPlayingWatcher` observes `DistributedNotificationCenter`: `com.apple.Music.playerInfo` and `com.spotify.client.PlaybackStateChanged`. Keys: `Player State` (Playing / Paused / Stopped), `Name`, `Artist`, `Album`. Both apps post these themselves on every change, so the watcher is purely event-driven and needs no permission.

**Consequences:**
- Only Apple Music and Spotify are supported; other players (browser, VLC) are not detected.
- Known limit: the apps post only on change, so after launching ClawdIsland the headphones appear at the next play, pause or track change.
- The notification payloads are not a documented API; unknown or missing keys must degrade to "not playing".

**Rejected:**
- **MediaRemote (system now-playing):** restricted to Apple-signed processes since macOS 15.4; the `/usr/bin/perl` workaround is fragile and could break in any update.
- **CoreAudio output activity:** gives no titles and also fires for calls and videos.
- **Spotify Web API:** needs a login and tokens, against the no-login constraint, and requires polling.
