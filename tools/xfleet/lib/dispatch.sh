#!/usr/bin/env bash
# dispatch.sh — Message dispatch lib for xfleet inbox listeners (Task 29a).
#
# Public API:
#   dispatch_message <message-json>
#       Route an inbound wire message to its receiver-side handler based on
#       XFLEET_ROLE and the message's "type" field. Performs ONLY mechanical
#       receiver-side state writes and reflexive handler invocations; cognitive
#       work (reading, deciding, acting) is the agent's job.
#
#       Returns 0 when the message was handled or deliberately no-op'd (unknown
#       type). Returns non-zero when the matched handler exits non-zero — the
#       caller (listener loop) must NOT XACK on non-zero return.
#
# Routing matrix:
#   XFLEET_ROLE=worker:
#     directive        → directive-ack-handler.sh
#     task             → task-ack-handler.sh
#     (other)          → no-op / return 0
#
#   XFLEET_ROLE=orchestrator:
#     task-response    → task-response-handler.sh
#     directive-response → update _orchestrator.json directive_log[].response_status
#     escalation       → append escalation_log[] entry to _orchestrator.json
#     phase-complete   → append completion_log[] entry to _orchestrator.json
#     (other)          → no-op / return 0
#
# Usage (source, do not execute directly):
#   source tools/xfleet/lib/dispatch.sh

_DISPATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${_DISPATCH_DIR}/../../.." && pwd)}"

# shellcheck source=strict-mode.sh
source "${_DISPATCH_DIR}/strict-mode.sh"
# shellcheck source=redis.sh
source "${_DISPATCH_DIR}/redis.sh"
# shellcheck source=state-io.sh
source "${_DISPATCH_DIR}/state-io.sh"

# ---------------------------------------------------------------------------
# Handler paths (resolved once at source time)
# ---------------------------------------------------------------------------
_DISPATCH_HANDLERS="${PLUGIN_ROOT}/tools/xfleet/handlers"

# ---------------------------------------------------------------------------
# dispatch_message <message-json>
# ---------------------------------------------------------------------------
dispatch_message() {
    local msg="$1"

    local TYPE
    TYPE="$(printf '%s' "${msg}" | jq -r '.type // empty')"

    if [[ -z "${TYPE}" ]]; then
        # No type field — can't route; no-op.
        return 0
    fi

    local ROLE="${XFLEET_ROLE:-}"

    if [[ "${ROLE}" = "worker" ]]; then
        _dispatch_worker "${TYPE}" "${msg}"
    elif [[ "${ROLE}" = "orchestrator" ]]; then
        _dispatch_orchestrator "${TYPE}" "${msg}"
    else
        # Unknown or unset role — no-op (agent will handle cognitively).
        return 0
    fi
}

# ---------------------------------------------------------------------------
# _dispatch_worker <type> <message-json>
# ---------------------------------------------------------------------------
_dispatch_worker() {
    local type="$1"
    local msg="$2"

    case "${type}" in
        directive)
            local id expected_action scope concern_id
            id="$(printf '%s' "${msg}" | jq -r '.id // empty')"
            expected_action="$(printf '%s' "${msg}" | jq -r '.expected_action // empty')"
            scope="$(printf '%s' "${msg}" | jq -r '.scope // empty')"
            concern_id="$(printf '%s' "${msg}" | jq -r '.concern_id // empty')"
            local handler="${_DISPATCH_HANDLERS}/directive-ack-handler.sh"
            if [[ ! -x "${handler}" ]]; then
                printf 'dispatch_message: handler not found or not executable: %s\n' "${handler}" >&2
                return 1
            fi
            "${handler}" "${XFLEET_WORKER_NAME:-}" "${id}" "${expected_action}" "${scope}" "${concern_id}"
            ;;
        task)
            local id description task_kind
            id="$(printf '%s' "${msg}" | jq -r '.id // empty')"
            description="$(printf '%s' "${msg}" | jq -r '.content // .description // empty')"
            task_kind="$(printf '%s' "${msg}" | jq -r '.task_kind // empty')"
            local handler="${_DISPATCH_HANDLERS}/task-ack-handler.sh"
            if [[ ! -x "${handler}" ]]; then
                printf 'dispatch_message: handler not found or not executable: %s\n' "${handler}" >&2
                return 1
            fi
            "${handler}" "${id}" "${description}" "${task_kind}"
            ;;
        *)
            # Unknown type for worker role — no-op (agent handles cognitively).
            return 0
            ;;
    esac
}

# ---------------------------------------------------------------------------
# _dispatch_orchestrator <type> <message-json>
# ---------------------------------------------------------------------------
_dispatch_orchestrator() {
    local type="$1"
    local msg="$2"

    case "${type}" in
        task-response)
            local task_id response_status worker
            task_id="$(printf '%s' "${msg}" | jq -r '.task_id // empty')"
            response_status="$(printf '%s' "${msg}" | jq -r '.response_status // "done"')"
            worker="$(printf '%s' "${msg}" | jq -r '.worker // empty')"
            local handler="${_DISPATCH_HANDLERS}/task-response-handler.sh"
            if [[ ! -x "${handler}" ]]; then
                printf 'dispatch_message: handler not found or not executable: %s\n' "${handler}" >&2
                return 1
            fi
            "${handler}" "${task_id}" "${response_status}" "${worker}"
            ;;
        directive-response)
            local directive_id response_status
            directive_id="$(printf '%s' "${msg}" | jq -r '.directive_id // empty')"
            response_status="$(printf '%s' "${msg}" | jq -r '.response_status // empty')"
            _dispatch_update_directive_log "${directive_id}" "${response_status}"
            ;;
        escalation)
            _dispatch_append_escalation_log "${msg}"
            ;;
        phase-complete)
            _dispatch_append_completion_log
            ;;
        *)
            # Unknown type for orchestrator role — no-op.
            return 0
            ;;
    esac
}

# ---------------------------------------------------------------------------
# _dispatch_update_directive_log <directive-id> <response-status>
# Updates _orchestrator.json directive_log[].response_status for the matching entry.
# ---------------------------------------------------------------------------
_dispatch_update_directive_log() {
    local directive_id="$1"
    local response_status="$2"

    local coord_root="${XFLEET_COORDINATION_ROOT:-}"
    if [[ -z "${coord_root}" ]]; then
        printf 'dispatch_message: XFLEET_COORDINATION_ROOT is not set; cannot update directive_log.\n' >&2
        return 1
    fi

    local orch_state="${coord_root}/state/_orchestrator.json"
    if [[ ! -f "${orch_state}" ]]; then
        printf 'dispatch_message: orchestrator state file not found: %s\n' "${orch_state}" >&2
        return 1
    fi

    # Build the literal id and status JSON values to embed in the jq program,
    # following the task-response-handler.sh pattern (jq -cn --arg v ... '$v').
    local id_json status_json
    id_json="$(jq -cn --arg v "${directive_id}" '$v')"
    status_json="$(jq -cn --arg v "${response_status}" '$v')"

    state_update_field "${orch_state}" \
        "(.directive_log // []) |= map(if .directive_id == ${id_json} then .response_status = ${status_json} else . end)"
}

# ---------------------------------------------------------------------------
# _dispatch_append_escalation_log <message-json>
# Appends an escalation_log[] entry to _orchestrator.json.
# ---------------------------------------------------------------------------
_dispatch_append_escalation_log() {
    local msg="$1"

    local coord_root="${XFLEET_COORDINATION_ROOT:-}"
    if [[ -z "${coord_root}" ]]; then
        printf 'dispatch_message: XFLEET_COORDINATION_ROOT is not set; cannot append escalation_log.\n' >&2
        return 1
    fi

    local orch_state="${coord_root}/state/_orchestrator.json"
    if [[ ! -f "${orch_state}" ]]; then
        printf 'dispatch_message: orchestrator state file not found: %s\n' "${orch_state}" >&2
        return 1
    fi

    local esc_id src_worker reason path priority
    esc_id="$(printf '%s' "${msg}" | jq -r '.id // empty')"
    src_worker="$(printf '%s' "${msg}" | jq -r '.worker // .from // empty')"
    reason="$(printf '%s' "${msg}" | jq -r '.reason // empty')"
    path="$(printf '%s' "${msg}" | jq -r '.path // empty')"
    priority="$(printf '%s' "${msg}" | jq -r '.priority // empty')"
    local now
    now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    # Build the entry with --arg for all string fields; resolved_at is null via literal.
    local entry
    entry="$(jq -cn \
        --arg escalation_id  "${esc_id}" \
        --arg source_worker  "${src_worker}" \
        --arg reason         "${reason}" \
        --arg path           "${path}" \
        --arg priority       "${priority}" \
        --arg received_at    "${now}" \
        --arg surfaced_at    "${now}" \
        '{escalation_id: $escalation_id, source_worker: $source_worker, reason: $reason, path: $path, priority: $priority, received_at: $received_at, surfaced_at: $surfaced_at, resolved_at: null}'
    )"

    state_update_field "${orch_state}" \
        ". + {escalation_log: ((.escalation_log // []) + [${entry}])}"
}

# ---------------------------------------------------------------------------
# _dispatch_append_completion_log
# Appends a completion_log[] entry to _orchestrator.json recording receipt.
# ---------------------------------------------------------------------------
_dispatch_append_completion_log() {
    local coord_root="${XFLEET_COORDINATION_ROOT:-}"
    if [[ -z "${coord_root}" ]]; then
        printf 'dispatch_message: XFLEET_COORDINATION_ROOT is not set; cannot append completion_log.\n' >&2
        return 1
    fi

    local orch_state="${coord_root}/state/_orchestrator.json"
    if [[ ! -f "${orch_state}" ]]; then
        printf 'dispatch_message: orchestrator state file not found: %s\n' "${orch_state}" >&2
        return 1
    fi

    local now
    now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    local entry
    entry="$(jq -cn \
        --arg evaluated_at      "${now}" \
        --arg trigger_msg_type  "phase-complete" \
        --arg outcome           "logged" \
        '{evaluated_at: $evaluated_at, trigger_msg_type: $trigger_msg_type, outcome: $outcome, missing_workers: [], missing_signals: []}'
    )"

    state_update_field "${orch_state}" \
        ". + {completion_log: ((.completion_log // []) + [${entry}])}"
}
