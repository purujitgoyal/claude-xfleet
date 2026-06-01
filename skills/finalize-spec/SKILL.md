---
name: finalize-spec
description: >
  Use when finalizing a spec at an xfleet phase exit — synthesizes a single
  cross-repo `spec.md` from worker answers + captured decisions (qa-spec mode)
  or from per-repo `section.md` files + cross-repo resolutions (repo-spec mode),
  populates the `## Decisions Log`, and snapshots an immutable `spec-v{N}.md`
  milestone. Runs in the ORCH session after a worker emits `xfleet
  phase-complete`. Must run before `/cleanup` — the cleanup pre-flight guard
  aborts if resolutions remain but per-repo sections are gone (signal that
  finalize-spec has NOT run). Trigger phrases: "finalize the spec", "run
  finalize-spec", "run /xfleet:finalize-spec". Invokable as
  `/xfleet:finalize-spec [--mode <mode>] [dest_path]`.
---

## Protocol

- **Design principles:** see `shared/design-principles.md` — loaded every
  session, every `/clear`+resume.
- **Wire taxonomy:** see `shared/messaging.md` for the subcommand list, sender
  authority, and `--message`/`--message-file` rules. Do not restate it here.

This is a procedure-**declaring** skill. The actual finalize logic lands in
Phase B subcommands (`xfleet phase --complete` wires the call); this skill
DECLARES the procedure the orchestrator follows. Synthesize, do not
concatenate; every resolution must surface in the output spec.

### Session role (cluster 4l CL3)

finalize-spec runs in the **orch session**, not the worker session. `spec.md`
write authority is **orch only** — workers never edit `spec.md` directly. The
worker emits `xfleet phase-complete` (the SIGNAL; worker → orch, recipient
always orch). The orch handler receives it, runs the completion-check
(cluster 4a), then invokes finalize-spec locally before re-emitting downstream
phase signals. The cross-repo synthesis is orch-side; the worker only
contributes its `section.md` + captured decisions + concerns.

## Modes (cluster 4l)

Two modes, **auto-detected from `current_phase` + available inputs**, with an
explicit `--mode <qa-spec|repo-spec>` override. A post-impl **section-template
only** is appended in any mode — it is NOT a full mode today (see below).

| `current_phase` at exit | Auto-detected mode |
|-------------------------|--------------------|
| `qa-spec`               | qa-spec            |
| `repo-spec`             | repo-spec          |

If `--mode` is passed, it wins over auto-detection. If `current_phase` is
ambiguous or missing, prompt the human rather than guessing.

### qa-spec mode — per-mode I/O

- **Inputs:** worker answers + drafted sections + captured decisions from the
  qa-spec phase.
- **Output:** the cross-repo `spec.md` — the PRD seed that drives repo-spec.
- **Snapshot:** `spec-v0.md` (the immutable seed; see Snapshot mechanic).

### repo-spec mode — per-mode I/O

- **Inputs:** per-repo `section.md` files + cross-repo resolutions at
  `$XFLEET_COORDINATION_ROOT/resolutions/*.md`.
- **Output:** the updated cross-repo `spec.md` with sections merged + the
  `## Decisions Log` populated.
- **Snapshot:** `spec-v1.md` (and so on at later phase exits).

### Post-Implementation Resolution (section-template only — F-24 #3 trimmed)

finalize-spec output **in any mode** appends an empty `## Post-Implementation
Resolution` section template at the end of `spec.md`. Populating it is manual /
future-tooling. It is **NOT a full mode** today — no single agent runs it and
iterative implementation has no natural trigger. Append the empty template;
do not attempt to populate it.

## Snapshot mechanic (Model A — cluster 4c)

Snapshots are versioned `spec-v{N}.md` milestones, created **at phase exits
only**. Mid-phase orch edits to `spec.md` are permitted but rare and do NOT
trigger a new snapshot — they land in the current `spec.md` until the next
phase-exit snapshot. This is stricter than per-repo `section.md` (continuously
snapshotted via `finalize-section`), asymmetric on purpose: cross-repo
synthesis is heavyweight and happens at milestones.

**Procedure (Model A):**

1. Apply all pending revisions (merged sections, baked-in review/concern
   findings, the populated Decisions Log) to `spec.md` **first**.
2. Then copy `spec.md` → `spec-v{N+1}.md`, where **N = max version among
   existing `spec-vN.md` files** (N = 0 if only the `spec-v0.md` seed exists,
   i.e. the first repo-spec exit produces `spec-v1.md`).

The **filesystem is the source of truth for the version counter** — there is
no stateful counter anywhere else. To compute the next version, list existing
`spec-v*.md` files and take `max(N) + 1`. `spec-v0.md` is the immutable seed
written at qa-spec exit; `spec-v1.md` after repo-spec; etc. `spec.md` is always
the current working copy; the `spec-v{N}.md` files are immutable phase-exit
milestones reviewers diff against.

## Decisions Log format (cluster 4l + 4b nomination)

finalize-spec emits a structured `## Decisions Log` section in `spec.md`,
populated from `$XFLEET_COORDINATION_ROOT/resolutions/*.md` summaries during
finalize. Forward-looking voice — sister to ADRs but lighter (per-spec,
session-scoped; cross-project decisions go to repo-local ADRs). Each entry:

```markdown
### D-N: <title>
**Decision:** <forward-looking statement>
**Rationale:** <one paragraph why>
**Resolved in:** <phase + round + ref to resolution file>
```

Rules:

- One `### D-N` entry per resolved decision; number sequentially.
- **Decision** is forward-looking — state what the spec now does, not the
  debate.
- **Rationale** is one paragraph; keep it tight.
- **Resolved in** cites the phase, round, and the
  `$XFLEET_COORDINATION_ROOT/resolutions/*.md` file the entry derives from.
- State files are for state; decisions live here in the spec (cluster 4b).

## Checklist gate (repo-spec mode — mandatory)

In repo-spec mode, **before producing the snapshot**, run:

```
xfleet checklist --mode repo-spec
```

- **Exit 0 (pass, warnings allowed):** proceed to snapshot.
- **Non-zero exit (one or more ERROR-tier findings):** REFUSE the snapshot.
  Surface every finding to the user and stop. Do not write `spec.md` or
  `spec-v{N}.md` until the user resolves the errors and the gate passes.

Warnings (e.g. a referenced test path missing because a repo is not checked
out locally) do NOT fail the gate — only ERROR-tier findings cause non-zero
exit. The gate validates structural completeness of the IP table +
`contracts.md`: no dangling IP/contract refs, no orphan contracts, all
required fields present, T4 flag explicit.

## Procedure

1. **Resolve mode** — auto-detect from `current_phase`, honor `--mode`
   override; prompt the human if ambiguous.
2. **Inventory inputs** for the resolved mode (qa-spec: worker answers +
   drafted sections + captured decisions; repo-spec: per-repo `section.md`
   files + `$XFLEET_COORDINATION_ROOT/resolutions/*.md`). Read each fully.
3. **(repo-spec only) Checklist gate** — run `xfleet checklist --mode
   repo-spec`; on non-zero exit, REFUSE the snapshot and surface all findings
   to the user; on exit 0, proceed.
4. **Synthesize / merge** into `spec.md` — synthesize, don't concatenate;
   resolve duplication, align terminology, order logically. Every resolution
   must surface.
5. **Populate `## Decisions Log`** from the resolutions per the format above.
6. **Append the `## Post-Implementation Resolution`** empty template (any mode).
7. **Destination validation** — `spec.md` and its `spec-v{N}.md` snapshots live
   under the cross-repo coordination tree
   (`merlin-ai/docs/superpowers/xfleet/{slug}/`). Reject any final destination
   that resolves under a transient coordination dir (e.g. anything that the
   `--final` cleanup glob would later delete). If a provided/default path is
   invalid, prompt the human; do not write until a valid destination is given.
8. **Human approval** — present `spec.md` (Slack summary + upload, or terminal
   pointer); wait for approval. Apply requested changes and re-present.
9. **Snapshot (Model A)** — apply pending revisions to `spec.md` first, then
   copy to `spec-v{N+1}.md` with N from the filesystem max (above).
10. **Report** — final `spec.md` path, snapshot filename, mode, sections
    merged, resolutions incorporated, any review findings noted but not
    addressed. Do NOT remove `$XFLEET_COORDINATION_ROOT/resolutions/` — those
    are cleaned by `/cleanup`.

## Rationalizations to reject

| Excuse | Reality |
|--------|---------|
| "Concatenating the sections is faster than synthesizing." | Sections duplicate terminology, overlap on contracts, and contradict each other on points the resolutions settled. Concatenation preserves the conflicts; synthesis resolves them once so `spec.md` is the implementation reference. |
| "This resolution is obvious — I'll skip it in the Decisions Log." | Every resolution must surface as a `### D-N` entry. The Decisions Log is the forward-looking audit trail for why the spec diverges from any repo's earlier draft. |
| "I'll bump a counter / state field for the snapshot version." | There is no stateful version counter. The filesystem is the source of truth — `max(N)` among existing `spec-v*.md` files `+ 1`. A side counter drifts. |
| "I'll snapshot on every mid-phase edit." | Snapshots happen at phase exits only. Mid-phase orch edits land in the current `spec.md` until the next phase-exit snapshot. |
| "The checklist gate failed — I'll snapshot anyway / ignore the findings." | The gate is mandatory in repo-spec mode. A non-zero exit means ERROR-tier findings exist; snapshotting over them hides structural defects in the spec. Surface the findings, wait for resolution, re-run the gate. |
| "No workers active — I'll skip human approval too." | Worker review is conditional on availability; human approval is mandatory. Present `spec.md` and wait. |
| "I'll `rm $XFLEET_COORDINATION_ROOT/resolutions/` while I'm here." | Don't. Those are cleaned by `/cleanup`. Removing them here leaves a partial cleanup and breaks the `/cleanup` pre-flight guard's signal. |
