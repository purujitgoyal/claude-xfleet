# Installing xfleet

xfleet is a Claude Code plugin for multi-repo coordination via Redis Streams.

## Install

```
/plugin marketplace add purujitgoyal/claude-xfleet
/plugin install xfleet
```

## Runtime Prerequisites

Before using xfleet subcommands, ensure these are available in your environment:

| Variable | Default | Requirement |
|---|---|---|
| `XFLEET_REDIS_URL` | `redis://127.0.0.1:6379` | Redis instance for message transport |
| `XFLEET_COORDINATION_ROOT` | (required) | Path to the `.xfleet/` coordination tree |
| `XFLEET_PYTHON` | `python3` | Python 3 interpreter with `jsonschema>=4` installed |

**Redis**: Must be reachable at `$XFLEET_REDIS_URL`. Verify with `redis-cli -u "$XFLEET_REDIS_URL" ping`.

**Python + jsonschema**: Used by `validate-state.sh` on every state-mutating subcommand. Install via `pip install jsonschema`.

**Coordination root**: `$XFLEET_COORDINATION_ROOT` must point to the `.xfleet/` directory tree of the repo under coordination. This variable is required — no subcommand will work without it.

For one-time coordination-root initialization and full setup instructions, see `SETUP.md` (provided by Task 31 — not yet shipped). That guide covers `setup-coordination-root.sh`, Redis connectivity checks, and exporting config for session discovery.

## Versioning

`MAJOR.MINOR.PATCH`. Bump `MAJOR` on breaking schema or CLI changes; `MINOR` on additive features; `PATCH` on fixes.

## Local Install Verification (Operator Manual Step)

To verify the install path locally before pushing to GitHub:

```bash
claude --plugin-dir /path/to/claude-xfleet
```

This loads the plugin from the local checkout. Confirm `xfleet` appears in `/plugins` and that `xfleet status` responds without errors.
