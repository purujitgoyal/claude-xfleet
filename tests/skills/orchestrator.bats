#!/usr/bin/env bats
# Section-presence tests for skills/orchestrator/SKILL.md (Task 9).
#
# tests/skills/ is two levels below the repo root, so:
#   BATS_TEST_DIRNAME = <repo>/tests/skills
#   ../../skills/orchestrator/SKILL.md = <repo>/skills/orchestrator/SKILL.md
#
# Asserts the migrated orchestrator skill carries the 12 required sections (each
# a Markdown heading), the third-person frontmatter, the load-bearing Protocol
# section, and the two shared-doc cross-references (design-principles.md is a
# forward reference to Task 13).

bats_require_minimum_version 1.5.0

SKILL="${BATS_TEST_DIRNAME}/../../skills/orchestrator/SKILL.md"

# Robust heading-substring assertion: matches a Markdown heading line (one or
# more leading '#') that contains the given substring (case-sensitive).
assert_heading() {
    run grep -E "^#+ .*${1}" "${SKILL}"
    [ "$status" -eq 0 ]
}

@test "skills/orchestrator/SKILL.md exists" {
    [ -f "${SKILL}" ]
}

@test "frontmatter declares name: orchestrator" {
    run grep -E "^name: *orchestrator" "${SKILL}"
    [ "$status" -eq 0 ]
}

@test "frontmatter description is third-person trigger-phrase form" {
    run grep -E "Use when|This skill should be used when" "${SKILL}"
    [ "$status" -eq 0 ]
}

# --- load-bearing Protocol section (carries the shared-doc pointers) --------
# Pinned to the exact heading via a literal match so it does NOT also match
# "## Wire Protocol ...".

@test "Protocol section is present (exact heading)" {
    grep -Fq "## Protocol" "${SKILL}"
}

# --- 12 required sections ---------------------------------------------------

@test "section 1: Identity + scope" {
    assert_heading "Identity"
}

@test "section 2: Autonomous Execution" {
    assert_heading "Autonomous Execution"
}

@test "section 3: Authority Hierarchy" {
    assert_heading "Authority Hierarchy"
}

@test "section 4: Wire protocol" {
    assert_heading "Wire Protocol"
}

@test "section 5: Completion gating" {
    assert_heading "Completion Gating"
}

@test "section 6: Escalation handling" {
    assert_heading "Escalation Handling"
}

@test "section 7: Reviewer-findings flow" {
    assert_heading "Reviewer-Findings"
}

@test "section 8: human_engaged toggling" {
    assert_heading "human_engaged"
}

@test "section 9: Phase-exit" {
    assert_heading "Phase-Exit"
}

@test "section 10: Cross-worker synthesis" {
    assert_heading "Cross-Worker Synthesis"
}

@test "section 11: Concern-reopen" {
    assert_heading "Concern-Reopen"
}

@test "section 12: Spec.md write authority" {
    assert_heading "Spec\\.md Write Authority"
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
