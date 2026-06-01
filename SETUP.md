# xfleet Coordination Root Setup

One-time operator guide for initializing an xfleet coordination root and satisfying all runtime prerequisites. Run this once per coordination repo; it is idempotent.

## Quick Start

```bash
bash <plugin-root>/tools/xfleet/install/setup-coordination-root.sh [<target-coordination-root-path>]
```

`<plugin-root>` is the local checkout of this plugin (e.g. `~/.claude/plugins/claude-xfleet`). If omitted, `<target-coordination-root-path>` defaults to `$PWD/.xfleet`.

The script is safe to re-run: it will not duplicate directories, gitignore entries, config keys, permissions, or a bootstrap venv.

## What the Script Does

1. Resolves the coordination root to an absolute path; creates it if missing.
2. Creates the 6 required subdirectories under the root: `state`, `concerns`, `resolutions`, `directives`, `tasks`, `messages`.
3. Adds `.xfleet/` to the parent directory's `.gitignore` if not already present.
4. Persists `coordination_root` to `~/.config/xfleet/config.json` (merged, atomic write).
5. Verifies Redis is reachable (aborts with an actionable message if not).
6. Resolves a working Python interpreter with `jsonschema`, `pydantic`, and `deepdiff`; persists it as `python_bin` in `~/.config/xfleet/config.json`.
7. Grants 3 path-scoped Claude Code permissions in `~/.claude/settings.local.json`.

## Permissions

The plugin manifest grants only `Bash(xfleet *)` — the broad shell permission for invoking subcommands. The setup script additionally writes three exact literal-path rules into `~/.claude/settings.local.json`, scoped to your resolved coordination root (not a broad glob):

| Rule | Purpose |
|---|---|
| `Write(//<coordination-root>/**)` | Write state files, concerns, resolutions, etc. |
| `Read(//<coordination-root>/**)` | Read state and coordination artifacts |
| `Read(//private/tmp/claude-*/**/tasks/*.output)` | Read subagent task-output temp files |

Because these rules contain your actual resolved path, they are specific to this root. **Re-run the setup script if you move the coordination root.**

## Prerequisites

### Redis

Redis must be running and reachable before setup and at plugin runtime.

- Default URL: `redis://127.0.0.1:6379`
- Override: set `XFLEET_REDIS_URL` before running setup (and in your shell sessions).
- The setup script verifies connectivity with `redis-cli ... ping` and aborts on failure.
- Install: `brew install redis && redis-server`
- Verify manually: `redis-cli -u "${XFLEET_REDIS_URL:-redis://127.0.0.1:6379}" ping` → should return `PONG`.

### Python + jsonschema + pydantic + deepdiff

Python 3 with `jsonschema>=4`, `pydantic`, and `deepdiff` is required. The setup script probes candidates in this order and uses the first that passes `import jsonschema, pydantic, deepdiff`:

1. `$XFLEET_PYTHON` (if set in the environment)
2. Existing `python_bin` value in `~/.config/xfleet/config.json` (if present and working)
3. System `python3`
4. `~/.config/xfleet/venv/bin/python`

If no candidate works and `uv` is on PATH, setup bootstraps a virtual environment at `~/.config/xfleet/venv/` and installs `jsonschema pydantic deepdiff` there. If `uv` is not available, setup aborts with instructions:

- Option A: `brew install uv` then re-run.
- Option B: `pip install jsonschema pydantic deepdiff` into any Python 3, then `export XFLEET_PYTHON=/path/to/that/python` and re-run.

`pydantic` and `deepdiff` are used by `xfleet drift-check`: pydantic executes the canonical Pydantic model block extracted from `contracts.md` (calling `model_json_schema()`), and deepdiff performs the JSON-Schema structural diff.

The resolved path is written to `python_bin` in `~/.config/xfleet/config.json`. The SessionStart hook reads this value and exports it as `$XFLEET_PYTHON` so all subcommands pick it up automatically.

**jsonschema CLI note**: the plugin uses `validate-state.py` (jsonschema Python API), not `python -m jsonschema`. The `python -m jsonschema` CLI is deprecated in recent jsonschema releases; the wrapper script calls the library directly.

## $XFLEET_COORDINATION_ROOT Resolution

Subcommands resolve the coordination root in this precedence order:

1. `$XFLEET_COORDINATION_ROOT` environment variable (highest priority)
2. `coordination_root` key in `~/.config/xfleet/config.json`
3. Ancestor walk from `$PWD` looking for a `.xfleet-marker` file (fallback)

The setup script writes your root to `config.json` (step 2). Export `XFLEET_COORDINATION_ROOT` in your shell profile if you prefer the env-var approach.

## No Auto-Configuration

The plugin does not auto-configure any repo. The operator declares the coordination root exactly once via this script. Until setup is run (or `$XFLEET_COORDINATION_ROOT` is set), no xfleet subcommand will function.

## Verifying Setup

After running the script, confirm everything is wired up:

```bash
# Redis still reachable
redis-cli -u "${XFLEET_REDIS_URL:-redis://127.0.0.1:6379}" ping

# Python + jsonschema + pydantic + deepdiff
"$(jq -r .python_bin ~/.config/xfleet/config.json)" -c "import jsonschema, pydantic, deepdiff; print(jsonschema.__version__)"

# Coordination root exists
ls "$(jq -r .coordination_root ~/.config/xfleet/config.json)"

# Plugin responds
xfleet status
```
