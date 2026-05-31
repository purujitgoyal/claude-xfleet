#!/usr/bin/env bash
# peek.sh — xfleet peek subcommand (Task 20).
#
# Non-blocking stream inspection: shows depth, pending count, and recent
# messages for inbox:{name} on Redis. Consumes nothing. Ports wave-1
# peek.sh semantics with XFLEET_REDIS_URL generalization (SC-3).
#
# Usage: xfleet peek <name>

_PEEK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_PEEK_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/redis.sh
source "${_PEEK_DIR}/../lib/redis.sh"

if [[ $# -lt 1 ]]; then
    printf 'Usage: xfleet peek <name>\n' >&2
    exit 1
fi

NAME="$1"
STREAM="inbox:${NAME}"
GROUP="worker"

# ---------------------------------------------------------------------------
# Stream depth
# ---------------------------------------------------------------------------
DEPTH="$(xfleet_redis XLEN "${STREAM}" 2>/dev/null)" || DEPTH="0"
[[ -z "${DEPTH}" ]] && DEPTH="0"

printf 'Stream: %s\n' "${STREAM}"
printf 'Depth:  %s\n' "${DEPTH}"

# ---------------------------------------------------------------------------
# Pending (unACKed) messages
# ---------------------------------------------------------------------------
printf '\nPending (unACKed):\n'
printf -- '---\n'

PENDING_RAW="$(xfleet_redis XPENDING "${STREAM}" "${GROUP}" - + 10 2>/dev/null)" || PENDING_RAW=""

if [[ -z "${PENDING_RAW}" ]]; then
    printf '(none or group does not exist)\n'
else
    PENDING_COUNT=0
    while IFS= read -r line; do
        [[ -z "${line}" ]] && continue
        PENDING_COUNT=$(( PENDING_COUNT + 1 ))
        printf '  %s\n' "${line}"
    done <<< "${PENDING_RAW}"
    if [[ "${PENDING_COUNT}" -eq 0 ]]; then
        printf '(none)\n'
    fi
fi
printf -- '---\n'

# ---------------------------------------------------------------------------
# Recent messages (up to 10) — XRANGE, read-only
# ---------------------------------------------------------------------------
printf '\nRecent messages (up to 10):\n'
printf -- '---\n'

if [[ "${DEPTH}" -gt 0 ]]; then
    MESSAGES="$(xfleet_redis XRANGE "${STREAM}" - + COUNT 10 2>/dev/null)" || MESSAGES=""

    INDEX=0
    CURRENT_ID=""
    while IFS= read -r line; do
        [[ -z "${line}" ]] && continue

        # Stream message IDs match digits-digits
        if [[ "${line}" =~ ^[0-9]+-[0-9]+$ ]]; then
            CURRENT_ID="${line}"
            continue
        fi

        [[ -z "${CURRENT_ID}" ]] && continue

        # Skip bare field names (e.g. "msg", "data")
        if [[ "${line}" =~ ^[a-zA-Z_]+$ ]]; then
            continue
        fi

        # This is the value — pretty-print
        INDEX=$(( INDEX + 1 ))
        printf '[%d] id=%s\n' "${INDEX}" "${CURRENT_ID}"
        printf '%s' "${line}" | jq . 2>/dev/null || printf '%s\n' "${line}"
        printf -- '---\n'
        CURRENT_ID=""
    done <<< "${MESSAGES}"

    if [[ "${INDEX}" -eq 0 ]]; then
        printf '(no messages)\n'
        printf -- '---\n'
    fi
else
    printf '(empty stream)\n'
    printf -- '---\n'
fi
