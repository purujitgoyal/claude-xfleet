# prd-review Integration Smoke Test (Task 14)

Manual smoke test for the two Task-14 extensions to the `prd-review` skill
ecosystem. These skills live outside the plugin repo, in the **holocron**
plugin (git repo `claude-holocron`: `skills/prd-review/SKILL.md` and
`agents/prd-boundaries-reviewer.md`), so they cannot be covered by the
plugin's BATS suite. A human runs the steps below against a sample wave.

> **General vs xfleet.** `prd-review` is a general skill (risk +
> boundaries + adversarial) with an xfleet sidecar
> (`claude-holocron/skills/prd-review/xfleet.md`) that adds the Distributability
> dimension and a fixed `~/merlin-ai/docs/superpowers/reviews/` findings
> location. Both features below — the prior-decisions block and asymmetry
> detection — are **general** behavior; this test exercises a plain
> `/prd-review` run (no xfleet session, so no distributability dim).
> `<REVIEWS_DIR>` below = the skill's resolved findings dir: repo-local
> `docs/superpowers/reviews/` in a plain run, or
> `~/merlin-ai/docs/superpowers/reviews/` inside an xfleet session.

## What is under test

1. **Prior-decisions context block (cluster 4l, items 4 + 5 / F-28).**
   `prd-review` reads the spec's `## Decisions Log` section plus any prior
   `prd-review-*.md` findings for the same slug, concatenates them into a
   `prior_decisions` block, and passes that block to **every** dim agent.
   Dim agents are instructed to skip or explicitly reference findings that
   map to an already-resolved decision rather than re-raising them.

2. **Asymmetry detection (cluster 4o / F-46, reviewer-side).** The
   `prd-boundaries-reviewer` agent (Check 5) scans the PRD and the
   `prior_decisions` block for narrowing language (`KEEP X untouched`,
   `defer to wave-N`, `leave alone`, `no change`) and surfaces each as a
   **JUDGMENT** finding: "is this a product call or convenience?"

3. **Graceful degradation.** When the `## Decisions Log` section is absent
   and no prior `prd-review-{slug}*.md` files match the glob, the review
   proceeds with an empty `prior_decisions` block — no error, no block.

## Preconditions

- `claude-holocron/skills/prd-review/SKILL.md` contains a `## Step 2.5: Assemble
  Prior-Decisions Context` section, and Step 3's per-agent inputs list
  `prior_decisions`.
- `claude-holocron/agents/prd-boundaries-reviewer.md` contains a Check 5
  (`### 5. Asymmetry Detection`) with the four narrowing-language triggers
  and JUDGMENT tagging.
- A sample cross-repo PRD you can run `/prd-review` against. If you don't
  have one, build the fixture in the next section.

## Fixture: sample wave with a Decisions Log + narrowing resolution

Create a throwaway PRD (any path; e.g. `/tmp/sample-wave.md`) containing:

- Standard PRD frontmatter with `intensity: standard` (or higher).
- A `## Decisions Log` section with at least one settled decision in the
  locked format, e.g.:

  ```
  ## Decisions Log

  ### D-1: Server owns the estimation error taxonomy
  **Decision:** Server is the sole owner of the estimation error taxonomy; web consumes via the SDK.
  **Rationale:** Single-owner rule; web has no backend surface for error classification.
  **Resolved in:** qa-spec round 2 (resolutions/estimation-owner.md)
  ```

- At least one **narrowing** statement in the spec body or a resolution that
  trips Check 5, e.g.:
  - "KEEP the receipt pipeline untouched this wave."
  - "Invoice and PO get the new validation; defer receipt to wave-2."
  - "Leave the legacy webhook alone."

To exercise source 2 of the prior-decisions block (the glob path corrected in
this task), drop a prior findings file at
`<REVIEWS_DIR>/prd-review-sample-wave.md`
(slug = PRD filename minus date prefix and `.md`) — this is the same
`reviews/` directory the skill writes its own findings to. The glob
`prd-review-sample-wave*.md` also picks up re-review suffixes
(`-2.md`, `-3.md`). Give this fixture a recognizable prior finding (e.g. an
`F-9` referencing a settled boundary) so Step 7 can confirm it was pulled in.
**Step 7 below makes exercising source 2 mandatory, not optional** — it is
the path corrected in this task and must be verified working.

## Steps

1. **Run the review.** Invoke `/prd-review /tmp/sample-wave.md` (add
   `--intensity high` to force the adversarial dim too, if desired).

2. **Verify the prior-decisions block is assembled (Step 2.5).** In the
   skill's trace, confirm it read the PRD's `## Decisions Log` and globbed
   `<REVIEWS_DIR>/prd-review-sample-wave*.md`.
   Confirm `D-1` (and any prior `F-N` from the optional findings file)
   appears in the assembled `prior_decisions` text.

3. **Verify the block reaches the dim agents.** Inspect the dispatch prompts
   the skill sent to each dim agent (risk, boundaries, and adversarial if
   intensity ≥ high; xfleet sessions also dispatch distributability). Each
   prompt must contain the
   `prior_decisions` block **and** the instruction to skip/reference resolved
   decisions instead of re-raising them. Expected: the block text is present
   verbatim in all dim-agent prompts, not just one.

4. **Verify dims honor resolved decisions.** Confirm no dim re-raises a
   finding that `D-1` already settles (e.g., no "estimation error taxonomy
   has no owner" finding). If a dim does reference it, it should cite `D-1`
   explicitly rather than presenting it as a fresh ambiguity.

5. **Verify asymmetry findings surface (Check 5).** In the boundaries dim
   output (and the final findings file's Boundaries section), confirm at
   least one `JUDGMENT`-tagged finding with `subcategory: ASSUMPTION` for
   each narrowing statement in the fixture, phrased as the
   product-call-vs-convenience question and naming the sibling surface left
   behind (e.g., receipt left out while invoice/PO are in scope). A
   `JUDGMENT` finding with the wrong subcategory does not count as a pass.

6. **Verify graceful degradation.** Run `/prd-review` against a second PRD
   that has **no** `## Decisions Log` and whose slug has **no** matching
   `<REVIEWS_DIR>/prd-review-{slug}*.md` files (a
   first review of a fresh slug). Confirm the review completes normally with
   an empty/omitted `prior_decisions` block and no error about a missing
   section or empty glob.

7. **Verify source 2 (prior findings glob) — REQUIRED.** With the prior
   findings fixture `<REVIEWS_DIR>/prd-review-sample-wave.md`
   in place (from the fixture section), re-run `/prd-review /tmp/sample-wave.md`.
   In the skill's trace, confirm the glob
   `<REVIEWS_DIR>/prd-review-sample-wave*.md` matched
   that file and that its recognizable prior finding (e.g. `F-9`) appears in
   the assembled `prior_decisions` block — and therefore in the dim-agent
   dispatch prompts (Step 3). This is the path corrected in this task; it must
   be demonstrated working, not assumed. (Bonus: drop a second file
   `prd-review-sample-wave-2.md` and confirm the trailing-`*` glob pulls in
   both.)

## Expected outcome

- The `prior_decisions` block appears in every dim-agent dispatch prompt
  (Step 3) and carries the skip/reference instruction.
- Dims do not re-raise decisions already settled in the Decisions Log.
- The boundaries dim emits `JUDGMENT` + `subcategory: ASSUMPTION` asymmetry
  findings for the fixture's narrowing statements (Step 5).
- The no-Decisions-Log / no-prior-findings run completes cleanly (Step 6).
- The prior-findings glob pulls the `reviews/prd-review-sample-wave*.md`
  fixture (incl. `-2` suffix) into `prior_decisions` (Step 7).

Record the actual findings file path and the observed dim-agent prompts as
evidence. Do not record a pass without inspecting the prompts and findings —
the point of this doc is to verify the wiring end to end, not to assert
success.
