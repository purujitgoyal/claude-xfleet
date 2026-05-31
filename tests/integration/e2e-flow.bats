#!/usr/bin/env bats
# e2e-flow.bats — End-to-end integration test for a minimal xfleet coordination flow.
#
# DETERMINISTIC DISPATCH APPROACH:
#   The real inbox listener (xfleet listen) processes messages asynchronously in a
#   background loop. To avoid timing-based flakiness, this test drives dispatch
#   SYNCHRONOUSLY: after each sender subcommand XADD's a message, the test reads the
#   message directly from Redis (XRANGE), extracts its JSON payload, and calls
#   dispatch_message "<json>" in the receiver's role+env. This exercises the identical
#   dispatch path the real listener uses — dispatch.sh's dispatch_message() — without
#   racing a background process.
#
# CLEANUP:
#   teardown() flushes the two test inbox streams from Redis and removes the temp
#   coordination root (BATS_TMPDIR-based). No real coordination root is touched.
#
# AUTHORIZED: the operator has explicitly authorized this ONE e2e test file despite
#   the project's no-tests policy. No other test files are introduced here.

bats_require_minimum_version 1.5.0

# ---------------------------------------------------------------------------
# Path constants
# ---------------------------------------------------------------------------
REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
SUBCOMMANDS="${REPO_ROOT}/tools/xfleet/subcommands"
LIB_DIR="${REPO_ROOT}/tools/xfleet/lib"
DISPATCH_SH="${LIB_DIR}/dispatch.sh"
VALIDATE_SH="${REPO_ROOT}/tools/xfleet/validate-state.sh"

# Worker name with PID suffix to avoid cross-run contamination.
# Kept deterministic within a run (same $$ across all tests in a file).
WORKER_NAME="w1_$$"

# ---------------------------------------------------------------------------
# setup / teardown
# ---------------------------------------------------------------------------

setup() {
    # Required env for state writes (jsonschema validation).
    export XFLEET_PYTHON="/Users/purujit/.config/xfleet/venv/bin/python"
    export XFLEET_REDIS_URL="${XFLEET_REDIS_URL:-redis://127.0.0.1:6379}"
    export CLAUDE_PLUGIN_ROOT="${REPO_ROOT}"

    # Temp coordination root under BATS_TMPDIR (auto-cleaned by BATS).
    COORD_ROOT="${BATS_TMPDIR}/xfleet-e2e-$$"
    mkdir -p "${COORD_ROOT}/state"
    export XFLEET_COORDINATION_ROOT="${COORD_ROOT}"

    # Pre-create schema-valid orchestrator state.
    # Only schema_version is required; all other fields are optional per schema.
    cat > "${COORD_ROOT}/state/_orchestrator.json" <<'ORCH_JSON'
{"schema_version": "1"}
ORCH_JSON

    # Pre-create schema-valid worker state.
    local now
    now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    cat > "${COORD_ROOT}/state/${WORKER_NAME}.json" <<WORKER_JSON
{
  "schema_version": "1",
  "current_phase": "implement",
  "status": "working",
  "current_task": null,
  "last_updated": "${now}",
  "context_pct": 20
}
WORKER_JSON

    # Flush test inboxes from any previous run to start clean.
    redis-cli -u "${XFLEET_REDIS_URL}" DEL "inbox:orchestrator" "inbox:${WORKER_NAME}" >/dev/null 2>&1 || true
}

teardown() {
    redis-cli -u "${XFLEET_REDIS_URL}" DEL "inbox:orchestrator" "inbox:${WORKER_NAME}" >/dev/null 2>&1 || true
    rm -rf "${COORD_ROOT}"
}

# ---------------------------------------------------------------------------
# Helper: read the LATEST message payload from an inbox stream.
# Reads ALL entries with XRANGE and picks the last one's "data" field.
# ---------------------------------------------------------------------------
read_last_inbox_msg() {
    local stream="$1"
    local raw
    # XRANGE stream - + returns all entries in order; last entry is most recent.
    raw="$(redis-cli -u "${XFLEET_REDIS_URL}" XRANGE "${stream}" - + 2>/dev/null)"
    # redis-cli XRANGE output format: "entry-id\ndata\n<json>\n..."
    # We parse by extracting the last occurrence of a valid JSON object.
    # Each entry looks like: <id>\ndata\n{...json...}
    # Use awk to collect only lines that start with '{' (the JSON payloads).
    printf '%s' "${raw}" | awk '/^\{/{last=$0} END{print last}'
}

# ---------------------------------------------------------------------------
# Helper: read ALL messages of a given type from an inbox, return last match.
# ---------------------------------------------------------------------------
read_last_msg_of_type() {
    local stream="$1"
    local msg_type="$2"
    local raw
    raw="$(redis-cli -u "${XFLEET_REDIS_URL}" XRANGE "${stream}" - + 2>/dev/null)"
    # Extract JSON lines and filter by type field.
    printf '%s' "${raw}" | awk '/^\{/{print}' | while IFS= read -r line; do
        t="$(printf '%s' "${line}" | jq -r '.type // empty' 2>/dev/null)"
        if [[ "${t}" == "${msg_type}" ]]; then
            printf '%s' "${line}"
        fi
    done | tail -1
}

# ---------------------------------------------------------------------------
# Helper: invoke dispatch_message synchronously in a given role+env.
# Runs in a subshell to isolate env changes.
# ---------------------------------------------------------------------------
dispatch_as() {
    local role="$1"
    local worker_name="$2"   # empty string for orchestrator
    local msg_json="$3"

    (
        export XFLEET_ROLE="${role}"
        export XFLEET_WORKER_NAME="${worker_name}"
        export XFLEET_COORDINATION_ROOT="${XFLEET_COORDINATION_ROOT}"
        export XFLEET_REDIS_URL="${XFLEET_REDIS_URL}"
        export XFLEET_PYTHON="${XFLEET_PYTHON}"
        export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"

        # Source dispatch.sh and invoke dispatch_message.
        # shellcheck disable=SC1090
        source "${DISPATCH_SH}"
        dispatch_message "${msg_json}"
    )
}

# ===========================================================================
# STEP 1: directive (orchestrator → worker)
# ===========================================================================

@test "step1: directive subcommand writes directive_log + human_engaged; publishes to inbox:WORKER" {
    # Guard: skip if Redis is unavailable.
    if ! redis-cli -u "${XFLEET_REDIS_URL}" ping >/dev/null 2>&1; then
        skip "redis unavailable"
    fi

    export XFLEET_ROLE=orchestrator
    export XFLEET_COORDINATION_ROOT="${COORD_ROOT}"

    run bash "${SUBCOMMANDS}/directive.sh" "${WORKER_NAME}" \
        --message "do X" \
        --expected_action "implement"

    [ "$status" -eq 0 ]

    # Orchestrator state: directive_log must have one entry with response_status=pending.
    local log_count
    log_count="$(jq '.directive_log | length' "${COORD_ROOT}/state/_orchestrator.json")"
    [ "${log_count}" -eq 1 ]

    local resp_status
    resp_status="$(jq -r '.directive_log[0].response_status' "${COORD_ROOT}/state/_orchestrator.json")"
    [ "${resp_status}" = "pending" ]

    local expected_action
    expected_action="$(jq -r '.directive_log[0].expected_action' "${COORD_ROOT}/state/_orchestrator.json")"
    [ "${expected_action}" = "implement" ]

    # human_engaged must be active=true.
    local engaged
    engaged="$(jq -r '.human_engaged.active' "${COORD_ROOT}/state/_orchestrator.json")"
    [ "${engaged}" = "true" ]

    # Message must have landed in the worker inbox.
    local msg
    msg="$(read_last_msg_of_type "inbox:${WORKER_NAME}" "directive")"
    [ -n "${msg}" ]

    local msg_type
    msg_type="$(printf '%s' "${msg}" | jq -r '.type')"
    [ "${msg_type}" = "directive" ]
}

# ===========================================================================
# STEP 2: worker receives directive via dispatch_message
# ===========================================================================

@test "step2: dispatch_message(directive) as worker sets current_task; emits directive-response to inbox:orchestrator" {
    if ! redis-cli -u "${XFLEET_REDIS_URL}" ping >/dev/null 2>&1; then
        skip "redis unavailable"
    fi

    # First, send the directive (as orchestrator) to populate the inbox.
    export XFLEET_ROLE=orchestrator
    bash "${SUBCOMMANDS}/directive.sh" "${WORKER_NAME}" \
        --message "do X" \
        --expected_action "implement"

    # Read the directive from the worker inbox.
    local directive_msg
    directive_msg="$(read_last_msg_of_type "inbox:${WORKER_NAME}" "directive")"
    [ -n "${directive_msg}" ]

    # Simulate the worker's listener: dispatch the directive synchronously.
    dispatch_as "worker" "${WORKER_NAME}" "${directive_msg}"

    # Assert: worker state now has current_task with source=orch-directive.
    local task_source
    task_source="$(jq -r '.current_task.source' "${COORD_ROOT}/state/${WORKER_NAME}.json")"
    [ "${task_source}" = "orch-directive" ]

    local task_desc
    task_desc="$(jq -r '.current_task.description' "${COORD_ROOT}/state/${WORKER_NAME}.json")"
    [ "${task_desc}" = "implement" ]

    # Assert: directive-response landed in inbox:orchestrator.
    local dr_msg
    dr_msg="$(read_last_msg_of_type "inbox:orchestrator" "directive-response")"
    [ -n "${dr_msg}" ]

    local dr_status
    dr_status="$(printf '%s' "${dr_msg}" | jq -r '.response_status')"
    [ "${dr_status}" = "acked" ]
}

# ===========================================================================
# STEP 3: orchestrator processes directive-response
# ===========================================================================

@test "step3: dispatch_message(directive-response) as orchestrator updates directive_log response_status to acked" {
    if ! redis-cli -u "${XFLEET_REDIS_URL}" ping >/dev/null 2>&1; then
        skip "redis unavailable"
    fi

    # Send directive.
    export XFLEET_ROLE=orchestrator
    bash "${SUBCOMMANDS}/directive.sh" "${WORKER_NAME}" \
        --message "do X" \
        --expected_action "implement"

    # Worker receives directive.
    local directive_msg
    directive_msg="$(read_last_msg_of_type "inbox:${WORKER_NAME}" "directive")"
    dispatch_as "worker" "${WORKER_NAME}" "${directive_msg}"

    # Read directive-response from orchestrator inbox.
    local dr_msg
    dr_msg="$(read_last_msg_of_type "inbox:orchestrator" "directive-response")"
    [ -n "${dr_msg}" ]

    # Orchestrator processes directive-response.
    dispatch_as "orchestrator" "" "${dr_msg}"

    # Assert: directive_log entry response_status updated to "acked".
    local resp_status
    resp_status="$(jq -r '.directive_log[0].response_status' "${COORD_ROOT}/state/_orchestrator.json")"
    [ "${resp_status}" = "acked" ]
}

# ===========================================================================
# STEP 4: question (worker → orchestrator)
# ===========================================================================

@test "step4: question subcommand publishes question message to inbox:orchestrator" {
    if ! redis-cli -u "${XFLEET_REDIS_URL}" ping >/dev/null 2>&1; then
        skip "redis unavailable"
    fi

    export XFLEET_ROLE=worker
    export XFLEET_WORKER_NAME="${WORKER_NAME}"

    run bash "${SUBCOMMANDS}/question.sh" "orchestrator" --message "scope?"
    [ "$status" -eq 0 ]

    local q_msg
    q_msg="$(read_last_msg_of_type "inbox:orchestrator" "question")"
    [ -n "${q_msg}" ]

    local content
    content="$(printf '%s' "${q_msg}" | jq -r '.content')"
    [ "${content}" = "scope?" ]
}

# ===========================================================================
# STEP 5: answer (orchestrator → worker)
# ===========================================================================

@test "step5: answer subcommand publishes answer message to inbox:WORKER" {
    if ! redis-cli -u "${XFLEET_REDIS_URL}" ping >/dev/null 2>&1; then
        skip "redis unavailable"
    fi

    export XFLEET_ROLE=orchestrator

    run bash "${SUBCOMMANDS}/answer.sh" "${WORKER_NAME}" --message "full scope"
    [ "$status" -eq 0 ]

    local a_msg
    a_msg="$(read_last_msg_of_type "inbox:${WORKER_NAME}" "answer")"
    [ -n "${a_msg}" ]

    local content
    content="$(printf '%s' "${a_msg}" | jq -r '.content')"
    [ "${content}" = "full scope" ]
}

# ===========================================================================
# STEP 6: worker phase --complete (worker → orchestrator)
# ===========================================================================

@test "step6: worker phase --complete sets worker status=compacting; publishes phase-complete to inbox:orchestrator" {
    if ! redis-cli -u "${XFLEET_REDIS_URL}" ping >/dev/null 2>&1; then
        skip "redis unavailable"
    fi

    export XFLEET_ROLE=worker
    export XFLEET_WORKER_NAME="${WORKER_NAME}"
    # Pass a real repo root and slug so write_phase_handoff has somewhere to write.
    export XFLEET_SLUG="e2e-test-$$"

    run bash "${SUBCOMMANDS}/phase.sh" --complete \
        --slug "e2e-test-$$" \
        --repo-root "${COORD_ROOT}"
    [ "$status" -eq 0 ]

    # Worker status must now be "compacting".
    local w_status
    w_status="$(jq -r '.status' "${COORD_ROOT}/state/${WORKER_NAME}.json")"
    [ "${w_status}" = "compacting" ]

    # phase-complete signal must be in inbox:orchestrator.
    local pc_msg
    pc_msg="$(read_last_msg_of_type "inbox:orchestrator" "phase-complete")"
    [ -n "${pc_msg}" ]

    local pc_worker
    pc_worker="$(printf '%s' "${pc_msg}" | jq -r '.worker')"
    [ "${pc_worker}" = "${WORKER_NAME}" ]
}

# ===========================================================================
# STEP 7: orchestrator processes phase-complete
# ===========================================================================

@test "step7: dispatch_message(phase-complete) as orchestrator appends completion_log entry" {
    if ! redis-cli -u "${XFLEET_REDIS_URL}" ping >/dev/null 2>&1; then
        skip "redis unavailable"
    fi

    # Worker sends phase-complete.
    export XFLEET_ROLE=worker
    export XFLEET_WORKER_NAME="${WORKER_NAME}"
    bash "${SUBCOMMANDS}/phase.sh" --complete \
        --slug "e2e-test-$$" \
        --repo-root "${COORD_ROOT}"

    # Read phase-complete from orchestrator inbox.
    local pc_msg
    pc_msg="$(read_last_msg_of_type "inbox:orchestrator" "phase-complete")"
    [ -n "${pc_msg}" ]

    # Orchestrator dispatches phase-complete.
    dispatch_as "orchestrator" "" "${pc_msg}"

    # Assert: completion_log has one entry.
    local log_count
    log_count="$(jq '.completion_log | length' "${COORD_ROOT}/state/_orchestrator.json")"
    [ "${log_count}" -ge 1 ]

    local outcome
    outcome="$(jq -r '.completion_log[-1].outcome' "${COORD_ROOT}/state/_orchestrator.json")"
    [ -n "${outcome}" ]

    local trigger
    trigger="$(jq -r '.completion_log[-1].trigger_msg_type' "${COORD_ROOT}/state/_orchestrator.json")"
    [ "${trigger}" = "phase-complete" ]
}

# ===========================================================================
# STEP 8: human-gated phase emission (orchestrator emits after human approval)
# ===========================================================================

@test "step8: orch phase --complete with approved_by_human=true fires emission; records phase_emissions + emission_log" {
    if ! redis-cli -u "${XFLEET_REDIS_URL}" ping >/dev/null 2>&1; then
        skip "redis unavailable"
    fi

    local phase="implement"
    local signal="phase-complete"

    # First attempt WITHOUT approval — should be blocked (exit 0, no emission).
    export XFLEET_ROLE=orchestrator
    run bash "${SUBCOMMANDS}/phase.sh" --complete \
        --phase "${phase}" \
        --signal "${signal}" \
        --to "${WORKER_NAME}"
    [ "$status" -eq 0 ]
    [[ "${output}" == *"BLOCKED"* ]]

    # Confirm emission_log has a "blocked" entry.
    local blocked_count
    blocked_count="$(jq '[.emission_log[]? | select(.outcome=="blocked")] | length' \
        "${COORD_ROOT}/state/_orchestrator.json")"
    [ "${blocked_count}" -ge 1 ]

    # Simulate human approval: inject a complete, valid emission record with
    # approved_by_human=true. The gated path (phase.sh) reads
    # phase_emissions[P][S].approved_by_human; a minimal valid record with
    # approved_by_human=true is all it needs.
    local now
    now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    local approval_record
    approval_record="$(jq -cn \
        --argjson approved true \
        --arg sent_at "${now}" \
        --arg eid "pre-approved-$$" \
        '{approved_by_human: $approved, sent_at: $sent_at, sent_to: [], emission_id: $eid}')"

    # Write the approval into _orchestrator.json via a jq + validate + mv pipeline
    # (state_update_field only takes path + jq-expr, no --arg passthrough, so we
    # build the updated state with jq --arg/--argjson directly here).
    local orch_path="${COORD_ROOT}/state/_orchestrator.json"
    local current_state
    current_state="$(cat "${orch_path}")"
    local updated_state
    updated_state="$(printf '%s' "${current_state}" | jq \
        --arg p "${phase}" \
        --arg s "${signal}" \
        --argjson rec "${approval_record}" \
        '.phase_emissions = ((.phase_emissions // {}) | .[$p] = ((.[$p] // {}) | .[$s] = $rec))')"
    local tmp
    tmp="$(mktemp "${COORD_ROOT}/state/.tmp.XXXXXX")"
    printf '%s' "${updated_state}" > "${tmp}"
    "${XFLEET_PYTHON}" "${REPO_ROOT}/tools/xfleet/lib/validate-state.py" \
        "${tmp}" "${REPO_ROOT}/tools/xfleet/state-schema.json" "orchestrator" >/dev/null 2>&1
    mv -f "${tmp}" "${orch_path}"

    # Confirm approved_by_human is now true in the file.
    local approved_val
    approved_val="$(jq -r --arg p "${phase}" --arg s "${signal}" \
        '.phase_emissions[$p][$s].approved_by_human' "${orch_path}")"
    [ "${approved_val}" = "true" ]

    # Flush the worker inbox so we can cleanly check the new emission.
    redis-cli -u "${XFLEET_REDIS_URL}" DEL "inbox:${WORKER_NAME}" >/dev/null 2>&1 || true

    # Now re-run orch phase --complete — should fire.
    export XFLEET_ROLE=orchestrator
    run bash "${SUBCOMMANDS}/phase.sh" --complete \
        --phase "${phase}" \
        --signal "${signal}" \
        --to "${WORKER_NAME}"
    [ "$status" -eq 0 ]
    [[ "${output}" == *"emitted"* ]] || [[ "${output}" == *"emission_id"* ]]

    # Assert: emission_log has a "sent" entry.
    local sent_count
    sent_count="$(jq '[.emission_log[]? | select(.outcome=="sent")] | length' "${orch_path}")"
    [ "${sent_count}" -ge 1 ]

    # Assert: phase_emissions[phase][signal] now has sent_to + sent_at populated.
    local emission_rec_ok
    emission_rec_ok="$(jq -r --arg p "${phase}" --arg s "${signal}" \
        '.phase_emissions[$p][$s] | (.sent_at != null and (.sent_to | length >= 0)) | tostring' "${orch_path}")"
    [ "${emission_rec_ok}" = "true" ]

    # Assert: the phase-complete signal landed in the worker inbox.
    local emission_msg
    emission_msg="$(read_last_msg_of_type "inbox:${WORKER_NAME}" "${signal}")"
    [ -n "${emission_msg}" ]

    local msg_phase
    msg_phase="$(printf '%s' "${emission_msg}" | jq -r '.phase')"
    [ "${msg_phase}" = "${phase}" ]
}

# ===========================================================================
# STEP 9: final state validity
# ===========================================================================

@test "step9: _orchestrator.json and WORKER.json both pass validate-state.sh after the full flow" {
    if ! redis-cli -u "${XFLEET_REDIS_URL}" ping >/dev/null 2>&1; then
        skip "redis unavailable"
    fi

    # Re-run the full flow to produce a non-trivial final state.
    local phase="implement"
    local signal="phase-complete"

    # Step 1: directive.
    export XFLEET_ROLE=orchestrator
    bash "${SUBCOMMANDS}/directive.sh" "${WORKER_NAME}" \
        --message "do X" --expected_action "implement"

    # Step 2: worker receives directive.
    local d_msg
    d_msg="$(read_last_msg_of_type "inbox:${WORKER_NAME}" "directive")"
    dispatch_as "worker" "${WORKER_NAME}" "${d_msg}"

    # Step 3: orch processes directive-response.
    local dr_msg
    dr_msg="$(read_last_msg_of_type "inbox:orchestrator" "directive-response")"
    dispatch_as "orchestrator" "" "${dr_msg}"

    # Step 4: question.
    export XFLEET_ROLE=worker
    export XFLEET_WORKER_NAME="${WORKER_NAME}"
    bash "${SUBCOMMANDS}/question.sh" "orchestrator" --message "scope?"

    # Step 5: answer.
    export XFLEET_ROLE=orchestrator
    bash "${SUBCOMMANDS}/answer.sh" "${WORKER_NAME}" --message "full scope"

    # Step 6: worker phase --complete.
    export XFLEET_ROLE=worker
    export XFLEET_WORKER_NAME="${WORKER_NAME}"
    bash "${SUBCOMMANDS}/phase.sh" --complete \
        --slug "e2e-test-$$" --repo-root "${COORD_ROOT}"

    # Step 7: orch processes phase-complete.
    local pc_msg
    pc_msg="$(read_last_msg_of_type "inbox:orchestrator" "phase-complete")"
    dispatch_as "orchestrator" "" "${pc_msg}"

    # Step 8: inject approval and emit.
    local now
    now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    local orch_path="${COORD_ROOT}/state/_orchestrator.json"
    local approval_record
    approval_record="$(jq -cn \
        --argjson approved true \
        --arg sent_at "${now}" \
        --arg eid "pre-approved-$$" \
        '{approved_by_human: $approved, sent_at: $sent_at, sent_to: [], emission_id: $eid}')"
    local current_state updated_state tmp
    current_state="$(cat "${orch_path}")"
    updated_state="$(printf '%s' "${current_state}" | jq \
        --arg p "${phase}" --arg s "${signal}" --argjson rec "${approval_record}" \
        '.phase_emissions = ((.phase_emissions // {}) | .[$p] = ((.[$p] // {}) | .[$s] = $rec))')"
    tmp="$(mktemp "${COORD_ROOT}/state/.tmp.XXXXXX")"
    printf '%s' "${updated_state}" > "${tmp}"
    "${XFLEET_PYTHON}" "${REPO_ROOT}/tools/xfleet/lib/validate-state.py" \
        "${tmp}" "${REPO_ROOT}/tools/xfleet/state-schema.json" "orchestrator" >/dev/null 2>&1
    mv -f "${tmp}" "${orch_path}"

    redis-cli -u "${XFLEET_REDIS_URL}" DEL "inbox:${WORKER_NAME}" >/dev/null 2>&1 || true
    export XFLEET_ROLE=orchestrator
    bash "${SUBCOMMANDS}/phase.sh" --complete \
        --phase "${phase}" --signal "${signal}" --to "${WORKER_NAME}"

    # Final validation: both state files must pass the schema validator.
    run bash "${VALIDATE_SH}" "${orch_path}" "orchestrator"
    [ "$status" -eq 0 ]

    run bash "${VALIDATE_SH}" "${COORD_ROOT}/state/${WORKER_NAME}.json" "worker"
    [ "$status" -eq 0 ]
}
