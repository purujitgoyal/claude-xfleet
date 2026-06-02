#!/usr/bin/env bats
# phase-enter-scratch.bats — C1: worker `phase --enter` advises when
# session_scratch is non-empty. Advisory only; no state change, no auto-action.

bats_require_minimum_version 1.5.0

REPO="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
XFLEET="${REPO}/bin/xfleet"

setup() {
    COORD="${BATS_TEST_TMPDIR}/coord"
    mkdir -p "${COORD}/state"
    WORKER="w1"
    export XFLEET_ROLE="worker"
    export XFLEET_WORKER_NAME="${WORKER}"
    export XFLEET_COORDINATION_ROOT="${COORD}"
}

# Write a valid worker state file; arg $1 is the session_scratch JSON value.
_write_state() {
    jq -cn --argjson scratch "$1" \
        '{schema_version:"1", current_phase:"idle", status:"idle",
          last_updated:"2026-06-02T10:00:00Z", session_scratch:$scratch}' \
        > "${COORD}/state/${WORKER}.json"
}

@test "non-empty session_scratch → advisory printed on enter" {
    _write_state '{"a":1,"b":2}'
    run "${XFLEET}" phase --enter qa-spec
    [ "$status" -eq 0 ]
    [[ "$output" == *"session_scratch holds 2"* ]]
    [[ "$output" == *"phase-cleanup"* ]]
}

@test "empty session_scratch → no advisory" {
    _write_state '{}'
    run "${XFLEET}" phase --enter qa-spec
    [ "$status" -eq 0 ]
    [[ "$output" != *"session_scratch holds"* ]]
}

@test "absent session_scratch → no advisory" {
    jq -cn '{schema_version:"1", current_phase:"idle", status:"idle",
             last_updated:"2026-06-02T10:00:00Z"}' \
        > "${COORD}/state/${WORKER}.json"
    run "${XFLEET}" phase --enter qa-spec
    [ "$status" -eq 0 ]
    [[ "$output" != *"session_scratch holds"* ]]
}
