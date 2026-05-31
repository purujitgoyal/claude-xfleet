#!/usr/bin/env bash
# review.sh — xfleet review subcommand (Task 22b).
#
# Sends a finalized review document alert to the orchestrator (worker → orchestrator).
# Per messaging.md (b): sender must be worker; recipient is always orchestrator.
# This is an alert-not-content signal: --path points at the review file on disk;
# the file contents are NOT copied into the wire message.
#
# Reflexive state update: for each --finding <id> provided, sets
# findings_status[<id>] = "awaiting-review" in the worker's own state file.
#
# Usage: xfleet review --path <review-file> [--finding <id>] [--finding <id>] ...
#
# Options:
#   --path <file>      Path to the review file (SC-5 scoped; REQUIRED)
#   --finding <id>     Finding id to mark "awaiting-review" (repeatable; optional)
#
# Exit codes:
#   0 — review signal sent; findings_status updated for any provided finding ids
#   1 — validation error or Redis/state failure

_REVIEW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_REVIEW_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/redis.sh
source "${_REVIEW_DIR}/../lib/redis.sh"
# shellcheck source=../lib/sender-authority.sh
source "${_REVIEW_DIR}/../lib/sender-authority.sh"
# shellcheck source=../lib/state-io.sh
source "${_REVIEW_DIR}/../lib/state-io.sh"

# ---------------------------------------------------------------------------
# Role check — worker only (messaging.md b)
# ---------------------------------------------------------------------------
assert_role worker

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
REVIEW_PATH=""
FINDING_IDS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --path)
            if [[ $# -lt 2 ]]; then
                printf 'review: --path requires a value\n' >&2
                exit 1
            fi
            REVIEW_PATH="$2"
            shift 2
            ;;
        --finding)
            if [[ $# -lt 2 ]]; then
                printf 'review: --finding requires a value\n' >&2
                exit 1
            fi
            FINDING_IDS+=("$2")
            shift 2
            ;;
        *)
            printf 'review: unknown option: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

if [[ -z "${REVIEW_PATH}" ]]; then
    printf 'Usage: xfleet review --path <review-file> [--finding <id>] ...\n' >&2
    printf 'Error: --path is required.\n' >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Validate and SC-5 scope --path (must resolve under $XFLEET_COORDINATION_ROOT)
# ---------------------------------------------------------------------------
COORD_ROOT="${XFLEET_COORDINATION_ROOT:-}"
if [[ -z "${COORD_ROOT}" ]]; then
    printf 'Error: XFLEET_COORDINATION_ROOT is not set.\n' >&2
    exit 1
fi

# Resolve the coordination root to a canonical path.
RESOLVED_ROOT=""
if ! RESOLVED_ROOT="$(realpath "${COORD_ROOT}" 2>/dev/null)"; then
    printf 'Error: XFLEET_COORDINATION_ROOT "%s" could not be resolved.\n' "${COORD_ROOT}" >&2
    exit 1
fi

# Resolve the review file path.
RESOLVED_PATH=""
if ! RESOLVED_PATH="$(realpath "${REVIEW_PATH}" 2>/dev/null)"; then
    printf 'Error: --path "%s" could not be resolved (file may not exist).\n' "${REVIEW_PATH}" >&2
    exit 1
fi

# File must be a regular file.
if [[ ! -f "${RESOLVED_PATH}" ]]; then
    printf 'Error: --path "%s" does not exist or is not a regular file.\n' "${REVIEW_PATH}" >&2
    exit 1
fi

# Ensure the resolved path lies under the coordination root (SC-5).
ROOT_PREFIX="${RESOLVED_ROOT}/"
if [[ "${RESOLVED_PATH}" != "${RESOLVED_ROOT}" && "${RESOLVED_PATH}" != "${ROOT_PREFIX}"* ]]; then
    printf "Error: --path '%s' resolves outside allowed roots; copy the file under \$XFLEET_COORDINATION_ROOT first.\n" \
        "${REVIEW_PATH}" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Resolve the worker's own state file (same convention as resolution.sh)
# ---------------------------------------------------------------------------
WORKER_NAME="${XFLEET_WORKER_NAME:-}"
if [[ -z "${WORKER_NAME}" ]]; then
    printf 'Error: XFLEET_WORKER_NAME is not set (required to locate the worker'\''s own state file).\n' >&2
    exit 1
fi

WORKER_STATE_PATH="${COORD_ROOT}/state/${WORKER_NAME}.json"

# ---------------------------------------------------------------------------
# Build the review wire message (worker → orchestrator)
# ---------------------------------------------------------------------------
SENDER="${XFLEET_ROLE}"   # "worker" (already asserted)
RECIPIENT="orchestrator"
MSG_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

REVIEW_MSG="$(jq -cn \
    --arg id        "${MSG_ID}" \
    --arg type      "review" \
    --arg from      "${SENDER}" \
    --arg to        "${RECIPIENT}" \
    --arg ts        "${TIMESTAMP}" \
    --arg path      "${RESOLVED_PATH}" \
    '{id: $id, type: $type, from: $from, to: $to, timestamp: $ts, path: $path}'
)"

# ---------------------------------------------------------------------------
# Publish to orchestrator inbox
# ---------------------------------------------------------------------------
xfleet_redis XADD "inbox:${RECIPIENT}" MAXLEN "~" 200 "*" data "${REVIEW_MSG}" >/dev/null

# ---------------------------------------------------------------------------
# Reflexive findings_status update: set each provided finding to "awaiting-review"
# ---------------------------------------------------------------------------
if [[ "${#FINDING_IDS[@]}" -gt 0 ]]; then
    # Build a jq expression that sets each finding id to "awaiting-review".
    # findings_status defaults to {} if absent.
    JQ_UPDATES=". + {findings_status: ((.findings_status // {}) "
    for fid in "${FINDING_IDS[@]}"; do
        JQ_UPDATES="${JQ_UPDATES}+ {\"${fid}\": \"awaiting-review\"} "
    done
    JQ_UPDATES="${JQ_UPDATES})}"

    state_update_field "${WORKER_STATE_PATH}" "${JQ_UPDATES}"
fi

printf 'review: sent to %s (msg_id: %s, path: %s)' \
    "${RECIPIENT}" "${MSG_ID}" "${RESOLVED_PATH}"

if [[ "${#FINDING_IDS[@]}" -gt 0 ]]; then
    printf '; findings marked awaiting-review:'
    for fid in "${FINDING_IDS[@]}"; do
        printf ' %s' "${fid}"
    done
fi
printf '\n'
