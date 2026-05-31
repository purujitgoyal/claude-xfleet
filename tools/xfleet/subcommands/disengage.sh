#!/usr/bin/env bash
# disengage.sh — xfleet disengage subcommand (Task 27).
#
# Sets _orchestrator.json:human_engaged.active = false and clears the scoping
# fields (concern_id / set_at / reason → null, per the schema's "null when
# inactive" semantics). Per A3 this is an ANY-SESSION writer (the sanctioned
# exception to strict writer-ownership); no role check.
#
# C2 last-write-wins: no lock primitive; atomicity comes from state-io's tmp+mv.
#
# Usage:
#   xfleet disengage
#
# Exit codes:
#   0 — human_engaged.active set false in _orchestrator.json
#   1 — state failure

_DISENGAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_DISENGAGE_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/state-io.sh
source "${_DISENGAGE_DIR}/../lib/state-io.sh"

# disengage takes no arguments.
if [[ $# -gt 0 ]]; then
    printf 'disengage: unexpected argument: %s\n' "$1" >&2
    printf 'Usage: xfleet disengage\n' >&2
    exit 1
fi

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
# Clear human_engaged atomically (all fields null/false when inactive).
# ---------------------------------------------------------------------------
state_update_field "${ORCH_STATE_PATH}" \
    '. + {human_engaged: {active: false, concern_id: null, set_at: null, reason: null}}'

printf 'disengage: human_engaged.active=false\n'
