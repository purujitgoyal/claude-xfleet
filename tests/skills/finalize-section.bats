#!/usr/bin/env bats
# Doc-structure tests for skills/finalize-section/SKILL.md (Task 12).
#
# tests/skills/ is two levels below the repo root, so:
#   BATS_TEST_DIRNAME = <repo>/tests/skills
#   ../../skills/finalize-section/SKILL.md = <repo>/skills/finalize-section/SKILL.md
#
# finalize-section is a procedure-DECLARING skill (like finalize-spec): the
# actual snapshot logic lands in Phase B. These assertions verify the skill
# DOCUMENTS each behavior — they are NOT executable-logic tests.
#
# Asserts the skill documents: (a) the v0 seed + first snapshot is v1;
# (b) the max-version increment rule with filesystem-as-counter; (c) the
# apply-then-copy ORDER (revisions to section.md BEFORE the snapshot copy);
# (d) the subdir-versioning trigger on mid-session re-distribute. Plus
# frontmatter, the load-bearing ## Protocol heading, and the two shared-doc
# cross-refs (design-principles.md is a forward ref to Task 13).

bats_require_minimum_version 1.5.0

SKILL="${BATS_TEST_DIRNAME}/../../skills/finalize-section/SKILL.md"

# Robust heading-substring assertion: matches a Markdown heading line (one or
# more leading '#') that contains the given substring (case-sensitive).
assert_heading() {
    run grep -E "^#+ .*${1}" "${SKILL}"
    [ "$status" -eq 0 ]
}

# --- existence + frontmatter ------------------------------------------------

@test "skills/finalize-section/SKILL.md exists" {
    [ -f "${SKILL}" ]
}

@test "frontmatter declares name: finalize-section" {
    run grep -E "^name: *finalize-section" "${SKILL}"
    [ "$status" -eq 0 ]
}

@test "frontmatter description is third-person trigger-phrase form" {
    run grep -E "Use when|Use at the end" "${SKILL}"
    [ "$status" -eq 0 ]
}

# --- load-bearing Protocol section (carries the shared-doc pointers) --------
# Pinned to the exact heading via a literal match.

@test "Protocol section is present (exact heading)" {
    grep -Fq "## Protocol" "${SKILL}"
}

# --- (a) v0 seed + first snapshot is v1 -------------------------------------

@test "documents section-v0.md as the immutable spec-distribution seed" {
    run grep -E "section-v0\\.md.*(immutable|seed)" "${SKILL}"
    [ "$status" -eq 0 ]
}

@test "documents that the first snapshot off the v0 seed is section-v1.md" {
    run grep -E "section-v1\\.md" "${SKILL}"
    [ "$status" -eq 0 ]
}

@test "documents that v0 seed is never overwritten" {
    run grep -E "never (overwritten|over-written)|immutable seed" "${SKILL}"
    [ "$status" -eq 0 ]
}

# --- (b) max-version increment rule / filesystem-as-counter -----------------

@test "documents the section-v{N+1} snapshot increment rule" {
    run grep -E "section-v\\{N\\+1\\}" "${SKILL}"
    [ "$status" -eq 0 ]
}

@test "documents N = max version among existing section-vN files" {
    run grep -E "max version among existing|max\\(N\\)|max version among" "${SKILL}"
    [ "$status" -eq 0 ]
}

@test "documents filesystem-as-counter (no stateful counter)" {
    run grep -E "[Ff]ilesystem.*(source of truth|counter)" "${SKILL}"
    [ "$status" -eq 0 ]
}

# --- (c) apply-then-copy ORDER (revisions BEFORE the snapshot copy) ----------
# Assert the actual ordering phrase, not just a label.

@test "documents apply-revisions-to-section.md-first then copy (Model A order)" {
    run grep -E "pending revisions to .section\\.md. (first|FIRST)|apply.*revisions.*first.*then copy|revisions.*before.*(snapshot|copy)" "${SKILL}"
    [ "$status" -eq 0 ]
}

@test "documents the copy direction section.md to section-v{N+1}.md" {
    run grep -E "section\\.md . section-v\\{N\\+1\\}\\.md|copy .section\\.md. . .section-v" "${SKILL}"
    [ "$status" -eq 0 ]
}

# --- (d) mid-session re-distribute -> subdir versioning ----------------------

@test "documents subdir versioning on mid-session re-distribute" {
    run grep -E "re-distribut" "${SKILL}"
    [ "$status" -eq 0 ]
    run grep -E "\\{slug\\}-v1/|\\{slug\\}-v2/" "${SKILL}"
    [ "$status" -eq 0 ]
}

# --- reviewers diff section.md against latest snapshot (review-without-git) --

@test "documents reviewers diff section.md against section-v{max}.md" {
    run grep -E "section-v\\{max\\}\\.md|diff.*section\\.md.*section-v" "${SKILL}"
    [ "$status" -eq 0 ]
}

@test "documents F-54 git-tracking-rejected rationale" {
    run grep -E "F-54|without git|review-without-git|pollute.*history|PR-irrelevant" "${SKILL}"
    [ "$status" -eq 0 ]
}

# --- relationship to finalize-spec (per-repo analog) ------------------------

@test "documents continuous snapshotting (vs finalize-spec phase-exit only)" {
    run grep -E "continuous|whenever finalize-section runs|each milestone" "${SKILL}"
    [ "$status" -eq 0 ]
}

# --- per-repo path convention -----------------------------------------------

@test "uses the per-repo docs/superpowers/xfleet/{slug}/ path convention" {
    run grep -F "docs/superpowers/xfleet/{slug}" "${SKILL}"
    [ "$status" -eq 0 ]
}

@test "does not hardcode merlin-ai/ in the per-repo path" {
    run grep -E "merlin-ai/docs/superpowers/xfleet/\\{slug\\}/section\\.md" "${SKILL}"
    [ "$status" -ne 0 ]
}

# --- plugin path/transport model (no wave-1 leftovers) ----------------------

@test "does not use wave-1 send.sh transport" {
    run grep -F "send.sh" "${SKILL}"
    [ "$status" -ne 0 ]
}

# --- shared-doc cross-references --------------------------------------------

@test "references shared/design-principles.md (Task 13 forward ref)" {
    run grep -F "shared/design-principles.md" "${SKILL}"
    [ "$status" -eq 0 ]
}

@test "references shared/messaging.md for wire taxonomy" {
    run grep -F "shared/messaging.md" "${SKILL}"
    [ "$status" -eq 0 ]
}
