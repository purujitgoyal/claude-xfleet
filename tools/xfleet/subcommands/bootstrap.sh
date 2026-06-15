#!/usr/bin/env bash
# bootstrap.sh — xfleet bootstrap subcommand: worker cold-start initial-state write.
#
# Writes initial worker-state JSON to ${XFLEET_COORDINATION_ROOT}/state/{worker}.json
# if it does not already exist. Refuses to clobber an existing file — use
# `xfleet resume` instead if the file is present.
#
# Usage:
#   xfleet bootstrap [<worker>]
#
# Options:
#   <worker> (positional)  Worker short-name (default: $XFLEET_WORKER_NAME).
#
# Exit codes:
#   0 — initial state written successfully
#   1 — state file already exists, role mismatch, or missing required env vars

_BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_BOOTSTRAP_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/state-io.sh
source "${_BOOTSTRAP_DIR}/../lib/state-io.sh"
# shellcheck source=../lib/sender-authority.sh
source "${_BOOTSTRAP_DIR}/../lib/sender-authority.sh"

# ---------------------------------------------------------------------------
# Role gate — worker only.
# ---------------------------------------------------------------------------
assert_role worker

# ---------------------------------------------------------------------------
# Arg parsing — optional positional worker name.
# ---------------------------------------------------------------------------
WORKER="${XFLEET_WORKER_NAME:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --*)
            printf 'bootstrap: unknown option: %s\n' "$1" >&2
            exit 1
            ;;
        *)
            WORKER="$1"
            shift
            ;;
    esac
done

if [[ -z "${WORKER}" ]]; then
    printf 'Error: bootstrap requires a worker name (positional arg or $XFLEET_WORKER_NAME).\n' >&2
    exit 1
fi

COORD_ROOT="${XFLEET_COORDINATION_ROOT:-}"
if [[ -z "${COORD_ROOT}" ]]; then
    printf 'Error: XFLEET_COORDINATION_ROOT is not set (required to locate worker state).\n' >&2
    exit 1
fi

WORKER_STATE_PATH="${COORD_ROOT}/state/${WORKER}.json"

# ---------------------------------------------------------------------------
# Refuse to clobber an existing state file.
# ---------------------------------------------------------------------------
if [[ -f "${WORKER_STATE_PATH}" ]]; then
    printf 'Error: %s already exists. Use `xfleet resume` to resume an existing worker session.\n' \
        "${WORKER_STATE_PATH}" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Build and write initial state.
# ---------------------------------------------------------------------------
NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
json="$(jq -cn --arg last_updated "${NOW}" \
    '{schema_version:"1", current_phase:"idle", status:"idle",
      current_task:null, standby:false, last_updated:$last_updated}')"

state_write_atomic "${WORKER_STATE_PATH}" "${json}"

printf 'bootstrap: worker=%s state initialized (phase=idle, status=idle).\n' "${WORKER}"
