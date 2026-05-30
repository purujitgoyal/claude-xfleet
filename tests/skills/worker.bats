#!/usr/bin/env bats
# Section-presence tests for skills/worker/SKILL.md (Task 8).
#
# tests/skills/ is two levels below the repo root, so:
#   BATS_TEST_DIRNAME = <repo>/tests/skills
#   ../../skills/worker/SKILL.md = <repo>/skills/worker/SKILL.md
#
# Asserts the migrated worker skill carries the 12 required sections (each a
# Markdown heading), the third-person frontmatter, and the two shared-doc
# cross-references (design-principles.md is a forward reference to Task 13).

bats_require_minimum_version 1.5.0

SKILL="${BATS_TEST_DIRNAME}/../../skills/worker/SKILL.md"

# Robust heading-substring assertion: matches a Markdown heading line (one or
# more leading '#') that contains the given substring (case-sensitive).
assert_heading() {
    run grep -E "^#+ .*${1}" "${SKILL}"
    [ "$status" -eq 0 ]
}

@test "skills/worker/SKILL.md exists" {
    [ -f "${SKILL}" ]
}

@test "references/rationalizations.md exists" {
    [ -f "${BATS_TEST_DIRNAME}/../../skills/worker/references/rationalizations.md" ]
}

@test "frontmatter declares name: worker" {
    run grep -E "^name: *worker" "${SKILL}"
    [ "$status" -eq 0 ]
}

@test "frontmatter description is third-person trigger-phrase form" {
    run grep -E "Use when|This skill should be used when" "${SKILL}"
    [ "$status" -eq 0 ]
}

# --- load-bearing Protocol section (carries the shared-doc pointers) --------
# Pinned to the exact heading via a literal match so it does NOT also match
# "## Wire Protocol Cheat-Sheet".

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

@test "section 4: Wire protocol cheat-sheet" {
    assert_heading "Wire Protocol"
}

@test "section 5: Context Discipline" {
    assert_heading "Context Discipline"
}

@test "section 6: Cross-Repo Source Reads" {
    assert_heading "Cross-Repo Source Reads"
}

@test "section 7: State Label Verification" {
    assert_heading "State Label Verification"
}

@test "section 8: Task .output recovery" {
    assert_heading "Task \\.output Recovery"
}

@test "section 9: Boundary-first presentation" {
    assert_heading "Boundary-First Presentation"
}

@test "section 10: Asymmetry pushback" {
    assert_heading "Asymmetry Pushback"
}

@test "section 11: Skill-load + standby semantics" {
    assert_heading "Skill-Load.*Standby"
}

@test "section 12: Phase-exit handoff discipline" {
    assert_heading "Phase-Exit Handoff"
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
