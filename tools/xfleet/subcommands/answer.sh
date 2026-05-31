#!/usr/bin/env bash
# answer.sh — xfleet answer subcommand (Task 21).
#
# Sends a clarification answer to the original questioner. Per messaging.md (b):
# sender may be orchestrator or worker; recipient is the original questioner
# (must be supplied explicitly by the caller).
#
# Usage: xfleet answer <recipient> --message <text>
#        xfleet answer <recipient> --message-file <path>
#
# Options:
#   --message <text>      Inline message text (exactly one of --message/--message-file)
#   --message-file <path> Path to a file containing the message (SC-5 scoped)
#
# Exit codes:
#   0 — message published to inbox:{recipient}
#   1 — validation error or Redis failure

_ANSWER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_ANSWER_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/redis.sh
source "${_ANSWER_DIR}/../lib/redis.sh"
# shellcheck source=../lib/sender-authority.sh
source "${_ANSWER_DIR}/../lib/sender-authority.sh"
# shellcheck source=../lib/message-content.sh
source "${_ANSWER_DIR}/../lib/message-content.sh"

# ---------------------------------------------------------------------------
# Role check — orchestrator OR worker both allowed.
# Validate XFLEET_ROLE is set and known (not blank/garbage), without asserting
# a single required value. Re-use assert_role logic selectively.
# ---------------------------------------------------------------------------
_ROLE="${XFLEET_ROLE:-}"
if [[ -z "${_ROLE}" ]]; then
    printf 'Error: XFLEET_ROLE is not set. Export XFLEET_ROLE=orchestrator or XFLEET_ROLE=worker before running xfleet subcommands.\n' >&2
    exit 1
fi
if [[ "${_ROLE}" != "orchestrator" && "${_ROLE}" != "worker" ]]; then
    printf 'Error: XFLEET_ROLE has unknown value "%s". Valid values: orchestrator, worker.\n' "${_ROLE}" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
    printf 'Usage: xfleet answer <recipient> --message <text>\n' >&2
    printf '       xfleet answer <recipient> --message-file <path>\n' >&2
    exit 1
fi

RECIPIENT="$1"
shift

# Reject a blank recipient so we never XADD to a degenerate "inbox:" stream.
if [[ -z "${RECIPIENT}" ]]; then
    printf 'Error: answer requires a recipient.\n' >&2
    exit 1
fi

MESSAGE_TEXT=""
MESSAGE_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --message)
            if [[ $# -lt 2 ]]; then
                printf 'answer: --message requires a value\n' >&2
                exit 1
            fi
            MESSAGE_TEXT="$2"
            shift 2
            ;;
        --message-file)
            if [[ $# -lt 2 ]]; then
                printf 'answer: --message-file requires a value\n' >&2
                exit 1
            fi
            MESSAGE_FILE="$2"
            shift 2
            ;;
        *)
            printf 'answer: unknown option: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Validate and resolve message content (exactly one of --message/--message-file)
# ---------------------------------------------------------------------------
MESSAGE_CONTENT=""
resolve_message_content MESSAGE_TEXT MESSAGE_FILE answer

# ---------------------------------------------------------------------------
# Build and publish the wire message
# ---------------------------------------------------------------------------
SENDER="${_ROLE}"
MSG_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

FULL_MSG="$(jq -cn \
    --arg id        "${MSG_ID}" \
    --arg type      "answer" \
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
# Publish via XADD.
xfleet_redis XADD "${STREAM}" MAXLEN "~" 200 "*" data "${FULL_MSG}" >/dev/null

printf 'answer: sent to %s (msg_id: %s)\n' "${RECIPIENT}" "${MSG_ID}"
