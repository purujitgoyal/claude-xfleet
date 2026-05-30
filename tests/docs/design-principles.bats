#!/usr/bin/env bats
# Doc-structure tests for shared/design-principles.md + skill cross-refs (Task 13).
#
# tests/docs/ is two levels below the repo root, so:
#   BATS_TEST_DIRNAME = <repo>/tests/docs
#   ../../shared/design-principles.md      = <repo>/shared/design-principles.md
#   ../../skills/<name>/SKILL.md           = the 9 xfleet skill bodies
#
# These assertions verify two things:
#   (1) shared/design-principles.md exists and documents the inaugural
#       principles (F-35 + its 5 corollaries, F-36 + its 4-question rubric and
#       Rationalizations-to-Reject table) plus the placeholder collection.
#   (2) every one of the 9 xfleet skills carries a present-tense Protocol-section
#       cross-reference to the doc, and NO skill still carries the
#       "forthcoming; Task 13" qualifier (the Step-5 regression guard).

bats_require_minimum_version 1.5.0

DOC="${BATS_TEST_DIRNAME}/../../shared/design-principles.md"

# The 9 xfleet skills that must reference design-principles.md in their Protocol
# section (worker, orchestrator, the five phase-* skills, the two finalize-*).
SKILLS=(
    worker
    orchestrator
    phase-qa-spec
    phase-repo-spec
    phase-plan
    phase-implement
    phase-cleanup
    finalize-spec
    finalize-section
)

skill_path() {
    echo "${BATS_TEST_DIRNAME}/../../skills/${1}/SKILL.md"
}

# Heading-substring assertion: a Markdown heading line (one or more leading '#')
# that contains the given substring (case-sensitive).
assert_doc_heading() {
    run grep -E "^#+ .*${1}" "${DOC}"
    [ "$status" -eq 0 ]
}

# --- doc existence ----------------------------------------------------------

@test "shared/design-principles.md exists" {
    [ -f "${DOC}" ]
}

# --- F-35 documented (principle + 5 corollaries) ----------------------------

@test "documents F-35 as a principle heading" {
    assert_doc_heading "F-35"
}

@test "F-35 corollary: skills-first correction" {
    run grep -Ei "skills-first correction" "${DOC}"
    [ "$status" -eq 0 ]
}

@test "F-35 corollary: memory-as-signal" {
    run grep -Ei "memory-as-signal" "${DOC}"
    [ "$status" -eq 0 ]
}

@test "F-35 corollary: durability test" {
    run grep -Ei "durability test" "${DOC}"
    [ "$status" -eq 0 ]
}

@test "F-35 corollary: memory-appropriate scope" {
    run grep -Ei "memory[- ]appropriate scope" "${DOC}"
    [ "$status" -eq 0 ]
}

@test "F-35 corollary: review guard" {
    run grep -Ei "review guard" "${DOC}"
    [ "$status" -eq 0 ]
}

# --- F-36 documented (principle + rubric + rationalizations) ----------------

@test "documents F-36 as a principle heading" {
    assert_doc_heading "F-36"
}

@test "F-36 documents the 4-question decision rubric" {
    run grep -Ei "4-question|four-question|decision rubric" "${DOC}"
    [ "$status" -eq 0 ]
}

@test "F-36 documents the Rationalizations-to-Reject table" {
    run grep -F "Rationalizations-to-Reject" "${DOC}"
    [ "$status" -eq 0 ]
}

@test "F-36 documents the pause-only-for gate list" {
    run grep -Ei "explicit gate" "${DOC}"
    [ "$status" -eq 0 ]
    run grep -Ei "breaking error" "${DOC}"
    [ "$status" -eq 0 ]
    run grep -Ei "deviation from (the )?plan" "${DOC}"
    [ "$status" -eq 0 ]
}

# --- placeholder collection (cluster 4n #4) ---------------------------------

@test "documents the placeholder collection of other principles" {
    run grep -Ei "coordination-vs-durability|coordination vs durability" "${DOC}"
    [ "$status" -eq 0 ]
    run grep -Ei "authority hierarchy" "${DOC}"
    [ "$status" -eq 0 ]
    run grep -Ei "verify-before-claim|verify before claim" "${DOC}"
    [ "$status" -eq 0 ]
    run grep -Ei "atomic state transition" "${DOC}"
    [ "$status" -eq 0 ]
}

# --- xfleet-scoped / no CLAUDE.md duplication (cluster 4n #5) ----------------

@test "documents that the doc is xfleet-scoped (not duplicated into CLAUDE.md)" {
    run grep -Ei "xfleet-scoped|xfleet scoped" "${DOC}"
    [ "$status" -eq 0 ]
}

# --- path notation: no hardcoded coordination paths -------------------------

@test "does not hardcode merlin-ai/.xfleet/ coordination path" {
    run grep -F "merlin-ai/.xfleet/" "${DOC}"
    [ "$status" -ne 0 ]
}

@test "does not mention retired send.sh transport" {
    run grep -F "send.sh" "${DOC}"
    [ "$status" -ne 0 ]
}

# --- per-skill Protocol cross-references (all 9) ----------------------------

@test "every skill has a ## Protocol section (pinned literal)" {
    for s in "${SKILLS[@]}"; do
        grep -Fq "## Protocol" "$(skill_path "$s")" \
            || { echo "missing ## Protocol in $s"; return 1; }
    done
}

@test "every skill references shared/design-principles.md" {
    for s in "${SKILLS[@]}"; do
        grep -Fq "shared/design-principles.md" "$(skill_path "$s")" \
            || { echo "missing design-principles.md ref in $s"; return 1; }
    done
}

@test "no skill still carries the forthcoming; Task 13 qualifier" {
    for s in "${SKILLS[@]}"; do
        if grep -Fq "forthcoming; Task 13" "$(skill_path "$s")"; then
            echo "stale forthcoming qualifier in $s"
            return 1
        fi
    done
}

@test "no skill still carries once-it-lands future-tense framing" {
    for s in "${SKILLS[@]}"; do
        if grep -Fq "once it lands" "$(skill_path "$s")"; then
            echo "stale 'once it lands' framing in $s"
            return 1
        fi
    done
}
