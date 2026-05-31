#!/usr/bin/env bash
# directive-response-handler.sh — Reflexive handler for directive-response (Task 23).
#
# This script is NOT a user-facing subcommand. It is invoked internally by
# directive-ack-handler.sh as the second half of the orchestrator→worker directive
# handshake. Per messaging.md (f), reflexive handlers are never user-invocable and
# never appear in the subcommand registry.
#
# Responsibilities:
#   Emit a "directive-response" wire message to inbox:orchestrator, recording the
#   worker's completed-ack status. This closes the directive loop from the worker's
#   perspective — the orchestrator can use it to update directive_log[].response_status
#   from "pending" to "acked".
#
# Writer ownership: this handler emits a wire message only — it writes NO state
# files. The orchestrator, upon receiving the directive-response, may update
# _orchestrator.json independently (orch-owned write).
#
# Usage (internal, called by directive-ack-handler.sh):
#   directive-response-handler.sh <worker-name> <directive-id> <expected-action> <concern-id>
#
# Arguments:
#   worker-name      — short-name of the worker sending the response
#   directive-id     — id of the originating directive (for correlation)
#   expected-action  — action value from the directive (may be empty string)
#   concern-id       — concern id (may be empty string: not concern-scoped)
#
# Exit codes:
#   0 — directive-response published to inbox:orchestrator
#   1 — argument or Redis failure

_DRESP_HANDLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_DRESP_HANDLER_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/redis.sh
source "${_DRESP_HANDLER_DIR}/../lib/redis.sh"

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------
if [[ $# -lt 4 ]]; then
    printf 'directive-response-handler: expected 4 arguments: <worker-name> <directive-id> <expected-action> <concern-id>\n' >&2
    exit 1
fi

WORKER_NAME="$1"
DIRECTIVE_ID="$2"
EXPECTED_ACTION="$3"
CONCERN_ID_ARG="$4"

if [[ -z "${WORKER_NAME}" ]]; then
    printf 'directive-response-handler: worker-name argument is empty.\n' >&2
    exit 1
fi

if [[ -z "${DIRECTIVE_ID}" ]]; then
    printf 'directive-response-handler: directive-id argument is empty.\n' >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Build and publish directive-response to inbox:orchestrator
# ---------------------------------------------------------------------------
SENDER="${XFLEET_ROLE:-worker}"
RESP_MSG_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# response_status: "acked" when the directive carried an expected_action (worker
# will action it); "informational-received" when it was informational only.
if [[ -n "${EXPECTED_ACTION}" ]]; then
    RESPONSE_STATUS="acked"
else
    RESPONSE_STATUS="informational-received"
fi

RESP_MSG="$(jq -cn \
    --arg id              "${RESP_MSG_ID}" \
    --arg type            "directive-response" \
    --arg from            "${SENDER}" \
    --arg to              "orchestrator" \
    --arg ts              "${TIMESTAMP}" \
    --arg directive_id    "${DIRECTIVE_ID}" \
    --arg worker          "${WORKER_NAME}" \
    --arg response_status "${RESPONSE_STATUS}" \
    --arg expected_action "${EXPECTED_ACTION}" \
    --argjson concern_id  "$([ -n "${CONCERN_ID_ARG}" ] && printf '"%s"' "${CONCERN_ID_ARG}" || printf 'null')" \
    '{id: $id, type: $type, from: $from, to: $to, timestamp: $ts, directive_id: $directive_id, worker: $worker, response_status: $response_status, expected_action: $expected_action, concern_id: $concern_id}'
)"

xfleet_redis XADD "inbox:orchestrator" MAXLEN "~" 200 "*" data "${RESP_MSG}" >/dev/null

printf 'directive-response-handler: response sent to orchestrator (resp_id: %s, directive_id: %s, status: %s)\n' \
    "${RESP_MSG_ID}" "${DIRECTIVE_ID}" "${RESPONSE_STATUS}"
