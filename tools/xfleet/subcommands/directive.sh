#!/usr/bin/env bash
# directive.sh — xfleet directive subcommand (Task 23).
#
# Sends an orchestrator→worker procedural directive. Per messaging.md (b):
# sender must be orchestrator. Auto-fires human_engaged.active=true in
# _orchestrator.json on every dispatch (cluster 4a #4). Appends a record to
# directive_log[] in _orchestrator.json (orch-owned state).
#
# The directive is published to inbox:{target-worker} as a "directive" wire
# message carrying the optional expected_action field. The worker-side reflexive
# handlers (directive-ack-handler.sh / directive-response-handler.sh) are fired by
# the TARGET worker's listener on receipt — NOT inline by this sender — and they
# overwrite the worker's current_task when expected_action is non-empty. Per
# ownership rules, THIS SCRIPT never writes the worker's state file.
#
# Usage:
#   xfleet directive <target> --message <text> [--expected_action <X>] [--scope <S>] [--concern_id <C>]
#   xfleet directive <target> --message-file <path> [--expected_action <X>] [--scope <S>] [--concern_id <C>]
#
# Options:
#   --message <text>          Inline message text (exactly one of --message/--message-file)
#   --message-file <path>     Path to a file containing the message (SC-5 scoped)
#   --expected_action <X>     Action the orchestrator expects the worker to take.
#                             When present: worker's current_task is overwritten (source=orch-directive).
#                             When absent:  informational only — directive_log[] appended, current_task untouched.
#   --scope <S>               Scope/subject of the directive (default: "general").
#   --concern_id <C>          Concern id this directive addresses (default: null / not concern-scoped).
#
# Exit codes:
#   0 — directive dispatched; directive_log[] + human_engaged updated in orch
#       state; directive published to inbox:{target} (worker-side reflexive
#       handlers fire later, on the worker's listener)
#   1 — validation error, role rejection, or Redis/state failure

_DIRECTIVE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_DIRECTIVE_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/redis.sh
source "${_DIRECTIVE_DIR}/../lib/redis.sh"
# shellcheck source=../lib/sender-authority.sh
source "${_DIRECTIVE_DIR}/../lib/sender-authority.sh"
# shellcheck source=../lib/message-content.sh
source "${_DIRECTIVE_DIR}/../lib/message-content.sh"
# shellcheck source=../lib/state-io.sh
source "${_DIRECTIVE_DIR}/../lib/state-io.sh"

# ---------------------------------------------------------------------------
# Role check — orchestrator only (messaging.md b)
# ---------------------------------------------------------------------------
assert_role orchestrator

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
    printf 'Usage: xfleet directive <target> --message <text> [--expected_action <X>] [--scope <S>] [--concern_id <C>]\n' >&2
    printf '       xfleet directive <target> --message-file <path> [--expected_action <X>] [--scope <S>] [--concern_id <C>]\n' >&2
    exit 1
fi

TARGET="$1"
shift

if [[ -z "${TARGET}" ]]; then
    printf 'Error: directive requires a target worker name.\n' >&2
    exit 1
fi

MESSAGE_TEXT=""
MESSAGE_FILE=""
EXPECTED_ACTION=""
SCOPE="general"
CONCERN_ID_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --message)
            if [[ $# -lt 2 ]]; then
                printf 'directive: --message requires a value\n' >&2
                exit 1
            fi
            MESSAGE_TEXT="$2"
            shift 2
            ;;
        --message-file)
            if [[ $# -lt 2 ]]; then
                printf 'directive: --message-file requires a value\n' >&2
                exit 1
            fi
            MESSAGE_FILE="$2"
            shift 2
            ;;
        --expected_action)
            if [[ $# -lt 2 ]]; then
                printf 'directive: --expected_action requires a value\n' >&2
                exit 1
            fi
            EXPECTED_ACTION="$2"
            shift 2
            ;;
        --scope)
            if [[ $# -lt 2 ]]; then
                printf 'directive: --scope requires a value\n' >&2
                exit 1
            fi
            SCOPE="$2"
            shift 2
            ;;
        --concern_id)
            if [[ $# -lt 2 ]]; then
                printf 'directive: --concern_id requires a value\n' >&2
                exit 1
            fi
            CONCERN_ID_ARG="$2"
            shift 2
            ;;
        *)
            printf 'directive: unknown option: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Validate and resolve message content (exactly one of --message/--message-file)
# ---------------------------------------------------------------------------
MESSAGE_CONTENT=""
resolve_message_content MESSAGE_TEXT MESSAGE_FILE directive

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
# Build directive wire message (orch → target worker)
# ---------------------------------------------------------------------------
MSG_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Build the wire message. expected_action is included as a (possibly empty)
# string field so the worker-side handler can decide based on emptiness.
DIRECTIVE_MSG="$(jq -cn \
    --arg id              "${MSG_ID}" \
    --arg type            "directive" \
    --arg from            "orchestrator" \
    --arg to              "${TARGET}" \
    --arg ts              "${TIMESTAMP}" \
    --arg content         "${MESSAGE_CONTENT}" \
    --arg expected_action "${EXPECTED_ACTION}" \
    --arg scope           "${SCOPE}" \
    --argjson concern_id  "$([ -n "${CONCERN_ID_ARG}" ] && printf '"%s"' "${CONCERN_ID_ARG}" || printf 'null')" \
    '{id: $id, type: $type, from: $from, to: $to, timestamp: $ts, content: $content, expected_action: $expected_action, scope: $scope, concern_id: $concern_id}'
)"

# ---------------------------------------------------------------------------
# Append directive_log[] entry to _orchestrator.json (orch-owned state).
# Schema requires all 7 fields (directive_id, target, concern_id, scope,
# expected_action, dispatched_at, response_status); expected_action stored as
# "" when not provided (empty string is a valid string per schema).
# ---------------------------------------------------------------------------
DIRECTIVE_LOG_ENTRY="$(jq -cn \
    --arg directive_id    "${MSG_ID}" \
    --arg target          "${TARGET}" \
    --argjson concern_id  "$([ -n "${CONCERN_ID_ARG}" ] && printf '"%s"' "${CONCERN_ID_ARG}" || printf 'null')" \
    --arg scope           "${SCOPE}" \
    --arg expected_action "${EXPECTED_ACTION}" \
    --arg dispatched_at   "${TIMESTAMP}" \
    --arg response_status "pending" \
    '{directive_id: $directive_id, target: $target, concern_id: $concern_id, scope: $scope, expected_action: $expected_action, dispatched_at: $dispatched_at, response_status: $response_status}'
)"

# Auto-fire human_engaged.active=true on every directive dispatch (cluster 4a #4).
# concern_id / reason stay null when not concern-scoped.
HUMAN_ENGAGED_UPDATE="$(jq -cn \
    --argjson concern_id "$([ -n "${CONCERN_ID_ARG}" ] && printf '"%s"' "${CONCERN_ID_ARG}" || printf 'null')" \
    --arg set_at         "${TIMESTAMP}" \
    '{active: true, concern_id: $concern_id, set_at: $set_at, reason: null}'
)"

# Apply both updates to _orchestrator.json atomically in a single jq expression
# so the file is only written once.
state_update_field "${ORCH_STATE_PATH}" \
    ". + {directive_log: ((.directive_log // []) + [${DIRECTIVE_LOG_ENTRY}]), human_engaged: ${HUMAN_ENGAGED_UPDATE}}"

# ---------------------------------------------------------------------------
# Publish directive to target worker inbox (senders only XADD; listeners own
# consumer-group creation).
# ---------------------------------------------------------------------------
xfleet_redis XADD "inbox:${TARGET}" MAXLEN "~" 200 "*" data "${DIRECTIVE_MSG}" >/dev/null

# ---------------------------------------------------------------------------
# The sender (orchestrator) is now DONE. The reflexive handlers
# (directive-ack-handler.sh / directive-response-handler.sh) are NOT invoked
# here: they are worker-side handlers fired by the TARGET worker's listener when
# the directive arrives in inbox:{target} (they write the worker's own
# current_task and emit directive-ack/directive-response). Invoking them inline
# from the orch session would violate Writer Ownership (the orchestrator must
# never write a worker's state file) and would mis-resolve XFLEET_WORKER_NAME.
# Listener wiring lands in the later listener task.
# ---------------------------------------------------------------------------
printf 'directive: sent to %s (directive_id: %s, scope: %s, expected_action: "%s"); human_engaged=true\n' \
    "${TARGET}" "${MSG_ID}" "${SCOPE}" "${EXPECTED_ACTION}"
