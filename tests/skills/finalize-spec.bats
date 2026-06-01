#!/usr/bin/env bats
# Doc-structure tests for skills/finalize-spec/SKILL.md (Task 11).
#
# tests/skills/ is two levels below the repo root, so:
#   BATS_TEST_DIRNAME = <repo>/tests/skills
#   ../../skills/finalize-spec/SKILL.md = <repo>/skills/finalize-spec/SKILL.md
#
# finalize-spec is a procedure-DECLARING skill (like the phase skills): the
# actual finalize logic lands in Phase B subcommands. These assertions verify
# the skill DOCUMENTS each behavior — they are NOT executable-logic tests.
#
# Asserts the skill documents: (a) mode auto-detection from current_phase;
# (b) --mode override; (c) the snapshot increment rule (max spec-vN + 1,
# filesystem-as-counter); (d) the Decisions Log format markers; (e) the
# checklist-gate hook as mandatory in repo-spec mode with refuse-on-nonzero.
# Plus frontmatter, the load-bearing ## Protocol heading, and the two
# shared-doc cross-refs (design-principles.md is a forward ref to Task 13).

bats_require_minimum_version 1.5.0

SKILL="${BATS_TEST_DIRNAME}/../../skills/finalize-spec/SKILL.md"

# Robust heading-substring assertion: matches a Markdown heading line (one or
# more leading '#') that contains the given substring (case-sensitive).
assert_heading() {
    run grep -E "^#+ .*${1}" "${SKILL}"
    [ "$status" -eq 0 ]
}

# --- existence + frontmatter ------------------------------------------------

@test "skills/finalize-spec/SKILL.md exists" {
    [ -f "${SKILL}" ]
}

@test "frontmatter declares name: finalize-spec" {
    run grep -E "^name: *finalize-spec" "${SKILL}"
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

# --- (a) mode auto-detection from current_phase -----------------------------

@test "documents mode auto-detection from current_phase" {
    run grep -F "current_phase" "${SKILL}"
    [ "$status" -eq 0 ]
    run grep -E "auto-detect" "${SKILL}"
    [ "$status" -eq 0 ]
}

@test "documents both qa-spec and repo-spec modes" {
    run grep -F "qa-spec" "${SKILL}"
    [ "$status" -eq 0 ]
    run grep -F "repo-spec" "${SKILL}"
    [ "$status" -eq 0 ]
}

# --- (b) --mode override ----------------------------------------------------

@test "documents the --mode override" {
    run grep -F -- "--mode" "${SKILL}"
    [ "$status" -eq 0 ]
}

# --- (c) snapshot increment rule (max spec-vN + 1 / filesystem-as-counter) --

@test "documents the spec-v{N+1} snapshot increment rule" {
    run grep -E "spec-v\\{N\\+1\\}|spec-v0\\.md|spec-vN" "${SKILL}"
    [ "$status" -eq 0 ]
}

@test "documents filesystem-as-counter (no stateful counter)" {
    run grep -E "[Ff]ilesystem.*(source of truth|counter)" "${SKILL}"
    [ "$status" -eq 0 ]
}

@test "documents apply-revisions-first then copy (Model A)" {
    run grep -E "pending revisions.*first|apply.*first.*then copy|revisions to .spec\\.md. .?.?first" "${SKILL}"
    [ "$status" -eq 0 ]
}

@test "documents spec-v0.md as the immutable seed" {
    run grep -E "spec-v0\\.md.*(immutable|seed)" "${SKILL}"
    [ "$status" -eq 0 ]
}

# --- (d) Decisions Log format markers ---------------------------------------

@test "documents the ## Decisions Log section" {
    assert_heading "Decisions Log"
}

@test "documents the D-N decision-entry marker" {
    run grep -E "### D-N" "${SKILL}"
    [ "$status" -eq 0 ]
}

@test "documents the **Decision:** marker" {
    grep -Fq "**Decision:**" "${SKILL}"
}

@test "documents the **Rationale:** marker" {
    grep -Fq "**Rationale:**" "${SKILL}"
}

@test "documents the **Resolved in:** marker" {
    grep -Fq "**Resolved in:**" "${SKILL}"
}

# --- (e) checklist-gate hook: mandatory in repo-spec, refuse-on-nonzero ------

@test "declares the checklist-gate hook point" {
    run grep -E "xfleet checklist --mode repo-spec" "${SKILL}"
    [ "$status" -eq 0 ]
}

@test "documents checklist gate is mandatory and refuse-on-nonzero" {
    run grep -E "REFUSE|refuse|non-zero|mandatory" "${SKILL}"
    [ "$status" -eq 0 ]
}

# --- Post-Implementation Resolution template (section-template only) ---------

@test "documents the Post-Implementation Resolution template" {
    run grep -F "Post-Implementation Resolution" "${SKILL}"
    [ "$status" -eq 0 ]
}

# --- session-role: runs in the orch session ---------------------------------

@test "documents that finalize-spec runs in the orch session" {
    run grep -E "orch session" "${SKILL}"
    [ "$status" -eq 0 ]
}

# --- plugin path/transport model (no wave-1 leftovers) ----------------------

@test "uses \$XFLEET_COORDINATION_ROOT for resolutions path" {
    run grep -F "XFLEET_COORDINATION_ROOT/resolutions" "${SKILL}"
    [ "$status" -eq 0 ]
}

@test "does not use wave-1 send.sh transport" {
    run grep -F "send.sh" "${SKILL}"
    [ "$status" -ne 0 ]
}

@test "does not hardcode ~/.claude/resolutions wave-1 path" {
    run grep -F "~/.claude/resolutions" "${SKILL}"
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
