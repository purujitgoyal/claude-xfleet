#!/usr/bin/env bash
# task-ack-handler.sh — Reflexive handler for task receipt on the worker side (Task 29a).
#
# This script is NOT a user-facing subcommand. It is invoked by the worker's inbox
# listener via dispatch_message when a "task" wire message arrives. Per messaging.md
# (f), reflexive handlers are never user-invocable and never appear in the subcommand
# registry.
#
# Responsibilities:
#   1. Overwrite the worker's current_task (source="orch-task") in the worker's own
#      state file (worker-owned write; uses XFLEET_WORKER_NAME to locate the file).
#   2. Emit a "task-response" wire message to inbox:orchestrator with response_status
#      "acked", so the orchestrator's task_log[] entry can be updated.
#
# Writer ownership: this handler writes ONLY {worker}.json — never _orchestrator.json.
#   The state_update_field call uses XFLEET_WORKER_NAME.
#
# Usage (internal, called by listener via dispatch_message):
#   task-ack-handler.sh <task-id> <description> [<task-kind>]
#
# Arguments:
#   task-id      — id of the inbound task (from wire message .id)
#   description  — human-readable task description (from .content // .description)
#   task-kind    — (optional) category of task (from .task_kind)
#
# Exit codes:
#   0 — current_task updated; task-response published to inbox:orchestrator
#   1 — argument, env, Redis, or state failure

_TACK_HANDLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_TACK_HANDLER_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/redis.sh
source "${_TACK_HANDLER_DIR}/../lib/redis.sh"
# shellcheck source=../lib/state-io.sh
source "${_TACK_HANDLER_DIR}/../lib/state-io.sh"

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------
if [[ $# -lt 2 ]]; then
    printf 'task-ack-handler: expected at least 2 arguments: <task-id> <description> [<task-kind>]\n' >&2
    exit 1
fi

TASK_ID="$1"
DESCRIPTION="$2"
TASK_KIND="${3:-}"

if [[ -z "${TASK_ID}" ]]; then
    printf 'task-ack-handler: task-id argument is empty.\n' >&2
    exit 1
fi

if [[ -z "${DESCRIPTION}" ]]; then
    printf 'task-ack-handler: description argument is empty.\n' >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Resolve worker state path from env
# ---------------------------------------------------------------------------
WORKER_NAME="${XFLEET_WORKER_NAME:-}"
if [[ -z "${WORKER_NAME}" ]]; then
    printf 'task-ack-handler: XFLEET_WORKER_NAME is not set; required to update current_task.\n' >&2
    exit 1
fi

COORD_ROOT="${XFLEET_COORDINATION_ROOT:-}"
if [[ -z "${COORD_ROOT}" ]]; then
    printf 'task-ack-handler: XFLEET_COORDINATION_ROOT is not set; required to locate worker state file.\n' >&2
    exit 1
fi

WORKER_STATE_PATH="${COORD_ROOT}/state/${WORKER_NAME}.json"

# ---------------------------------------------------------------------------
# Overwrite the worker's current_task (worker-owned write).
# ---------------------------------------------------------------------------
RECEIVED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

CURRENT_TASK="$(jq -cn \
    --arg task_id     "${TASK_ID}" \
    --arg description "${DESCRIPTION}" \
    --arg source      "orch-task" \
    --arg received_at "${RECEIVED_AT}" \
    '{task_id: $task_id, description: $description, source: $source, received_at: $received_at}'
)"

state_update_field "${WORKER_STATE_PATH}" \
    ". + {current_task: ${CURRENT_TASK}}"

# ---------------------------------------------------------------------------
# Build and publish task-response to inbox:orchestrator
# ---------------------------------------------------------------------------
RESP_MSG_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

RESP_MSG="$(jq -cn \
    --arg id              "${RESP_MSG_ID}" \
    --arg type            "task-response" \
    --arg from            "worker" \
    --arg to              "orchestrator" \
    --arg ts              "${TIMESTAMP}" \
    --arg task_id         "${TASK_ID}" \
    --arg worker          "${WORKER_NAME}" \
    --arg response_status "acked" \
    '{id: $id, type: $type, from: $from, to: $to, timestamp: $ts, task_id: $task_id, worker: $worker, response_status: $response_status}'
)"

xfleet_redis XADD "inbox:orchestrator" MAXLEN "~" 200 "*" data "${RESP_MSG}" >/dev/null

printf 'task-ack-handler: current_task updated and task-response sent (task_id: %s, worker: %s, resp_id: %s)\n' \
    "${TASK_ID}" "${WORKER_NAME}" "${RESP_MSG_ID}"
