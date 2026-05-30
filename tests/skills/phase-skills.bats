#!/usr/bin/env bats
# Metadata + section-presence tests for the five phase skills (Task 10):
#   skills/phase-qa-spec/SKILL.md
#   skills/phase-repo-spec/SKILL.md
#   skills/phase-plan/SKILL.md
#   skills/phase-implement/SKILL.md
#   skills/phase-cleanup/SKILL.md
#
# tests/skills/ is two levels below the repo root, so:
#   BATS_TEST_DIRNAME = <repo>/tests/skills
#   ../../skills/phase-*/SKILL.md = <repo>/skills/phase-*/SKILL.md
#
# Asserts each phase skill carries the metadata block (warn_at / critical_at /
# review_intensity), a recognizable entry step, the corrected threshold +
# intensity VALUES (so a regression is caught), and the two shared-doc
# cross-references (design-principles.md is a forward reference to Task 13).

bats_require_minimum_version 1.5.0

SKILLS_DIR="${BATS_TEST_DIRNAME}/../../skills"

# Asserts a frontmatter key is present in the given SKILL.md.
assert_key() {
    run grep -E "^${2}:" "${SKILLS_DIR}/${1}/SKILL.md"
    [ "$status" -eq 0 ]
}

# Asserts an exact "key: value" line is present WITHIN the YAML frontmatter
# block (between the first two `---` delimiters), so a future body-prose line
# starting at column 0 can't falsely satisfy a threshold assertion.
assert_kv() {
    # Match the exact value to end-of-line ([[:space:]]*$) instead of \b, which
    # BSD awk does not support; this still rejects 7 != 70 and 70 != 700.
    run awk '/^---/{c++} c==1 && /^'"${2}"': *'"${3}"'[[:space:]]*$/' "${SKILLS_DIR}/${1}/SKILL.md"
    [ "${#lines[@]}" -gt 0 ]
}

# --- existence -------------------------------------------------------------

@test "phase-qa-spec SKILL.md exists" {
    [ -f "${SKILLS_DIR}/phase-qa-spec/SKILL.md" ]
}

@test "phase-repo-spec SKILL.md exists" {
    [ -f "${SKILLS_DIR}/phase-repo-spec/SKILL.md" ]
}

@test "phase-plan SKILL.md exists" {
    [ -f "${SKILLS_DIR}/phase-plan/SKILL.md" ]
}

@test "phase-implement SKILL.md exists" {
    [ -f "${SKILLS_DIR}/phase-implement/SKILL.md" ]
}

@test "phase-cleanup SKILL.md exists" {
    [ -f "${SKILLS_DIR}/phase-cleanup/SKILL.md" ]
}

# --- metadata keys present on all five --------------------------------------

@test "phase-qa-spec declares warn_at/critical_at/review_intensity" {
    assert_key phase-qa-spec warn_at
    assert_key phase-qa-spec critical_at
    assert_key phase-qa-spec review_intensity
}

@test "phase-repo-spec declares warn_at/critical_at/review_intensity" {
    assert_key phase-repo-spec warn_at
    assert_key phase-repo-spec critical_at
    assert_key phase-repo-spec review_intensity
}

@test "phase-plan declares warn_at/critical_at/review_intensity" {
    assert_key phase-plan warn_at
    assert_key phase-plan critical_at
    assert_key phase-plan review_intensity
}

@test "phase-implement declares warn_at/critical_at/review_intensity" {
    assert_key phase-implement warn_at
    assert_key phase-implement critical_at
    assert_key phase-implement review_intensity
}

@test "phase-cleanup declares warn_at/critical_at/review_intensity" {
    assert_key phase-cleanup warn_at
    assert_key phase-cleanup critical_at
    assert_key phase-cleanup review_intensity
}

# --- context_heavy marker present on all five (may be empty list) -----------

@test "every phase skill declares a context_heavy marker" {
    for s in phase-qa-spec phase-repo-spec phase-plan phase-implement phase-cleanup; do
        run grep -E "^context_heavy:" "${SKILLS_DIR}/${s}/SKILL.md"
        [ "$status" -eq 0 ] || { echo "FAILED for skill: $s"; false; }
    done
}

# --- corrected threshold + intensity VALUES (regression guards) -------------
# Default phases are 70/80; only repo-spec drops to 50/65.
# qa-spec is the only default-threshold phase with critical intensity.

@test "phase-qa-spec values: warn 70, critical 80, intensity critical" {
    assert_kv phase-qa-spec warn_at 70
    assert_kv phase-qa-spec critical_at 80
    assert_kv phase-qa-spec review_intensity critical
}

@test "phase-repo-spec values: warn 50, critical 65, intensity high" {
    assert_kv phase-repo-spec warn_at 50
    assert_kv phase-repo-spec critical_at 65
    assert_kv phase-repo-spec review_intensity high
}

@test "phase-plan values: warn 70, critical 80, intensity standard" {
    assert_kv phase-plan warn_at 70
    assert_kv phase-plan critical_at 80
    assert_kv phase-plan review_intensity standard
}

@test "phase-implement values: warn 70, critical 80, intensity standard" {
    assert_kv phase-implement warn_at 70
    assert_kv phase-implement critical_at 80
    assert_kv phase-implement review_intensity standard
}

@test "phase-cleanup values: warn 70, critical 80, intensity standard" {
    assert_kv phase-cleanup warn_at 70
    assert_kv phase-cleanup critical_at 80
    assert_kv phase-cleanup review_intensity standard
}

# --- entry step present (stable "## Entry" heading across all five) ----------

@test "every phase skill has an Entry heading" {
    for s in phase-qa-spec phase-repo-spec phase-plan phase-implement phase-cleanup; do
        run grep -E "^#+ .*Entry" "${SKILLS_DIR}/${s}/SKILL.md"
        [ "$status" -eq 0 ] || { echo "FAILED for skill: $s"; false; }
    done
}

# --- exit step present (## Exit heading) ------------------------------------

@test "every phase skill has an Exit heading" {
    for s in phase-qa-spec phase-repo-spec phase-plan phase-implement phase-cleanup; do
        run grep -E "^#+ .*Exit" "${SKILLS_DIR}/${s}/SKILL.md"
        [ "$status" -eq 0 ] || { echo "FAILED for skill: $s"; false; }
    done
}

# --- shared-doc cross-references on all five ---------------------------------

@test "every phase skill references shared/design-principles.md" {
    for s in phase-qa-spec phase-repo-spec phase-plan phase-implement phase-cleanup; do
        run grep -F "shared/design-principles.md" "${SKILLS_DIR}/${s}/SKILL.md"
        [ "$status" -eq 0 ] || { echo "FAILED for skill: $s"; false; }
    done
}

@test "every phase skill references shared/messaging.md" {
    for s in phase-qa-spec phase-repo-spec phase-plan phase-implement phase-cleanup; do
        run grep -F "shared/messaging.md" "${SKILLS_DIR}/${s}/SKILL.md"
        [ "$status" -eq 0 ] || { echo "FAILED for skill: $s"; false; }
    done
}

# --- third-person trigger-phrase description on all five --------------------

@test "every phase skill description uses third-person trigger form" {
    for s in phase-qa-spec phase-repo-spec phase-plan phase-implement phase-cleanup; do
        run grep -E "Use when entering" "${SKILLS_DIR}/${s}/SKILL.md"
        [ "$status" -eq 0 ] || { echo "FAILED for skill: $s"; false; }
    done
}
