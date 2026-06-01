#!/usr/bin/env bash
# integration-ready.sh — xfleet integration-ready subcommand (Task 7).
#
# Signal-only worker→orchestrator message: emitted when a worker has finished
# all epics anchored to an IP and the workspace is drift-clean. No content body,
# no response expected, no rounds. Orch handler (next task) writes
# integration_readiness[IP][repo]=true on receive.
#
# Usage:
#   xfleet integration-ready --ip <N>
#   xfleet integration-ready --ip <IP-N>
#
# Options:
#   --ip <N|IP-N>   Required. Integration point identifier; normalized to IP-N form.
#
# Exit codes:
#   0 — signal sent to inbox:orchestrator
#   1 — validation error or Redis failure

_INTEGRATION_READY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_INTEGRATION_READY_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/redis.sh
source "${_INTEGRATION_READY_DIR}/../lib/redis.sh"
# shellcheck source=../lib/sender-authority.sh
source "${_INTEGRATION_READY_DIR}/../lib/sender-authority.sh"

# ---------------------------------------------------------------------------
# Role check — worker only
# ---------------------------------------------------------------------------
assert_role worker

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
IP_RAW=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ip)
            if [[ $# -lt 2 ]]; then
                printf 'integration-ready: --ip requires a value\n' >&2
                exit 1
            fi
            IP_RAW="$2"
            shift 2
            ;;
        *)
            printf 'integration-ready: unknown option: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Validate --ip (required)
# ---------------------------------------------------------------------------
if [[ -z "${IP_RAW}" ]]; then
    printf 'Usage: xfleet integration-ready --ip <N|IP-N>\n' >&2
    printf 'Error: --ip is required.\n' >&2
    exit 1
fi

# Normalize: accept "1" or "IP-1" → store as "IP-1".
if [[ "${IP_RAW}" =~ ^[0-9]+$ ]]; then
    IP_KEY="IP-${IP_RAW}"
elif [[ "${IP_RAW}" =~ ^IP-[0-9]+$ ]]; then
    IP_KEY="${IP_RAW}"
else
    printf 'integration-ready: --ip value "%s" is invalid; expected a number (1) or IP-N form (IP-1).\n' "${IP_RAW}" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Resolve the canonical worker/repo token (required for the wire message).
# Guard explicitly so an unset value yields a friendly error rather than a
# `set -u` "unbound variable" crash (parity with drift-check.sh).
# ---------------------------------------------------------------------------
WORKER_NAME="${XFLEET_WORKER_NAME:-}"
if [[ -z "${WORKER_NAME}" ]]; then
    printf 'Error: XFLEET_WORKER_NAME is not set (required for the integration-ready signal).\n' >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Build wire message (signal-only; no content body)
# ---------------------------------------------------------------------------
MSG_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

MSG="$(jq -cn \
    --arg type      "integration-ready" \
    --arg worker    "${WORKER_NAME}" \
    --arg repo      "${WORKER_NAME}" \
    --arg ip        "${IP_KEY}" \
    --arg id        "${MSG_ID}" \
    --arg timestamp "${TIMESTAMP}" \
    '{type: $type, worker: $worker, repo: $repo, ip: $ip, id: $id, timestamp: $timestamp}'
)"

# ---------------------------------------------------------------------------
# Publish to orchestrator inbox. No state writes — signal only.
# ---------------------------------------------------------------------------
xfleet_redis XADD "inbox:orchestrator" MAXLEN "~" 200 "*" data "${MSG}" >/dev/null

printf 'integration-ready: sent to orchestrator (id: %s, worker: %s, ip: %s)\n' \
    "${MSG_ID}" "${WORKER_NAME}" "${IP_KEY}"
