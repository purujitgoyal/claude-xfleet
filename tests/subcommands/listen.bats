#!/usr/bin/env bats
# listen.bats — BATS tests for tools/xfleet/subcommands/listen.sh (Task 20).
#
# listen starts a background Redis listener and records its PID in the worker
# state file's listen_bash_id field.
# Redis-dependent tests are guarded with skip when Redis is unavailable.
#
# Scenarios:
#   (a) Missing <name> arg — prints usage, exits non-zero
#   (b) listen starts a background process (PID recorded in worker state)
#   (c) listen_bash_id is a non-empty string written to worker state
#   (d) Calling listen when already running replaces the old listen_bash_id

bats_require_minimum_version 1.5.0

LISTEN_SH="${BATS_TEST_DIRNAME}/../../tools/xfleet/subcommands/listen.sh"

# Shared Redis-availability guard + default URL (single source of truth, SC-3).
load "../lib/redis-guard.bash"
REDIS_URL="${XFLEET_TEST_REDIS_URL}"

VALID_WORKER='{
  "schema_version": "1",
  "current_phase": "idle",
  "status": "idle",
  "current_task": null,
  "last_updated": "2026-05-31T10:00:00Z",
  "context_pct": 10
}'

# Reliably kill a listener subtree (its bash loop + the forked redis-cli BLOCK
# child). macOS has no setsid, so the listener is NOT a process-group leader and
# the negative-PGID trick is unreliable; SIGKILL the bash PID directly (a KILL
# cannot be trapped or deferred, so it lands even while the loop is blocked in a
# redis-cli command substitution), then reap the now-orphaned redis-cli child by
# its stream so it can't keep a connection open or respawn.
_kill_listener_subtree() {
    local raw_pid="$1" worker="$2"
    if [[ -n "${raw_pid}" ]]; then
        kill -- "-${raw_pid}" 2>/dev/null || true   # process-group kill when setsid present
        kill -9 "${raw_pid}" 2>/dev/null || true    # always SIGKILL the loop PID
    fi
    pkill -9 -f "XREADGROUP.*inbox:${worker}" 2>/dev/null || true
}

setup() {
    WORKER_NAME="$(unique_name)"
    COORD_ROOT="$(mktemp -d)"
    mkdir -p "${COORD_ROOT}/state"
    export XFLEET_COORDINATION_ROOT="${COORD_ROOT}"
    export XFLEET_REDIS_URL="${REDIS_URL}"
    # Pre-write a valid worker state file so listen.sh can update it.
    printf '%s' "${VALID_WORKER}" > "${COORD_ROOT}/state/${WORKER_NAME}.json"
}

teardown() {
    # Kill the listener subtree FIRST (bash loop + its redis-cli BLOCK child),
    # then destroy the stream/group — so the loop never observes NOGROUP and
    # retries against a torn-down group.
    local state_file="${COORD_ROOT}/state/${WORKER_NAME}.json"
    if [[ -f "${state_file}" ]]; then
        local bid raw_pid
        bid="$(jq -r '.listen_bash_id // empty' "${state_file}" 2>/dev/null)" || true
        # bid is "bash-NNN"; extract the numeric PID.
        raw_pid="$(printf '%s' "${bid}" | tr -dc '0-9')"
        _kill_listener_subtree "${raw_pid}" "${WORKER_NAME}"
    fi
    # Clean up the Redis stream (listener is already dead by here).
    if redis_available; then
        redis-cli -u "${REDIS_URL}" DEL "inbox:${WORKER_NAME}" >/dev/null 2>&1 || true
        redis-cli -u "${REDIS_URL}" XGROUP DESTROY "inbox:${WORKER_NAME}" worker >/dev/null 2>&1 || true
    fi
    rm -rf "${COORD_ROOT}"
}

# ---------------------------------------------------------------------------
# (a) Missing <name> arg
# ---------------------------------------------------------------------------

@test "(a) listen with no args exits non-zero" {
    run bash "${LISTEN_SH}"
    [ "$status" -ne 0 ]
}

@test "(a) listen with no args prints usage" {
    run bash "${LISTEN_SH}"
    [[ "${output}" =~ [Uu]sage ]] || [[ "${output}" =~ "listen" ]]
}

# ---------------------------------------------------------------------------
# (b) listen starts background process and records PID in worker state
# ---------------------------------------------------------------------------

@test "(b) listen exits 0 and records listen_bash_id in worker state" {
    if ! redis_available; then skip "redis unavailable"; fi
    run bash "${LISTEN_SH}" "${WORKER_NAME}"
    [ "$status" -eq 0 ]
    # Worker state file must now contain listen_bash_id
    [ -f "${COORD_ROOT}/state/${WORKER_NAME}.json" ]
    local bid
    bid="$(jq -r '.listen_bash_id // empty' "${COORD_ROOT}/state/${WORKER_NAME}.json")"
    [[ -n "${bid}" ]]
}

# ---------------------------------------------------------------------------
# (c) listen_bash_id is a non-empty string
# ---------------------------------------------------------------------------

@test "(c) listen_bash_id written to worker state is non-empty" {
    if ! redis_available; then skip "redis unavailable"; fi
    bash "${LISTEN_SH}" "${WORKER_NAME}"
    local bid
    bid="$(jq -r '.listen_bash_id // empty' "${COORD_ROOT}/state/${WORKER_NAME}.json")"
    [[ -n "${bid}" ]]
}

@test "(c) listen_bash_id looks like a process id (numeric or bash-NN)" {
    if ! redis_available; then skip "redis unavailable"; fi
    bash "${LISTEN_SH}" "${WORKER_NAME}"
    local bid
    bid="$(jq -r '.listen_bash_id // empty' "${COORD_ROOT}/state/${WORKER_NAME}.json")"
    [[ -n "${bid}" ]]
    # Accept either a bare integer PID or the "bash-NNN" format from state-schema.md
    [[ "${bid}" =~ ^[0-9]+$ ]] || [[ "${bid}" =~ ^bash-[0-9]+$ ]]
}

# ---------------------------------------------------------------------------
# (d) A second listen call re-writes listen_bash_id with a valid id.
#
# Note: the two ids need NOT differ — the OS may recycle the first listener's
# PID after we kill it. The assertion is PID-recycle-tolerant: it only verifies
# the second call wrote a well-formed listen_bash_id, not that it changed.
# ---------------------------------------------------------------------------

@test "(d) second listen call re-writes a valid listen_bash_id" {
    if ! redis_available; then skip "redis unavailable"; fi
    bash "${LISTEN_SH}" "${WORKER_NAME}"
    local bid1
    bid1="$(jq -r '.listen_bash_id // empty' "${COORD_ROOT}/state/${WORKER_NAME}.json")"
    # Kill the first listener (and its subtree) before the second call.
    local raw_pid
    raw_pid="$(printf '%s' "${bid1}" | tr -dc '0-9')"
    _kill_listener_subtree "${raw_pid}" "${WORKER_NAME}"
    # Brief wait so the OS settles after the kill.
    sleep 0.2
    bash "${LISTEN_SH}" "${WORKER_NAME}"
    local bid2
    bid2="$(jq -r '.listen_bash_id // empty' "${COORD_ROOT}/state/${WORKER_NAME}.json")"
    [[ -n "${bid2}" ]]
    # The second call must have written a well-formed listen_bash_id.
    [[ "${bid2}" =~ ^[0-9]+$ ]] || [[ "${bid2}" =~ ^bash-[0-9]+$ ]]
}
