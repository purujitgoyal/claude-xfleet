#!/usr/bin/env bats
# validate-state.bats — BATS tests for tools/xfleet/validate-state.sh (Task 18).
#
# tests/state-validator/ is two levels below the repo root, so:
#   BATS_TEST_DIRNAME = <repo>/tests/state-validator
#   ../../tools/xfleet/validate-state.sh = <repo>/tools/xfleet/validate-state.sh
#
# The script signature:
#   validate-state.sh <state-file> [<schema-file>] [orchestrator|worker]
#
# Exit codes:
#   0  = valid
#   1  = validation failure (bad key, bad value, missing required field)
#   2  = malformed JSON / unreadable file
#   3  = schema_version missing or not "1"
#
# Scenarios:
#   (a) valid orchestrator state file                     → exit 0, no output
#   (b) unknown top-level key in orchestrator             → exit 1, unknown key + suggestion
#   (c) unknown nested key inside human_engaged           → exit 1, path in output
#   (d) malformed JSON                                    → exit 2, parse error in output
#   (e) missing schema_version field                      → exit 3, version-error message
#   (f) schema_version "99" (unknown future version)      → exit 3, version-error message
#   (g) valid worker state file                           → exit 0, no output
#   (h) unknown top-level key in worker                   → exit 1, unknown key in output
#   (i) basename-based type inference (_orchestrator.json) → routes correctly
#   (j) unknown key far from every known key                → exit 1, no suggestion
#   (M-3) bad key at the third level of phase_emissions     → exit 1, path components

bats_require_minimum_version 1.5.0

SCRIPT="${BATS_TEST_DIRNAME}/../../tools/xfleet/validate-state.sh"
SCHEMA="${BATS_TEST_DIRNAME}/../../tools/xfleet/state-schema.json"

# Write a string to a temp file; print the path.
write_tmp() {
    local name="$1"
    local content="$2"
    local path="${BATS_TMPDIR}/${name}"
    printf '%s' "${content}" > "${path}"
    printf '%s' "${path}"
}

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# Minimal valid orchestrator state (matches schema $defs/orchestrator).
VALID_ORCHESTRATOR='{
  "schema_version": "1",
  "cycles": 0,
  "last_all_idle_notify": null,
  "last_round5_pause": null,
  "human_engaged": {
    "active": false,
    "concern_id": null,
    "set_at": null,
    "reason": null
  }
}'

# Minimal valid worker state (matches schema $defs/worker).
VALID_WORKER='{
  "schema_version": "1",
  "current_phase": "idle",
  "status": "idle",
  "current_task": null,
  "last_updated": "2026-05-31T10:00:00Z",
  "context_pct": 20
}'

# ---------------------------------------------------------------------------
# Guard: script exists and is executable
# ---------------------------------------------------------------------------

@test "validate-state.sh exists and is executable" {
    [ -f "${SCRIPT}" ]
    [ -x "${SCRIPT}" ]
}

# ---------------------------------------------------------------------------
# (a) Valid orchestrator file → exit 0
# ---------------------------------------------------------------------------

@test "(a) valid orchestrator state: exit 0" {
    state="$(write_tmp "_orchestrator.json" "${VALID_ORCHESTRATOR}")"
    run bash "${SCRIPT}" "${state}" "${SCHEMA}" orchestrator
    [ "$status" -eq 0 ]
}

@test "(a) valid orchestrator state: no output on success" {
    state="$(write_tmp "_orchestrator.json" "${VALID_ORCHESTRATOR}")"
    run bash "${SCRIPT}" "${state}" "${SCHEMA}" orchestrator
    [ -z "${output}" ]
}

# ---------------------------------------------------------------------------
# (b) Unknown top-level key in orchestrator → exit 1, key + suggestion in output
# ---------------------------------------------------------------------------

@test "(b) unknown top-level key in orchestrator: exit 1" {
    bad='{
      "schema_version": "1",
      "cycles": 0,
      "bogus_top_key": "oops"
    }'
    state="$(write_tmp "_orchestrator.json" "${bad}")"
    run bash "${SCRIPT}" "${state}" "${SCHEMA}" orchestrator
    [ "$status" -eq 1 ]
}

@test "(b) unknown top-level key in orchestrator: output names the unknown key" {
    bad='{
      "schema_version": "1",
      "cycles": 0,
      "bogus_top_key": "oops"
    }'
    state="$(write_tmp "_orchestrator.json" "${bad}")"
    run bash "${SCRIPT}" "${state}" "${SCHEMA}" orchestrator
    [[ "${output}" =~ "bogus_top_key" ]]
}

@test "(b) unknown top-level key in orchestrator: output includes a did-you-mean suggestion" {
    # 'cyclez' is one edit from 'cycles'
    bad='{
      "schema_version": "1",
      "cyclez": 0
    }'
    state="$(write_tmp "_orchestrator.json" "${bad}")"
    run bash "${SCRIPT}" "${state}" "${SCHEMA}" orchestrator
    [ "$status" -eq 1 ]
    [[ "${output}" =~ "did you mean" ]]
    [[ "${output}" =~ "cycles" ]]
}

# ---------------------------------------------------------------------------
# (c) Unknown nested key inside human_engaged → exit 1, path in output
# ---------------------------------------------------------------------------

@test "(c) unknown nested key inside human_engaged: exit 1" {
    bad='{
      "schema_version": "1",
      "human_engaged": {
        "active": false,
        "concern_id": null,
        "set_at": null,
        "reason": null,
        "bogus_nested": "nope"
      }
    }'
    state="$(write_tmp "_orchestrator.json" "${bad}")"
    run bash "${SCRIPT}" "${state}" "${SCHEMA}" orchestrator
    [ "$status" -eq 1 ]
}

@test "(c) unknown nested key inside human_engaged: output names the nested path" {
    bad='{
      "schema_version": "1",
      "human_engaged": {
        "active": false,
        "concern_id": null,
        "set_at": null,
        "reason": null,
        "bogus_nested": "nope"
      }
    }'
    state="$(write_tmp "_orchestrator.json" "${bad}")"
    run bash "${SCRIPT}" "${state}" "${SCHEMA}" orchestrator
    [[ "${output}" =~ "bogus_nested" ]]
    [[ "${output}" =~ "human_engaged" ]]
}

# ---------------------------------------------------------------------------
# (d) Malformed JSON → exit 2, parse error description in output
# ---------------------------------------------------------------------------

@test "(d) malformed JSON: exit 2" {
    state="$(write_tmp "_orchestrator.json" "{ not valid json !!!")"
    run bash "${SCRIPT}" "${state}" "${SCHEMA}" orchestrator
    [ "$status" -eq 2 ]
}

@test "(d) malformed JSON: output describes parse error" {
    state="$(write_tmp "_orchestrator.json" "{ not valid json !!!")"
    run bash "${SCRIPT}" "${state}" "${SCHEMA}" orchestrator
    [[ "${output}" =~ [Pp]arse ]] || [[ "${output}" =~ [Jj][Ss][Oo][Nn] ]] || [[ "${output}" =~ [Mm]alformed ]]
}

# ---------------------------------------------------------------------------
# (e) Missing schema_version → exit 3, version-error message
# ---------------------------------------------------------------------------

@test "(e) missing schema_version: exit 3" {
    bad='{
      "cycles": 0
    }'
    state="$(write_tmp "_orchestrator.json" "${bad}")"
    run bash "${SCRIPT}" "${state}" "${SCHEMA}" orchestrator
    [ "$status" -eq 3 ]
}

@test "(e) missing schema_version: output includes version-error message" {
    bad='{
      "cycles": 0
    }'
    state="$(write_tmp "_orchestrator.json" "${bad}")"
    run bash "${SCRIPT}" "${state}" "${SCHEMA}" orchestrator
    [[ "${output}" =~ "schema_version" ]]
}

@test "(e) missing schema_version: output mentions current plugin supports v1" {
    bad='{
      "cycles": 0
    }'
    state="$(write_tmp "_orchestrator.json" "${bad}")"
    run bash "${SCRIPT}" "${state}" "${SCHEMA}" orchestrator
    [[ "${output}" =~ "v1" ]] || [[ "${output}" =~ "version" ]]
}

# ---------------------------------------------------------------------------
# (f) schema_version "99" (unknown future version) → exit 3
# ---------------------------------------------------------------------------

@test "(f) schema_version 99 in orchestrator: exit 3" {
    bad='{
      "schema_version": "99",
      "cycles": 0
    }'
    state="$(write_tmp "_orchestrator.json" "${bad}")"
    run bash "${SCRIPT}" "${state}" "${SCHEMA}" orchestrator
    [ "$status" -eq 3 ]
}

@test "(f) schema_version 99 in orchestrator: output includes version-error message" {
    bad='{
      "schema_version": "99",
      "cycles": 0
    }'
    state="$(write_tmp "_orchestrator.json" "${bad}")"
    run bash "${SCRIPT}" "${state}" "${SCHEMA}" orchestrator
    [[ "${output}" =~ "schema_version" ]] || [[ "${output}" =~ "version" ]]
}

@test "(f) schema_version 99 in worker: exit 3" {
    bad='{
      "schema_version": "99",
      "current_phase": "idle",
      "status": "idle"
    }'
    state="$(write_tmp "my-worker.json" "${bad}")"
    run bash "${SCRIPT}" "${state}" "${SCHEMA}" worker
    [ "$status" -eq 3 ]
}

# ---------------------------------------------------------------------------
# (g) Valid worker state file → exit 0
# ---------------------------------------------------------------------------

@test "(g) valid worker state: exit 0" {
    state="$(write_tmp "my-worker.json" "${VALID_WORKER}")"
    run bash "${SCRIPT}" "${state}" "${SCHEMA}" worker
    [ "$status" -eq 0 ]
}

@test "(g) valid worker state: no output on success" {
    state="$(write_tmp "my-worker.json" "${VALID_WORKER}")"
    run bash "${SCRIPT}" "${state}" "${SCHEMA}" worker
    [ -z "${output}" ]
}

# ---------------------------------------------------------------------------
# (h) Unknown top-level key in worker → exit 1, key in output
# ---------------------------------------------------------------------------

@test "(h) unknown top-level key in worker: exit 1" {
    bad='{
      "schema_version": "1",
      "status": "idle",
      "unknown_worker_key": "bad"
    }'
    state="$(write_tmp "my-worker.json" "${bad}")"
    run bash "${SCRIPT}" "${state}" "${SCHEMA}" worker
    [ "$status" -eq 1 ]
}

@test "(h) unknown top-level key in worker: output names the unknown key" {
    bad='{
      "schema_version": "1",
      "status": "idle",
      "unknown_worker_key": "bad"
    }'
    state="$(write_tmp "my-worker.json" "${bad}")"
    run bash "${SCRIPT}" "${state}" "${SCHEMA}" worker
    [[ "${output}" =~ "unknown_worker_key" ]]
}

# ---------------------------------------------------------------------------
# (i) Basename-based type inference: _orchestrator.json → orchestrator def
# ---------------------------------------------------------------------------

@test "(i) basename _orchestrator.json auto-infers orchestrator type (valid passes)" {
    # Write to a path whose basename IS _orchestrator.json
    state="${BATS_TMPDIR}/_orchestrator.json"
    printf '%s' "${VALID_ORCHESTRATOR}" > "${state}"
    # No explicit type arg — inferred from basename
    run bash "${SCRIPT}" "${state}" "${SCHEMA}"
    [ "$status" -eq 0 ]
}

@test "(i) basename _orchestrator.json auto-infers orchestrator type (invalid fails)" {
    bad='{
      "schema_version": "1",
      "bogus_inferred_key": "bad"
    }'
    state="${BATS_TMPDIR}/_orchestrator.json"
    printf '%s' "${bad}" > "${state}"
    run bash "${SCRIPT}" "${state}" "${SCHEMA}"
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# (j) Unknown key far from every known key → exit 1, NO did-you-mean suggestion
# ---------------------------------------------------------------------------

@test "(j) unknown key far from all known keys: exit 1, names key, suppresses suggestion" {
    bad='{
      "schema_version": "1",
      "zzqqxx_nonsense": 1
    }'
    state="$(write_tmp "_orchestrator.json" "${bad}")"
    run bash "${SCRIPT}" "${state}" "${SCHEMA}" orchestrator
    [ "$status" -eq 1 ]
    [[ "${output}" =~ "zzqqxx_nonsense" ]]
    [[ ! "${output}" =~ "did you mean" ]]
}

# ---------------------------------------------------------------------------
# (M-3) Bad key at the THIRD level of phase_emissions (map-in-map-in-map) →
#       exit 1, reported path includes the phase/signal components.
# ---------------------------------------------------------------------------

@test "(M-3) unknown key at third level of phase_emissions: exit 1, path includes phase/signal" {
    bad='{
      "schema_version": "1",
      "phase_emissions": {
        "plan": {
          "phase-complete": {
            "approved_by_human": true,
            "sent_at": "2026-05-31T10:00:00Z",
            "sent_to": ["server"],
            "emission_id": "emit-1",
            "bogus_deep_key": "nope"
          }
        }
      }
    }'
    state="$(write_tmp "_orchestrator.json" "${bad}")"
    run bash "${SCRIPT}" "${state}" "${SCHEMA}" orchestrator
    [ "$status" -eq 1 ]
    [[ "${output}" =~ "bogus_deep_key" ]]
    [[ "${output}" =~ "phase_emissions" ]]
    [[ "${output}" =~ "plan" ]]
    [[ "${output}" =~ "phase-complete" ]]
}
