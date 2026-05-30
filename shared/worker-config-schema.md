# xfleet Worker Config Schema

> **Canonical reference for the per-repo `worker-config.md` schema** (cluster 4m,
> F-20). Every worker session loads the repo's `worker-config.md` to discover its
> reviewer, convention files, and language settings. This doc defines what fields
> that file may and must contain. Path notation throughout uses
> `$XFLEET_COORDINATION_ROOT/...` (SC-2 G1) — never hardcoded repo paths.
>
> Sibling docs in `shared/`: `messaging.md` (wire-message taxonomy) and
> `design-principles.md` (F-35 + F-36).
>
> **Per-dev worker-config.md files are not committed** — each developer maintains
> one per repo locally (or in their personal config directory). This schema doc is
> the durable reference so all per-dev files stay consistent.

---

## Overview

A `worker-config.md` file is a short YAML-flavored Markdown document that an
xfleet worker reads at session start to know (a) which repo it is operating in,
(b) what language and conventions apply, (c) which reviewer skill to invoke for
phase reviews, and (d) any extra skills or context the worker should load. The
file format is YAML front-matter; prose prose is not expected. Mandatory fields
must be present; optional fields may be omitted entirely.

**Reviewer default (cluster 4m).** The canonical reviewer for all xfleet phase
reviews is `architect-review`. The default `reviewers:` entry is a single item
with `agent: architect-review` and `intensity: high`. Phase-skill metadata
overrides this intensity per phase (see Per-Phase Intensity Defaults below). No
parallel per-repo reviewer ecosystem is maintained — architect-review's intensity
contract covers all phase-review needs.

**prd-review stays separate.** Cross-repo PRD review runs through the `prd-review`
skill with its four dimensional agents (risk, boundaries, distributability,
adversarial). prd-review is a different shape from architect-review — cross-repo
synthesis vs single-repo plan/spec/section review — and keeps its own dim-agent
structure. It is not represented in `worker-config.md:reviewers:`.

**/code-review is a separate third-party surface.** The `/code-review` skill is a
third-party post-implementation review tool. xfleet does not unify it with the
intensity contract; it is invoked after implementation as a separate review surface
and is not represented in `worker-config.md:reviewers:`.

---

## Schema Fields

### `name:` (required)

A string identifying the worker or repository. Used in log output, review
headings, and state-file paths. Example value: `oracle`.

### `language:` (required)

A string naming the primary programming language of the repo. Drives
convention-file and tooling assumptions. Example values: `python`, `typescript`,
`go`. A single string — not a list — even for polyglot repos: choose the dominant
language.

### `convention_files:` (optional)

A list of repo-relative paths to convention, style-guide, or standards documents
that the worker loads at session start to ground its implementation and review
decisions. Each entry is a string path relative to the repo root. Example entries:
`docs/conventions.md`, `docs/api-style-guide.md`. Omit the field entirely if there
are no convention docs.

### `reviewers:` (required; default is architect-review at high)

A list of reviewer declarations. Each entry in the list is a mapping with two
keys: `agent:` (a string naming the review skill to invoke) and `intensity:` (an
enum value, one of `standard`, `high`, or `critical`).

The intensity enum has three levels: `standard` (routine review pass, lower
threshold for raising findings); `high` (elevated scrutiny, recommended for
first-pass phase reviews); `critical` (maximum scrutiny, warranted for
spec-authoring phases where perfectionism is the goal). `critical` is the top
level — it is the term used in xfleet vocabulary, consistent with architect-review's
own intensity contract and cluster 4a's per-phase policy (cluster 4m).

**Default.** If a repo has no special reviewer requirements, the `reviewers:` list
contains a single entry: `agent: architect-review` with `intensity: high`. This
single-entry default covers all five xfleet phases at the base level; per-phase
intensity overrides (below) narrow it per phase without changing the config file.

Overriding the reviewer: specify a different `agent:` string to substitute a
different review skill for this repo. Overriding the intensity: per-phase
phase-skill metadata sets phase-local intensity (see below); a per-entry
`intensity:` in `worker-config.md` sets the fallback default for phases that do not
carry an explicit override.

### `additional_skills:` (optional)

A list of extra skill names the worker loads beyond the phase-default skill set.
Each entry is a string matching the skill's registered name. Example entries:
`capture-decision`, `oracle-create-pr`. Omit the field if no extra skills are
needed.

### `repo_specific_context:` (optional)

A freeform string or block scalar containing notes, pointers, or constraints
specific to this repo that the worker should keep in mind throughout the session.
No structure is imposed; write whatever the worker needs to know to operate
effectively in the repo. Example: a short paragraph describing the service's
primary responsibilities, auth patterns, or database topology.

---

## Per-Phase Intensity Defaults

Phase-skill metadata carries a `review_intensity` field that overrides the
`worker-config.md` default for each specific phase. This is cluster 4a's graduated
review-intensity policy — the worker-config sets the fallback; phase skills narrow
or raise intensity per phase. The canonical per-phase defaults are:

- `qa-spec` phase: `critical`. Spec-authoring is perfectionism-warranted; the
  highest scrutiny applies at the cross-repo PRD authoring stage.
- `repo-spec` phase: `high`. First-pass per-repo spec review runs at elevated
  intensity; re-finalize and post-implementation passes drop to `standard`.
- `plan` phase: `standard`. Plan reviews are routine-scrutiny passes.
- `implement` phase: `standard`. Implementation reviews are routine-scrutiny
  passes.
- `cleanup` phase: `standard`. Cleanup reviews are routine-scrutiny passes.

The `xfleet phase --enter <phase> --review-intensity <level>` flag overrides the
per-phase default at invocation time if a one-off adjustment is needed.

**Layering summary.** Worker-config sets the default reviewer and intensity.
Phase-skill metadata overrides intensity per phase using the values above.
Invocation-time `--review-intensity` overrides both for a single phase entry.
Later layers win; worker-config is the floor.
