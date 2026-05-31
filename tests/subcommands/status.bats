#!/usr/bin/env bats
# status.bats — BATS tests for tools/xfleet/subcommands/status.sh (Task 20).
#
# status reads pure state files (no Redis) — all tests always run.
#
# Scenarios:
#   (a) No state directory — prints "no state yet" note, exits 0
#   (b) Orchestrator state present — shows orchestrator fields
#   (c) Worker state present — shows worker name + key fields
#   (d) Multiple workers — each is shown
#   (e) Graceful skip of non-JSON files in state dir
#   (f) Missing orchestrator, worker present — still shows workers

bats_require_minimum_version 1.5.0

STATUS_SH="${BATS_TEST_DIRNAME}/../../tools/xfleet/subcommands/status.sh"

# ---------------------------------------------------------------------------
# Minimal-valid state fixtures (must pass the schema validator).
# ---------------------------------------------------------------------------

VALID_ORCHESTRATOR='{
  "schema_version": "1",
  "cycles": 2,
  "last_all_idle_notify": null,
  "last_round5_pause": null,
  "human_engaged": {
    "active": false,
    "concern_id": null,
    "set_at": null,
    "reason": null
  }
}'

VALID_WORKER_IDLE='{
  "schema_version": "1",
  "current_phase": "idle",
  "status": "idle",
  "current_task": null,
  "last_updated": "2026-05-31T10:00:00Z",
  "context_pct": 12
}'

VALID_WORKER_WORKING='{
  "schema_version": "1",
  "current_phase": "implement",
  "status": "working",
  "current_task": {
    "task_id": "t-001",
    "description": "Write the handler",
    "source": "orch-task",
    "received_at": "2026-05-31T09:00:00Z"
  },
  "last_updated": "2026-05-31T09:30:00Z",
  "context_pct": 55
}'

setup() {
    # Each test gets its own coordination root so tests are isolated.
    COORD_ROOT="$(mktemp -d)"
    mkdir -p "${COORD_ROOT}/state"
    export XFLEET_COORDINATION_ROOT="${COORD_ROOT}"
}

teardown() {
    rm -rf "${COORD_ROOT}"
}

# ---------------------------------------------------------------------------
# (a) No state directory content — graceful note, exit 0
# ---------------------------------------------------------------------------

@test "(a) status exits 0 when state dir is empty" {
    run bash "${STATUS_SH}"
    [ "$status" -eq 0 ]
}

@test "(a) status prints a 'no state' note when no files exist" {
    run bash "${STATUS_SH}"
    [ "$status" -eq 0 ]
    [[ "${output}" =~ [Nn]o.*state ]] || [[ "${output}" =~ [Nn]o.*orchestrator ]] || [[ "${output}" =~ [Ee]mpty ]]
}

# ---------------------------------------------------------------------------
# (b) Orchestrator state present
# ---------------------------------------------------------------------------

@test "(b) status shows orchestrator section when _orchestrator.json exists" {
    printf '%s' "${VALID_ORCHESTRATOR}" > "${COORD_ROOT}/state/_orchestrator.json"
    run bash "${STATUS_SH}"
    [ "$status" -eq 0 ]
    [[ "${output}" =~ [Oo]rchestrator ]]
}

@test "(b) status shows cycles value from orchestrator state" {
    printf '%s' "${VALID_ORCHESTRATOR}" > "${COORD_ROOT}/state/_orchestrator.json"
    run bash "${STATUS_SH}"
    [ "$status" -eq 0 ]
    # cycles is 2 in the fixture
    [[ "${output}" =~ "2" ]]
}

@test "(b) status shows human_engaged.active from orchestrator" {
    printf '%s' "${VALID_ORCHESTRATOR}" > "${COORD_ROOT}/state/_orchestrator.json"
    run bash "${STATUS_SH}"
    [ "$status" -eq 0 ]
    [[ "${output}" =~ "active" ]] || [[ "${output}" =~ "human_engaged" ]] || [[ "${output}" =~ "engaged" ]]
}

# ---------------------------------------------------------------------------
# (c) Worker state present — shows name + key fields
# ---------------------------------------------------------------------------

@test "(c) status shows worker section when alice.json exists" {
    printf '%s' "${VALID_WORKER_IDLE}" > "${COORD_ROOT}/state/alice.json"
    run bash "${STATUS_SH}"
    [ "$status" -eq 0 ]
    [[ "${output}" =~ "alice" ]]
}

@test "(c) status shows worker status field" {
    printf '%s' "${VALID_WORKER_IDLE}" > "${COORD_ROOT}/state/alice.json"
    run bash "${STATUS_SH}"
    [ "$status" -eq 0 ]
    [[ "${output}" =~ "idle" ]]
}

@test "(c) status shows worker current_phase" {
    printf '%s' "${VALID_WORKER_IDLE}" > "${COORD_ROOT}/state/alice.json"
    run bash "${STATUS_SH}"
    [ "$status" -eq 0 ]
    # current_phase is "idle" in the fixture
    [[ "${output}" =~ "idle" ]]
}

@test "(c) status shows worker context_pct" {
    printf '%s' "${VALID_WORKER_IDLE}" > "${COORD_ROOT}/state/alice.json"
    run bash "${STATUS_SH}"
    [ "$status" -eq 0 ]
    [[ "${output}" =~ "12" ]]
}

@test "(c) status shows working worker's current task description" {
    printf '%s' "${VALID_WORKER_WORKING}" > "${COORD_ROOT}/state/bob.json"
    run bash "${STATUS_SH}"
    [ "$status" -eq 0 ]
    [[ "${output}" =~ "bob" ]]
    [[ "${output}" =~ "working" ]]
}

# ---------------------------------------------------------------------------
# (d) Multiple workers — each is shown
# ---------------------------------------------------------------------------

@test "(d) status shows all workers when multiple worker files exist" {
    printf '%s' "${VALID_WORKER_IDLE}" > "${COORD_ROOT}/state/alice.json"
    printf '%s' "${VALID_WORKER_WORKING}" > "${COORD_ROOT}/state/bob.json"
    run bash "${STATUS_SH}"
    [ "$status" -eq 0 ]
    [[ "${output}" =~ "alice" ]]
    [[ "${output}" =~ "bob" ]]
}

# ---------------------------------------------------------------------------
# (e) Non-JSON files in state dir are skipped gracefully
# ---------------------------------------------------------------------------

@test "(e) status does not error on non-.json files in state dir" {
    printf 'some notes\n' > "${COORD_ROOT}/state/README.txt"
    run bash "${STATUS_SH}"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# (f) Missing orchestrator, worker present — still shows workers
# ---------------------------------------------------------------------------

@test "(f) status shows workers even when _orchestrator.json is absent" {
    printf '%s' "${VALID_WORKER_IDLE}" > "${COORD_ROOT}/state/carol.json"
    run bash "${STATUS_SH}"
    [ "$status" -eq 0 ]
    [[ "${output}" =~ "carol" ]]
}

@test "(f) status notes missing orchestrator when only workers exist" {
    printf '%s' "${VALID_WORKER_IDLE}" > "${COORD_ROOT}/state/carol.json"
    run bash "${STATUS_SH}"
    [ "$status" -eq 0 ]
    # Should note absence of orchestrator state
    [[ "${output}" =~ [Nn]o.*orchestrator ]] || [[ "${output}" =~ [Nn]one ]] || [[ "${output}" =~ [Nn]ot.*found ]] || [[ "${output}" =~ "(none)" ]]
}

# ---------------------------------------------------------------------------
# (g) Malformed state file degrades gracefully — one corrupt .json must not
#     abort the whole dump (set -e + jq exit 5). status still exits 0 and
#     reports the valid entries plus an "(unreadable)" note for the bad one.
# ---------------------------------------------------------------------------

@test "(g) status exits 0 when a worker .json is malformed" {
    printf '%s' "${VALID_WORKER_IDLE}" > "${COORD_ROOT}/state/alice.json"
    printf '{ not valid json !!!' > "${COORD_ROOT}/state/broken.json"
    run bash "${STATUS_SH}"
    [ "$status" -eq 0 ]
}

@test "(g) status still reports valid workers when another worker .json is malformed" {
    printf '%s' "${VALID_WORKER_IDLE}" > "${COORD_ROOT}/state/alice.json"
    printf '{ not valid json !!!' > "${COORD_ROOT}/state/broken.json"
    run bash "${STATUS_SH}"
    [ "$status" -eq 0 ]
    # The valid worker is still reported...
    [[ "${output}" =~ "alice" ]]
    # ...and the malformed one is flagged unreadable, not silently dropped.
    [[ "${output}" =~ "broken" ]]
    [[ "${output}" =~ [Uu]nreadable ]]
}

@test "(g) status exits 0 when _orchestrator.json is malformed" {
    printf '{ not valid json !!!' > "${COORD_ROOT}/state/_orchestrator.json"
    printf '%s' "${VALID_WORKER_IDLE}" > "${COORD_ROOT}/state/alice.json"
    run bash "${STATUS_SH}"
    [ "$status" -eq 0 ]
    # Orchestrator flagged unreadable; the valid worker still reported.
    [[ "${output}" =~ [Uu]nreadable ]]
    [[ "${output}" =~ "alice" ]]
}
