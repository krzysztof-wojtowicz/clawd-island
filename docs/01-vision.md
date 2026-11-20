# 01 — Vision

A tiny, always-visible companion for Claude Code that lives in the notch.

**What it does:** an orange, rounded, Clawd-inspired creature sits just to the right of the MacBook notch, in one compact wing together with its session counter and HP bar. On an external monitor without a notch, it sits beside a virtual notch at the top centre of the main display. At a glance it tells you:

- **What Claude is doing.** Its pose and animation show this: sleeping, thinking, using tools (hammering), talking, done, or needs-you.
- **How many sessions** are running, and, by the colour of the counter, whether any of them needs you.
- **How much of the current 5-hour usage window is left**, drawn as a game-style HP bar.

When a session finishes or asks for input, the pet pops out of the notch so you notice, even in a full-screen app or on another Space.

**Principles**
- *Glanceable, not noisy.* Its default footprint is close to the notch, and it grows only when something changes or when you hover.
- *Featherweight.* It is event-driven, with no polling and no runtime dependencies, and the operating system's compositor draws the animations. It should be invisible in Activity Monitor.
- *Fully owned.* The code is written from scratch, with only native Apple frameworks and no third-party code.
- *Safe integration.* It never slows Claude Code down and never touches credentials. Install and uninstall are clean.

**Non-goals (v1):** approving permissions or starting new sessions from the notch (both planned for v2), weekly usage, Windows and Linux, multiple pets, themes, and analytics.

**Inspiration:** `rullerzhou-afk/clawd-on-desk` (concept only; none of its code is used). The Clawd character belongs to Anthropic. This is a private fan project and is not for commercial distribution.
