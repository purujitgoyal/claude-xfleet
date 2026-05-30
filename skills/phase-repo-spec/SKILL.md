---
name: phase-repo-spec
description: >
  Use when entering the repo-spec phase of an xfleet multi-repo coordination
  session — the per-repo spec-section authoring + cross-repo negotiation phase.
  The worker loads this skill on `xfleet phase --enter repo-spec`; it sets the
  burst-heavy context thresholds, review intensity, a prior-decisions entry
  step, and a finalize-spec (repo-spec mode) exit with a checklist-gate hook
  point. Trigger phrases: "enter the repo-spec phase", "start repo-spec",
  "run /xfleet:phase-repo-spec".
warn_at: 50
critical_at: 65
review_intensity: high
context_heavy:
  - section-authoring
---

## Protocol

- **Design principles:** see `shared/design-principles.md` — loaded every
  session, every `/clear`+resume.
- **Wire taxonomy:** see `shared/messaging.md` for the subcommand list, sender
  authority, and `--message`/`--message-file` rules. Do not restate it here.

This is a phase skill: thin metadata + entry/exit composition. The worker base
loop (`skills/worker/SKILL.md`) owns the always-on loop, context-discipline,
and authority rules; this skill only adds repo-spec specifics.

## Metadata

- `warn_at: 50` / `critical_at: 65` — **lower than the 70/80 default**: repo-spec
  is write + review burst-heavy (cluster 4f, manually validated 2026-04-22).
  This matches the threshold already encoded in `skills/worker/SKILL.md`. Read
  on phase entry; propagate to `check-context`.
- `review_intensity: high` — repo-spec **first pass** is high (cluster 4a);
  re-finalize / post-implementation passes drop to standard. Override at
  invocation with `xfleet phase --enter repo-spec --review-intensity <level>`.
- `context_heavy: [section-authoring]` — before authoring a repo `section.md`,
  run `check-context`; if ≥ `warn_at`, run prepare-compact and set
  `status: "compacting"` first (cluster 4f pre-flight compact).

## Entry

1. **Read prior decisions before authoring** — load the cross-repo `spec.md`
   `## Decisions Log` (cluster 4l/4b) and any prior resolutions at
   `$XFLEET_COORDINATION_ROOT/resolutions/*.md`. Don't re-litigate settled
   decisions; reference D-N entries rather than re-raising.
2. Author/evolve this repo's `section.md` (the `section-authoring`
   `context_heavy` subtask — run the pre-flight check above). Workers write to
   their own `section.md` + concerns; `spec.md` write authority is orch-only.
3. Set `current_phase: repo-spec`; propagate `warn_at`/`critical_at` to
   `check-context`; resume the always-on worker loop.

## Exit

`xfleet phase --complete` is the SIGNAL (worker → orch; recipient always orch).
The phase command runs the cluster 4d phase-exit discipline: prepare-compact →
write handoff at `{repo}/docs/superpowers/xfleet/{slug}/handoff-repo-spec.md` →
update state → emit `phase-complete`.

Orch-side (cluster 4l): on `phase-complete`, the orchestrator runs the
completion-check, then invokes **finalize-spec in repo-spec mode** locally —
merging per-repo `section.md` files + `$XFLEET_COORDINATION_ROOT/resolutions/*.md`
into the updated cross-repo `spec.md` with a populated `## Decisions Log`.

### Checklist-gate hook point (forthcoming — cluster 5, NOT in this plan)

finalize-spec repo-spec mode will invoke a checklist gate
(`xfleet checklist --mode repo-spec`) before producing the final spec. That
subcommand is **cluster 5 scope and does not exist yet** — do NOT call it. This
skill only DECLARES the hook point. Until the gate ships, finalize-spec
proceeds without it; treat the gate as forthcoming and degrade gracefully.
