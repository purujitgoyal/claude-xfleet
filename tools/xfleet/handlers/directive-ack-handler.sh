#!/usr/bin/env bash
# directive-ack-handler.sh — Reflexive handler for directive-ack (Task 23).
#
# This script is NOT a user-facing subcommand. It is invoked by the worker's
# inbox listener via dispatch_message when a "directive" wire message arrives.
# Per messaging.md (f), reflexive handlers are never user-invocable and never
# appear in the subcommand registry.
#
# Responsibilities:
#   1. If expected_action is non-empty, overwrite the worker's current_task
#      (source="orch-directive") in the worker's own state file (worker-owned
#      write; uses XFLEET_WORKER_NAME to locate the file).
#   2. Emit a "directive-ack" wire message back to inbox:orchestrator.
#   3. Invoke directive-response-handler.sh to emit the "directive-response"
#      follow-up that closes the directive loop.
#
# Writer ownership: this handler writes ONLY {worker}.json — never
# _orchestrator.json. The state_update_field call uses XFLEET_WORKER_NAME.
#
# Usage (internal, called by listener via dispatch_message on inbound directive):
#   directive-ack-handler.sh <target-worker> <directive-id> <expected-action> <scope> <concern-id>
#
# Arguments:
#   target-worker    — short-name of the worker receiving the directive
#   directive-id     — id of the originating directive (for correlation)
#   expected-action  — action value (may be empty string: informational directive)
#   scope            — scope/subject of the directive
#   concern-id       — concern id (may be empty string: not concern-scoped)
#
# Exit codes:
#   0 — directive-ack published; current_task updated if expected_action non-empty
#   1 — argument or Redis/state failure

_DACK_HANDLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_DACK_HANDLER_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/redis.sh
source "${_DACK_HANDLER_DIR}/../lib/redis.sh"
# shellcheck source=../lib/state-io.sh
source "${_DACK_HANDLER_DIR}/../lib/state-io.sh"

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------
if [[ $# -lt 5 ]]; then
    printf 'directive-ack-handler: expected 5 arguments: <target-worker> <directive-id> <expected-action> <scope> <concern-id>\n' >&2
    exit 1
fi

TARGET_WORKER="$1"
DIRECTIVE_ID="$2"
EXPECTED_ACTION="$3"
SCOPE="$4"
CONCERN_ID_ARG="$5"

if [[ -z "${TARGET_WORKER}" ]]; then
    printf 'directive-ack-handler: target-worker argument is empty.\n' >&2
    exit 1
fi

if [[ -z "${DIRECTIVE_ID}" ]]; then
    printf 'directive-ack-handler: directive-id argument is empty.\n' >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# If expected_action is non-empty, overwrite the worker's current_task.
# Writer ownership: {worker}.json is owned by the worker session.
# XFLEET_WORKER_NAME identifies which worker state file to update.
# ---------------------------------------------------------------------------
if [[ -n "${EXPECTED_ACTION}" ]]; then
    WORKER_NAME="${XFLEET_WORKER_NAME:-}"
    if [[ -z "${WORKER_NAME}" ]]; then
        printf 'directive-ack-handler: XFLEET_WORKER_NAME is not set; required to update current_task when expected_action is present.\n' >&2
        exit 1
    fi

    COORD_ROOT="${XFLEET_COORDINATION_ROOT:-}"
    if [[ -z "${COORD_ROOT}" ]]; then
        printf 'directive-ack-handler: XFLEET_COORDINATION_ROOT is not set; required to locate worker state file.\n' >&2
        exit 1
    fi

    WORKER_STATE_PATH="${COORD_ROOT}/state/${WORKER_NAME}.json"
    RECEIVED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    # Build the new current_task object.
    CURRENT_TASK="$(jq -cn \
        --arg task_id     "${DIRECTIVE_ID}" \
        --arg description "${EXPECTED_ACTION}" \
        --arg source      "orch-directive" \
        --arg received_at "${RECEIVED_AT}" \
        '{task_id: $task_id, description: $description, source: $source, received_at: $received_at}'
    )"

    # Overwrite current_task in the worker's state file (atomic + validated).
    state_update_field "${WORKER_STATE_PATH}" \
        ". + {current_task: ${CURRENT_TASK}}"
fi

# ---------------------------------------------------------------------------
# Build and publish directive-ack to inbox:orchestrator
# ---------------------------------------------------------------------------
SENDER="${XFLEET_ROLE:-worker}"
ACK_MSG_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

ACK_MSG="$(jq -cn \
    --arg id              "${ACK_MSG_ID}" \
    --arg type            "directive-ack" \
    --arg from            "${SENDER}" \
    --arg to              "orchestrator" \
    --arg ts              "${TIMESTAMP}" \
    --arg directive_id    "${DIRECTIVE_ID}" \
    --arg expected_action "${EXPECTED_ACTION}" \
    --argjson concern_id  "$([ -n "${CONCERN_ID_ARG}" ] && printf '"%s"' "${CONCERN_ID_ARG}" || printf 'null')" \
    '{id: $id, type: $type, from: $from, to: $to, timestamp: $ts, directive_id: $directive_id, expected_action: $expected_action, concern_id: $concern_id}'
)"

xfleet_redis XADD "inbox:orchestrator" MAXLEN "~" 200 "*" data "${ACK_MSG}" >/dev/null

# ---------------------------------------------------------------------------
# Invoke directive-response-handler.sh to emit the directive-response
# follow-up that closes the directive loop.
# ---------------------------------------------------------------------------
_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${_DACK_HANDLER_DIR}/../../.." && pwd)}"
_DRESP_HANDLER="${_PLUGIN_ROOT}/tools/xfleet/handlers/directive-response-handler.sh"

if [[ ! -x "${_DRESP_HANDLER}" ]]; then
    printf 'directive-ack-handler: directive-response-handler.sh not found or not executable at %s\n' "${_DRESP_HANDLER}" >&2
    exit 1
fi

"${_DRESP_HANDLER}" "${TARGET_WORKER}" "${DIRECTIVE_ID}" "${EXPECTED_ACTION}" "${CONCERN_ID_ARG}"

printf 'directive-ack-handler: ack sent to orchestrator (ack_id: %s, directive_id: %s, expected_action: "%s")\n' \
    "${ACK_MSG_ID}" "${DIRECTIVE_ID}" "${EXPECTED_ACTION}"
