#!/usr/bin/env bats
# Section-presence tests for skills/explore/SKILL.md (exploration mode).
#
# tests/skills/ is two levels below the repo root, so:
#   BATS_TEST_DIRNAME = <repo>/tests/skills
#   ../../skills/explore/SKILL.md = <repo>/skills/explore/SKILL.md
#
# Asserts the explore responder skill carries its load-bearing invariants:
# frontmatter, the await/answer/reply_to wiring, the read-only refusal rule,
# and the absence of orchestrated-mode machinery (coordination root, phases,
# escalation).

bats_require_minimum_version 1.5.0

SKILL="${BATS_TEST_DIRNAME}/../../skills/explore/SKILL.md"

@test "skills/explore/SKILL.md exists" {
    [ -f "${SKILL}" ]
}

@test "frontmatter declares name: explore" {
    run grep -E "^name: *explore" "${SKILL}"
    [ "$status" -eq 0 ]
}

@test "frontmatter description is third-person trigger-phrase form" {
    run grep -E "Use when|This skill should be used when" "${SKILL}"
    [ "$status" -eq 0 ]
}

# --- park-loop wiring --------------------------------------------------------

@test "body references xfleet await" {
    grep -Fq "xfleet await" "${SKILL}"
}

@test "body references xfleet answer" {
    grep -Fq "xfleet answer" "${SKILL}"
}

@test "body references the reply_to field" {
    grep -Fq "reply_to" "${SKILL}"
}

@test "body runs await via run_in_background" {
    grep -Fq "run_in_background" "${SKILL}"
}

@test "body references --unpark for shutdown" {
    grep -Fq -- "--unpark" "${SKILL}"
}

@test "body warns against bare --timeout-less await only in background (no foreground park)" {
    # The park loop must use the background mechanism, never a foreground block.
    run grep -E "run_in_background.*true|run_in_background: true" "${SKILL}"
    [ "$status" -eq 0 ]
}

# --- read-only discipline ----------------------------------------------------

@test "body contains the read-only refusal rule" {
    grep -Fq "exploration mode is read-only" "${SKILL}"
}

@test "body declares the responder strictly read-only" {
    run grep -iE "read-only" "${SKILL}"
    [ "$status" -eq 0 ]
}

# --- orchestrated-mode machinery must be absent -------------------------------
# The only permitted mention of a coordination root is the SC-5 note explaining
# why --message-file is unavailable; phases and escalation must not appear.

@test "body does not reference XFLEET_COORDINATION_ROOT" {
    run grep -F "XFLEET_COORDINATION_ROOT" "${SKILL}"
    [ "$status" -ne 0 ]
}

@test "body does not reference phase machinery" {
    run grep -E "^.*xfleet phase|phase-complete" "${SKILL}"
    [ "$status" -ne 0 ]
}

@test "body does not reference escalation" {
    run grep -iE "xfleet escalation" "${SKILL}"
    [ "$status" -ne 0 ]
}
