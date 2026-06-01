#!/usr/bin/env bash
# integration-ready-handler.sh — inbound handler for integration-ready (Task 8).
#
# Invoked internally by the ORCHESTRATOR's inbox listener when an
# "integration-ready" wire message arrives from a worker. Records
# integration_readiness[ip][repo]=true in _orchestrator.json.
# Does NOT compute all-ready and does NOT emit any reflexive message.
#
# Writer ownership: writes ONLY _orchestrator.json (orch-owned).
#
# Usage (internal, called by orchestrator listener via dispatch.sh):
#   integration-ready-handler.sh <ip> <repo>
#
# Arguments:
#   ip    — IP identifier the worker reports ready for (e.g. IP-1)
#   repo  — repo token written verbatim (== XFLEET_WORKER_NAME of sender)
#
# Exit codes:
#   0 — integration_readiness[ip][repo] written to _orchestrator.json
#   1 — argument, state-file, or validation failure

_IR_HANDLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_IR_HANDLER_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/state-io.sh
source "${_IR_HANDLER_DIR}/../lib/state-io.sh"

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------
if [[ $# -lt 2 ]]; then
    printf 'integration-ready-handler: expected 2 arguments: <ip> <repo>\n' >&2
    exit 1
fi

IP="$1"
REPO="$2"

if [[ -z "${IP}" ]]; then
    printf 'integration-ready-handler: ip argument is empty.\n' >&2
    exit 1
fi

if [[ -z "${REPO}" ]]; then
    printf 'integration-ready-handler: repo argument is empty.\n' >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Resolve orchestrator state file path
# ---------------------------------------------------------------------------
COORD_ROOT="${XFLEET_COORDINATION_ROOT:-}"
if [[ -z "${COORD_ROOT}" ]]; then
    printf 'integration-ready-handler: XFLEET_COORDINATION_ROOT is not set.\n' >&2
    exit 1
fi

ORCH_STATE_PATH="${COORD_ROOT}/state/_orchestrator.json"

if [[ ! -f "${ORCH_STATE_PATH}" ]]; then
    printf 'integration-ready-handler: orchestrator state file not found: %s\n' "${ORCH_STATE_PATH}" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Write integration_readiness[ip][repo] = true (JSON boolean).
# state_update_field has no --arg passthrough, so use the injection-safe
# state_read + jq --arg + state_write_atomic pattern (mirrors drift-check.sh).
# ---------------------------------------------------------------------------
CURRENT_STATE="$(state_read "${ORCH_STATE_PATH}")"
UPDATED_STATE="$(printf '%s' "${CURRENT_STATE}" | jq \
    --arg ip   "${IP}" \
    --arg repo "${REPO}" \
    '.integration_readiness[$ip][$repo] = true')"
state_write_atomic "${ORCH_STATE_PATH}" "${UPDATED_STATE}"

printf 'integration-ready-handler: integration_readiness[%s][%s] = true written to %s\n' \
    "${IP}" "${REPO}" "${ORCH_STATE_PATH}"
