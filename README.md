# claude-xfleet

Multi-repo coordination plugin for Claude Code. Orchestrates parallel agent sessions across repositories via Redis Streams — send/listen/ack messages, track concern rounds, and gate phase transitions from a single operator session.

## Purpose

xfleet solves the "N repos, N Claude sessions" problem: when a task spans multiple repos simultaneously, operators need a way to broadcast directives, collect worker status, and advance phases without manual copy-paste across terminal windows. This plugin provides the command surface and transport layer for that coordination.

## Runtime Requirements

- **Redis** — transport layer for inter-session messaging. Default URL: `redis://127.0.0.1:6379`. Override via `$XFLEET_REDIS_URL`.
- **Python 3 + jsonschema** (>=4) — used by `validate-state.sh` on every state-mutating subcommand to enforce schema correctness. Override interpreter via `$XFLEET_PYTHON`.
- **Coordination root** — a `.xfleet/` directory tree in the repo under coordination. Declare its path via `$XFLEET_COORDINATION_ROOT`. This env var must be set for any plugin subcommand to work.

## Install

```
claude plugin install xfleet@<marketplace>
```

Then run the setup script to verify connectivity and initialize the coordination root:

```
xfleet-setup.sh <path-to-coordination-root>
```

> **Note:** `xfleet-setup.sh` is not yet shipped (created in Task 31 of the F-51 implementation plan). The setup script checks Redis reachability (`redis-cli ping`) and exports `$XFLEET_COORDINATION_ROOT` to `~/.config/xfleet/config.json` for session discovery.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `XFLEET_REDIS_URL` | `redis://127.0.0.1:6379` | Redis instance for message transport |
| `XFLEET_COORDINATION_ROOT` | (required) | Path to the `.xfleet/` coordination tree |
| `XFLEET_PYTHON` | `python3` | Python interpreter with jsonschema installed |

## Design Rationale

Design rationale and architectural decisions are tracked in the project's internal design docs.

## Versioning

`MAJOR.MINOR.PATCH`. Bump `MAJOR` on breaking schema or CLI changes; `MINOR` on additive features; `PATCH` on fixes.
