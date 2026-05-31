#!/usr/bin/env bash
# task-response-handler.sh — Reflexive handler for task-response (Task 24).
#
# This script is NOT a user-facing subcommand. It is invoked internally by the
# ORCHESTRATOR's inbox listener when a "task-response" wire message arrives from
# a worker. Per messaging.md (f), reflexive handlers are never user-invocable
# and never appear in the subcommand registry.
#
# Responsibilities:
#   Update the matching task_log[] entry's response_status in _orchestrator.json
#   from "pending" to the status carried by the task-response wire message (e.g.
#   "done"). Matches the entry by task_id. The orch owns _orchestrator.json, so
#   this write is ownership-correct.
#
# Writer ownership: this handler writes ONLY _orchestrator.json (orch-owned).
#   It never writes a worker's state file.
#
# Usage (internal, called by orchestrator listener):
#   task-response-handler.sh <task-id> <response-status> [<worker-name>]
#
# Arguments:
#   task-id          — id of the originating task (correlates with task_log[] entry)
#   response-status  — status to record (e.g. "done", "failed")
#   worker-name      — (optional) worker that completed the task; informational only
#
# Exit codes:
#   0 — task_log[] entry updated in _orchestrator.json
#   1 — argument, state-file, or validation failure

_TRESP_HANDLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_TRESP_HANDLER_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/state-io.sh
source "${_TRESP_HANDLER_DIR}/../lib/state-io.sh"

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------
if [[ $# -lt 2 ]]; then
    printf 'task-response-handler: expected at least 2 arguments: <task-id> <response-status> [<worker-name>]\n' >&2
    exit 1
fi

TASK_ID="$1"
RESPONSE_STATUS="$2"
WORKER_NAME="${3:-}"

if [[ -z "${TASK_ID}" ]]; then
    printf 'task-response-handler: task-id argument is empty.\n' >&2
    exit 1
fi

if [[ -z "${RESPONSE_STATUS}" ]]; then
    printf 'task-response-handler: response-status argument is empty.\n' >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Resolve orchestrator state file path
# ---------------------------------------------------------------------------
COORD_ROOT="${XFLEET_COORDINATION_ROOT:-}"
if [[ -z "${COORD_ROOT}" ]]; then
    printf 'task-response-handler: XFLEET_COORDINATION_ROOT is not set.\n' >&2
    exit 1
fi

ORCH_STATE_PATH="${COORD_ROOT}/state/_orchestrator.json"

if [[ ! -f "${ORCH_STATE_PATH}" ]]; then
    printf 'task-response-handler: orchestrator state file not found: %s\n' "${ORCH_STATE_PATH}" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Update the matching task_log[] entry's response_status in _orchestrator.json.
# Matches by task_id. If no matching entry is found, log a warning but do not
# fail — the task may have been dispatched in a prior session.
# ---------------------------------------------------------------------------
MATCH_COUNT="$(jq -r --arg tid "${TASK_ID}" \
    '[.task_log // [] | .[] | select(.task_id == $tid)] | length' \
    "${ORCH_STATE_PATH}")"

if [[ "${MATCH_COUNT}" -eq 0 ]]; then
    printf 'task-response-handler: warning: no task_log entry found for task_id=%s; skipping update.\n' \
        "${TASK_ID}" >&2
    exit 0
fi

# Embed the literal values directly into the jq expression (state_update_field
# passes the expression as a single string to `jq`; no --arg passthrough).
# Both TASK_ID and RESPONSE_STATUS are validated non-empty strings above and
# originate from our own argument list, not from untrusted user input piped in.
TASK_ID_JSON="$(jq -cn --arg v "${TASK_ID}" '$v')"
RESPONSE_STATUS_JSON="$(jq -cn --arg v "${RESPONSE_STATUS}" '$v')"

state_update_field "${ORCH_STATE_PATH}" \
    "(.task_log // []) |= map(if .task_id == ${TASK_ID_JSON} then .response_status = ${RESPONSE_STATUS_JSON} else . end)"

printf 'task-response-handler: task_log updated (task_id: %s, response_status: %s%s)\n' \
    "${TASK_ID}" "${RESPONSE_STATUS}" \
    "$([ -n "${WORKER_NAME}" ] && printf ', worker: %s' "${WORKER_NAME}" || true)"
