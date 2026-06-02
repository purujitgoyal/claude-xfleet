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
/plugin marketplace add purujitgoyal/claude-xfleet
/plugin install xfleet
```

See [INSTALL.md](INSTALL.md) for full install steps and prerequisites.

Then initialize a coordination root (one-time, idempotent):

```
bash <plugin-root>/tools/xfleet/install/setup-coordination-root.sh [<coordination-root-path>]
```

This creates the `.xfleet/` tree, adds it to `.gitignore`, verifies Redis is reachable, resolves a Python interpreter with the required libraries, persists config to `~/.config/xfleet/config.json`, and grants the path-scoped Claude Code permissions. See [SETUP.md](SETUP.md) for full details.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `XFLEET_REDIS_URL` | `redis://127.0.0.1:6379` | Redis instance for message transport |
| `XFLEET_COORDINATION_ROOT` | (required) | Path to the `.xfleet/` coordination tree |
| `XFLEET_PYTHON` | `python3` | Python interpreter with jsonschema installed |

## Design Rationale

The locked design decisions (clusters 4a–4o, 5, A1–A3; findings F-1…F-61) are recorded in [`docs/design/2026-04-20-xfleet-shakedown-findings.md`](docs/design/2026-04-20-xfleet-shakedown-findings.md).

## Versioning

`MAJOR.MINOR.PATCH`. Bump `MAJOR` on breaking schema or CLI changes; `MINOR` on additive features; `PATCH` on fixes.
