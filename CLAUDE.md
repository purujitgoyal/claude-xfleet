# CLAUDE.md

Guidance for Claude Code when working in the **xfleet plugin repo** — the plugin's own source, not a live xfleet coordination session.

## What this is

xfleet is a Claude Code plugin for multi-repo coordination over Redis Streams. This repo is the plugin source: a `bin/xfleet` CLI dispatcher, supporting shell tooling, skills, hooks, and the canonical contract docs in `shared/`.

## Companion skills (external)

xfleet references skills it does **not** bundle — `prd-review`, `architect-review`, `capture-decision`, `prepare-handoff`, `resume-handoff`, `code-review`. These live in the separate **holocron** plugin (git repo `claude-holocron`; invoke as `/holocron:<skill>`), which is now their single source of truth — they were formerly loose under `~/.claude/skills/`. Don't vendor copies into this repo; reference them by name and keep the source in holocron.

## Commands

- **Run tests:** `bash tests/run-all.sh` (what CI runs). Direct alternative: `bats tests/ -r`. 400+ bats tests span CLI, subcommands, handlers, hooks, state-validator, docs, manifest, and integration.
- **CLI:** `bin/xfleet <subcommand>` — dispatches to `tools/xfleet/subcommands/<subcommand>.sh`.
- **Init a coordination root:** `bash tools/xfleet/install/setup-coordination-root.sh [<path>]` (idempotent; see SETUP.md).

## Layout

- `bin/xfleet` — dispatcher; routes to `tools/xfleet/subcommands/` (21 subcommands) via `tools/xfleet/lib/subcommand-registry.sh`.
- `tools/xfleet/` — `subcommands/`, `handlers/` (reflexive inbound handlers), `lib/` (shared bash + `validate-state.py`), `hooks/load-grounding.sh`, `check-context.sh`, `validate-state.sh`, `state-schema.json`.
- `shared/` — canonical contracts: `messaging.md` (wire taxonomy), `state-schema.md` (prose) + `state-schema.json` (validator), `worker-config-schema.md`, `design-principles.md`, `cluster-5-templates.md`.
- `skills/` — `worker`, `orchestrator`, five `phase-*`, `finalize-spec`, `finalize-section`, `x-vergence-check`.
- `hooks/hooks.json` — PostToolUse context-check + SessionStart grounding loader.
- `commands/`, `.claude-plugin/` (`plugin.json` + `marketplace.json`), `tests/`.

## Conventions (load-bearing — tests enforce these)

- **State writes** are validated against `tools/xfleet/state-schema.json` by `validate-state.sh` (strict, recursive unknown-key rejection with did-you-mean). The prose `state-schema.md` and the JSON Schema are dual source-of-truth; `check-state-schema-drift.sh` keeps them in sync — update **both** when adding a field.
- **Messaging** uses one subcommand per message type, never a `--type` flag. The `shared/messaging.md` section-(h) table must stay in sync with `subcommand-registry.sh` (tested).
- **Paths** go through `$XFLEET_COORDINATION_ROOT`; never hardcode a workspace path (tested).
- **Permissions:** `plugin.json` ships only `Bash(xfleet *)`. The three path-scoped file permissions are granted at setup time by `setup-coordination-root.sh` (the coordination-root path is dynamic) — do NOT add them to the manifest (tested).
- **Runtime:** Redis (`$XFLEET_REDIS_URL`), Python 3 with `jsonschema` / `pydantic` / `deepdiff` (`$XFLEET_PYTHON`).

## Design rationale

Locked design decisions (clusters 4a–4o, 5, A1–A3; findings F-1…F-61) live in `docs/design/2026-04-20-xfleet-shakedown-findings.md`.

## Gotchas

- Nested Task agents can't dispatch their own subagents — skills that fan out must dispatch from the top-level session.
- Plugin hooks are auto-discovered from `hooks/hooks.json`; there is no `plugin.json` hooks key.
- macOS `sed -i` requires an explicit `''` argument.
