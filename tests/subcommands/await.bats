#!/usr/bin/env bats
# await.bats — BATS tests for tools/xfleet/subcommands/await.sh
#
# await is the responder wait primitive for exploration mode. A parked
# responder calls `xfleet await` to block until a question lands in its
# inbox (inbox:{name}), then exits 0 with the message on stdout.
#
# All tests that touch Redis are guarded with a skip when Redis is unavailable.
#
# Scenarios:
#   (a) Empty inbox with --timeout exits 2
#   (b) Presence key exists with correct TTL and JSON fields during/after await
#   (c) Pre-seeded message is printed, exits 0, XACKed (XPENDING shows none)
#   (d) --unpark deletes the presence key and exits 0
#   (e) Name resolution: --name > $XFLEET_WORKER_NAME

bats_require_minimum_version 1.5.0

AWAIT_SH="${BATS_TEST_DIRNAME}/../../tools/xfleet/subcommands/await.sh"

# Shared Redis-availability guard + default URL (single source of truth, SC-3).
load "../lib/redis-guard.bash"
REDIS_URL="${XFLEET_TEST_REDIS_URL}"

setup() {
    STREAM_NAME="$(unique_name)"
    PRESENCE_KEY="xfleet:explore:presence:${STREAM_NAME}"
    export XFLEET_REDIS_URL="${REDIS_URL}"
    # Clear any environment name so tests control it explicitly
    unset XFLEET_WORKER_NAME || true
}

teardown() {
    if redis_available; then
        redis-cli -u "${REDIS_URL}" DEL "inbox:${STREAM_NAME}" >/dev/null 2>&1 || true
        redis-cli -u "${REDIS_URL}" DEL "${PRESENCE_KEY}" >/dev/null 2>&1 || true
        redis-cli -u "${REDIS_URL}" XGROUP DESTROY "inbox:${STREAM_NAME}" explore >/dev/null 2>&1 || true
    fi
}

# ---------------------------------------------------------------------------
# (a) Empty inbox with --timeout exits 2
# ---------------------------------------------------------------------------

@test "(a) await --name on empty inbox with --timeout 1 exits 2" {
    if ! redis_available; then skip "redis unavailable"; fi
    run bash "${AWAIT_SH}" --name "${STREAM_NAME}" --timeout 1
    [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# (b) Presence key exists with correct TTL and JSON fields
# ---------------------------------------------------------------------------

@test "(b) presence key is set during await with TTL in (0, 900]" {
    if ! redis_available; then skip "redis unavailable"; fi
    # Run await briefly in background so presence key gets set
    bash "${AWAIT_SH}" --name "${STREAM_NAME}" --timeout 2 &
    AWAIT_PID=$!
    # Give it a moment to set the presence key (it sets it before the first BLOCK)
    sleep 1
    TTL="$(redis-cli -u "${REDIS_URL}" TTL "${PRESENCE_KEY}" 2>/dev/null)" || TTL="-1"
    wait "${AWAIT_PID}" || true
    [ "${TTL}" -gt 0 ]
    [ "${TTL}" -le 900 ]
}

@test "(b) presence key value has repo and parked_at fields" {
    if ! redis_available; then skip "redis unavailable"; fi
    bash "${AWAIT_SH}" --name "${STREAM_NAME}" --timeout 2 &
    AWAIT_PID=$!
    sleep 1
    VAL="$(redis-cli -u "${REDIS_URL}" GET "${PRESENCE_KEY}" 2>/dev/null)" || VAL=""
    wait "${AWAIT_PID}" || true
    # Must be non-empty JSON with repo and parked_at
    [[ -n "${VAL}" ]]
    printf '%s' "${VAL}" | jq -e '.repo' >/dev/null
    printf '%s' "${VAL}" | jq -e '.parked_at' >/dev/null
}

# ---------------------------------------------------------------------------
# (c) Pre-seeded message is printed, exits 0, XACKed
# ---------------------------------------------------------------------------

@test "(c) pre-seeded message is printed to stdout on await" {
    if ! redis_available; then skip "redis unavailable"; fi
    local payload='{"type":"explore_question","q":"what is the answer?"}'
    redis-cli -u "${REDIS_URL}" XADD "inbox:${STREAM_NAME}" '*' data "${payload}" >/dev/null
    run bash "${AWAIT_SH}" --name "${STREAM_NAME}" --timeout 5
    [ "$status" -eq 0 ]
    [[ "${output}" =~ "explore_question" ]]
}

@test "(c) await exits 0 when a message is delivered" {
    if ! redis_available; then skip "redis unavailable"; fi
    local payload='{"type":"explore_question","q":"hello"}'
    redis-cli -u "${REDIS_URL}" XADD "inbox:${STREAM_NAME}" '*' data "${payload}" >/dev/null
    run bash "${AWAIT_SH}" --name "${STREAM_NAME}" --timeout 5
    [ "$status" -eq 0 ]
}

@test "(c) message is XACKed after await (XPENDING shows none)" {
    if ! redis_available; then skip "redis unavailable"; fi
    local payload='{"type":"explore_question","q":"pending check"}'
    redis-cli -u "${REDIS_URL}" XADD "inbox:${STREAM_NAME}" '*' data "${payload}" >/dev/null
    run bash "${AWAIT_SH}" --name "${STREAM_NAME}" --timeout 5
    [ "$status" -eq 0 ]
    # XPENDING should show 0 pending after XACK
    PENDING="$(redis-cli -u "${REDIS_URL}" XPENDING "inbox:${STREAM_NAME}" explore - + 10 2>/dev/null)" || PENDING=""
    [[ -z "${PENDING}" ]]
}

# ---------------------------------------------------------------------------
# (d) --unpark deletes the presence key and exits 0
# ---------------------------------------------------------------------------

@test "(d) --unpark deletes the presence key and exits 0" {
    if ! redis_available; then skip "redis unavailable"; fi
    # Seed presence key manually
    redis-cli -u "${REDIS_URL}" SET "${PRESENCE_KEY}" '{"repo":"/tmp/test","parked_at":"2026-01-01T00:00:00Z"}' EX 900 >/dev/null
    run bash "${AWAIT_SH}" --name "${STREAM_NAME}" --unpark
    [ "$status" -eq 0 ]
    EXISTS="$(redis-cli -u "${REDIS_URL}" EXISTS "${PRESENCE_KEY}" 2>/dev/null)" || EXISTS="1"
    [ "${EXISTS}" -eq 0 ]
}

@test "(d) --unpark prints a confirmation message" {
    if ! redis_available; then skip "redis unavailable"; fi
    redis-cli -u "${REDIS_URL}" SET "${PRESENCE_KEY}" '{"repo":"/tmp/test","parked_at":"2026-01-01T00:00:00Z"}' EX 900 >/dev/null
    run bash "${AWAIT_SH}" --name "${STREAM_NAME}" --unpark
    [ "$status" -eq 0 ]
    [[ "${output}" =~ "unpark" ]] || [[ "${output}" =~ "unparked" ]] || [[ "${output}" =~ "${STREAM_NAME}" ]]
}

# ---------------------------------------------------------------------------
# (e) Name resolution: --name > $XFLEET_WORKER_NAME
# ---------------------------------------------------------------------------

@test "(e) --name flag overrides XFLEET_WORKER_NAME" {
    if ! redis_available; then skip "redis unavailable"; fi
    local override_name="${STREAM_NAME}_override"
    local override_presence="xfleet:explore:presence:${override_name}"
    export XFLEET_WORKER_NAME="${STREAM_NAME}_env"
    # Run briefly to let presence key get set
    bash "${AWAIT_SH}" --name "${override_name}" --timeout 2 &
    AWAIT_PID=$!
    sleep 1
    wait "${AWAIT_PID}" || true
    # The presence key should use the --name value, not the env var
    EXISTS_OVERRIDE="$(redis-cli -u "${REDIS_URL}" EXISTS "${override_presence}" 2>/dev/null)" || EXISTS_OVERRIDE="0"
    EXISTS_ENV="$(redis-cli -u "${REDIS_URL}" EXISTS "xfleet:explore:presence:${STREAM_NAME}_env" 2>/dev/null)" || EXISTS_ENV="0"
    # Cleanup extra keys
    redis-cli -u "${REDIS_URL}" DEL "${override_presence}" >/dev/null 2>&1 || true
    redis-cli -u "${REDIS_URL}" DEL "inbox:${override_name}" >/dev/null 2>&1 || true
    redis-cli -u "${REDIS_URL}" XGROUP DESTROY "inbox:${override_name}" explore >/dev/null 2>&1 || true
    [ "${EXISTS_OVERRIDE}" -eq 1 ]
    [ "${EXISTS_ENV}" -eq 0 ]
}

@test "(e) XFLEET_WORKER_NAME used when no --name flag" {
    if ! redis_available; then skip "redis unavailable"; fi
    local env_name="${STREAM_NAME}_fromenv"
    local env_presence="xfleet:explore:presence:${env_name}"
    export XFLEET_WORKER_NAME="${env_name}"
    bash "${AWAIT_SH}" --timeout 2 &
    AWAIT_PID=$!
    sleep 1
    wait "${AWAIT_PID}" || true
    EXISTS="$(redis-cli -u "${REDIS_URL}" EXISTS "${env_presence}" 2>/dev/null)" || EXISTS="0"
    # Cleanup
    redis-cli -u "${REDIS_URL}" DEL "${env_presence}" >/dev/null 2>&1 || true
    redis-cli -u "${REDIS_URL}" DEL "inbox:${env_name}" >/dev/null 2>&1 || true
    redis-cli -u "${REDIS_URL}" XGROUP DESTROY "inbox:${env_name}" explore >/dev/null 2>&1 || true
    [ "${EXISTS}" -eq 1 ]
}
