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
(per-`{slug}` dir + `handoff-*.md` + mtime ≥ session start) so unrelated handoffs
are never touched.

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

# Worker names (for the Redis inbox flush below) — basenames of the per-worker
# state files, skipping the _-prefixed orchestrator/session files.
# Portable for bash 3.2 (macOS default): a plain *.json glob with an existence guard.
WORKERS=()
for f in "$XFLEET_COORDINATION_ROOT"/state/*.json; do
  [ -e "$f" ] || continue              # no-match guard (replaces zsh (N))
  name="$(basename "$f" .json)"
  case "$name" in _*) continue;; esac  # skip _session.json, _orchestrator.json
  WORKERS+=("$name")
done

# Participating repos + slugs for the handoff sweep come from the session ROSTER —
# the canonical source of repo paths (the same file the SessionStart grounding hook
# reads). Each entry is {"repo": "<path>", "slug": "<slug>"}; this session's
# phase-exit handoffs live at {repo}/docs/superpowers/xfleet/{slug}/. Repo paths are
# NOT a worker state field — state-schema.md has none (the old `repo_path` read here
# was a stale assumption; no session ever wrote it).
ROSTER="$XFLEET_COORDINATION_ROOT/roster.json"

# Portable mtime floor: BSD find (macOS default) lacks GNU's -newermt, so stamp a
# marker file to SESSION_START and compare with the portable `find -newer`.
SESSION_MARKER="$(mktemp)"
touch -d "$SESSION_START" "$SESSION_MARKER" 2>/dev/null \
  || touch -t "$(date -j -f '%Y-%m-%dT%H:%M:%SZ' "$SESSION_START" '+%Y%m%d%H%M.%S')" "$SESSION_MARKER"
```

## Handoff Sweep (per-slug, session-scoped)

Sweep this session's phase-exit handoffs. These live at
`{repo}/docs/superpowers/xfleet/{slug}/handoff-{phase}.md` (written by `xfleet phase`
via `handoff-writer.sh`). Filter: filename `handoff-*.md` in the wave's `{slug}` dir
AND mtime >= `SESSION_START`. The per-`{slug}` directory is the isolation boundary —
the sweep is scoped to xfleet's own subtree and never touches unrelated handoffs.

If `roster.json` is missing or not a non-empty array, skip the entire sweep with a
`[skipped] no roster — cannot locate repos` line (there is no other source for repo
paths). Otherwise, for each `{repo, slug}` entry in the roster:
- Target dir: `${repo}/docs/superpowers/xfleet/${slug}/`
- If the dir doesn't exist, skip that entry with a `[skipped]` line.
- Find files matching `handoff-*.md` newer than the session marker.
- `--apply`: delete matches.
- DRY-RUN: list matches prefixed with `[dry-run] would remove:`.

```bash
# Read each roster entry, then sweep its wave dir:
jq -c '.[]' "$ROSTER" | while read -r entry; do
  repo="$(jq -r '.repo' <<<"$entry")"; slug="$(jq -r '.slug' <<<"$entry")"
  DIR="${repo}/docs/superpowers/xfleet/${slug}"
  [ -d "$DIR" ] || { printf '[skipped] %s (dir absent)\n' "$DIR"; continue; }
  find "$DIR" -maxdepth 1 -type f -name 'handoff-*.md' -newer "$SESSION_MARKER" -print
  # --apply branch appends -delete to the find invocation.
done
```

The orchestrator's own handoffs are NOT swept here: cleanup runs in a worker session,
the orchestrator is not a roster entry, and there is no reliable source for its repo
path. Its repo-local handoffs are left for the orchestrator session to clean up; the
legacy coordination-root handoffs are still removed by the artifact step below.

Only `handoff-*.md` files are swept. Other artifacts in the `{slug}` dir
(`section.md`, `plan.md`, `section-vN.md`, …) are deliberately left — selecting by the
`handoff-` prefix is what prevents clobbering those durable/transient siblings.

## Remove Intermediate Artifacts

```bash
rm -f "$XFLEET_COORDINATION_ROOT"/concerns/*.md
rm -f "$XFLEET_COORDINATION_ROOT"/resolutions/*.md
rm -f "$XFLEET_COORDINATION_ROOT"/reviews/*.md
rm -f "$XFLEET_COORDINATION_ROOT"/alignment/*.md
rm -f "$XFLEET_COORDINATION_ROOT"/state/*.json           # includes _session.json, _orchestrator.json
rm -f "$XFLEET_COORDINATION_ROOT"/handoffs/*.md          # legacy non-repo-local handoff location
```

`$XFLEET_COORDINATION_ROOT/handoffs/*.md` is a legacy destination used before phase handoffs moved to each repo's `docs/superpowers/xfleet/{slug}/`. It may contain stragglers from older sessions that fell through prepare-compact's output-location fallback chain. Safe to sweep here — these files are session-scoped by the state/resolutions cleanup that follows, not by individual inspection.

**DRY-RUN behavior:** do NOT run the `rm` commands. For each pattern, list matches via `ls` prefixed with `[dry-run] would remove:`. Empty matches print `[dry-run] (none) <pattern>`.

**Do NOT** wildcard-delete a repo's `docs/superpowers/xfleet/{slug}/*.md` — that dir also holds durable/transient siblings (`section.md`, `plan.md`, snapshots). Repo-local handoffs are handled by the selective `handoff-*.md` sweep above.

## Flush Redis Streams

For each worker name extracted above, delete its inbox stream. **Every
`redis-cli` call here MUST target `$XFLEET_REDIS_URL`** (via `-u`) — the rest of
xfleet routes all Redis through that URL, and a bare `redis-cli` would flush the
default instance, not the session's configured one:

```bash
REDIS="redis-cli -u ${XFLEET_REDIS_URL:-redis://127.0.0.1:6379}"
for worker in "${WORKERS[@]}"; do
  $REDIS DEL "inbox:${worker}"
done
$REDIS DEL "inbox:orchestrator"

# Delete per-concern round counters (xfleet concern INCRs concern:{id}:rounds).
# Idempotent: xargs -r is a no-op if no keys match.
$REDIS --scan --pattern 'concern:*:rounds' | xargs -r $REDIS DEL >/dev/null
```

**DRY-RUN behavior:** do NOT issue `DEL` commands. Instead (still using
`$REDIS`, i.e. `redis-cli -u "$XFLEET_REDIS_URL"`):
- For each worker, print `[dry-run] would flush stream: inbox:<worker>` along with its current `XLEN` (read-only).
- Print `[dry-run] would flush stream: inbox:orchestrator` plus its `XLEN`.
- Replace the `concern:*:rounds` DEL pipeline with scan-and-list only: `$REDIS --scan --pattern 'concern:*:rounds'` prefixed with `[dry-run] would delete key:` per match.

Do NOT remove `$XFLEET_COORDINATION_ROOT/specs/` or `$XFLEET_COORDINATION_ROOT/plans/` directories — these hold durable artifacts.

## Exit

List what was removed/would-be-removed: artifact counts per directory, handoff files swept per repo/slug, Redis streams deleted, counter keys deleted.

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
| "I'll just `rm -f docs/superpowers/xfleet/{slug}/*.md` to speed things up." | That's the exact anti-pattern this skill prevents (the "Do NOT" note above). That dir also holds `section.md` / `plan.md` / snapshots — a wildcard clobbers durable artifacts. Use the selective `handoff-*.md` sweep above. |
| "Dry-run shows some stuff I don't care about — I'll `--apply` without reading." | Dry-run is also how you catch handoffs accidentally written without the `xfleet-` prefix (they get flagged but not swept). Reading once prevents silent leaks. |
| "Files in `$XFLEET_COORDINATION_ROOT/handoffs/` might be personal or from unrelated sessions — safer to prompt per file." | That path IS the legacy destination where non-repo-local handoffs legitimately land via the fallback chain. The surrounding session + resolutions cleanup already scopes the sweep — per-file prompting is not a safer default, it's a misread of what this directory holds. Sweep all. |
