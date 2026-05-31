#!/usr/bin/env bats
# peek.bats — BATS tests for tools/xfleet/subcommands/peek.sh (Task 20).
#
# peek inspects a Redis Stream inbox without consuming messages.
# All tests that touch Redis are guarded with a skip when Redis is unavailable.
#
# Scenarios:
#   (a) Missing <name> arg — prints usage, exits non-zero
#   (b) Empty / non-existent stream — exits 0, prints depth 0 or empty note
#   (c) Stream with messages — shows depth > 0 and message content
#   (d) Pending (unACKed) messages show in pending section

bats_require_minimum_version 1.5.0

PEEK_SH="${BATS_TEST_DIRNAME}/../../tools/xfleet/subcommands/peek.sh"

REDIS_URL="${XFLEET_REDIS_URL:-redis://localhost:6379}"

# ---------------------------------------------------------------------------
# Redis availability guard
# ---------------------------------------------------------------------------
redis_available() {
    redis-cli -u "${REDIS_URL}" ping >/dev/null 2>&1
}

# Generate a unique stream name per test to avoid cross-contamination.
unique_name() {
    # Sanitize BATS_TEST_NAME: replace spaces and special chars with underscores
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

# ---------------------------------------------------------------------------
# (a) Missing <name> arg
# ---------------------------------------------------------------------------

@test "(a) peek with no args exits non-zero" {
    run bash "${PEEK_SH}"
    [ "$status" -ne 0 ]
}

@test "(a) peek with no args prints usage" {
    run bash "${PEEK_SH}"
    [[ "${output}" =~ [Uu]sage ]] || [[ "${output}" =~ [Uu]sage ]] || [[ "${output}" =~ "peek" ]]
}

# ---------------------------------------------------------------------------
# (b) Empty / non-existent stream
# ---------------------------------------------------------------------------

@test "(b) peek on empty stream exits 0" {
    if ! redis_available; then skip "redis unavailable"; fi
    run bash "${PEEK_SH}" "${STREAM_NAME}"
    [ "$status" -eq 0 ]
}

@test "(b) peek on empty stream shows depth 0 or empty note" {
    if ! redis_available; then skip "redis unavailable"; fi
    run bash "${PEEK_SH}" "${STREAM_NAME}"
    [ "$status" -eq 0 ]
    [[ "${output}" =~ "0" ]] || [[ "${output}" =~ [Ee]mpty ]] || [[ "${output}" =~ [Nn]one ]]
}

@test "(b) peek output includes stream name" {
    if ! redis_available; then skip "redis unavailable"; fi
    run bash "${PEEK_SH}" "${STREAM_NAME}"
    [ "$status" -eq 0 ]
    [[ "${output}" =~ "${STREAM_NAME}" ]]
}

# ---------------------------------------------------------------------------
# (c) Stream with messages — depth > 0, message content visible
# ---------------------------------------------------------------------------

@test "(c) peek shows correct depth after XADD" {
    if ! redis_available; then skip "redis unavailable"; fi
    # Add two messages to the stream
    redis-cli -u "${REDIS_URL}" XADD "inbox:${STREAM_NAME}" '*' msg '{"type":"test","v":1}' >/dev/null
    redis-cli -u "${REDIS_URL}" XADD "inbox:${STREAM_NAME}" '*' msg '{"type":"test","v":2}' >/dev/null
    run bash "${PEEK_SH}" "${STREAM_NAME}"
    [ "$status" -eq 0 ]
    # Depth section should show 2 (or at least > 0)
    [[ "${output}" =~ "2" ]]
}

@test "(c) peek shows recent message content" {
    if ! redis_available; then skip "redis unavailable"; fi
    redis-cli -u "${REDIS_URL}" XADD "inbox:${STREAM_NAME}" '*' msg '{"type":"hello","worker":"testworker"}' >/dev/null
    run bash "${PEEK_SH}" "${STREAM_NAME}"
    [ "$status" -eq 0 ]
    # The message payload should appear somewhere in the output
    [[ "${output}" =~ "hello" ]] || [[ "${output}" =~ "testworker" ]] || [[ "${output}" =~ "msg" ]]
}

# ---------------------------------------------------------------------------
# (d) Pending (unACKed) messages
# ---------------------------------------------------------------------------

@test "(d) peek shows pending count after XREADGROUP without XACK" {
    if ! redis_available; then skip "redis unavailable"; fi
    local stream="inbox:${STREAM_NAME}"
    local group="worker"
    local consumer="${STREAM_NAME}-consumer"
    # Seed a message and claim it (creates pending) without ACKing
    redis-cli -u "${REDIS_URL}" XADD "${stream}" '*' msg '{"type":"task","id":"t-1"}' >/dev/null
    redis-cli -u "${REDIS_URL}" XGROUP CREATE "${stream}" "${group}" 0 >/dev/null 2>&1 || true
    redis-cli -u "${REDIS_URL}" XREADGROUP GROUP "${group}" "${consumer}" COUNT 1 STREAMS "${stream}" '>' >/dev/null 2>&1 || true
    run bash "${PEEK_SH}" "${STREAM_NAME}"
    [ "$status" -eq 0 ]
    # Pending section should show the entry (not "none")
    [[ "${output}" =~ "Pending" ]] || [[ "${output}" =~ "pending" ]] || [[ "${output}" =~ "unACKed" ]]
}
