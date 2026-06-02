#!/usr/bin/env bash
# concern.sh — xfleet concern subcommand (Task 22).
#
# Sends a peer-to-peer concern from one worker to another. Per messaging.md (b):
# sender must be worker; recipient is a peer worker. Increments the round counter
# (messaging.md g, F-15) keyed on the STABLE concern-id (not the per-message id),
# so repeated concerns in the same dispute accumulate.
#
# Usage: xfleet concern <recipient> <concern-id> --message <text>
#        xfleet concern <recipient> <concern-id> --message-file <path>
#
# Options:
#   --message <text>      Inline message text (exactly one of --message/--message-file)
#   --message-file <path> Path to a file containing the message (SC-5 scoped)
#
# Exit codes:
#   0 — message published to inbox:{recipient}, round counter incremented
#   1 — validation error or Redis failure

_CONCERN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_CONCERN_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/redis.sh
source "${_CONCERN_DIR}/../lib/redis.sh"
# shellcheck source=../lib/sender-authority.sh
source "${_CONCERN_DIR}/../lib/sender-authority.sh"
# shellcheck source=../lib/message-content.sh
source "${_CONCERN_DIR}/../lib/message-content.sh"
# shellcheck source=../lib/round-counter.sh
source "${_CONCERN_DIR}/../lib/round-counter.sh"
# shellcheck source=../lib/listener.sh
source "${_CONCERN_DIR}/../lib/listener.sh"

# ---------------------------------------------------------------------------
# Role check — worker only (messaging.md b)
# ---------------------------------------------------------------------------
assert_role worker "concerns are peer-to-peer (worker to peer-worker); from an orchestrator session use 'directive' instead."

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
if [[ $# -lt 2 ]]; then
    printf 'Usage: xfleet concern <recipient> <concern-id> --message <text>\n' >&2
    printf '       xfleet concern <recipient> <concern-id> --message-file <path>\n' >&2
    exit 1
fi

RECIPIENT="$1"
CONCERN_ID="$2"
shift 2

if [[ -z "${RECIPIENT}" ]]; then
    printf 'Error: concern requires a recipient.\n' >&2
    exit 1
fi

if [[ -z "${CONCERN_ID}" ]]; then
    printf 'Error: concern requires a concern-id (stable across all rounds of the dispute).\n' >&2
    exit 1
fi

MESSAGE_TEXT=""
MESSAGE_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --message)
            if [[ $# -lt 2 ]]; then
                printf 'concern: --message requires a value\n' >&2
                exit 1
            fi
            MESSAGE_TEXT="$2"
            shift 2
            ;;
        --message-file)
            if [[ $# -lt 2 ]]; then
                printf 'concern: --message-file requires a value\n' >&2
                exit 1
            fi
            MESSAGE_FILE="$2"
            shift 2
            ;;
        *)
            printf 'concern: unknown option: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Validate and resolve message content (exactly one of --message/--message-file)
# ---------------------------------------------------------------------------
MESSAGE_CONTENT=""
resolve_message_content MESSAGE_TEXT MESSAGE_FILE concern

# ---------------------------------------------------------------------------
# Build wire message
# ---------------------------------------------------------------------------
SENDER="${XFLEET_ROLE}"   # "worker" (already asserted)
MSG_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

FULL_MSG="$(jq -cn \
    --arg id         "${MSG_ID}" \
    --arg type       "concern" \
    --arg from       "${SENDER}" \
    --arg to         "${RECIPIENT}" \
    --arg ts         "${TIMESTAMP}" \
    --arg content    "${MESSAGE_CONTENT}" \
    --arg concern_id "${CONCERN_ID}" \
    '{id: $id, type: $type, from: $from, to: $to, timestamp: $ts, content: $content, concern_id: $concern_id}'
)"

# ---------------------------------------------------------------------------
# Increment round counter BEFORE publishing (F-15: concern increments, not response).
# Keyed on the STABLE concern-id so all rounds of the same dispute accumulate.
# ---------------------------------------------------------------------------
ROUND="$(incr_round "${CONCERN_ID}")"

# ---------------------------------------------------------------------------
# Publish to recipient inbox
# ---------------------------------------------------------------------------
STREAM="inbox:${RECIPIENT}"

# Senders only XADD — the listener owns consumer-group creation.
xfleet_redis XADD "${STREAM}" MAXLEN "~" 200 "*" data "${FULL_MSG}" >/dev/null

# F-42 two-call pattern: ensure our own listener is live so the response is not dropped.
send_with_verify "${XFLEET_WORKER_NAME}"

printf 'concern: sent to %s (msg_id: %s, concern_id: %s, round: %s)\n' \
    "${RECIPIENT}" "${MSG_ID}" "${CONCERN_ID}" "${ROUND}"
