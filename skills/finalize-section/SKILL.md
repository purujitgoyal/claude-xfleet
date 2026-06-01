---
name: finalize-section
description: >
  Use when finalizing or snapshotting a repo's per-repo `section.md` during an
  xfleet session — applies all pending revisions to `section.md`, then snapshots
  an immutable `section-v{N+1}.md` milestone (N = max version among existing
  `section-vN.md` files; filesystem is the version counter). Runs continuously
  in the worker session whenever the section reaches a milestone, so reviewers
  can diff `section.md` against the latest snapshot without git. Per-repo analog
  of finalize-spec's snapshot mechanic. Trigger phrases: "snapshot the section",
  "finalize the section", "run finalize-section", "run /xfleet:finalize-section".
  Invokable as `/xfleet:finalize-section`.
---

## Protocol

- **Design principles:** see `shared/design-principles.md` — loaded every
  session, every `/clear`+resume.
- **Wire taxonomy:** see `shared/messaging.md` for the subcommand list, sender
  authority, and `--message`/`--message-file` rules. Do not restate it here.

This is a procedure-**declaring** skill. The actual snapshot logic lands in
Phase B; this skill DECLARES the procedure the worker follows. finalize-section
is the per-repo analog of finalize-spec's snapshot mechanic — same Model A
apply-then-copy, but for per-repo `section.md` → `section-vN.md` rather than
cross-repo `spec.md` → `spec-vN.md`.

## Per-repo path convention (cluster 4c)

Per-repo xfleet work lives at `{repo}/docs/superpowers/xfleet/{slug}/` — NOT
mixed with the repo's regular `plans/`, `specs/`, `research/`, or `handoffs/`
dirs. `section.md`, the `section-vN.md` snapshots, and the `section-v0.md` seed
all live under this per-repo tree. Refer to paths
`{repo}/docs/superpowers/xfleet/{slug}/`-relative or via
`$XFLEET_COORDINATION_ROOT` for cross-repo state — never hardcode `merlin-ai/`
into the per-repo path.

## Snapshot mechanic (Model A — cluster 4c)

Snapshots are versioned `section-v{N}.md` milestones. Unlike finalize-spec
(which snapshots at **phase exits only**), per-repo `section.md` is
**continuously evolving and snapshotted whenever finalize-section runs** — at
each milestone the worker reaches. The asymmetry is on purpose: cross-repo
synthesis is heavyweight and milestone-gated; per-repo section work is lighter
and snapshotted continuously so review stays current.

**The v0 seed.** `section-v0.md` is the **immutable seed** — the
spec-distribution seed written when the section is first distributed to the
repo (the semantic equivalent of the former `section-init.md`). It is **never
overwritten**. The first snapshot off the v0 seed is `section-v1.md`.

**Procedure (Model A):**

1. Apply all pending revisions (baked-in review/concern/alignment findings,
   accepted edits) to `section.md` **first**.
2. Then copy `section.md` → `section-v{N+1}.md`, where **N = max version among
   existing `section-vN.md` files** (N = 0 if only the `section-v0.md` seed
   exists, i.e. the first finalize-section run produces `section-v1.md`).

The **filesystem is the source of truth for the version counter** — there is no
stateful counter anywhere else. To compute the next version, list existing
`section-v*.md` files and take `max(N) + 1`. `section.md` is always the current
working copy; the `section-v{N}.md` files are immutable snapshot milestones.

The apply-then-copy ORDER is load-bearing: revisions land in `section.md`
**before** the snapshot copy, so `section-v{N+1}.md` captures the section
*including* the pending revisions, never a stale pre-revision copy.

### Parallel contracts snapshot (cluster 5)

At the same moment `section.md` → `section-v{N+1}.md` is taken (end of
repo-spec), take a **parallel snapshot** of `contracts.md` →
`contracts-v{M+1}.md`. The contracts snapshot uses the **same Model A mechanic
and filesystem-as-counter rule**, but with an **independent version counter**:
count existing `contracts-v*.md` files specifically (not `section-v*` files) and
take `max(M) + 1`. The two counters are never coupled — section and contracts
snapshots increment separately. This extends the cluster 4c durable list.

Absence of a `contracts.md` (e.g. the section predates cluster 5) skips the
parallel snapshot without error — section snapshotting proceeds unchanged.

## Review without git (F-54)

Reviewers **diff `section.md` against `section-v{max}.md`** (the latest
snapshot) to see what changed since the last milestone. This is how
review-without-git works: F-54 was closed by **rejecting git tracking** —
tracking `section.md`/snapshots in git would pollute the repo's history with
PR-irrelevant churn. Manual `section-vN.md` snapshots give reviewers a stable
diff baseline without committing intermediate coordination state.

## Mid-session re-distribute → subdir versioning (cluster 4c)

If a section is **re-distributed mid-session** (the spec changes a repo's scope
after distribution), do NOT bump `section-vN` in place. Instead use **subdir
versioning**: a fresh per-repo tree at `xfleet/{slug}-v1/`, then
`xfleet/{slug}-v2/`, etc., each with its own `section.md` + `section-vN.md`
lineage. This keeps the prior section's snapshot history intact and isolates
the re-scoped work. BMAD epics (F-49) likely make mid-session re-distribute
rare, so subdir versioning is the exception, not the common path.

## Procedure

1. **Locate the section tree** at `{repo}/docs/superpowers/xfleet/{slug}/`.
   Confirm `section.md` and the `section-v0.md` seed exist; the seed is the
   immutable spec-distribution baseline.
2. **Apply pending revisions** to `section.md` — bake in accepted
   review/concern/alignment findings and edits. This happens **before** any
   snapshot copy (Model A order).
3. **Compute the next version** — list existing `section-v*.md` files, take
   `max(N)`, the next snapshot is `section-v{N+1}.md` (filesystem is the
   counter; if only `section-v0.md` exists, the next is `section-v1.md`).
4. **Snapshot (Model A)** — copy the revised `section.md` →
   `section-v{N+1}.md`. Never overwrite `section-v0.md` or any existing
   snapshot.
5. **(Parallel — contracts snapshot)** If `contracts.md` is present, list
   existing `contracts-v*.md` files, take `max(M)` (independent counter), and
   copy `contracts.md` → `contracts-v{M+1}.md`. The contracts version counter
   is independent of the section counter — count `contracts-v*` files only.
   Skip silently if `contracts.md` is absent.
6. **(re-distribute case)** If this finalize follows a mid-session
   re-distribute, work under a fresh `xfleet/{slug}-v{K}/` subdir rather than
   continuing the prior section's `section-vN` lineage.
7. **Report** — the section path, the snapshot filenames written (section and
   contracts), the revisions baked in, and the diff baseline
   (`section-v{max}.md`) reviewers should compare `section.md` against.

## Rationalizations to reject

| Excuse | Reality |
|--------|---------|
| "I'll bump a counter / state field for the snapshot version." | There is no stateful version counter. The filesystem is the source of truth — `max(N)` among existing `section-v*.md` files `+ 1`. A side counter drifts. |
| "I'll copy `section.md` first, then apply the revisions." | Model A is apply-then-copy. Revisions land in `section.md` **before** the snapshot copy, or `section-v{N+1}.md` captures a stale pre-revision section. |
| "I'll overwrite `section-v0.md` with the latest." | `section-v0.md` is the immutable spec-distribution seed. It is never overwritten — snapshots only ever add new `section-v{N+1}.md` files. |
| "The section was re-distributed; I'll just bump `section-vN`." | Mid-session re-distribute uses subdir versioning (`xfleet/{slug}-v1/`, `-v2/`), not an in-place `section-vN` bump. The prior lineage stays intact. |
| "Let me track `section.md` in git so reviewers can diff it." | F-54 rejected git tracking — it pollutes the repo's history with PR-irrelevant churn. Reviewers diff `section.md` against `section-v{max}.md`; that's the review-without-git mechanism. |
| "I'll use the section-vN counter for the contracts snapshot too." | The contracts version counter is independent — count `contracts-v*.md` files specifically. The two counters are never coupled; using the wrong file glob gives a wrong version number. |
