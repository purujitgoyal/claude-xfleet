#!/usr/bin/env bash
# question.sh — xfleet question subcommand (Task 21).
#
# Sends an ad-hoc clarification question from a worker to the orchestrator or a
# peer worker. Per messaging.md (b): sender must be worker; recipient must NOT
# be the literal "human".
#
# Usage: xfleet question <recipient> --message <text>
#        xfleet question <recipient> --message-file <path>
#
# Options:
#   --message <text>      Inline message text (exactly one of --message/--message-file)
#   --message-file <path> Path to a file containing the message (SC-5 scoped)
#
# Exit codes:
#   0 — message published to inbox:{recipient}
#   1 — validation error or Redis failure

_QUESTION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_QUESTION_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/redis.sh
source "${_QUESTION_DIR}/../lib/redis.sh"
# shellcheck source=../lib/sender-authority.sh
source "${_QUESTION_DIR}/../lib/sender-authority.sh"
# shellcheck source=../lib/message-content.sh
source "${_QUESTION_DIR}/../lib/message-content.sh"
# shellcheck source=../lib/listener.sh
source "${_QUESTION_DIR}/../lib/listener.sh"

# ---------------------------------------------------------------------------
# Role check — worker only
# ---------------------------------------------------------------------------
assert_role worker "questions are worker-originated (to orch or a peer-worker); from an orchestrator session use 'directive' to clarify scope instead."

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
    printf 'Usage: xfleet question <recipient> --message <text>\n' >&2
    printf '       xfleet question <recipient> --message-file <path>\n' >&2
    exit 1
fi

RECIPIENT="$1"
shift

# Reject the literal recipient "human" (messaging.md b, cluster 4g §1).
if [[ "${RECIPIENT}" = "human" ]]; then
    printf 'Error: question recipient cannot be "human". Direct questions to the orchestrator or a peer worker.\n' >&2
    exit 1
fi

MESSAGE_TEXT=""
MESSAGE_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --message)
            if [[ $# -lt 2 ]]; then
                printf 'question: --message requires a value\n' >&2
                exit 1
            fi
            MESSAGE_TEXT="$2"
            shift 2
            ;;
        --message-file)
            if [[ $# -lt 2 ]]; then
                printf 'question: --message-file requires a value\n' >&2
                exit 1
            fi
            MESSAGE_FILE="$2"
            shift 2
            ;;
        *)
            printf 'question: unknown option: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Validate and resolve message content (exactly one of --message/--message-file)
# ---------------------------------------------------------------------------
MESSAGE_CONTENT=""
resolve_message_content MESSAGE_TEXT MESSAGE_FILE question

# ---------------------------------------------------------------------------
# Build and publish the wire message
# ---------------------------------------------------------------------------
SENDER="${XFLEET_ROLE}"   # "worker" (already asserted above)
MSG_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

FULL_MSG="$(jq -cn \
    --arg id        "${MSG_ID}" \
    --arg type      "question" \
    --arg from      "${SENDER}" \
    --arg to        "${RECIPIENT}" \
    --arg ts        "${TIMESTAMP}" \
    --arg content   "${MESSAGE_CONTENT}" \
    '{id: $id, type: $type, from: $from, to: $to, timestamp: $ts, content: $content}'
)"

STREAM="inbox:${RECIPIENT}"

# The recipient's listener owns consumer-group creation (listen.sh does
# XGROUP CREATE ... <group> 0 MKSTREAM, reading from id 0 so it sees messages
# added before the group existed). Senders only XADD.
#
# Publish via XADD. Use a modest MAXLEN cap consistent with wave-1 worker inboxes.
xfleet_redis XADD "${STREAM}" MAXLEN "~" 200 "*" data "${FULL_MSG}" >/dev/null

# F-42 two-call pattern: ensure our own listener is live so the response is not dropped.
send_with_verify "${XFLEET_WORKER_NAME}"

printf 'question: sent to %s (msg_id: %s)\n' "${RECIPIENT}" "${MSG_ID}"
