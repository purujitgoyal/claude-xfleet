#!/usr/bin/env bash
# concern-reopen.sh — xfleet concern-reopen subcommand (Task 22).
#
# Reopens a previously closed concern. Per messaging.md (b): sender may be
# orchestrator (human review) or worker (new findings); recipient is a peer worker.
# Does NOT increment or reset the round counter — continues the existing counter
# (messaging.md g, F-15).
#
# Usage: xfleet concern-reopen <recipient> <concern-id> --message <text>
#        xfleet concern-reopen <recipient> <concern-id> --message-file <path>
#        [--alignment-hint <text>]
#
# Options:
#   --message <text>        Inline message text (exactly one of --message/--message-file)
#   --message-file <path>   Path to a file containing the message (SC-5 scoped)
#   --alignment-hint <text> Optional hint for realignment (not part of wire content)
#
# Exit codes:
#   0 — message published to inbox:{recipient}
#   1 — validation error or Redis failure

_CONCERN_REOPEN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_CONCERN_REOPEN_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/redis.sh
source "${_CONCERN_REOPEN_DIR}/../lib/redis.sh"
# shellcheck source=../lib/sender-authority.sh
source "${_CONCERN_REOPEN_DIR}/../lib/sender-authority.sh"
# shellcheck source=../lib/message-content.sh
source "${_CONCERN_REOPEN_DIR}/../lib/message-content.sh"

# ---------------------------------------------------------------------------
# Role check — orchestrator OR worker (messaging.md b: peer-symmetry).
# Mirror the either-role inline validation from answer.sh.
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
if [[ $# -lt 2 ]]; then
    printf 'Usage: xfleet concern-reopen <recipient> <concern-id> --message <text>\n' >&2
    printf '       xfleet concern-reopen <recipient> <concern-id> --message-file <path>\n' >&2
    exit 1
fi

RECIPIENT="$1"
CONCERN_ID="$2"
shift 2

if [[ -z "${RECIPIENT}" ]]; then
    printf 'Error: concern-reopen requires a recipient.\n' >&2
    exit 1
fi

if [[ -z "${CONCERN_ID}" ]]; then
    printf 'Error: concern-reopen requires a concern-id.\n' >&2
    exit 1
fi

MESSAGE_TEXT=""
MESSAGE_FILE=""
ALIGNMENT_HINT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --message)
            if [[ $# -lt 2 ]]; then
                printf 'concern-reopen: --message requires a value\n' >&2
                exit 1
            fi
            MESSAGE_TEXT="$2"
            shift 2
            ;;
        --message-file)
            if [[ $# -lt 2 ]]; then
                printf 'concern-reopen: --message-file requires a value\n' >&2
                exit 1
            fi
            MESSAGE_FILE="$2"
            shift 2
            ;;
        --alignment-hint)
            if [[ $# -lt 2 ]]; then
                printf 'concern-reopen: --alignment-hint requires a value\n' >&2
                exit 1
            fi
            ALIGNMENT_HINT="$2"
            shift 2
            ;;
        *)
            printf 'concern-reopen: unknown option: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Validate and resolve message content (exactly one of --message/--message-file)
# ---------------------------------------------------------------------------
MESSAGE_CONTENT=""
resolve_message_content MESSAGE_TEXT MESSAGE_FILE concern-reopen

# ---------------------------------------------------------------------------
# Build wire message
# Include concern_id so the recipient can correlate with the original concern.
# alignment_hint is an optional advisory field (null when absent).
# ---------------------------------------------------------------------------
SENDER="${_ROLE}"
MSG_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

FULL_MSG="$(jq -cn \
    --arg id              "${MSG_ID}" \
    --arg type            "concern-reopen" \
    --arg from            "${SENDER}" \
    --arg to              "${RECIPIENT}" \
    --arg ts              "${TIMESTAMP}" \
    --arg content         "${MESSAGE_CONTENT}" \
    --arg concern_id      "${CONCERN_ID}" \
    --arg alignment_hint  "${ALIGNMENT_HINT}" \
    '{
        id: $id,
        type: $type,
        from: $from,
        to: $to,
        timestamp: $ts,
        content: $content,
        concern_id: $concern_id,
        alignment_hint: (if $alignment_hint == "" then null else $alignment_hint end)
    }'
)"

# ---------------------------------------------------------------------------
# Publish to recipient inbox (no round-counter increment — continues existing)
# ---------------------------------------------------------------------------
STREAM="inbox:${RECIPIENT}"

xfleet_redis XADD "${STREAM}" MAXLEN "~" 200 "*" data "${FULL_MSG}" >/dev/null

printf 'concern-reopen: sent to %s (msg_id: %s, concern_id: %s)\n' \
    "${RECIPIENT}" "${MSG_ID}" "${CONCERN_ID}"
