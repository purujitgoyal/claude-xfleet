#!/usr/bin/env bash
# await.sh — xfleet await subcommand (exploration mode responder wait primitive).
#
# Parks the calling session in its inbox, blocking until a message arrives.
# One message per invocation — the agent re-arms by calling await again.
# Presence is maintained in Redis so senders can discover parked responders.
#
# Usage: xfleet await [--name <name>] [--timeout <secs>] [--unpark]
#
# Options:
#   --name <name>   Worker/responder name (default: $XFLEET_WORKER_NAME or basename "$PWD")
#   --timeout <n>   Overall deadline in seconds; exits 2 on expiry
#   --unpark        Delete the presence key and exit 0 (no blocking)
#
# Exit codes:
#   0  Message received and printed to stdout (or --unpark succeeded)
#   1  Usage / validation error
#   2  Timeout elapsed with no message received

_AWAIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_AWAIT_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/redis.sh
source "${_AWAIT_DIR}/../lib/redis.sh"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
NAME=""
TIMEOUT_SECS=""
UNPARK=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)
            if [[ $# -lt 2 ]]; then
                printf 'await: --name requires a value\n' >&2
                exit 1
            fi
            NAME="$2"
            shift 2
            ;;
        --timeout)
            if [[ $# -lt 2 ]]; then
                printf 'await: --timeout requires a value\n' >&2
                exit 1
            fi
            TIMEOUT_SECS="$2"
            shift 2
            ;;
        --unpark)
            UNPARK=1
            shift
            ;;
        *)
            printf 'Usage: xfleet await [--name <name>] [--timeout <secs>] [--unpark]\n' >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Name resolution: --name > $XFLEET_WORKER_NAME > basename "$PWD"
# ---------------------------------------------------------------------------
if [[ -z "${NAME}" ]]; then
    NAME="${XFLEET_WORKER_NAME:-}"
fi
if [[ -z "${NAME}" ]]; then
    NAME="$(basename "${PWD}")"
fi

STREAM="inbox:${NAME}"
GROUP="explore"
PRESENCE_KEY="xfleet:explore:presence:${NAME}"
PRESENCE_TTL=900

# ---------------------------------------------------------------------------
# --unpark: remove presence key and exit
# ---------------------------------------------------------------------------
if [[ "${UNPARK}" -eq 1 ]]; then
    xfleet_redis DEL "${PRESENCE_KEY}" >/dev/null
    printf 'await: unparked %s\n' "${NAME}"
    exit 0
fi

# ---------------------------------------------------------------------------
# Deadline tracking
# ---------------------------------------------------------------------------
# SECONDS is a bash built-in that counts elapsed seconds since shell started.
# We capture the start so we can compute remaining time relative to it.
START_SECONDS="${SECONDS}"

# check_deadline: exits 2 (the whole script) if the deadline has passed.
# Must be called directly (not via command substitution) so exit propagates.
check_deadline() {
    [[ -z "${TIMEOUT_SECS}" ]] && return 0
    local elapsed=$(( SECONDS - START_SECONDS ))
    local left=$(( TIMEOUT_SECS - elapsed ))
    if [[ "${left}" -le 0 ]]; then
        exit 2
    fi
}

# compute_block_ms: prints the BLOCK duration in milliseconds.
# Caps at 300s cycle; caps at remaining time when --timeout is set.
# Caller must run check_deadline first so this is never called past the deadline.
compute_block_ms() {
    if [[ -z "${TIMEOUT_SECS}" ]]; then
        printf '300000'
        return 0
    fi
    local elapsed=$(( SECONDS - START_SECONDS ))
    local left=$(( TIMEOUT_SECS - elapsed ))
    if [[ "${left}" -le 0 ]]; then
        # Deadline passed — return 1ms so the BLOCK returns immediately;
        # the check_deadline call after the loop will exit 2.
        printf '1'
        return 0
    fi
    local left_ms=$(( left * 1000 ))
    # Cap cycle at 300s (300000ms) to refresh presence regularly
    if [[ "${left_ms}" -gt 300000 ]]; then
        printf '300000'
    else
        printf '%s' "${left_ms}"
    fi
}

# ---------------------------------------------------------------------------
# Presence refresh helper
# ---------------------------------------------------------------------------
refresh_presence() {
    local parked_at
    parked_at="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || parked_at="unknown"
    local json
    # Use printf to build JSON — no jq dependency for writes
    json="$(printf '{"repo":"%s","parked_at":"%s"}' "${PWD}" "${parked_at}")"
    xfleet_redis SET "${PRESENCE_KEY}" "${json}" EX "${PRESENCE_TTL}" >/dev/null
}

# ---------------------------------------------------------------------------
# Ensure consumer group exists (idempotent)
# ---------------------------------------------------------------------------
xfleet_redis XGROUP CREATE "${STREAM}" "${GROUP}" 0 MKSTREAM >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# Pending recovery: consume any message delivered but not yet ACKed
# (handles prior await crash)
# ---------------------------------------------------------------------------
PENDING_RAW=""
PENDING_RAW="$(xfleet_redis XREADGROUP GROUP "${GROUP}" "${NAME}" COUNT 1 STREAMS "${STREAM}" 0 2>/dev/null)" || true

if [[ -n "${PENDING_RAW}" ]]; then
    # wc -l counts newlines; command substitution strips trailing newline, so
    # a 4-line redis-cli reply arrives as 3 newlines → wc -l = 3. Threshold is 3.
    line_count="$(printf '%s' "${PENDING_RAW}" | wc -l | tr -d ' ')"
    if [[ "${line_count}" -ge 3 ]]; then
        stream_id="$(printf '%s' "${PENDING_RAW}" | sed -n '2p')"
        data_value="$(printf '%s' "${PENDING_RAW}" | sed -n '4p')"
        xfleet_redis XACK "${STREAM}" "${GROUP}" "${stream_id}" >/dev/null
        printf '%s\n' "${data_value}"
        exit 0
    fi
fi

# ---------------------------------------------------------------------------
# Blocking read loop
# ---------------------------------------------------------------------------
while true; do
    # Check deadline before blocking (exits 2 if past deadline)
    check_deadline

    refresh_presence

    CYCLE_MS="$(compute_block_ms)"

    rc=0
    RESULT="$(xfleet_redis XREADGROUP GROUP "${GROUP}" "${NAME}" BLOCK "${CYCLE_MS}" COUNT 1 STREAMS "${STREAM}" '>' 2>/dev/null)" || rc=$?

    if [[ "${rc}" -ne 0 ]]; then
        # Redis error — back off before retrying (avoids busy-spin, same rationale as listen.sh)
        sleep 1
        continue
    fi

    if [[ -n "${RESULT}" ]]; then
        # wc -l counts newlines; command substitution strips trailing newline, so
        # a 4-line redis-cli reply arrives as 3 newlines → wc -l = 3. Threshold is 3.
        line_count="$(printf '%s' "${RESULT}" | wc -l | tr -d ' ')"
        if [[ "${line_count}" -ge 3 ]]; then
            stream_id="$(printf '%s' "${RESULT}" | sed -n '2p')"
            data_value="$(printf '%s' "${RESULT}" | sed -n '4p')"
            xfleet_redis XACK "${STREAM}" "${GROUP}" "${stream_id}" >/dev/null
            printf '%s\n' "${data_value}"
            exit 0
        fi
    fi

    # Empty cycle (BLOCK timed out) — check deadline and loop
    check_deadline
done
