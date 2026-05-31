#!/usr/bin/env bash
# listener.sh — Listener restart-safety primitives for xfleet (Task 29b).
#
# Implements the F-8 / F-37 discipline: a worker reaps ONLY its own recorded
# listener (tracked by listen_bash_id), never `pgrep`-kills every matching
# process. The pgrep-kill-all approach is unsafe across parallel sessions —
# multiple sessions running the same worker spawn byte-identical command lines,
# so a broad kill would silently break a peer session's inbox consumption.
# Foreign listeners are surfaced diagnostically, never killed.
#
# Public API:
#   listener_stop_own <worker>
#       Read listen_bash_id ("bash-NNN") from the worker state file and stop
#       ONLY that process (its process group when it is a setsid leader, else
#       the bare PID). Best-effort: a no-op when nothing is recorded or the
#       process is already dead. Never touches any other process.
#
#   listener_warn_foreign <worker>
#       Diagnostic only. pgrep for candidate xfleet listener processes that are
#       NOT the recorded own-listener PID and warn about them on stderr. NEVER
#       kills them (a peer session may legitimately own them).
#
#   listener_restart <worker>
#       Safe restart: warn about foreign listeners, then (re)start via the
#       listen subcommand (which itself stops the recorded own-listener before
#       launching a fresh one and records the new listen_bash_id atomically).
#
#   listener_alive <self>
#       Return 0 if <self>'s recorded listen_bash_id maps to a live process,
#       1 otherwise (including when nothing is recorded).
#
#   send_with_verify <self>
#       The F-42 "two-call pattern" post-send step. The caller has ALREADY
#       published its wire message (each typed subcommand builds + XADDs its own
#       message). This verifies <self>'s own listener is still alive so a peer
#       RESPONSE is not silently dropped; if it is not alive, it restarts the
#       listener. No-op (with a note) when <self> has no recorded listen_bash_id
#       — e.g. the orchestrator, whose v1 state schema does not track one.
#
# Scope note (F-42 vs plan): F-42's mechanism is verify-OWN-listener (so the
# response comes back), keyed on the worker's listen_bash_id. The plan's
# "GET on recipient to confirm receipt" wording does not match F-42's intent
# and does not fit the typed-subcommand architecture, so this implements the
# F-42 own-listener-liveness check.
#
# Usage (source, do not execute directly):
#   source tools/xfleet/lib/listener.sh

_LISTENER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=strict-mode.sh
source "${_LISTENER_LIB_DIR}/strict-mode.sh"
# shellcheck source=state-io.sh
source "${_LISTENER_LIB_DIR}/state-io.sh"

_LISTENER_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${_LISTENER_LIB_DIR}/../../.." && pwd)}"
_LISTENER_LISTEN_SH="${_LISTENER_PLUGIN_ROOT}/tools/xfleet/subcommands/listen.sh"

# ---------------------------------------------------------------------------
# _listener_recorded_pid <worker>
# Echo the numeric PID parsed from the recorded listen_bash_id ("bash-NNN"),
# or nothing if unrecorded / unparseable.
# ---------------------------------------------------------------------------
_listener_recorded_pid() {
    local worker="$1"
    local coord_root="${XFLEET_COORDINATION_ROOT:-}"
    [[ -z "${coord_root}" ]] && return 0

    local state_path="${coord_root}/state/${worker}.json"
    [[ ! -f "${state_path}" ]] && return 0

    local bid
    bid="$(jq -r '.listen_bash_id // empty' "${state_path}" 2>/dev/null)" || return 0
    [[ -z "${bid}" ]] && return 0

    # Format is "bash-NNN"; strip the prefix and keep only if numeric.
    local pid="${bid#bash-}"
    if [[ "${pid}" =~ ^[0-9]+$ ]]; then
        printf '%s' "${pid}"
    fi
}

# ---------------------------------------------------------------------------
# listener_stop_own <worker>
# ---------------------------------------------------------------------------
listener_stop_own() {
    local worker="$1"
    if [[ -z "${worker}" ]]; then
        printf 'listener_stop_own: worker name required\n' >&2
        return 1
    fi

    local pid
    pid="$(_listener_recorded_pid "${worker}")"
    if [[ -z "${pid}" ]]; then
        # Nothing recorded — nothing to stop.
        return 0
    fi

    # Stop ONLY this recorded process. listen.sh launches via setsid so the PID
    # is its own process-group leader; kill the whole group to also reap the
    # redis-cli BLOCK child. Fall back to a bare-PID kill when it is not a group
    # leader (setsid-absent launch). Best-effort — already-dead is fine.
    if kill -TERM -- "-${pid}" 2>/dev/null; then
        :
    else
        kill -TERM "${pid}" 2>/dev/null || true
    fi

    printf 'listener_stop_own: signalled own listener PID %s for %s\n' "${pid}" "${worker}" >&2
    return 0
}

# ---------------------------------------------------------------------------
# listener_warn_foreign <worker>
# ---------------------------------------------------------------------------
listener_warn_foreign() {
    local worker="$1"
    if [[ -z "${worker}" ]]; then
        printf 'listener_warn_foreign: worker name required\n' >&2
        return 1
    fi

    local own_pid
    own_pid="$(_listener_recorded_pid "${worker}")"

    # Best-effort: find candidate xfleet listener processes. The listener body
    # runs from a temp script named xfleet-listen-XXXXXX; match on that. The
    # temp file is removed shortly after launch, so this is genuinely best-effort
    # and may legitimately find nothing.
    local candidates
    candidates="$(pgrep -f 'xfleet-listen-' 2>/dev/null || true)"
    [[ -z "${candidates}" ]] && return 0

    local found_foreign=""
    while IFS= read -r cpid; do
        [[ -z "${cpid}" ]] && continue
        if [[ "${cpid}" != "${own_pid}" ]]; then
            found_foreign="${found_foreign} ${cpid}"
        fi
    done <<EOF
${candidates}
EOF

    if [[ -n "${found_foreign}" ]]; then
        printf 'listener_warn_foreign: foreign xfleet listener process(es) detected (PIDs:%s) that are NOT this session'\''s recorded listener (%s). NOT killing them — a peer session may own them. Run `ps`/`pkill` manually only if they are confirmed stale.\n' \
            "${found_foreign}" "${own_pid:-none}" >&2
    fi
    return 0
}

# ---------------------------------------------------------------------------
# listener_restart <worker>
# ---------------------------------------------------------------------------
listener_restart() {
    local worker="$1"
    if [[ -z "${worker}" ]]; then
        printf 'listener_restart: worker name required\n' >&2
        return 1
    fi

    listener_warn_foreign "${worker}"

    # listen.sh stops the recorded own-listener before launching a fresh one and
    # records the new listen_bash_id atomically, so it IS the safe restart.
    if [[ ! -x "${_LISTENER_LISTEN_SH}" ]]; then
        printf 'listener_restart: listen subcommand not found or not executable: %s\n' "${_LISTENER_LISTEN_SH}" >&2
        return 1
    fi
    bash "${_LISTENER_LISTEN_SH}" "${worker}"
}

# ---------------------------------------------------------------------------
# listener_alive <self>
# ---------------------------------------------------------------------------
listener_alive() {
    local self="$1"
    local pid
    pid="$(_listener_recorded_pid "${self}")"
    [[ -z "${pid}" ]] && return 1
    # kill -0 tests for existence + signalability without sending a signal.
    kill -0 "${pid}" 2>/dev/null
}

# ---------------------------------------------------------------------------
# send_with_verify <self>
# Post-send F-42 step: ensure <self>'s own listener is live (restart if not),
# so a peer response is not dropped. The caller already XADD'd its message.
# ---------------------------------------------------------------------------
send_with_verify() {
    local self="$1"
    if [[ -z "${self}" ]]; then
        printf 'send_with_verify: self name required\n' >&2
        return 1
    fi

    # No recorded listener (e.g. orchestrator — no listen_bash_id in v1 schema):
    # nothing to verify; surface a note and succeed.
    local pid
    pid="$(_listener_recorded_pid "${self}")"
    if [[ -z "${pid}" ]]; then
        printf 'send_with_verify: no recorded listen_bash_id for %s; skipping listener verify.\n' "${self}" >&2
        return 0
    fi

    if listener_alive "${self}"; then
        printf 'send_with_verify: own listener (PID %s) verified live for %s.\n' "${pid}" "${self}" >&2
        return 0
    fi

    # Listener is dead — restart so the response is not dropped (F-42).
    printf 'send_with_verify: own listener (PID %s) for %s is not alive; restarting.\n' "${pid}" "${self}" >&2
    listener_restart "${self}"
}
