#!/usr/bin/env bats
# bootstrap.bats — xfleet bootstrap subcommand: worker cold-start initial-state write.

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

# (a) clean state dir → exits 0; state/w1.json exists; fields are correct.
@test "clean state dir: exits 0 and writes state/w1.json" {
    run "${XFLEET}" bootstrap
    [ "$status" -eq 0 ]
    [ -f "${COORD}/state/w1.json" ]
}

@test "written state has schema_version==1" {
    "${XFLEET}" bootstrap
    val="$(jq -r '.schema_version' "${COORD}/state/w1.json")"
    [ "${val}" = "1" ]
}

@test "written state has status==idle" {
    "${XFLEET}" bootstrap
    val="$(jq -r '.status' "${COORD}/state/w1.json")"
    [ "${val}" = "idle" ]
}

@test "written state has current_phase==idle" {
    "${XFLEET}" bootstrap
    val="$(jq -r '.current_phase' "${COORD}/state/w1.json")"
    [ "${val}" = "idle" ]
}

@test "written state has current_task==null" {
    "${XFLEET}" bootstrap
    val="$(jq -r '.current_task' "${COORD}/state/w1.json")"
    [ "${val}" = "null" ]
}

@test "written state has standby==false" {
    "${XFLEET}" bootstrap
    val="$(jq -r '.standby' "${COORD}/state/w1.json")"
    [ "${val}" = "false" ]
}

@test "written state has non-empty last_updated" {
    "${XFLEET}" bootstrap
    val="$(jq -r '.last_updated' "${COORD}/state/w1.json")"
    [ -n "${val}" ]
    [ "${val}" != "null" ]
}

# (b) written file passes the validator.
@test "written state passes validate-state.sh" {
    "${XFLEET}" bootstrap
    run "${REPO}/tools/xfleet/validate-state.sh" "${COORD}/state/w1.json" worker
    [ "$status" -eq 0 ]
}

# (c) file already exists → exits non-zero, output mentions `resume`, file unchanged.
@test "existing state file: exits non-zero" {
    echo '{"existing":true}' > "${COORD}/state/w1.json"
    run "${XFLEET}" bootstrap
    [ "$status" -ne 0 ]
}

@test "existing state file: output mentions resume" {
    echo '{"existing":true}' > "${COORD}/state/w1.json"
    run "${XFLEET}" bootstrap
    [[ "$output" == *"resume"* ]]
}

@test "existing state file: existing file is unchanged" {
    original='{"existing":true}'
    echo "${original}" > "${COORD}/state/w1.json"
    run "${XFLEET}" bootstrap
    actual="$(cat "${COORD}/state/w1.json")"
    [ "${actual}" = "${original}" ]
}

# (d) role gate: orchestrator role → exits non-zero with role-mismatch error.
@test "role gate: orchestrator role exits non-zero" {
    XFLEET_ROLE=orchestrator run "${XFLEET}" bootstrap
    [ "$status" -ne 0 ]
}

@test "role gate: orchestrator role prints role-mismatch error" {
    XFLEET_ROLE=orchestrator run "${XFLEET}" bootstrap
    [[ "$output" == *"worker"* ]]
}

# (e) missing XFLEET_COORDINATION_ROOT → exits non-zero with a clear message.
@test "missing XFLEET_COORDINATION_ROOT: exits non-zero" {
    unset XFLEET_COORDINATION_ROOT
    run "${XFLEET}" bootstrap
    [ "$status" -ne 0 ]
}

@test "missing XFLEET_COORDINATION_ROOT: clear error message" {
    unset XFLEET_COORDINATION_ROOT
    run "${XFLEET}" bootstrap
    [[ "$output" == *"XFLEET_COORDINATION_ROOT"* ]]
}
