#!/usr/bin/env bash
# resolution.sh — xfleet resolution subcommand (Task 22).
#
# Closes a concern by sending a resolution to the peer worker. Per messaging.md (b)
# and section (e): sender must be worker; recipient is the peer worker who raised
# the concern. Handler-internally emits resolution-ack to the peer and
# resolution-summary to the orchestrator (F-33 closure handshake); marks the
# concern closed-acked in the sender's own state.
#
# Usage: xfleet resolution <recipient> <concern-id> --message <text>
#        xfleet resolution <recipient> <concern-id> --message-file <path>
#
# Options:
#   --message <text>      Inline message text (exactly one of --message/--message-file)
#   --message-file <path> Path to a file containing the message (SC-5 scoped)
#
# Exit codes:
#   0 — resolution sent; reflexive resolution-ack + resolution-summary emitted;
#       concern recorded in confirmed_closed_concerns[]
#   1 — validation error or Redis/state failure

_RESOLUTION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_RESOLUTION_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/redis.sh
source "${_RESOLUTION_DIR}/../lib/redis.sh"
# shellcheck source=../lib/sender-authority.sh
source "${_RESOLUTION_DIR}/../lib/sender-authority.sh"
# shellcheck source=../lib/message-content.sh
source "${_RESOLUTION_DIR}/../lib/message-content.sh"
# shellcheck source=../lib/state-io.sh
source "${_RESOLUTION_DIR}/../lib/state-io.sh"

# ---------------------------------------------------------------------------
# Role check — worker only (messaging.md b)
# ---------------------------------------------------------------------------
assert_role worker

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
if [[ $# -lt 2 ]]; then
    printf 'Usage: xfleet resolution <recipient> <concern-id> --message <text>\n' >&2
    printf '       xfleet resolution <recipient> <concern-id> --message-file <path>\n' >&2
    exit 1
fi

RECIPIENT="$1"
CONCERN_ID="$2"
shift 2

if [[ -z "${RECIPIENT}" ]]; then
    printf 'Error: resolution requires a recipient.\n' >&2
    exit 1
fi

if [[ -z "${CONCERN_ID}" ]]; then
    printf 'Error: resolution requires a concern-id.\n' >&2
    exit 1
fi

MESSAGE_TEXT=""
MESSAGE_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --message)
            if [[ $# -lt 2 ]]; then
                printf 'resolution: --message requires a value\n' >&2
                exit 1
            fi
            MESSAGE_TEXT="$2"
            shift 2
            ;;
        --message-file)
            if [[ $# -lt 2 ]]; then
                printf 'resolution: --message-file requires a value\n' >&2
                exit 1
            fi
            MESSAGE_FILE="$2"
            shift 2
            ;;
        *)
            printf 'resolution: unknown option: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Validate and resolve message content (exactly one of --message/--message-file)
# ---------------------------------------------------------------------------
MESSAGE_CONTENT=""
resolve_message_content MESSAGE_TEXT MESSAGE_FILE resolution

# ---------------------------------------------------------------------------
# Resolve the worker's own state file the standard way (matches listen.sh):
#   $XFLEET_COORDINATION_ROOT/state/${XFLEET_WORKER_NAME}.json
# Required so the closure handshake can mark the concern closed-acked.
# ---------------------------------------------------------------------------
COORD_ROOT="${XFLEET_COORDINATION_ROOT:-}"
if [[ -z "${COORD_ROOT}" ]]; then
    printf 'Error: XFLEET_COORDINATION_ROOT is not set (required for resolution closure handshake).\n' >&2
    exit 1
fi

WORKER_NAME="${XFLEET_WORKER_NAME:-}"
if [[ -z "${WORKER_NAME}" ]]; then
    printf 'Error: XFLEET_WORKER_NAME is not set (the worker'\''s short-name; required to locate its own state file).\n' >&2
    exit 1
fi

WORKER_STATE_PATH="${COORD_ROOT}/state/${WORKER_NAME}.json"

# ---------------------------------------------------------------------------
# Build the primary resolution wire message (worker → peer worker)
# ---------------------------------------------------------------------------
SENDER="${XFLEET_ROLE}"   # "worker" (already asserted)
MSG_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

RESOLUTION_MSG="$(jq -cn \
    --arg id         "${MSG_ID}" \
    --arg type       "resolution" \
    --arg from       "${SENDER}" \
    --arg to         "${RECIPIENT}" \
    --arg ts         "${TIMESTAMP}" \
    --arg content    "${MESSAGE_CONTENT}" \
    --arg concern_id "${CONCERN_ID}" \
    '{id: $id, type: $type, from: $from, to: $to, timestamp: $ts, content: $content, concern_id: $concern_id}'
)"

# ---------------------------------------------------------------------------
# Publish primary resolution to peer worker inbox
# ---------------------------------------------------------------------------
xfleet_redis XADD "inbox:${RECIPIENT}" MAXLEN "~" 200 "*" data "${RESOLUTION_MSG}" >/dev/null

# ---------------------------------------------------------------------------
# Reflexive: emit resolution-ack to peer worker (F-33, messaging.md e)
# ---------------------------------------------------------------------------
# Invoke the resolution-ack handler directly — it handles its own XADD.
_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${_RESOLUTION_DIR}/../../.." && pwd)}"
_ACK_HANDLER="${_PLUGIN_ROOT}/tools/xfleet/handlers/resolution-ack-handler.sh"

if [[ ! -x "${_ACK_HANDLER}" ]]; then
    printf 'Error: resolution-ack-handler.sh not found or not executable at %s\n' "${_ACK_HANDLER}" >&2
    exit 1
fi

"${_ACK_HANDLER}" "${RECIPIENT}" "${CONCERN_ID}" "${MSG_ID}" "${MESSAGE_CONTENT}"

# ---------------------------------------------------------------------------
# Reflexive: emit resolution-summary to orchestrator (F-33, messaging.md e)
# ---------------------------------------------------------------------------
ORCH_RECIPIENT="orchestrator"
SUMMARY_MSG_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
SUMMARY_TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

SUMMARY_MSG="$(jq -cn \
    --arg id              "${SUMMARY_MSG_ID}" \
    --arg type            "resolution-summary" \
    --arg from            "${SENDER}" \
    --arg to              "${ORCH_RECIPIENT}" \
    --arg ts              "${SUMMARY_TIMESTAMP}" \
    --arg content         "${MESSAGE_CONTENT}" \
    --arg concern_id      "${CONCERN_ID}" \
    --arg resolution_id   "${MSG_ID}" \
    '{id: $id, type: $type, from: $from, to: $to, timestamp: $ts, content: $content, concern_id: $concern_id, resolution_id: $resolution_id}'
)"

xfleet_redis XADD "inbox:${ORCH_RECIPIENT}" MAXLEN "~" 200 "*" data "${SUMMARY_MSG}" >/dev/null

# ---------------------------------------------------------------------------
# Mark concern closed-acked in sender's state (confirmed_closed_concerns[])
# Deduplicate via jq: add concern_id only if not already present.
# ---------------------------------------------------------------------------
state_update_field "${WORKER_STATE_PATH}" \
    ". + {confirmed_closed_concerns: ((.confirmed_closed_concerns // []) + [\"${CONCERN_ID}\"] | unique)}"

printf 'resolution: sent to %s (msg_id: %s, concern_id: %s); resolution-ack + resolution-summary emitted; concern marked closed\n' \
    "${RECIPIENT}" "${MSG_ID}" "${CONCERN_ID}"
