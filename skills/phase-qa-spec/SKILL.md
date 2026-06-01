---
name: phase-qa-spec
description: >
  Use when entering the qa-spec phase of an xfleet multi-repo coordination
  session — the cross-repo Q&A + spec-authoring phase. The worker loads this
  skill on `xfleet phase --enter qa-spec`; it sets context thresholds, review
  intensity, the grounding-onboarding entry step, and the finalize-spec
  (qa-spec mode) exit step. Trigger phrases: "enter the qa-spec phase",
  "start qa-spec", "run /xfleet:phase-qa-spec".
warn_at: 70
critical_at: 80
review_intensity: critical
context_heavy:
  - grounding-authoring
---

## Protocol

- **Design principles:** see `shared/design-principles.md` — loaded every
  session, every `/clear`+resume.
- **Wire taxonomy:** see `shared/messaging.md` for the subcommand list, sender
  authority, and `--message`/`--message-file` rules. Do not restate it here.

This is a phase skill: thin metadata + entry/exit composition. The worker base
loop (`skills/worker/SKILL.md`) owns the always-on loop, context-discipline,
and authority rules; this skill only adds qa-spec specifics.

## Metadata

- `warn_at: 70` / `critical_at: 80` — default thresholds (cluster 4f). Read on
  phase entry; propagate to `check-context`.
- `review_intensity: critical` — qa-spec is initial authoring; reviewer
  perfectionism is warranted (cluster 4a). Override at invocation with
  `xfleet phase --enter qa-spec --review-intensity <level>`.
- `context_heavy: [grounding-authoring]` — before authoring/refreshing
  `grounding.md` run `check-context`; if ≥ `warn_at`, run prepare-compact and
  set `status: "compacting"` first (cluster 4f pre-flight compact).

## Entry

1. **Produce/refresh `grounding.md`** (cluster 4h onboarding) at
   `{repo}/docs/superpowers/xfleet/{slug}/grounding.md`. ~50–100 lines:
   - **Purpose** of this repo in the wave.
   - **Scope of this wave** for this repo (what's in / out).
   - **Key abstractions** the wave touches (modules, entry points, contracts).
   - **Pitfalls** — known traps, stale handlers, asymmetries.
   - **Serena memory titles** (optional) worth reading first.
   This is the `context_heavy: grounding-authoring` subtask — run the pre-flight
   compact check above before starting.
2. Set `current_phase: qa-spec`; propagate `warn_at`/`critical_at` to
   `check-context`; resume the always-on worker loop.

## Exit

`xfleet phase --complete` is the SIGNAL (worker → orch; recipient always orch).
The phase command runs the cluster 4d phase-exit discipline: prepare-compact →
write handoff at `{repo}/docs/superpowers/xfleet/{slug}/handoff-qa-spec.md` →
update state → emit `phase-complete`. (idle → first-phase needs no handoff.)

The actual cross-repo synthesis is **orch-side** (cluster 4l): on receiving
`phase-complete`, the orchestrator runs the completion-check, then invokes
**finalize-spec in qa-spec mode** locally → produces the cross-repo `spec.md`
seed (the PRD that drives repo-spec). The worker does not edit `spec.md`
directly; it contributes drafted sections + captured decisions.

Optionally, before repo-spec begins, run `/prd-review` on the finalized
`spec.md` for a cross-repo stress-test (its xfleet sidecar adds the
Distributability dimension); route any JUDGMENT findings through the human
gate. This is operator-invoked — not an automated phase step.
