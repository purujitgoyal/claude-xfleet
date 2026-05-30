#!/usr/bin/env bats
# Doc-structure tests for shared/worker-config-schema.md (Task 15).
#
# tests/docs/ is two levels below the repo root, so:
#   BATS_TEST_DIRNAME = <repo>/tests/docs
#   ../../shared/worker-config-schema.md = <repo>/shared/worker-config-schema.md
#
# These tests verify:
#   (1) The schema doc exists and documents all 6 required fields with their
#       types, required/optional status, and the architect-review default.
#   (2) The intensity enum (standard/high/critical) and per-phase override
#       defaults (cluster 4a) are documented.
#   (3) A fixture sample worker-config.md conforms to the documented schema:
#       every required field appears, and the intensity value is within the
#       documented enum.
#   (4) The doc records the cluster 4m design decisions: architect-review as
#       canonical reviewer, prd-review staying separate, /code-review as
#       third-party, and `critical` as the top intensity term.

bats_require_minimum_version 1.5.0

DOC="${BATS_TEST_DIRNAME}/../../shared/worker-config-schema.md"

# ---------------------------------------------------------------------------
# Fixtures — a minimal but complete valid worker-config.md sample.
# Written to a temp file so tests that verify schema conformance are
# self-contained (no dependency on out-of-repo personal worker-config files).
# ---------------------------------------------------------------------------

FIXTURE_CONTENT='name: my-repo
language: python
convention_files:
  - docs/conventions.md
  - docs/style-guide.md
reviewers:
  - agent: architect-review
    intensity: high
additional_skills:
  - capture-decision
repo_specific_context: |
  Primary service. FastAPI + PostgreSQL.
  Uses the standard merlin auth middleware.
'

# Literal-heading assertion: the doc must contain the given Markdown heading
# line verbatim (load-bearing structural anchors).
assert_doc_heading() {
    grep -Fq "${1}" "${DOC}"
}

# ---------------------------------------------------------------------------
# Existence
# ---------------------------------------------------------------------------

@test "shared/worker-config-schema.md exists" {
    [ -f "${DOC}" ]
}

@test "has the ## Schema Fields structural heading" {
    assert_doc_heading "## Schema Fields"
}

@test "has the ## Per-Phase Intensity Defaults structural heading" {
    assert_doc_heading "## Per-Phase Intensity Defaults"
}

# ---------------------------------------------------------------------------
# All 6 schema fields are documented
# ---------------------------------------------------------------------------

@test "documents the name: field" {
    run grep -F "name:" "${DOC}"
    [ "$status" -eq 0 ]
}

@test "documents the language: field" {
    run grep -F "language:" "${DOC}"
    [ "$status" -eq 0 ]
}

@test "documents the convention_files: field" {
    run grep -F "convention_files:" "${DOC}"
    [ "$status" -eq 0 ]
}

@test "documents the reviewers: field" {
    run grep -F "reviewers:" "${DOC}"
    [ "$status" -eq 0 ]
}

@test "documents the additional_skills: field" {
    run grep -F "additional_skills:" "${DOC}"
    [ "$status" -eq 0 ]
}

@test "documents the repo_specific_context: field" {
    run grep -F "repo_specific_context:" "${DOC}"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Default reviewer is architect-review at high intensity
# ---------------------------------------------------------------------------

@test "documents architect-review as the default reviewer agent" {
    run grep -F "architect-review" "${DOC}"
    [ "$status" -eq 0 ]
}

@test "documents the default intensity as high" {
    # Must mention 'high' as the default — not just as an enum member.
    # We assert 'high' appears alongside 'default' in the doc.
    run grep -Ei "default.*high|high.*default" "${DOC}"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Intensity enum: standard / high / critical — all three documented
# ---------------------------------------------------------------------------

@test "documents standard as an intensity enum value" {
    run grep -Ei "\bstandard\b" "${DOC}"
    [ "$status" -eq 0 ]
}

@test "documents high as an intensity enum value" {
    run grep -Ei "\bhigh\b" "${DOC}"
    [ "$status" -eq 0 ]
}

@test "documents critical as an intensity enum value" {
    run grep -Ei "\bcritical\b" "${DOC}"
    [ "$status" -eq 0 ]
}

@test "documents critical as the top intensity term (not extreme)" {
    # Cluster 4m locks: keep 'critical' — F-20's informal 'extreme' is NOT used.
    run grep -Ei "\bextreme\b" "${DOC}"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Per-phase intensity defaults (cluster 4a graduated policy)
# ---------------------------------------------------------------------------

# Each per-phase test pins the phase name TO its intensity on the same bullet
# (exact doc form: `<phase>` phase: `<intensity>`), so flipping the documented
# intensity would fail the test. A loose "both tokens appear somewhere" grep
# would false-positive (e.g. the repo-spec bullet's "post-implementation passes
# drop to standard" contains both "implement" and "standard").

@test "documents qa-spec phase with critical intensity" {
    run grep -F '`qa-spec` phase: `critical`' "${DOC}"
    [ "$status" -eq 0 ]
}

@test "documents repo-spec phase with high intensity" {
    run grep -F '`repo-spec` phase: `high`' "${DOC}"
    [ "$status" -eq 0 ]
}

@test "documents plan phase with standard intensity" {
    run grep -F '`plan` phase: `standard`' "${DOC}"
    [ "$status" -eq 0 ]
}

@test "documents implement phase with standard intensity" {
    run grep -F '`implement` phase: `standard`' "${DOC}"
    [ "$status" -eq 0 ]
}

@test "documents cleanup phase with standard intensity" {
    run grep -F '`cleanup` phase: `standard`' "${DOC}"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Cluster 4m design decisions
# ---------------------------------------------------------------------------

@test "documents architect-review as the canonical phase reviewer (cluster 4m point 1)" {
    run grep -Ei "canonical.*architect-review|architect-review.*canonical" "${DOC}"
    [ "$status" -eq 0 ]
}

@test "documents that prd-review stays separate (cluster 4m point 2)" {
    run grep -F "prd-review" "${DOC}"
    [ "$status" -eq 0 ]
}

@test "documents that /code-review is a separate third-party surface (cluster 4m point 3)" {
    run grep -Ei "code-review|/code-review" "${DOC}"
    [ "$status" -eq 0 ]
}

@test "documents the layering: worker-config default overridden by phase-skill" {
    run grep -Ei "override|overrid" "${DOC}"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Path notation: no hardcoded coordination paths
# ---------------------------------------------------------------------------

@test "does not hardcode merlin-ai/.xfleet/ coordination path" {
    run grep -F "merlin-ai/.xfleet/" "${DOC}"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Fixture conformance: validate a sample worker-config against the schema
# ---------------------------------------------------------------------------

# Helper: write the fixture to a temp file and return the path.
# BATS_TMPDIR is provided by the BATS runtime.
write_fixture() {
    local tmp_file="${BATS_TMPDIR}/sample-worker-config.md"
    printf '%s' "${FIXTURE_CONTENT}" > "${tmp_file}"
    echo "${tmp_file}"
}

@test "fixture contains the name: field" {
    local f
    f="$(write_fixture)"
    run grep -E "^name:" "${f}"
    [ "$status" -eq 0 ]
    # Value must be non-empty (not just the key).
    [[ "${output}" =~ name:\ .+ ]]
}

@test "fixture contains the language: field" {
    local f
    f="$(write_fixture)"
    run grep -E "^language:" "${f}"
    [ "$status" -eq 0 ]
    [[ "${output}" =~ language:\ .+ ]]
}

@test "fixture contains the reviewers: field" {
    local f
    f="$(write_fixture)"
    run grep -E "^reviewers:" "${f}"
    [ "$status" -eq 0 ]
}

@test "fixture reviewers block contains agent: architect-review" {
    local f
    f="$(write_fixture)"
    run grep -F "agent: architect-review" "${f}"
    [ "$status" -eq 0 ]
}

@test "fixture intensity value is within the documented enum (standard|high|critical)" {
    local f
    f="$(write_fixture)"
    # Guard against vacuous pass: a fixture that dropped the reviewers: block
    # would have zero intensity: lines, the loop body would never run, and the
    # test would pass. Require at least one intensity: line first.
    local count
    count="$(grep -c "intensity:" "${f}")"
    [ "${count}" -gt 0 ]
    # Assert every intensity: value is a valid enum member.
    while IFS= read -r line; do
        local val
        val="$(printf '%s' "${line}" | sed 's/.*intensity:[[:space:]]*//')"
        case "${val}" in
            standard|high|critical) ;;
            *) echo "Invalid intensity value: '${val}'" >&2; return 1 ;;
        esac
    done < <(grep -E "intensity:" "${f}")
}

@test "fixture contains convention_files: field" {
    local f
    f="$(write_fixture)"
    run grep -E "^convention_files:" "${f}"
    [ "$status" -eq 0 ]
}

@test "fixture contains additional_skills: field" {
    local f
    f="$(write_fixture)"
    run grep -E "^additional_skills:" "${f}"
    [ "$status" -eq 0 ]
}

@test "fixture contains repo_specific_context: field" {
    local f
    f="$(write_fixture)"
    run grep -E "^repo_specific_context:" "${f}"
    [ "$status" -eq 0 ]
}
