#!/usr/bin/env bash
# task.sh — xfleet task subcommand (Task 24).
#
# Sends an orchestrator→worker procedural task. Per messaging.md (b):
# sender must be orchestrator. Appends a record to task_log[] in
# _orchestrator.json (orch-owned state).
#
# The task is published to inbox:{target-worker} as a "task" wire message
# carrying task_kind, description, and an optional expected_action field.
# The worker-side reflexive handler (task-response-handler.sh) is fired by
# the TARGET worker's listener on receipt — NOT inline by this sender — and
# it overwrites the worker's current_task (source="orch-task"). Per
# ownership rules, THIS SCRIPT never writes the worker's state file.
#
# Usage:
#   xfleet task <target> --task-kind <kind> --message <text> [--expected-action <X>]
#   xfleet task <target> --task-kind <kind> --message-file <path> [--expected-action <X>]
#
# Options:
#   --task-kind <kind>        Category of task (required, stored in task_log[].task_kind).
#   --message <text>          Inline description of the work to be done.
#   --message-file <path>     Path to a file containing the task description.
#   --expected-action <X>     Optional action label the orchestrator expects the worker to take.
#
# Exit codes:
#   0 — task dispatched; task_log[] updated in orch state; task published to inbox:{target}
#   1 — validation error, role rejection, or Redis/state failure

_TASK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_TASK_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/redis.sh
source "${_TASK_DIR}/../lib/redis.sh"
# shellcheck source=../lib/sender-authority.sh
source "${_TASK_DIR}/../lib/sender-authority.sh"
# shellcheck source=../lib/message-content.sh
source "${_TASK_DIR}/../lib/message-content.sh"
# shellcheck source=../lib/state-io.sh
source "${_TASK_DIR}/../lib/state-io.sh"

# ---------------------------------------------------------------------------
# Role check — orchestrator only (messaging.md b)
# ---------------------------------------------------------------------------
assert_role orchestrator "tasks are orchestrator-originated procedural work (orch to worker); from a worker session use 'concern' or 'question' instead."

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
    printf 'Usage: xfleet task <target> --task-kind <kind> --message <text> [--expected-action <X>]\n' >&2
    printf '       xfleet task <target> --task-kind <kind> --message-file <path> [--expected-action <X>]\n' >&2
    exit 1
fi

TARGET="$1"
shift

if [[ -z "${TARGET}" ]]; then
    printf 'Error: task requires a target worker name.\n' >&2
    exit 1
fi

MESSAGE_TEXT=""
MESSAGE_FILE=""
TASK_KIND=""
EXPECTED_ACTION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --task-kind)
            if [[ $# -lt 2 ]]; then
                printf 'task: --task-kind requires a value\n' >&2
                exit 1
            fi
            TASK_KIND="$2"
            shift 2
            ;;
        --message)
            if [[ $# -lt 2 ]]; then
                printf 'task: --message requires a value\n' >&2
                exit 1
            fi
            MESSAGE_TEXT="$2"
            shift 2
            ;;
        --message-file)
            if [[ $# -lt 2 ]]; then
                printf 'task: --message-file requires a value\n' >&2
                exit 1
            fi
            MESSAGE_FILE="$2"
            shift 2
            ;;
        --expected-action)
            if [[ $# -lt 2 ]]; then
                printf 'task: --expected-action requires a value\n' >&2
                exit 1
            fi
            EXPECTED_ACTION="$2"
            shift 2
            ;;
        *)
            printf 'task: unknown option: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Validate required --task-kind
# ---------------------------------------------------------------------------
if [[ -z "${TASK_KIND}" ]]; then
    printf 'Error: task requires --task-kind <kind>.\n' >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Validate and resolve message content (exactly one of --message/--message-file)
# ---------------------------------------------------------------------------
MESSAGE_CONTENT=""
resolve_message_content MESSAGE_TEXT MESSAGE_FILE task

# ---------------------------------------------------------------------------
# Resolve orchestrator state file path
# ---------------------------------------------------------------------------
COORD_ROOT="${XFLEET_COORDINATION_ROOT:-}"
if [[ -z "${COORD_ROOT}" ]]; then
    printf 'Error: XFLEET_COORDINATION_ROOT is not set (required for orchestrator state writes).\n' >&2
    exit 1
fi

ORCH_STATE_PATH="${COORD_ROOT}/state/_orchestrator.json"

# ---------------------------------------------------------------------------
# Build task wire message (orch → target worker)
# ---------------------------------------------------------------------------
TASK_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

TASK_MSG="$(jq -cn \
    --arg id              "${TASK_ID}" \
    --arg type            "task" \
    --arg from            "orchestrator" \
    --arg to              "${TARGET}" \
    --arg ts              "${TIMESTAMP}" \
    --arg task_kind       "${TASK_KIND}" \
    --arg description     "${MESSAGE_CONTENT}" \
    --arg expected_action "${EXPECTED_ACTION}" \
    '{id: $id, type: $type, from: $from, to: $to, timestamp: $ts, task_kind: $task_kind, description: $description, expected_action: $expected_action}'
)"

# ---------------------------------------------------------------------------
# Append task_log[] entry to _orchestrator.json (orch-owned state).
# Schema requires exactly 5 fields: task_id, target, task_kind,
# dispatched_at, response_status. No extra fields (additionalProperties: false).
# ---------------------------------------------------------------------------
TASK_LOG_ENTRY="$(jq -cn \
    --arg task_id         "${TASK_ID}" \
    --arg target          "${TARGET}" \
    --arg task_kind       "${TASK_KIND}" \
    --arg dispatched_at   "${TIMESTAMP}" \
    --arg response_status "pending" \
    '{task_id: $task_id, target: $target, task_kind: $task_kind, dispatched_at: $dispatched_at, response_status: $response_status}'
)"

state_update_field "${ORCH_STATE_PATH}" \
    ". + {task_log: ((.task_log // []) + [${TASK_LOG_ENTRY}])}"

# ---------------------------------------------------------------------------
# Publish task to target worker inbox (senders only XADD; listeners own
# consumer-group creation).
# ---------------------------------------------------------------------------
xfleet_redis XADD "inbox:${TARGET}" MAXLEN "~" 200 "*" data "${TASK_MSG}" >/dev/null

# ---------------------------------------------------------------------------
# The sender (orchestrator) is now DONE. The reflexive handler
# (task-response-handler.sh) is NOT invoked here: it is the worker-side
# handler fired by the TARGET worker's listener when the task arrives in
# inbox:{target} (it writes the worker's own current_task and emits
# task-response). Invoking it inline from the orch session would violate
# Writer Ownership (the orchestrator must never write a worker's state file)
# and would mis-resolve XFLEET_WORKER_NAME. Listener wiring lands in the
# later listener task.
# ---------------------------------------------------------------------------
printf 'task: sent to %s (task_id: %s, task_kind: %s)\n' \
    "${TARGET}" "${TASK_ID}" "${TASK_KIND}"
