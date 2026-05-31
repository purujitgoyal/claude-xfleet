#!/usr/bin/env bats
# ack.bats — BATS tests for tools/xfleet/subcommands/ack.sh (Task 20).
#
# ack XACKs a Redis Stream message by id.
# Redis-dependent tests are guarded with skip when Redis is unavailable.
#
# Scenarios:
#   (a) Missing args — prints usage, exits non-zero
#   (b) Valid XACK of a pending message — exits 0
#   (c) Stale/double-ACK without --force — exits non-zero
#   (d) Stale/double-ACK with --force — exits 0
#   (e) Unknown flag — exits non-zero

bats_require_minimum_version 1.5.0

ACK_SH="${BATS_TEST_DIRNAME}/../../tools/xfleet/subcommands/ack.sh"

REDIS_URL="${XFLEET_REDIS_URL:-redis://localhost:6379}"

redis_available() {
    redis-cli -u "${REDIS_URL}" ping >/dev/null 2>&1
}

unique_name() {
    local sanitized
    sanitized="$(printf '%s' "${BATS_TEST_NAME}" | tr -cs 'a-zA-Z0-9_' '_')"
    printf 'test_%s_%s' "${sanitized}" "$$"
}

setup() {
    STREAM_NAME="$(unique_name)"
    export XFLEET_REDIS_URL="${REDIS_URL}"
}

teardown() {
    if redis_available; then
        redis-cli -u "${REDIS_URL}" DEL "inbox:${STREAM_NAME}" >/dev/null 2>&1 || true
        redis-cli -u "${REDIS_URL}" XGROUP DESTROY "inbox:${STREAM_NAME}" worker >/dev/null 2>&1 || true
    fi
}

# Helper: seed a message into the stream and claim it (creates a PEL entry).
# Prints the stream message_id (for use in XACK).
seed_pending_message() {
    local stream="inbox:${STREAM_NAME}"
    local group="worker"
    local consumer="${STREAM_NAME}-consumer"
    redis-cli -u "${REDIS_URL}" XGROUP CREATE "${stream}" "${group}" 0 MKSTREAM >/dev/null 2>&1 || true
    local msg_id
    msg_id="$(redis-cli -u "${REDIS_URL}" XADD "${stream}" '*' msg '{"type":"test"}')"
    # Claim (read without ACK) to move it to PEL
    redis-cli -u "${REDIS_URL}" XREADGROUP GROUP "${group}" "${consumer}" COUNT 1 STREAMS "${stream}" '>' >/dev/null 2>&1 || true
    printf '%s' "${msg_id}"
}

# ---------------------------------------------------------------------------
# (a) Missing args
# ---------------------------------------------------------------------------

@test "(a) ack with no args exits non-zero" {
    run bash "${ACK_SH}"
    [ "$status" -ne 0 ]
}

@test "(a) ack with only name exits non-zero (missing message_id)" {
    run bash "${ACK_SH}" "somename"
    [ "$status" -ne 0 ]
}

@test "(a) ack usage message is printed on no args" {
    run bash "${ACK_SH}"
    [[ "${output}" =~ [Uu]sage ]] || [[ "${output}" =~ "ack" ]]
}

# ---------------------------------------------------------------------------
# (b) Valid XACK — exits 0
# ---------------------------------------------------------------------------

@test "(b) ack of a pending message exits 0" {
    if ! redis_available; then skip "redis unavailable"; fi
    local msg_id
    msg_id="$(seed_pending_message)"
    run bash "${ACK_SH}" "${STREAM_NAME}" "${msg_id}"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# (c) Stale / double-ACK without --force — exits non-zero
# ---------------------------------------------------------------------------

@test "(c) double-ack without --force exits non-zero" {
    if ! redis_available; then skip "redis unavailable"; fi
    local msg_id
    msg_id="$(seed_pending_message)"
    # First ACK — succeeds
    bash "${ACK_SH}" "${STREAM_NAME}" "${msg_id}"
    # Second ACK — should fail (strict mode)
    run bash "${ACK_SH}" "${STREAM_NAME}" "${msg_id}"
    [ "$status" -ne 0 ]
}

@test "(c) ack of non-existent message_id exits non-zero" {
    if ! redis_available; then skip "redis unavailable"; fi
    # Ensure the stream + group exist but the message id is bogus
    redis-cli -u "${REDIS_URL}" XGROUP CREATE "inbox:${STREAM_NAME}" worker 0 MKSTREAM >/dev/null 2>&1 || true
    run bash "${ACK_SH}" "${STREAM_NAME}" "9999999999999-0"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# (d) Stale / double-ACK with --force — exits 0
# ---------------------------------------------------------------------------

@test "(d) double-ack with --force exits 0" {
    if ! redis_available; then skip "redis unavailable"; fi
    local msg_id
    msg_id="$(seed_pending_message)"
    bash "${ACK_SH}" "${STREAM_NAME}" "${msg_id}"
    run bash "${ACK_SH}" "${STREAM_NAME}" "${msg_id}" --force
    [ "$status" -eq 0 ]
}

@test "(d) ack --force on bogus message_id exits 0 with a warning" {
    if ! redis_available; then skip "redis unavailable"; fi
    redis-cli -u "${REDIS_URL}" XGROUP CREATE "inbox:${STREAM_NAME}" worker 0 MKSTREAM >/dev/null 2>&1 || true
    run bash "${ACK_SH}" "${STREAM_NAME}" "9999999999999-0" --force
    [ "$status" -eq 0 ]
    # Should warn (to stderr, captured in output by bats)
    [[ "${output}" =~ [Ww]arn ]] || [[ "${output}" =~ "XACK" ]] || [[ "${output}" =~ "0" ]]
}

# ---------------------------------------------------------------------------
# (e) Unknown flag
# ---------------------------------------------------------------------------

@test "(e) ack with unknown flag exits non-zero" {
    if ! redis_available; then skip "redis unavailable"; fi
    local msg_id
    msg_id="$(seed_pending_message)"
    run bash "${ACK_SH}" "${STREAM_NAME}" "${msg_id}" --unknown-flag
    [ "$status" -ne 0 ]
}
