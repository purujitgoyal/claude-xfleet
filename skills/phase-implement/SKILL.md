---
name: phase-implement
description: >
  Use when entering the implement phase of an xfleet multi-repo coordination
  session — the per-repo plan-execution phase. The worker loads this skill on
  `xfleet phase --enter implement`; it sets context thresholds, review
  intensity, a subagent-driven-development orientation entry step, marks the
  context-heavy subtasks, and the phase-complete exit. Trigger phrases:
  "enter the implement phase", "start implement", "run /xfleet:phase-implement".
warn_at: 70
critical_at: 80
review_intensity: standard
context_heavy:
  - deep-multi-file-analysis
  - cross-module-refactor
---

## Protocol

- **Design principles:** see `shared/design-principles.md` (forthcoming;
  Task 13) — loaded every session, every `/clear`+resume once it lands.
- **Wire taxonomy:** see `shared/messaging.md` for the subcommand list, sender
  authority, and `--message`/`--message-file` rules. Do not restate it here.

This is a phase skill: thin metadata + entry/exit composition. The worker base
loop (`skills/worker/SKILL.md`) owns the always-on loop, context-discipline,
and authority rules; this skill only adds implement specifics.

## Metadata

- `warn_at: 70` / `critical_at: 80` — default thresholds (cluster 4f).
- `review_intensity: standard` — implement reviews run at standard intensity
  (cluster 4a). Override with `xfleet phase --enter implement --review-intensity <level>`.
- `context_heavy: [deep-multi-file-analysis, cross-module-refactor]` — before
  entering either subtask run `check-context`; if ≥ `warn_at`, prepare-compact
  and set `status: "compacting"` first (cluster 4f). Independent context-heavy
  work may instead be delegated fire-and-forget via the `Agent` tool — the
  subagent returns a summary and is never resumed.

## Entry

1. **subagent-driven-development orientation** — the implement phase executes
   the plan task-by-task. Load `superpowers:subagent-driven-development` and
   work the plan's task list in order. After each task completes with DONE,
   start the next immediately (worker Autonomous Execution rule); only stop for
   BLOCKED / NEEDS_CONTEXT, which become a concern or an escalation.
2. Set `current_phase: implement`; propagate `warn_at`/`critical_at` to
   `check-context`; resume the always-on worker loop.

## Exit

`xfleet phase --complete` is the SIGNAL (worker → orch; recipient always orch).
The phase command runs the cluster 4d phase-exit discipline: prepare-compact →
write handoff at `{repo}/docs/superpowers/xfleet/{slug}/handoff-implement.md` →
update state → emit `phase-complete`. Emit only once all plan tasks are
complete and reviewer findings are resolved below the convergence threshold.
