#!/usr/bin/env bash
# continue.sh — xfleet continue subcommand (Task 28; F-58).
#
# Explicit unpause: exits standby mode and resumes whatever current_task points
# to NOW. F-58: standby is a self-drive gate; `continue` is how the human/agent
# releases it. Writes the worker's OWN state (standby=false).
#
# Usage:
#   xfleet continue [<worker>]
#
# Options:
#   <worker> (positional)  Worker short-name (default: $XFLEET_WORKER_NAME).
#
# Exit codes:
#   0 — standby cleared; current_task (if any) surfaced for resumption
#   1 — validation error or state failure

_CONTINUE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_CONTINUE_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/state-io.sh
source "${_CONTINUE_DIR}/../lib/state-io.sh"

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
WORKER="${XFLEET_WORKER_NAME:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --*)
            printf 'continue: unknown option: %s\n' "$1" >&2
            exit 1
            ;;
        *)
            WORKER="$1"
            shift
            ;;
    esac
done

if [[ -z "${WORKER}" ]]; then
    printf 'Error: continue requires a worker name (positional arg or $XFLEET_WORKER_NAME).\n' >&2
    exit 1
fi

COORD_ROOT="${XFLEET_COORDINATION_ROOT:-}"
if [[ -z "${COORD_ROOT}" ]]; then
    printf 'Error: XFLEET_COORDINATION_ROOT is not set (required to locate worker state).\n' >&2
    exit 1
fi

WORKER_STATE_PATH="${COORD_ROOT}/state/${WORKER}.json"

# ---------------------------------------------------------------------------
# Clear standby (own-state write) and surface current_task for resumption.
# ---------------------------------------------------------------------------
NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
state_update_field "${WORKER_STATE_PATH}" \
    ". + {standby: false, last_updated: \"${NOW}\"}"

STATE="$(state_read "${WORKER_STATE_PATH}")"
HAS_TASK="$(printf '%s' "${STATE}" | jq -r 'if (.current_task // null) == null then "no" else "yes" end')"
TASK_DESC="$(printf '%s' "${STATE}" | jq -r '.current_task.description // ""')"

if [[ "${HAS_TASK}" == "yes" ]]; then
    printf 'continue: standby cleared — resume current_task now: %s\n' "${TASK_DESC}"
else
    printf 'continue: standby cleared — no current_task to resume (worker idle).\n'
fi
