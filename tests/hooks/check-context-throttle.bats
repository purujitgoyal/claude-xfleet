#!/usr/bin/env bats
# check-context-throttle.bats — tests for the below-warn throttle (cluster 4j)
# in tools/xfleet/check-context.sh.
#
# The throttle must short-circuit BEFORE the transcript scan when:
#   - a worker state file exists, AND
#   - its last_check_at is within THROTTLE_SECONDS, AND
#   - its stored context_pct is below the warn threshold.
#
# We prove the early-exit by feeding a transcript whose usage is ABOVE warn:
# if the script read it, it would emit a warn <system-reminder>. A throttled
# run stays silent; a non-throttled run emits.

bats_require_minimum_version 1.5.0

SCRIPT="${BATS_TEST_DIRNAME}/../../tools/xfleet/check-context.sh"
PLUGIN_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

setup() {
    COORD="${BATS_TEST_TMPDIR}/coord"
    mkdir -p "${COORD}/state"
    WORKER="w1"
    STATE="${COORD}/state/${WORKER}.json"

    # Transcript whose usage = 150000/200000 = 75% (above the default warn of 70).
    TRANSCRIPT="${BATS_TEST_TMPDIR}/transcript.jsonl"
    printf '%s\n' '{"message":{"usage":{"input_tokens":150000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}' > "${TRANSCRIPT}"

    PAYLOAD="${BATS_TEST_TMPDIR}/payload.json"
    jq -cn --arg t "${TRANSCRIPT}" '{transcript_path: $t}' > "${PAYLOAD}"

    NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

# Write a worker state file with the given last_check_at and context_pct.
_write_state() {
    jq -cn --arg lc "$1" --argjson pct "$2" \
        '{schema_version:"1", current_phase:"idle", status:"idle", last_check_at:$lc, context_pct:$pct}' \
        > "${STATE}"
}

@test "throttle: recent check + below-warn pct → silent early-exit (transcript not read)" {
    _write_state "${NOW}" 20
    run env XFLEET_COORDINATION_ROOT="${COORD}" XFLEET_WORKER_NAME="${WORKER}" \
        CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000 \
        bash -c "'${SCRIPT}' < '${PAYLOAD}'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "no throttle: stale last_check_at → transcript read → warn emitted" {
    _write_state "2000-01-01T00:00:00Z" 20
    run env XFLEET_COORDINATION_ROOT="${COORD}" XFLEET_WORKER_NAME="${WORKER}" \
        CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000 \
        bash -c "'${SCRIPT}' < '${PAYLOAD}'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"system-reminder"* ]]
    [[ "$output" == *"75%"* ]]
}

@test "no throttle: recent check but pct at/above warn → not throttled → warn emitted" {
    _write_state "${NOW}" 72
    run env XFLEET_COORDINATION_ROOT="${COORD}" XFLEET_WORKER_NAME="${WORKER}" \
        CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000 \
        bash -c "'${SCRIPT}' < '${PAYLOAD}'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"system-reminder"* ]]
}

@test "throttle disabled via env (0) → transcript read even when recent + below warn" {
    _write_state "${NOW}" 20
    run env XFLEET_COORDINATION_ROOT="${COORD}" XFLEET_WORKER_NAME="${WORKER}" \
        CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000 XFLEET_CONTEXT_CHECK_THROTTLE_SECONDS=0 \
        bash -c "'${SCRIPT}' < '${PAYLOAD}'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"system-reminder"* ]]
}

@test "no worker state → throttle inert, degraded emission still fires" {
    run env -u XFLEET_COORDINATION_ROOT -u XFLEET_WORKER_NAME \
        CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000 \
        bash -c "'${SCRIPT}' < '${PAYLOAD}'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"system-reminder"* ]]
}
