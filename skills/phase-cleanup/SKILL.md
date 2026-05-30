---
name: phase-cleanup
description: >
  Use when entering the cleanup phase of an xfleet multi-repo coordination
  session — removes intermediate coordination artifacts (concerns, resolutions,
  reviews, state files, session-scoped xfleet handoffs), flushes Redis inboxes,
  and deletes round-counter keys. Defaults to a read-only dry-run preview; pass
  `--apply` to execute. Pre-flight guard aborts `--apply` when resolutions exist
  but finalize-spec (repo-spec mode) has not merged them. Does NOT combine or
  merge specs. Trigger phrases: "enter the cleanup phase", "start cleanup",
  "run /xfleet:phase-cleanup".
warn_at: 70
critical_at: 80
review_intensity: standard
context_heavy: []
---

## Protocol

- **Design principles:** see `shared/design-principles.md` — loaded every
  session, every `/clear`+resume.
- **Wire taxonomy:** see `shared/messaging.md` for the subcommand list, sender
  authority, and `--message`/`--message-file` rules. Do not restate it here.

This is the xfleet plugin's **own** cleanup phase skill — not a wrapper around
an external command. It carries real teardown procedure, so it is longer than
the other phase skills. The worker base loop (`skills/worker/SKILL.md`) owns the
always-on loop, context-discipline, and authority rules.

## Metadata

- `warn_at: 70` / `critical_at: 80` — default thresholds (cluster 4f).
- `review_intensity: standard` — cleanup is mechanical teardown (cluster 4a).
- `context_heavy: []` — no write-heavy subtasks; teardown is I/O, not authoring.

## Overview

This is a two-mode skill: **DRY-RUN** (default, read-only preview) and
**--apply** (executes). The pre-flight guard protects against destroying
cross-repo decisions that have not been merged into a final spec —
`--apply --force` bypasses it consciously. Handoff sweep is session-scoped
(prefix `xfleet-` + mtime ≥ session start) so unrelated handoffs are never
touched.

## Arguments

Parse `$ARGUMENTS` for the following flags:

- **(no flags) — DEFAULT: dry-run.** Prints exactly what would be removed, which Redis streams would be flushed, and which handoff files would be swept, but performs no changes. Safe at any time.
- `--apply` — execute for real. Requires the pre-flight safety guard to pass (see below).
- `--force` — bypass the pre-flight safety guard. Only meaningful with `--apply`. The guard exists to prevent losing cross-repo decisions; only force when you've consciously decided the resolutions don't need to be preserved into a final spec.

**Flag interplay:**
- `--apply` alone: real run with guard active.
- `--apply --force`: real run, bypass guard.
- `--force` without `--apply`: error — "use --apply --force, or pass --force alone to see the dry-run preview with guard skipped" (still dry-run).
- Neither flag: dry-run with guard evaluated and shown.

In the prose below, "DRY-RUN" means any invocation without `--apply` (including `--force` alone).

## Entry

The cleanup phase is entered via `xfleet phase --enter cleanup` (cluster 4d:
this triggers prepare-compact + the phase-exit handoff for the *outgoing* phase
before cleanup begins). Then run the Pre-flight Safety Check below before any
deletion.

## Pre-flight Safety Check

Run this check BEFORE any deletion. Its purpose is to prevent destroying
cross-repo decision records that have not yet been merged into a final spec.

**Dry-run interaction:** In DRY-RUN mode, the guard still evaluates and prints its finding (so the human can see whether real cleanup would be blocked), but it never aborts — dry-run is read-only and always safe to complete. Only `--apply` runs enforce abort.

Procedure:

1. Check whether `$XFLEET_COORDINATION_ROOT/resolutions/` contains any `*.md` files.
2. Check whether `$XFLEET_COORDINATION_ROOT/specs/` contains any `*-section.md` files. The
   presence of per-repo section files indicates that finalize-spec (repo-spec
   mode) has NOT been run — a successful finalize removes those section files
   after merging them into the final spec.
3. If BOTH conditions are true AND `--apply` is set AND `--force` was NOT passed: ABORT cleanup
   immediately. Print this message to the human and stop:

   > Resolutions are present but per-repo spec sections remain — finalize-spec (repo-spec mode) has not been run. Cross-repo decisions would be lost. Run finalize-spec first, or pass `--apply --force` to proceed anyway.

   Do not delete anything. Do not flush Redis. Exit the skill.
4. If `--apply --force` AND both conditions are true: proceed, but first
   print a warning listing the resolution files and section files that are
   about to be deleted.
5. In DRY-RUN mode with both conditions true: print the same warning (prefixed `[dry-run]`) listing files that *would* be discarded by a real run, then continue into the preview output below.
6. If either condition is false (no resolutions to lose, or finalize-spec
   already ran): proceed normally with no warning.

## Session Context (read once, reuse below)

Before any deletion, read shared session context. Used by handoff sweep and worker-inbox iteration. This step is always read-only; runs identically in both DRY-RUN and `--apply`.

```bash
# Session start time — used as mtime floor for handoff sweep.
# If _session.json is missing (shouldn't happen if orchestrator ran properly),
# fall back to 24 hours ago.
SESSION_START="$(jq -r '.started_at // "1970-01-01T00:00:00Z"' "$XFLEET_COORDINATION_ROOT/state/_session.json" 2>/dev/null)"
if [[ "$SESSION_START" == "1970-01-01T00:00:00Z" || -z "$SESSION_START" ]]; then
  # macOS/BSD date syntax. GNU/Linux equivalent: date -u -d "24 hours ago" +%Y-%m-%dT%H:%M:%SZ
  SESSION_START="$(date -u -v-24H +%Y-%m-%dT%H:%M:%SZ)"
  echo "Warning: no valid _session.json:started_at; using $SESSION_START (24h ago) as mtime floor."
fi

# Workers and their repo paths (for handoff sweep).
# repo_path was written by each worker at /xfleet:worker startup.
# Portable for bash 3.2 (macOS default): parallel indexed arrays + a plain
# *.json glob with an existence guard (no zsh (N) qualifier, no bash-4 -A).
WORKERS=()
WORKER_REPO_PATHS=()   # parallel indexed array; index aligns with WORKERS
for f in "$XFLEET_COORDINATION_ROOT"/state/*.json; do
  [ -e "$f" ] || continue              # no-match guard (replaces zsh (N))
  name="$(basename "$f" .json)"
  case "$name" in _*) continue;; esac  # skip _session.json, _orchestrator.json
  WORKERS+=("$name")
  WORKER_REPO_PATHS+=("$(jq -r '.repo_path // empty' "$f")")
done

# Orchestrator repo path (for its own handoff sweep below).
# repo_path was written by the orchestrator at /xfleet:orchestrator startup.
# Guarded: empty if the file or field is absent, so the orch sweep skips
# gracefully rather than running against an undefined/empty path.
ORCH_REPO_PATH="$(jq -r '.repo_path // empty' "$XFLEET_COORDINATION_ROOT/state/_orchestrator.json" 2>/dev/null)"
```

## Handoff Sweep (xfleet-prefixed, session-scoped)

Sweep handoff files produced during THIS session. Belt-and-suspenders filter: filename prefix `xfleet-` AND mtime >= `SESSION_START`. Never touch non-xfleet handoffs; never touch xfleet handoffs older than this session's start.

For each worker index `i` in `WORKERS` (use the index to read the parallel
`WORKER_REPO_PATHS[i]`, e.g. `for i in "${!WORKERS[@]}"; do …`):
- Target dir: `${WORKER_REPO_PATHS[$i]}/docs/superpowers/handoffs/`
- If `WORKER_REPO_PATHS[$i]` is empty or the dir doesn't exist, skip with a `[skipped]` line.
- Find files matching `xfleet-*.md` with mtime >= `SESSION_START`.
- `--apply`: delete matches.
- DRY-RUN: list matches prefixed with `[dry-run] would remove:`.

Also sweep the orchestrator's own handoffs at `${ORCH_REPO_PATH}/docs/superpowers/handoffs/` with the same filter (`ORCH_REPO_PATH` is assigned in the Session Context block above). If `ORCH_REPO_PATH` is empty (no `_orchestrator.json` or no `repo_path` field) or the dir doesn't exist, skip the orch sweep with a `[skipped]` line.

```bash
# Pseudocode for each target dir $DIR:
find "$DIR" -maxdepth 1 -name 'xfleet-*.md' -newermt "$SESSION_START" -print
# --apply branch appends -delete to the find invocation.
```

Handoffs NOT matching the pattern (e.g., non-xfleet handoffs from unrelated sessions) are never touched. If a human accidentally omits the `xfleet-` prefix on a multi-repo handoff, that file leaks — flag this in the DRY-RUN output if any `*.md` files in the target dir post-date `SESSION_START` but don't match the pattern.

## Remove Intermediate Artifacts

```bash
rm -f "$XFLEET_COORDINATION_ROOT"/concerns/*.md
rm -f "$XFLEET_COORDINATION_ROOT"/resolutions/*.md
rm -f "$XFLEET_COORDINATION_ROOT"/reviews/*.md
rm -f "$XFLEET_COORDINATION_ROOT"/alignment/*.md
rm -f "$XFLEET_COORDINATION_ROOT"/state/*.json           # includes _session.json, _orchestrator.json
rm -f "$XFLEET_COORDINATION_ROOT"/handoffs/*.md          # legacy non-repo-local handoff location
```

`$XFLEET_COORDINATION_ROOT/handoffs/*.md` is the legacy destination used before handoffs moved to each worker's repo-local `docs/superpowers/handoffs/`. It may contain stragglers from older sessions that fell through the `docs/superpowers/handoffs/` → coordination-root fallback chain in prepare-compact's output location. Safe to sweep here — these files are session-scoped by the state/resolutions cleanup that follows, not by individual inspection.

**DRY-RUN behavior:** do NOT run the `rm` commands. For each pattern, list matches via `ls` prefixed with `[dry-run] would remove:`. Empty matches print `[dry-run] (none) <pattern>`.

**Do NOT** run a `rm -f docs/superpowers/handoffs/*.md` — worker-repo handoffs are handled by the selective sweep above. Removing them with a wildcard would clobber unrelated handoffs from other sessions.

## Flush Redis Streams

For each worker name extracted above, delete its inbox stream:

```bash
for worker in "${WORKERS[@]}"; do
  redis-cli DEL "inbox:${worker}"
done
redis-cli DEL "inbox:orchestrator"

# Delete per-concern round counters (xfleet concern INCRs concern:{id}:rounds).
# Idempotent: xargs -r is a no-op if no keys match.
redis-cli --scan --pattern 'concern:*:rounds' | xargs -r redis-cli DEL >/dev/null
```

**DRY-RUN behavior:** do NOT issue `DEL` commands. Instead:
- For each worker, print `[dry-run] would flush stream: inbox:<worker>` along with its current `XLEN` (read-only).
- Print `[dry-run] would flush stream: inbox:orchestrator` plus its `XLEN`.
- Replace the `concern:*:rounds` DEL pipeline with scan-and-list only: `redis-cli --scan --pattern 'concern:*:rounds'` prefixed with `[dry-run] would delete key:` per match.

Do NOT remove `$XFLEET_COORDINATION_ROOT/specs/` or `$XFLEET_COORDINATION_ROOT/plans/` directories — these hold durable artifacts.

## Exit

List what was removed/would-be-removed: artifact counts per directory, handoff files swept per worker (grouped by repo), Redis streams deleted, counter keys deleted.

**DRY-RUN header:** `Dry-run preview — no changes made. Pass --apply to execute.`
**Real-run header:** `Cleanup complete.`

Cleanup is the terminal phase; there is no `xfleet phase --complete` downstream
emission after it.

## Rationalizations to reject

| Excuse | Reality |
|--------|---------|
| "I'll just pass `--apply --force` — finalize-spec is a separate concern." | `--force` means cross-repo decisions in `$XFLEET_COORDINATION_ROOT/resolutions/` get deleted before they've been merged into any final spec. The guard exists to catch this exact mistake. Run finalize-spec first. |
| "Dry-run is a formality, I can skip straight to `--apply`." | The dry-run output shows which handoff files will be swept, which Redis streams will be flushed, and whether the guard would abort. Reading it is 15 seconds of insurance against destroying non-xfleet handoffs or aborted sessions' state. |
| "The guard is conservative — the resolutions must be stale." | If resolutions exist and per-repo sections still exist, finalize-spec has NOT been run. The presence/absence check is literal, not heuristic. |
| "I'll just `rm -f docs/superpowers/handoffs/*.md` to speed things up." | That's the exact anti-pattern this skill prevents (line with the "Do NOT run" comment). It clobbers handoffs from unrelated sessions in the same directory. Use the selective session-scoped sweep above. |
| "Dry-run shows some stuff I don't care about — I'll `--apply` without reading." | Dry-run is also how you catch handoffs accidentally written without the `xfleet-` prefix (they get flagged but not swept). Reading once prevents silent leaks. |
| "Files in `$XFLEET_COORDINATION_ROOT/handoffs/` might be personal or from unrelated sessions — safer to prompt per file." | That path IS the legacy destination where non-repo-local handoffs legitimately land via the fallback chain. The surrounding session + resolutions cleanup already scopes the sweep — per-file prompting is not a safer default, it's a misread of what this directory holds. Sweep all. |
