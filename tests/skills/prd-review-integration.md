# prd-review Integration Smoke Test (Task 14)

Manual smoke test for the two Task-14 extensions to the **personal global**
`prd-review` skill ecosystem. These changes live outside the plugin repo
(`~/.claude/skills/prd-review/SKILL.md` and
`~/.claude/agents/prd-boundaries-reviewer.md`), so they cannot be covered by
the plugin's BATS suite. A human runs the steps below against a sample wave.

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
   and no prior `prd-review-*.md` files match the glob, the review proceeds
   with an empty `prior_decisions` block — no error, no block.

## Preconditions

- `~/.claude/skills/prd-review/SKILL.md` contains a `## Step 2.5: Assemble
  Prior-Decisions Context` section, and Step 3's per-agent inputs list
  `prior_decisions`.
- `~/.claude/agents/prd-boundaries-reviewer.md` contains a Check 5
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

To also exercise source 2 of the prior-decisions block, optionally drop a
prior findings file at
`~/merlin-ai/docs/superpowers/xfleet/sample-wave/prd-review-sample-wave.md`
(slug = PRD filename minus date prefix and `.md`). This directory does not
exist by default — creating it is part of exercising source 2.

## Steps

1. **Run the review.** Invoke `/prd-review /tmp/sample-wave.md` (add
   `--intensity high` to force the adversarial dim too, if desired).

2. **Verify the prior-decisions block is assembled (Step 2.5).** In the
   skill's trace, confirm it read the PRD's `## Decisions Log` and globbed
   `~/merlin-ai/docs/superpowers/xfleet/sample-wave/prd-review-*.md`.
   Confirm `D-1` (and any prior `F-N` from the optional findings file)
   appears in the assembled `prior_decisions` text.

3. **Verify the block reaches the dim agents.** Inspect the dispatch prompts
   the skill sent to each dim agent (risk, boundaries, distributability, and
   adversarial if intensity ≥ high). Each prompt must contain the
   `prior_decisions` block **and** the instruction to skip/reference resolved
   decisions instead of re-raising them. Expected: the block text is present
   verbatim in all dim-agent prompts, not just one.

4. **Verify dims honor resolved decisions.** Confirm no dim re-raises a
   finding that `D-1` already settles (e.g., no "estimation error taxonomy
   has no owner" finding). If a dim does reference it, it should cite `D-1`
   explicitly rather than presenting it as a fresh ambiguity.

5. **Verify asymmetry findings surface (Check 5).** In the boundaries dim
   output (and the final findings file's Boundaries section), confirm at
   least one **JUDGMENT**-tagged finding for each narrowing statement in the
   fixture, phrased as the product-call-vs-convenience question and naming
   the sibling surface left behind (e.g., receipt left out while invoice/PO
   are in scope).

6. **Verify graceful degradation.** Run `/prd-review` against a second PRD
   that has **no** `## Decisions Log` and whose slug has **no** matching
   `prd-review-*.md` files (and whose `xfleet/{slug}/` directory does not
   exist). Confirm the review completes normally with an empty/omitted
   `prior_decisions` block and no error about a missing section, missing
   file, or missing directory.

## Expected outcome

- The `prior_decisions` block appears in every dim-agent dispatch prompt
  (Step 3) and carries the skip/reference instruction.
- Dims do not re-raise decisions already settled in the Decisions Log.
- The boundaries dim emits JUDGMENT asymmetry findings for the fixture's
  narrowing statements (Step 5).
- The no-Decisions-Log / no-prior-findings run completes cleanly (Step 6).

Record the actual findings file path and the observed dim-agent prompts as
evidence. Do not record a pass without inspecting the prompts and findings —
the point of this doc is to verify the wiring end to end, not to assert
success.
