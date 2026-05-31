#!/usr/bin/env bash
# status.sh — xfleet status subcommand (Task 20).
#
# Reads orchestrator + worker state files from $XFLEET_COORDINATION_ROOT/state/
# and prints a structured, human-readable summary. No Redis access — pure
# state-file reads. No authority enforcement (read-only per messaging.md A3).
#
# Usage: xfleet status

_STATUS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_STATUS_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/state-io.sh
source "${_STATUS_DIR}/../lib/state-io.sh"

COORD_ROOT="${XFLEET_COORDINATION_ROOT:-}"
if [[ -z "${COORD_ROOT}" ]]; then
    printf 'status: XFLEET_COORDINATION_ROOT is not set\n' >&2
    exit 1
fi

STATE_DIR="${COORD_ROOT}/state"

# ---------------------------------------------------------------------------
# Orchestrator section
# ---------------------------------------------------------------------------
ORCH_FILE="${STATE_DIR}/_orchestrator.json"

printf '=== Orchestrator ===\n'
if [[ -f "${ORCH_FILE}" ]]; then
    local_cycles="$(jq -r '.cycles // "n/a"' "${ORCH_FILE}")"
    local_engaged="$(jq -r '.human_engaged.active // false' "${ORCH_FILE}")"
    local_idle_notify="$(jq -r '.last_all_idle_notify // "null"' "${ORCH_FILE}")"
    printf '  cycles:               %s\n' "${local_cycles}"
    printf '  human_engaged.active: %s\n' "${local_engaged}"
    printf '  last_all_idle_notify: %s\n' "${local_idle_notify}"
else
    printf '  (no orchestrator state yet)\n'
fi

# ---------------------------------------------------------------------------
# Workers section — all *.json except _orchestrator.json
# ---------------------------------------------------------------------------
printf '\n=== Workers ===\n'

worker_found=0
for wf in "${STATE_DIR}"/*.json; do
    # glob expands to literal "*.json" when no files match
    [[ -e "${wf}" ]] || continue
    base="$(basename "${wf}")"
    # Skip orchestrator file
    [[ "${base}" = "_orchestrator.json" ]] && continue

    worker_name="${base%.json}"
    worker_found=1

    w_phase="$(jq -r '.current_phase // "n/a"' "${wf}")"
    w_status="$(jq -r '.status // "n/a"' "${wf}")"
    w_context="$(jq -r '.context_pct // "n/a"' "${wf}")"
    w_updated="$(jq -r '.last_updated // "n/a"' "${wf}")"
    w_task="$(jq -r 'if .current_task != null then .current_task.description else "null" end' "${wf}")"

    printf '  [%s]\n' "${worker_name}"
    printf '    current_phase: %s\n' "${w_phase}"
    printf '    status:        %s\n' "${w_status}"
    printf '    context_pct:   %s\n' "${w_context}"
    printf '    last_updated:  %s\n' "${w_updated}"
    printf '    current_task:  %s\n' "${w_task}"
done

if [[ "${worker_found}" -eq 0 ]]; then
    printf '  (none)\n'
fi
