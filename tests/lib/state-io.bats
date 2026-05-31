#!/usr/bin/env bats
# state-io.bats — BATS tests for tools/xfleet/lib/state-io.sh (Task 19).
#
# tests/lib/ is two levels below the repo root, so:
#   BATS_TEST_DIRNAME = <repo>/tests/lib
#   ../../tools/xfleet/lib/state-io.sh = <repo>/tools/xfleet/lib/state-io.sh
#
# Orchestrator test files use "_orchestrator.json" as the basename (matching
# the inference rule in validate-state.sh and state-io.sh). Worker test files
# use arbitrary names (any basename other than _orchestrator.json → worker).
#
# Scenarios covered:
#   (a) state_read returns valid JSON                               → exit 0, content matches
#   (b) state_write_atomic writes via tmp + mv                     → file written, content correct
#   (c) state_update_field applies a jq expression atomically      → field updated, JSON valid
#   (d) state_write_atomic refuses to write on validation failure  → non-zero exit, target unchanged
#   (e) concurrent writes last-writer-wins (C2)                    → second content wins, JSON valid
#   (f) torn reads do not occur (atomicity via tmp+mv)             → target only replaced by complete mv
#   (g) state_migrate_if_needed: v1 no-ops; v99 errors             → exit 0 for v1; exit 1+message for v99
#   (g2) state_migrate_if_needed: missing schema_version errors    → exit 1+message

bats_require_minimum_version 1.5.0

LIB="${BATS_TEST_DIRNAME}/../../tools/xfleet/lib/state-io.sh"
SCHEMA="${BATS_TEST_DIRNAME}/../../tools/xfleet/state-schema.json"
VALIDATE_SH="${BATS_TEST_DIRNAME}/../../tools/xfleet/validate-state.sh"

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

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

VALID_WORKER='{
  "schema_version": "1",
  "current_phase": "idle",
  "status": "idle",
  "current_task": null,
  "last_updated": "2026-05-31T10:00:00Z",
  "context_pct": 20
}'

# ---------------------------------------------------------------------------
# Guard: lib exists
# ---------------------------------------------------------------------------

@test "state-io.sh exists" {
    [ -f "${LIB}" ]
}

# ---------------------------------------------------------------------------
# (a) state_read: returns valid JSON from an existing file
# ---------------------------------------------------------------------------

@test "(a) state_read returns file contents" {
    # Orchestrator files must be named _orchestrator.json for inference.
    local target="${BATS_TMPDIR}/_orchestrator.json"
    printf '%s' "${VALID_ORCHESTRATOR}" > "${target}"
    run bash -c "source '${LIB}'; state_read '${target}'"
    [ "$status" -eq 0 ]
    # Output should be parseable JSON
    printf '%s' "${output}" | jq . > /dev/null
}

@test "(a) state_read content matches original" {
    local target="${BATS_TMPDIR}/_orchestrator.json"
    printf '%s' "${VALID_ORCHESTRATOR}" > "${target}"
    run bash -c "source '${LIB}'; state_read '${target}'"
    [ "$status" -eq 0 ]
    local schema_version
    schema_version="$(printf '%s' "${output}" | jq -r '.schema_version')"
    [ "${schema_version}" = "1" ]
}

@test "(a) state_read fails on missing file" {
    run bash -c "source '${LIB}'; state_read '/nonexistent/path/state.json'"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# (b) state_write_atomic: writes via tmp + mv, file has correct content
#
# Orchestrator files use "_orchestrator.json" so type inference resolves to
# the orchestrator schema def (matches validate-state.sh basename rule).
# ---------------------------------------------------------------------------

@test "(b) state_write_atomic creates orchestrator target file" {
    local dir="${BATS_TMPDIR}/b_create"
    mkdir -p "${dir}"
    local target="${dir}/_orchestrator.json"
    run bash -c "source '${LIB}'; state_write_atomic '${target}' '${VALID_ORCHESTRATOR}'"
    [ "$status" -eq 0 ]
    [ -f "${target}" ]
}

@test "(b) state_write_atomic writes correct orchestrator content" {
    local dir="${BATS_TMPDIR}/b_content"
    mkdir -p "${dir}"
    local target="${dir}/_orchestrator.json"
    run bash -c "source '${LIB}'; state_write_atomic '${target}' '${VALID_ORCHESTRATOR}'"
    [ "$status" -eq 0 ]
    local schema_version
    schema_version="$(jq -r '.schema_version' "${target}")"
    [ "${schema_version}" = "1" ]
}

@test "(b) state_write_atomic leaves no temp files in target dir" {
    # Fresh unique dir so a stale temp from a prior run cannot poison the
    # no-leak assertion (BATS_TMPDIR persists across runs).
    local dir
    dir="$(mktemp -d "${BATS_TMPDIR}/b_notmp.XXXXXX")"
    local target="${dir}/_orchestrator.json"
    run bash -c "source '${LIB}'; state_write_atomic '${target}' '${VALID_ORCHESTRATOR}'"
    [ "$status" -eq 0 ]
    # No .tmp.* files should remain in the target directory after successful write
    local tmp_count
    tmp_count="$(find "${dir}" -maxdepth 1 -name '.tmp.*' | wc -l | tr -d ' ')"
    [ "${tmp_count}" -eq 0 ]
}

@test "(b) state_write_atomic works for worker file" {
    local dir="${BATS_TMPDIR}/b_worker"
    mkdir -p "${dir}"
    local target="${dir}/myworker.json"
    run bash -c "source '${LIB}'; state_write_atomic '${target}' '${VALID_WORKER}'"
    [ "$status" -eq 0 ]
    [ -f "${target}" ]
    local status_val
    status_val="$(jq -r '.status' "${target}")"
    [ "${status_val}" = "idle" ]
}

# ---------------------------------------------------------------------------
# (c) state_update_field: applies jq expression, result is valid JSON
# ---------------------------------------------------------------------------

@test "(c) state_update_field updates a scalar field in orchestrator" {
    local dir="${BATS_TMPDIR}/c_update"
    mkdir -p "${dir}"
    local target="${dir}/_orchestrator.json"
    printf '%s' "${VALID_ORCHESTRATOR}" > "${target}"
    # Increment cycles from 0 to 1
    run bash -c "source '${LIB}'; state_update_field '${target}' '.cycles = 1'"
    [ "$status" -eq 0 ]
    local cycles
    cycles="$(jq -r '.cycles' "${target}")"
    [ "${cycles}" = "1" ]
}

@test "(c) state_update_field result is valid JSON" {
    local dir="${BATS_TMPDIR}/c_valid"
    mkdir -p "${dir}"
    local target="${dir}/_orchestrator.json"
    printf '%s' "${VALID_ORCHESTRATOR}" > "${target}"
    run bash -c "source '${LIB}'; state_update_field '${target}' '.cycles = 2'"
    [ "$status" -eq 0 ]
    jq . "${target}" > /dev/null
}

@test "(c) state_update_field on worker file" {
    local dir="${BATS_TMPDIR}/c_worker"
    mkdir -p "${dir}"
    local target="${dir}/myworker.json"
    printf '%s' "${VALID_WORKER}" > "${target}"
    run bash -c "source '${LIB}'; state_update_field '${target}' '.context_pct = 50'"
    [ "$status" -eq 0 ]
    local pct
    pct="$(jq -r '.context_pct' "${target}")"
    [ "${pct}" = "50" ]
}

@test "(c) state_update_field preserves other fields" {
    local dir="${BATS_TMPDIR}/c_preserve"
    mkdir -p "${dir}"
    local target="${dir}/_orchestrator.json"
    printf '%s' "${VALID_ORCHESTRATOR}" > "${target}"
    run bash -c "source '${LIB}'; state_update_field '${target}' '.cycles = 3'"
    [ "$status" -eq 0 ]
    local schema_version
    schema_version="$(jq -r '.schema_version' "${target}")"
    [ "${schema_version}" = "1" ]
}

# ---------------------------------------------------------------------------
# (d) state_write_atomic: refuses to write on validation failure.
#     Target file must remain UNCHANGED when validation rejects content.
#
# INVALID_CONTENT has bogus_unknown_key_xyz which is unknown in BOTH the
# orchestrator and worker schemas, so it fails regardless of inferred type.
# Files here also use _orchestrator.json to test orchestrator-type rejection.
# ---------------------------------------------------------------------------

# Intentionally minimal-invalid: a single unknown top-level key to trip the
# validator's additionalProperties=false rule. Not a realistic state shape —
# its only job is to make validate-state.sh return non-zero.
INVALID_CONTENT='{
  "schema_version": "1",
  "bogus_unknown_key_xyz": "bad"
}'

@test "(d) state_write_atomic returns non-zero on invalid orchestrator content" {
    local dir="${BATS_TMPDIR}/d_reject"
    mkdir -p "${dir}"
    local target="${dir}/_orchestrator.json"
    run bash -c "source '${LIB}'; state_write_atomic '${target}' '${INVALID_CONTENT}'"
    [ "$status" -ne 0 ]
}

@test "(d) state_write_atomic does not create target on validation failure (new file)" {
    local dir="${BATS_TMPDIR}/d_nocreate"
    mkdir -p "${dir}"
    local target="${dir}/_orchestrator.json"
    run bash -c "source '${LIB}'; state_write_atomic '${target}' '${INVALID_CONTENT}'"
    [ "$status" -ne 0 ]
    # Target must NOT be created when validation fails
    [ ! -f "${target}" ]
}

@test "(d) state_write_atomic leaves existing target UNCHANGED on validation failure" {
    local dir="${BATS_TMPDIR}/d_unchanged"
    mkdir -p "${dir}"
    local target="${dir}/_orchestrator.json"
    # Pre-write a valid state
    printf '%s' "${VALID_ORCHESTRATOR}" > "${target}"
    local original_cycles
    original_cycles="$(jq -r '.cycles' "${target}")"
    # Attempt invalid write
    run bash -c "source '${LIB}'; state_write_atomic '${target}' '${INVALID_CONTENT}'"
    [ "$status" -ne 0 ]
    # Target must still have original content
    [ -f "${target}" ]
    local current_cycles
    current_cycles="$(jq -r '.cycles' "${target}")"
    [ "${current_cycles}" = "${original_cycles}" ]
}

@test "(d) state_write_atomic does not leave temp files on validation failure" {
    # Use a fresh unique dir so a stale temp from a prior run cannot poison
    # the no-leak assertion (BATS_TMPDIR persists across runs).
    local dir
    dir="$(mktemp -d "${BATS_TMPDIR}/d_notmp.XXXXXX")"
    local target="${dir}/_orchestrator.json"
    run bash -c "source '${LIB}'; state_write_atomic '${target}' '${INVALID_CONTENT}'"
    [ "$status" -ne 0 ]
    # No .tmp.* files should remain in the target directory after failed write
    local tmp_count
    tmp_count="$(find "${dir}" -maxdepth 1 -name '.tmp.*' | wc -l | tr -d ' ')"
    [ "${tmp_count}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# (e) Concurrent writes — last-writer-wins (C2 acceptable behavior).
#
# Design note: True concurrent writes in bash require background processes and
# races that are not deterministically controllable in a test harness. This
# test demonstrates the C2 last-writer-wins PROPERTY by running two sequential
# state_write_atomic calls to the same target; the second call's content must
# win, and the file must remain valid JSON at all times (no torn state).
# The tmp+mv implementation guarantees atomicity: a reader never sees partial
# content because the target is only ever replaced by a complete mv.
# ---------------------------------------------------------------------------

WORKER_V2='{
  "schema_version": "1",
  "current_phase": "plan",
  "status": "working",
  "current_task": null,
  "last_updated": "2026-05-31T11:00:00Z",
  "context_pct": 30
}'

@test "(e) last writer wins: second write content is in target" {
    local dir="${BATS_TMPDIR}/e_lww"
    mkdir -p "${dir}"
    local target="${dir}/myworker.json"
    # First write
    bash -c "source '${LIB}'; state_write_atomic '${target}' '${VALID_WORKER}'"
    # Second write (different content)
    bash -c "source '${LIB}'; state_write_atomic '${target}' '${WORKER_V2}'"
    # Last write wins
    local phase
    phase="$(jq -r '.current_phase' "${target}")"
    [ "${phase}" = "plan" ]
}

@test "(e) file remains valid JSON after two sequential writes" {
    local dir="${BATS_TMPDIR}/e_valid"
    mkdir -p "${dir}"
    local target="${dir}/myworker.json"
    bash -c "source '${LIB}'; state_write_atomic '${target}' '${VALID_WORKER}'"
    bash -c "source '${LIB}'; state_write_atomic '${target}' '${WORKER_V2}'"
    jq . "${target}" > /dev/null
}

# ---------------------------------------------------------------------------
# (f) Torn reads do not occur — atomicity is a property of the LIBRARY's
# tmp+mv discipline, so these tests DRIVE state_write_atomic (rather than
# re-implementing mktemp+mv in the test body, which would test the OS, not
# the library). The tmp+mv pattern guarantees the target is either the old
# complete content or the new complete content — never a partial write — and
# the staging temp never lingers. A "torn read" would require observing a
# partial file mid-write; since mv is atomic on one filesystem and the temp
# is replaced in a single rename, no intermediate partial view exists.
# ---------------------------------------------------------------------------

@test "(f) successful write: target replaced atomically and no temp lingers" {
    # Fresh unique dir so a stale temp from a prior run cannot poison the
    # no-leak assertion (BATS_TMPDIR persists across runs).
    local dir
    dir="$(mktemp -d "${BATS_TMPDIR}/f_success.XXXXXX")"
    local target="${dir}/_orchestrator.json"
    # Pre-existing old content.
    printf '%s' "${VALID_ORCHESTRATOR}" > "${target}"

    # Drive the library with new content (cycles bumped to 5).
    local new_content
    new_content="$(printf '%s' "${VALID_ORCHESTRATOR}" | jq '.cycles = 5')"
    run bash -c "source '${LIB}'; state_write_atomic '${target}' '${new_content}'"
    [ "$status" -eq 0 ]

    # Target holds the complete, parseable NEW content.
    jq . "${target}" > /dev/null
    local cycles
    cycles="$(jq -r '.cycles' "${target}")"
    [ "${cycles}" = "5" ]

    # No staging temp remains.
    local tmp_count
    tmp_count="$(find "${dir}" -maxdepth 1 -name '.tmp.*' | wc -l | tr -d ' ')"
    [ "${tmp_count}" -eq 0 ]
}

@test "(f) failed validation: target untouched and no temp lingers" {
    # Fresh unique dir so a stale temp from a prior run cannot poison the
    # no-leak assertion (BATS_TMPDIR persists across runs).
    local dir
    dir="$(mktemp -d "${BATS_TMPDIR}/f_failure.XXXXXX")"
    local target="${dir}/_orchestrator.json"
    # Pre-existing valid content.
    printf '%s' "${VALID_ORCHESTRATOR}" > "${target}"
    local before
    before="$(cat "${target}")"

    # Drive the library with content that fails validation.
    run bash -c "source '${LIB}'; state_write_atomic '${target}' '${INVALID_CONTENT}'"
    [ "$status" -ne 0 ]

    # Target is byte-for-byte unchanged (no torn/partial write).
    local after
    after="$(cat "${target}")"
    [ "${before}" = "${after}" ]

    # No staging temp remains.
    local tmp_count
    tmp_count="$(find "${dir}" -maxdepth 1 -name '.tmp.*' | wc -l | tr -d ' ')"
    [ "${tmp_count}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# (g) state_migrate_if_needed:
#   v1 → no-op (exit 0)
#   v99 → error + non-zero exit + explicit unknown-version message
# ---------------------------------------------------------------------------

@test "(g) state_migrate_if_needed is a no-op for v1 orchestrator file" {
    local dir="${BATS_TMPDIR}/g_v1orch"
    mkdir -p "${dir}"
    local target="${dir}/_orchestrator.json"
    printf '%s' "${VALID_ORCHESTRATOR}" > "${target}"
    run bash -c "source '${LIB}'; state_migrate_if_needed '${target}'"
    [ "$status" -eq 0 ]
}

@test "(g) state_migrate_if_needed is a no-op for v1 worker file" {
    local dir="${BATS_TMPDIR}/g_v1work"
    mkdir -p "${dir}"
    local target="${dir}/myworker.json"
    printf '%s' "${VALID_WORKER}" > "${target}"
    run bash -c "source '${LIB}'; state_migrate_if_needed '${target}'"
    [ "$status" -eq 0 ]
}

@test "(g) state_migrate_if_needed does not modify a v1 file" {
    local dir="${BATS_TMPDIR}/g_unchanged"
    mkdir -p "${dir}"
    local target="${dir}/_orchestrator.json"
    printf '%s' "${VALID_ORCHESTRATOR}" > "${target}"
    local before
    before="$(cat "${target}")"
    bash -c "source '${LIB}'; state_migrate_if_needed '${target}'"
    local after
    after="$(cat "${target}")"
    [ "${before}" = "${after}" ]
}

@test "(g) state_migrate_if_needed returns non-zero for v99 file" {
    local dir="${BATS_TMPDIR}/g_v99"
    mkdir -p "${dir}"
    local target="${dir}/_orchestrator.json"
    printf '{"schema_version":"99","cycles":0}' > "${target}"
    run bash -c "source '${LIB}'; state_migrate_if_needed '${target}'"
    [ "$status" -ne 0 ]
}

@test "(g) state_migrate_if_needed emits unknown-version message for v99" {
    local dir="${BATS_TMPDIR}/g_v99msg"
    mkdir -p "${dir}"
    local target="${dir}/_orchestrator.json"
    printf '{"schema_version":"99","cycles":0}' > "${target}"
    run bash -c "source '${LIB}'; state_migrate_if_needed '${target}'"
    [ "$status" -ne 0 ]
    # Output must mention the version or contain an explicit unknown-version message
    [[ "${output}" =~ "version" ]] || [[ "${output}" =~ "schema_version" ]]
}

# ---------------------------------------------------------------------------
# (g2) state_migrate_if_needed: missing schema_version → error
# ---------------------------------------------------------------------------

@test "(g2) state_migrate_if_needed returns non-zero for missing schema_version" {
    local dir="${BATS_TMPDIR}/g2_missing"
    mkdir -p "${dir}"
    local target="${dir}/state.json"
    printf '{"cycles":0}' > "${target}"
    run bash -c "source '${LIB}'; state_migrate_if_needed '${target}'"
    [ "$status" -ne 0 ]
}

@test "(g2) state_migrate_if_needed emits message for missing schema_version" {
    local dir="${BATS_TMPDIR}/g2_msg"
    mkdir -p "${dir}"
    local target="${dir}/state.json"
    printf '{"cycles":0}' > "${target}"
    run bash -c "source '${LIB}'; state_migrate_if_needed '${target}'"
    [ "$status" -ne 0 ]
    [[ "${output}" =~ "version" ]] || [[ "${output}" =~ "schema_version" ]]
}

# ---------------------------------------------------------------------------
# (g3) state_migrate_if_needed: malformed JSON is reported DISTINCTLY from a
#      well-formed file missing schema_version (I-3). jq fails to parse, so
#      the error must mention malformed/unreadable, not "missing schema_version".
# ---------------------------------------------------------------------------

@test "(g3) state_migrate_if_needed returns non-zero for malformed JSON" {
    local dir="${BATS_TMPDIR}/g3_malformed"
    mkdir -p "${dir}"
    local target="${dir}/state.json"
    printf '{ not valid json !!!' > "${target}"
    run bash -c "source '${LIB}'; state_migrate_if_needed '${target}'"
    [ "$status" -ne 0 ]
}

@test "(g3) malformed JSON message is distinct from missing-version message" {
    local dir="${BATS_TMPDIR}/g3_distinct"
    mkdir -p "${dir}"
    local target="${dir}/state.json"
    printf '{ not valid json !!!' > "${target}"
    run bash -c "source '${LIB}'; state_migrate_if_needed '${target}'"
    [ "$status" -ne 0 ]
    # Must signal malformed/unreadable JSON, NOT the missing-version message.
    [[ "${output}" =~ [Mm]alformed ]] || [[ "${output}" =~ [Uu]nreadable ]]
    [[ ! "${output}" =~ "missing schema_version" ]]
}
