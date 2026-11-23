# 01 — Vision

A tiny, always-visible companion for Claude Code that lives in the notch.

**What it does:** an orange, rounded, Clawd-inspired creature sits just to the right of the MacBook notch, in a small black island together with a session counter and an HP bar. On a display without a notch it uses a virtual notch at the top centre of the main display. At a glance it tells you:

- **What Claude is doing**, by its pose: sleeping, idle, thinking, using tools, talking, compacting, juggling subagents, done, or needs-you.
- **How many sessions** are running, and, by the counter's colour, whether any of them needs you.
- **How much of the 5-hour usage window is left** (HP bar) and, in the expanded panel, the weekly limit (WK).

When a session finishes or asks for input, the pet pops out so you notice, even over a full-screen app or on another Space. Hover the island to see every session, answer permission prompts, jump to a session's terminal or start a new one.

**Principles**
- *Glanceable, not noisy.* The default footprint hugs the notch; it grows only when something changes or when you hover.
- *Featherweight.* Event-driven, no polling, no dependencies; the window server draws the animations (`08`).
- *Fully owned.* Written from scratch with native Apple frameworks only.
- *Safe integration.* Never slows Claude Code down, never touches credentials; install and uninstall are clean and reversible.

**Non-goals:** Windows and Linux, Intel Macs, multiple pets, themes, analytics, network calls from the app (no update check), a weekly reset countdown.

**Distribution:** public on GitHub under MIT, as signed (self-signed, not notarized) release zips for Apple silicon (ADR-0008).

**Inspiration:** `rullerzhou-afk/clawd-on-desk` (concept only; none of its code is used). The Clawd character belongs to Anthropic; this is an unofficial fan project.
