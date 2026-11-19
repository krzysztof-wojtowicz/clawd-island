# ClawdNotch

A tiny Clawd-inspired pet that lives in your MacBook notch and mirrors what Claude Code is doing:

- **States:** sleeping, thinking, talking, done, and needs-you.
- **Counters:** active sessions and sessions needing attention.
- **HP bar:** your remaining 5-hour usage window.

It is native Swift, has no dependencies, and is built to be featherweight.

> Status: **planning / docs**. No code yet. See `docs/09-roadmap.md`.

## Docs
| | |
|---|---|
| [01 Vision](docs/01-vision.md) | what and why |
| [02 Requirements](docs/02-requirements.md) | REQ-xx with acceptance criteria |
| [03 Architecture](docs/03-architecture.md) | targets, types, data flow |
| [04 State machine](docs/04-state-machine.md) | hook event → pet state |
| [05 Claude Code integration](docs/05-claude-code-integration.md) | hooks, bridge, statusline, installer |
| [06 Window & notch](docs/06-window-and-notch.md) | NSPanel, geometry, hide mode |
| [07 Pet design](docs/07-pet-design.md) | tokens, anatomy, animations |
| [08 Performance](docs/08-performance.md) | budget and rules |
| [09 Roadmap](docs/09-roadmap.md) | work packages |
| [10 Code style](docs/10-code-style.md) | clean code and comments |
| [ADRs](docs/adr/) | key decisions |

## Build (after WP-0)
Requires macOS 14+ and Swift 6 (the Command Line Tools are enough).
```bash
swift build && scripts/test.sh
scripts/run.sh
```

## Working with agents
See [CLAUDE.md](CLAUDE.md). Ask Claude Code to "continue the roadmap", which uses the `orchestrate-wp` skill.

---
Unofficial fan project. Clawd is Anthropic's mascot. Not affiliated with Anthropic.
