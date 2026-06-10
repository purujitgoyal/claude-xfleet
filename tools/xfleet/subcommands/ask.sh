#!/usr/bin/env bash
# ask.sh — xfleet ask subcommand (exploration mode asker side).
#
# Sends a question to a parked explore responder (see `xfleet await` and the
# /xfleet:explore skill) and, by default, blocks until the answer lands in the
# asker's own inbox. Orchestrator-less: requires no coordination root, writes
# no state files, and deliberately skips assert_role — exploration mode is
# zero-setup, so the asker identity is self-bootstrapped (messaging.md (i)).
#
# The wire message is the standard `question` shape plus `reply_to`, because
# `from` carries the role string ("worker"), not a name — without `reply_to`
# the responder cannot address the answer.
#
# Usage: xfleet ask <responder> --message <text> [--timeout <secs>] [--async]
#        xfleet ask <responder> --message-file <path> [...]
#        xfleet ask --list
#
# Options:
#   --message <text>      Inline question text (exactly one of --message/--message-file)
#   --message-file <path> Path to question file (SC-5: requires a coordination root;
#                         rootless exploration uses --message)
#   --timeout <secs>      Blocking-wait deadline (default 120)
#   --async               Send and return immediately; fetch later via `xfleet peek`
#   --list                List parked responders (presence keys) and exit
#
# Exit codes:
#   0 — answer received (blocking), question sent (--async), or list printed
#   1 — validation error, Redis failure, or no answer within the timeout

_ASK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_ASK_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/redis.sh
source "${_ASK_DIR}/../lib/redis.sh"
# shellcheck source=../lib/message-content.sh
source "${_ASK_DIR}/../lib/message-content.sh"

PRESENCE_PREFIX="xfleet:explore:presence:"

# ---------------------------------------------------------------------------
# --list mode: scan presence keys and print parked responders
# ---------------------------------------------------------------------------
if [[ "${1:-}" = "--list" ]]; then
    CURSOR=0
    FOUND=0
    while true; do
        SCAN_RAW="$(xfleet_redis SCAN "${CURSOR}" MATCH "${PRESENCE_PREFIX}*" COUNT 100)" || {
            printf 'ask: redis SCAN failed\n' >&2
            exit 1
        }
        CURSOR="$(printf '%s' "${SCAN_RAW}" | sed -n '1p')"
        KEYS="$(printf '%s' "${SCAN_RAW}" | sed '1d')"
        while IFS= read -r key; do
            [[ -z "${key}" ]] && continue
            FOUND=1
            name="${key#"${PRESENCE_PREFIX}"}"
            val="$(xfleet_redis GET "${key}" 2>/dev/null)" || val=""
            repo="$(printf '%s' "${val}" | jq -r '.repo // "?"' 2>/dev/null)" || repo="?"
            parked_at="$(printf '%s' "${val}" | jq -r '.parked_at // "?"' 2>/dev/null)" || parked_at="?"
            printf '%s\t%s\t%s\n' "${name}" "${repo}" "${parked_at}"
        done <<< "${KEYS}"
        [[ "${CURSOR}" = "0" ]] && break
    done
    if [[ "${FOUND}" -eq 0 ]]; then
        printf '(no responders parked)\n'
    fi
    exit 0
fi

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
    printf 'Usage: xfleet ask <responder> --message <text> [--timeout <secs>] [--async]\n' >&2
    printf '       xfleet ask <responder> --message-file <path> [...]\n' >&2
    printf '       xfleet ask --list\n' >&2
    exit 1
fi

RECIPIENT="$1"
shift

MESSAGE_TEXT=""
MESSAGE_FILE=""
TIMEOUT_SECS=120
ASYNC=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --message)
            if [[ $# -lt 2 ]]; then
                printf 'ask: --message requires a value\n' >&2
                exit 1
            fi
            MESSAGE_TEXT="$2"
            shift 2
            ;;
        --message-file)
            if [[ $# -lt 2 ]]; then
                printf 'ask: --message-file requires a value\n' >&2
                exit 1
            fi
            MESSAGE_FILE="$2"
            shift 2
            ;;
        --timeout)
            if [[ $# -lt 2 ]]; then
                printf 'ask: --timeout requires a value\n' >&2
                exit 1
            fi
            TIMEOUT_SECS="$2"
            shift 2
            ;;
        --async)
            ASYNC=1
            shift
            ;;
        *)
            printf 'ask: unknown option: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Validate and resolve message content (exactly one of --message/--message-file)
# ---------------------------------------------------------------------------
MESSAGE_CONTENT=""
resolve_message_content MESSAGE_TEXT MESSAGE_FILE ask

# ---------------------------------------------------------------------------
# Self-bootstrapped asker identity (no assert_role — exploration mode)
# ---------------------------------------------------------------------------
ASKER="${XFLEET_WORKER_NAME:-}"
if [[ -z "${ASKER}" ]]; then
    ASKER="$(basename "${PWD}")"
fi

# ---------------------------------------------------------------------------
# Presence pre-check: warn (but still send) when no responder is parked
# ---------------------------------------------------------------------------
PRESENCE_VAL="$(xfleet_redis GET "${PRESENCE_PREFIX}${RECIPIENT}" 2>/dev/null)" || PRESENCE_VAL=""
if [[ -z "${PRESENCE_VAL}" ]]; then
    printf "ask: no responder parked as '%s' — sending anyway; see: xfleet ask --list\n" "${RECIPIENT}" >&2
fi

# ---------------------------------------------------------------------------
# Capture own-inbox high-water mark BEFORE sending, so the blocking wait only
# considers entries that arrive after the question goes out (avoids matching
# stale answers already sitting in the inbox).
# ---------------------------------------------------------------------------
OWN_STREAM="inbox:${ASKER}"
LAST_ID="$(xfleet_redis XREVRANGE "${OWN_STREAM}" + - COUNT 1 2>/dev/null | sed -n '1p')" || LAST_ID=""
[[ -z "${LAST_ID}" ]] && LAST_ID="0-0"

# ---------------------------------------------------------------------------
# Build and publish the wire message (question + reply_to)
# ---------------------------------------------------------------------------
MSG_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

FULL_MSG="$(jq -cn \
    --arg id        "${MSG_ID}" \
    --arg type      "question" \
    --arg from      "worker" \
    --arg reply_to  "${ASKER}" \
    --arg to        "${RECIPIENT}" \
    --arg ts        "${TIMESTAMP}" \
    --arg content   "${MESSAGE_CONTENT}" \
    '{id: $id, type: $type, from: $from, reply_to: $reply_to, to: $to, timestamp: $ts, content: $content}'
)"

# Senders only XADD; the responder's await owns consumer-group creation.
xfleet_redis XADD "inbox:${RECIPIENT}" MAXLEN "~" 200 "*" data "${FULL_MSG}" >/dev/null

if [[ "${ASYNC}" -eq 1 ]]; then
    printf 'ask: sent to %s (msg_id: %s)\n' "${RECIPIENT}" "${MSG_ID}"
    printf 'ask: answer will land in inbox:%s — check with: xfleet peek %s\n' "${ASKER}" "${ASKER}"
    exit 0
fi

# ---------------------------------------------------------------------------
# Blocking wait: plain XREAD (non-consuming, no group) after LAST_ID until an
# `answer`-type message arrives or the deadline passes. Non-answer messages
# advance LAST_ID and are otherwise ignored.
# ---------------------------------------------------------------------------
START_SECONDS="${SECONDS}"

while true; do
    elapsed=$(( SECONDS - START_SECONDS ))
    left=$(( TIMEOUT_SECS - elapsed ))
    if [[ "${left}" -le 0 ]]; then
        printf 'ask: no answer within %ss — responder may not be parked; try: xfleet ask --list\n' \
            "${TIMEOUT_SECS}" >&2
        exit 1
    fi

    rc=0
    RESULT="$(xfleet_redis XREAD BLOCK $(( left * 1000 )) COUNT 10 STREAMS "${OWN_STREAM}" "${LAST_ID}" 2>/dev/null)" || rc=$?
    if [[ "${rc}" -ne 0 ]]; then
        # Redis error — back off before retrying (avoids busy-spin).
        sleep 1
        continue
    fi
    [[ -z "${RESULT}" ]] && continue

    # Parse redis-cli XREAD output: stream-name line, then per entry an id line
    # ("NNN-NNN"), a field-name line ("data"), and the JSON value line.
    CURRENT_ID=""
    while IFS= read -r line; do
        [[ -z "${line}" ]] && continue
        if [[ "${line}" =~ ^[0-9]+-[0-9]+$ ]]; then
            CURRENT_ID="${line}"
            LAST_ID="${line}"
            continue
        fi
        [[ -z "${CURRENT_ID}" ]] && continue
        # Skip bare field names (e.g. "data"); the stream-name line contains
        # ':' so it never matches this pattern.
        if [[ "${line}" =~ ^[a-zA-Z_]+$ ]]; then
            continue
        fi
        # Value line — answer?
        TYPE="$(printf '%s' "${line}" | jq -r '.type // empty' 2>/dev/null)" || TYPE=""
        if [[ "${TYPE}" = "answer" ]]; then
            printf '%s\n' "$(printf '%s' "${line}" | jq -r '.content // empty')"
            exit 0
        fi
        CURRENT_ID=""
    done <<< "${RESULT}"
done
