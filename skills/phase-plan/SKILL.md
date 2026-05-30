---
name: phase-plan
description: >
  Use when entering the plan phase of an xfleet multi-repo coordination session
  — the per-repo implementation-plan authoring + reviewer-dispatch phase. The
  worker loads this skill on `xfleet phase --enter plan`; it sets context
  thresholds, review intensity, a writing-plans + plan-fold entry step, the
  reviewer dispatch policy, and the phase-complete exit. Trigger phrases:
  "enter the plan phase", "start plan", "run /xfleet:phase-plan".
warn_at: 70
critical_at: 80
review_intensity: standard
plan_reviewers:
  - architect-review
context_heavy:
  - plan-coverage-audit
---

## Protocol

- **Design principles:** see `shared/design-principles.md` — loaded every
  session, every `/clear`+resume.
- **Wire taxonomy:** see `shared/messaging.md` for the subcommand list, sender
  authority, and `--message`/`--message-file` rules. Do not restate it here.

This is a phase skill: thin metadata + entry/exit composition. The worker base
loop (`skills/worker/SKILL.md`) owns the always-on loop, context-discipline,
and authority rules; this skill only adds plan specifics.

## Metadata

- `warn_at: 70` / `critical_at: 80` — default thresholds (cluster 4f).
- `review_intensity: standard` — plan reviews run at standard intensity
  (cluster 4a). Override with `xfleet phase --enter plan --review-intensity <level>`.
- `plan_reviewers: [architect-review]` — default reviewer dispatched on plan
  edits (cluster 3 / cluster 4m). Override per invocation if a plan warrants
  additional surfaces.
- `context_heavy: [plan-coverage-audit]` — producing the plan-fold coverage
  table is a deep multi-section pass; run `check-context` first and, if ≥
  `warn_at`, prepare-compact before starting.

## Entry

1. **Load `superpowers:writing-plans`** — always invoke it for plan edits
   (F-34 / cluster 3). It is the source of structure for plan files.
2. **Load the `plan-fold` skill** (F-39 / cluster 3) — produce a coverage table
   per plan-fold BEFORE folding any plan edits. This is the
   `plan-coverage-audit` `context_heavy` subtask.
3. Author/evolve this repo's plan at
   `{repo}/docs/superpowers/plans/YYYY-MM-DD-{slug}.md`.
4. **Dispatch reviewers** per `plan_reviewers:` (default `architect-review`,
   cluster 4m). Triage findings locally per `review_intensity` (cluster 4a):
   LOOKUP/PATTERN findings → auto-revise + re-run reviewers (up to the
   convergence counter); JUDGMENT findings → alert-only escalation.
5. Set `current_phase: plan`; propagate `warn_at`/`critical_at` to
   `check-context`; resume the always-on worker loop.

## Exit

`xfleet phase --complete` is the SIGNAL (worker → orch; recipient always orch).
The phase command runs the cluster 4d phase-exit discipline: prepare-compact →
write handoff at `{repo}/docs/superpowers/xfleet/{slug}/handoff-plan.md` →
update state → emit `phase-complete`. Do not emit `phase-complete` while
reviewer findings are still unresolved above the convergence threshold.
