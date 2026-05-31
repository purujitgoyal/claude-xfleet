#!/usr/bin/env bash
# engage.sh — xfleet engage subcommand (Task 27).
#
# Sets _orchestrator.json:human_engaged.active = true. Per A3 this is an
# ANY-SESSION writer: it is the sanctioned exception to strict writer-ownership
# (a worker session may write _orchestrator.json:human_engaged). No role check.
#
# C2 last-write-wins: no lock primitive; atomicity comes from state-io's tmp+mv.
# When active, the orchestrator suppresses round-5 hard-stops, straggler
# warnings, and all-idle prompts (cluster 4a #4).
#
# Usage:
#   xfleet engage [concern_id] [--reason <text>]
#
# Options:
#   concern_id (positional)  Optional concern id the engagement is scoped to.
#   --reason <text>          Optional human-readable reason for engagement.
#
# Exit codes:
#   0 — human_engaged.active set true in _orchestrator.json
#   1 — validation error or state failure

_ENGAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_ENGAGE_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/state-io.sh
source "${_ENGAGE_DIR}/../lib/state-io.sh"

# ---------------------------------------------------------------------------
# Arg parsing — optional positional concern_id + optional --reason.
# ---------------------------------------------------------------------------
CONCERN_ID_ARG=""
REASON_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --reason)
            if [[ $# -lt 2 ]]; then
                printf 'engage: --reason requires a value\n' >&2
                exit 1
            fi
            REASON_ARG="$2"
            shift 2
            ;;
        --*)
            printf 'engage: unknown option: %s\n' "$1" >&2
            exit 1
            ;;
        *)
            if [[ -n "${CONCERN_ID_ARG}" ]]; then
                printf 'engage: unexpected extra argument: %s\n' "$1" >&2
                exit 1
            fi
            CONCERN_ID_ARG="$1"
            shift
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Resolve orchestrator state file path.
# ---------------------------------------------------------------------------
COORD_ROOT="${XFLEET_COORDINATION_ROOT:-}"
if [[ -z "${COORD_ROOT}" ]]; then
    printf 'Error: XFLEET_COORDINATION_ROOT is not set (required for human_engaged write).\n' >&2
    exit 1
fi

ORCH_STATE_PATH="${COORD_ROOT}/state/_orchestrator.json"

# ---------------------------------------------------------------------------
# Build human_engaged record and apply atomically.
# Scalars passed via jq --arg/--argjson (never interpolated into the program).
# ---------------------------------------------------------------------------
SET_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

HUMAN_ENGAGED="$(jq -cn \
    --argjson concern_id "$([ -n "${CONCERN_ID_ARG}" ] && printf '"%s"' "${CONCERN_ID_ARG}" || printf 'null')" \
    --arg     set_at     "${SET_AT}" \
    --argjson reason     "$([ -n "${REASON_ARG}" ] && jq -Rn --arg r "${REASON_ARG}" '$r' || printf 'null')" \
    '{active: true, concern_id: $concern_id, set_at: $set_at, reason: $reason}'
)"

state_update_field "${ORCH_STATE_PATH}" ". + {human_engaged: ${HUMAN_ENGAGED}}"

printf 'engage: human_engaged.active=true (concern_id: %s, set_at: %s)\n' \
    "${CONCERN_ID_ARG:-null}" "${SET_AT}"
