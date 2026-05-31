#!/usr/bin/env bash
# resume.sh — xfleet resume subcommand (Task 28; cluster 2 / F-12).
#
# The `xfleet resume` bash command bundles the MECHANICAL resume sequence:
# state load, listener restart, --standby flag, and auto-continue logic.
#
# Scope note (cluster 2 split): re-engaging the phase skill + applying the
# In-Session Directives + running the Resume Instructions is the F-53 resume
# FLOW's responsibility (the worker skill reads the handoff sections), NOT this
# bash command's. This command surfaces the state + a pointer so the agent can
# do that re-engagement; it does not parse handoff sections itself.
#
# Listener restart goes through lib/listener.sh's listener_restart: it warns
# about foreign listeners (never kills them), reaps this session's own recorded
# listener, then starts fresh and records the new listen_bash_id atomically.
#
# Usage:
#   xfleet resume [<worker>] [--standby]
#
# Options:
#   <worker> (positional)  Worker short-name (default: $XFLEET_WORKER_NAME).
#   --standby              Set standby=true; do NOT auto-continue the in-flight
#                          task (F-58: standby is a self-drive gate). Always-on
#                          listening is still (re)started.
#
# Exit codes:
#   0 — state loaded, listener restarted, standby/auto-continue resolved
#   1 — validation error or state failure

_RESUME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_RESUME_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/state-io.sh
source "${_RESUME_DIR}/../lib/state-io.sh"
# shellcheck source=../lib/listener.sh
source "${_RESUME_DIR}/../lib/listener.sh"

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
WORKER="${XFLEET_WORKER_NAME:-}"
STANDBY_FLAG="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --standby)
            STANDBY_FLAG="true"
            shift
            ;;
        --*)
            printf 'resume: unknown option: %s\n' "$1" >&2
            exit 1
            ;;
        *)
            WORKER="$1"
            shift
            ;;
    esac
done

if [[ -z "${WORKER}" ]]; then
    printf 'Error: resume requires a worker name (positional arg or $XFLEET_WORKER_NAME).\n' >&2
    exit 1
fi

COORD_ROOT="${XFLEET_COORDINATION_ROOT:-}"
if [[ -z "${COORD_ROOT}" ]]; then
    printf 'Error: XFLEET_COORDINATION_ROOT is not set (required to locate worker state).\n' >&2
    exit 1
fi

WORKER_STATE_PATH="${COORD_ROOT}/state/${WORKER}.json"

# ---------------------------------------------------------------------------
# 1) State load — read and report current worker state.
# ---------------------------------------------------------------------------
STATE="$(state_read "${WORKER_STATE_PATH}")"
CUR_PHASE="$(printf '%s' "${STATE}" | jq -r '.current_phase // "idle"')"
CUR_STATUS="$(printf '%s' "${STATE}" | jq -r '.status // "unknown"')"
HAS_TASK="$(printf '%s' "${STATE}" | jq -r 'if (.current_task // null) == null then "no" else "yes" end')"
TASK_DESC="$(printf '%s' "${STATE}" | jq -r '.current_task.description // ""')"

printf 'resume: worker=%s phase=%s status=%s\n' "${WORKER}" "${CUR_PHASE}" "${CUR_STATUS}"

# ---------------------------------------------------------------------------
# 2) Listener restart — safe restart via listener_restart (warns about foreign
#    listeners, reaps this session's own recorded listener, starts fresh).
# ---------------------------------------------------------------------------
listener_restart "${WORKER}"

# ---------------------------------------------------------------------------
# 3) Standby flag + 4) auto-continue logic (own-state write — worker file).
# ---------------------------------------------------------------------------
NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
state_update_field "${WORKER_STATE_PATH}" \
    ". + {standby: ${STANDBY_FLAG}, last_updated: \"${NOW}\"}"

if [[ "${STANDBY_FLAG}" == "true" ]]; then
    printf 'resume: standby=true — listening restarted; NOT auto-continuing in-flight work (run `xfleet continue` to exit standby).\n'
else
    if [[ "${HAS_TASK}" == "yes" ]]; then
        printf 'resume: auto-continue — resume current_task now: %s\n' "${TASK_DESC}"
    else
        printf 'resume: no in-flight current_task; worker is idle/reachable.\n'
    fi
fi

# ---------------------------------------------------------------------------
# Pointer to the F-53 resume flow (skill-level re-engagement).
# ---------------------------------------------------------------------------
printf 'resume: now re-engage your %s phase skill and apply the handoff Active-Skills / In-Session-Directives / Resume-Instructions (F-53 resume flow).\n' \
    "${CUR_PHASE}"
