#!/usr/bin/env bats
# ask.bats — BATS tests for tools/xfleet/subcommands/ask.sh
#
# ask is the asker-side subcommand for exploration mode: it sends a
# question-type wire message (plus reply_to) to a parked responder's inbox
# and, by default, blocks on the asker's own inbox until an answer arrives.
#
# All tests that touch Redis are guarded with a skip when Redis is unavailable.
#
# Scenarios (plan Task 2 step 1):
#   (a) No args — prints usage, exits non-zero
#   (b) Both / neither of --message / --message-file — exit 1
#   (c) Send shape: data JSON has type=question, reply_to, to, content
#   (d) Presence warning on stderr when no presence key; none when present
#   (e) Blocking receive: answer XADDed after send is printed, exit 0
#   (f) Timeout: --timeout 1 with no answer exits 1, stderr mentions --list
#   (g) Stale answers XADDed BEFORE the send are ignored (LAST_ID capture)
#   (h) --list prints parked responders; "(no responders parked)" when none

bats_require_minimum_version 1.5.0

ASK_SH="${BATS_TEST_DIRNAME}/../../tools/xfleet/subcommands/ask.sh"

# Shared Redis-availability guard + default URL (single source of truth, SC-3).
load "../lib/redis-guard.bash"
REDIS_URL="${XFLEET_TEST_REDIS_URL}"

setup() {
    BASE_NAME="$(unique_name)"
    ASKER="${BASE_NAME}_asker"
    RESPONDER="${BASE_NAME}_resp"
    RESP_PRESENCE="xfleet:explore:presence:${RESPONDER}"
    export XFLEET_REDIS_URL="${REDIS_URL}"
    export XFLEET_WORKER_NAME="${ASKER}"
}

teardown() {
    if redis_available; then
        redis-cli -u "${REDIS_URL}" DEL "inbox:${ASKER}" >/dev/null 2>&1 || true
        redis-cli -u "${REDIS_URL}" DEL "inbox:${RESPONDER}" >/dev/null 2>&1 || true
        redis-cli -u "${REDIS_URL}" DEL "${RESP_PRESENCE}" >/dev/null 2>&1 || true
    fi
}

# ---------------------------------------------------------------------------
# (a) No args — usage, non-zero exit
# ---------------------------------------------------------------------------

@test "(a) ask with no args exits non-zero" {
    run bash "${ASK_SH}"
    [ "$status" -ne 0 ]
}

@test "(a) ask with no args prints usage" {
    run --separate-stderr bash "${ASK_SH}"
    [[ "${stderr}" =~ [Uu]sage ]]
}

# ---------------------------------------------------------------------------
# (b) Both / neither of --message / --message-file — exit 1
# ---------------------------------------------------------------------------

@test "(b) ask with neither --message nor --message-file exits 1" {
    run bash "${ASK_SH}" "${RESPONDER}"
    [ "$status" -eq 1 ]
}

@test "(b) ask with both --message and --message-file exits 1" {
    run bash "${ASK_SH}" "${RESPONDER}" --message "hi" --message-file "/tmp/nonexistent.md"
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# (c) Send shape: question + reply_to land in the responder inbox
# ---------------------------------------------------------------------------

@test "(c) --async send writes question message with reply_to/to/content" {
    if ! redis_available; then skip "redis unavailable"; fi
    run bash "${ASK_SH}" "${RESPONDER}" --message "hi" --async
    [ "$status" -eq 0 ]
    RAW="$(redis-cli -u "${REDIS_URL}" XRANGE "inbox:${RESPONDER}" - +)"
    JSON="$(printf '%s\n' "${RAW}" | grep '^{' | head -1)"
    [[ -n "${JSON}" ]]
    [ "$(printf '%s' "${JSON}" | jq -r '.type')" = "question" ]
    [ "$(printf '%s' "${JSON}" | jq -r '.reply_to')" = "${ASKER}" ]
    [ "$(printf '%s' "${JSON}" | jq -r '.to')" = "${RESPONDER}" ]
    [ "$(printf '%s' "${JSON}" | jq -r '.content')" = "hi" ]
}

@test "(c) --async prints msg_id and peek hint" {
    if ! redis_available; then skip "redis unavailable"; fi
    run bash "${ASK_SH}" "${RESPONDER}" --message "hi" --async
    [ "$status" -eq 0 ]
    [[ "${output}" =~ "msg_id" ]]
    [[ "${output}" =~ "peek" ]]
}

# ---------------------------------------------------------------------------
# (d) Presence pre-check warning
# ---------------------------------------------------------------------------

@test "(d) warns on stderr when no responder presence key exists" {
    if ! redis_available; then skip "redis unavailable"; fi
    run --separate-stderr bash "${ASK_SH}" "${RESPONDER}" --message "hi" --async
    [ "$status" -eq 0 ]
    [[ "${stderr}" =~ "no responder parked" ]]
}

@test "(d) no warning when responder presence key is set" {
    if ! redis_available; then skip "redis unavailable"; fi
    redis-cli -u "${REDIS_URL}" SET "${RESP_PRESENCE}" '{"repo":"/tmp/test","parked_at":"2026-01-01T00:00:00Z"}' EX 60 >/dev/null
    run --separate-stderr bash "${ASK_SH}" "${RESPONDER}" --message "hi" --async
    [ "$status" -eq 0 ]
    [[ ! "${stderr}" =~ "no responder parked" ]]
}

# ---------------------------------------------------------------------------
# (e) Blocking receive: answer sent after the question is printed
# ---------------------------------------------------------------------------

@test "(e) blocking ask receives an answer XADDed after the send" {
    if ! redis_available; then skip "redis unavailable"; fi
    OUT_FILE="${BATS_TEST_TMPDIR}/ask-out"
    bash "${ASK_SH}" "${RESPONDER}" --message "q" --timeout 10 >"${OUT_FILE}" 2>/dev/null &
    ASK_PID=$!
    sleep 1
    ANSWER='{"id":"a-1","type":"answer","from":"worker","to":"'"${ASKER}"'","timestamp":"2026-06-10T00:00:00Z","content":"the answer"}'
    redis-cli -u "${REDIS_URL}" XADD "inbox:${ASKER}" MAXLEN '~' 200 '*' data "${ANSWER}" >/dev/null
    rc=0
    wait "${ASK_PID}" || rc=$?
    [ "${rc}" -eq 0 ]
    grep -q "the answer" "${OUT_FILE}"
}

# ---------------------------------------------------------------------------
# (f) Timeout: no answer → exit 1, stderr mentions --list
# ---------------------------------------------------------------------------

@test "(f) blocking ask with --timeout 1 and no answer exits 1" {
    if ! redis_available; then skip "redis unavailable"; fi
    run --separate-stderr bash "${ASK_SH}" "${RESPONDER}" --message "q" --timeout 1
    [ "$status" -eq 1 ]
    [[ "${stderr}" =~ "--list" ]]
}

# ---------------------------------------------------------------------------
# (g) Stale answers sent BEFORE the question are ignored
# ---------------------------------------------------------------------------

@test "(g) answer already in the inbox before send is ignored (times out)" {
    if ! redis_available; then skip "redis unavailable"; fi
    STALE='{"id":"a-0","type":"answer","from":"worker","to":"'"${ASKER}"'","timestamp":"2026-06-09T00:00:00Z","content":"stale answer"}'
    redis-cli -u "${REDIS_URL}" XADD "inbox:${ASKER}" '*' data "${STALE}" >/dev/null
    run bash "${ASK_SH}" "${RESPONDER}" --message "q" --timeout 1
    [ "$status" -eq 1 ]
    [[ ! "${output}" =~ "stale answer" ]]
}

# ---------------------------------------------------------------------------
# (h) --list
# ---------------------------------------------------------------------------

@test "(h) --list prints a seeded responder's name and repo" {
    if ! redis_available; then skip "redis unavailable"; fi
    redis-cli -u "${REDIS_URL}" SET "${RESP_PRESENCE}" '{"repo":"/tmp/test-repo","parked_at":"2026-01-01T00:00:00Z"}' EX 60 >/dev/null
    run bash "${ASK_SH}" --list
    [ "$status" -eq 0 ]
    [[ "${output}" =~ "${RESPONDER}" ]]
    [[ "${output}" =~ "/tmp/test-repo" ]]
}

@test "(h) --list prints '(no responders parked)' when none" {
    if ! redis_available; then skip "redis unavailable"; fi
    # The presence namespace is shared across the Redis instance; this
    # assertion is only meaningful when no other responder is parked.
    EXISTING="$(redis-cli -u "${REDIS_URL}" --scan --pattern 'xfleet:explore:presence:*' 2>/dev/null | head -1)"
    if [[ -n "${EXISTING}" ]]; then skip "presence namespace not empty (another responder is parked)"; fi
    run bash "${ASK_SH}" --list
    [ "$status" -eq 0 ]
    [[ "${output}" =~ "(no responders parked)" ]]
}
