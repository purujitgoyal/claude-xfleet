#!/usr/bin/env bash
# phase.sh — xfleet phase subcommand (Task 26).
#
# Self-session role-aware phase management. No --message/--message-file (self-session
# per messaging.md "phase" row — message rules = none).
#
# WORKER role:
#   --enter <new_phase>   Transition into <new_phase>. If leaving a real phase,
#                         signals compact and writes a phase-exit handoff. Updates
#                         own state with phase entry resets.
#   --complete            Signal phase completion. Writes handoff, transitions own
#                         status to compacting, and emits a structural (content-less)
#                         phase-complete to inbox:orchestrator.
#
# ORCHESTRATOR role:
#   --enter <phase>       Lightweight no-op acknowledgment. Orch has no current_phase
#                         to set; phase-entry for the orch is a conceptual setup step —
#                         the gating actually happens on --complete.
#   --complete            Gated phase-complete emission (cluster 4a human gate).
#                         Requires --phase <P>. Checks phase_emissions[P][S].approved_by_human;
#                         blocks and logs the attempt if not approved; emits to --to workers
#                         and records if approved.
#
# Usage (worker):
#   xfleet phase --enter <new_phase> [--review-intensity <level>] [--slug <s>] [--repo-root <path>]
#   xfleet phase --complete [--slug <s>] [--repo-root <path>]
#
# Usage (orchestrator):
#   xfleet phase --enter <new_phase> [--review-intensity <level>]
#   xfleet phase --complete --phase <P> [--signal <S>] [--to <worker>] ...
#
# Exit codes:
#   0 — action performed (including "blocked" which is not an error)
#   1 — validation error or state/Redis failure

_PHASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_PHASE_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/redis.sh
source "${_PHASE_DIR}/../lib/redis.sh"
# shellcheck source=../lib/state-io.sh
source "${_PHASE_DIR}/../lib/state-io.sh"
# shellcheck source=../lib/handoff-writer.sh
source "${_PHASE_DIR}/../lib/handoff-writer.sh"
# shellcheck source=../lib/compact-dispatcher.sh
source "${_PHASE_DIR}/../lib/compact-dispatcher.sh"

# ---------------------------------------------------------------------------
# Resolve and validate XFLEET_ROLE (required; phase is self-session any-role
# but must branch on it, so XFLEET_ROLE must be set)
# ---------------------------------------------------------------------------
ROLE="${XFLEET_ROLE:-}"
if [[ -z "${ROLE}" ]]; then
    printf 'Error: XFLEET_ROLE is not set. Export XFLEET_ROLE=orchestrator or XFLEET_ROLE=worker before running xfleet subcommands.\n' >&2
    exit 1
fi
if [[ "${ROLE}" != "orchestrator" && "${ROLE}" != "worker" ]]; then
    printf 'Error: XFLEET_ROLE has unknown value "%s". Valid values: orchestrator, worker.\n' "${ROLE}" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
SUBACTION=""
NEW_PHASE=""
REVIEW_INTENSITY=""
# Slug default: $XFLEET_SLUG env if set, else "current" (matches phase-complete.sh default).
SLUG="${XFLEET_SLUG:-current}"
REPO_ROOT="${PWD}"
# Orchestrator-only options
ORCH_PHASE=""
SIGNAL="phase-complete"
# bash-3.2 portable array for --to workers
TO_WORKERS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --enter)
            if [[ $# -lt 2 ]]; then
                printf 'phase: --enter requires a value\n' >&2
                exit 1
            fi
            SUBACTION="enter"
            NEW_PHASE="$2"
            shift 2
            ;;
        --complete)
            SUBACTION="complete"
            shift
            ;;
        --review-intensity)
            if [[ $# -lt 2 ]]; then
                printf 'phase: --review-intensity requires a value\n' >&2
                exit 1
            fi
            REVIEW_INTENSITY="$2"
            shift 2
            ;;
        --slug)
            if [[ $# -lt 2 ]]; then
                printf 'phase: --slug requires a value\n' >&2
                exit 1
            fi
            SLUG="$2"
            shift 2
            ;;
        --repo-root)
            if [[ $# -lt 2 ]]; then
                printf 'phase: --repo-root requires a value\n' >&2
                exit 1
            fi
            REPO_ROOT="$2"
            shift 2
            ;;
        --phase)
            if [[ $# -lt 2 ]]; then
                printf 'phase: --phase requires a value\n' >&2
                exit 1
            fi
            ORCH_PHASE="$2"
            shift 2
            ;;
        --signal)
            if [[ $# -lt 2 ]]; then
                printf 'phase: --signal requires a value\n' >&2
                exit 1
            fi
            SIGNAL="$2"
            shift 2
            ;;
        --to)
            if [[ $# -lt 2 ]]; then
                printf 'phase: --to requires a value\n' >&2
                exit 1
            fi
            # Accumulate in a newline-separated string (bash-3.2 portable).
            if [[ -z "${TO_WORKERS}" ]]; then
                TO_WORKERS="$2"
            else
                TO_WORKERS="${TO_WORKERS}"$'\n'"$2"
            fi
            shift 2
            ;;
        *)
            printf 'phase: unknown option: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

# Require exactly one subaction.
if [[ -z "${SUBACTION}" ]]; then
    printf 'Usage: xfleet phase --enter <new_phase> [--review-intensity <level>] [--slug <s>] [--repo-root <path>]\n' >&2
    printf '       xfleet phase --complete [--slug <s>] [--repo-root <path>]\n' >&2
    printf 'Error: one of --enter or --complete is required.\n' >&2
    exit 1
fi

# ===========================================================================
# WORKER ROLE
# ===========================================================================
if [[ "${ROLE}" == "worker" ]]; then

    WORKER_NAME="${XFLEET_WORKER_NAME:-}"
    if [[ -z "${WORKER_NAME}" ]]; then
        printf 'Error: XFLEET_WORKER_NAME is not set (required to locate worker state file).\n' >&2
        exit 1
    fi

    COORD_ROOT="${XFLEET_COORDINATION_ROOT:-}"
    if [[ -z "${COORD_ROOT}" ]]; then
        printf 'Error: XFLEET_COORDINATION_ROOT is not set (required to locate worker state file).\n' >&2
        exit 1
    fi

    WORKER_STATE_PATH="${COORD_ROOT}/state/${WORKER_NAME}.json"

    # -----------------------------------------------------------------------
    # WORKER --enter <new_phase>
    # -----------------------------------------------------------------------
    if [[ "${SUBACTION}" == "enter" ]]; then
        if [[ -z "${NEW_PHASE}" ]]; then
            printf 'phase: --enter requires a phase name.\n' >&2
            exit 1
        fi

        # Read current phase (treat missing/empty as "idle").
        CURRENT_STATE=""
        CURRENT_STATE="$(state_read "${WORKER_STATE_PATH}")"
        CUR_PHASE="$(printf '%s' "${CURRENT_STATE}" | jq -r '.current_phase // empty')"
        CUR_PHASE="${CUR_PHASE:-idle}"

        # C1: count carried-forward session_scratch entries (advisory only).
        SCRATCH_COUNT="$(printf '%s' "${CURRENT_STATE}" | jq -r '(.session_scratch // {}) | length' 2>/dev/null || echo 0)"

        # If leaving a real phase that is not idle and not the same as the target:
        # signal compact and write a phase-exit handoff (no message arg → template placeholder).
        if [[ "${CUR_PHASE}" != "idle" && "${CUR_PHASE}" != "${NEW_PHASE}" ]]; then
            dispatch_compact
            write_phase_handoff "${REPO_ROOT}" "${SLUG}" "${CUR_PHASE}"
        fi

        # Update own state: set current_phase, reset counters mandated on phase entry
        # (review_revision_count=0, last_warn_emitted_at=null, last_check_at=null).
        # NEW_PHASE is passed via jq --arg (not string-interpolated into the program)
        # so a phase name with jq metacharacters cannot break the expression.
        NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        ENTER_PATCH="$(jq -cn \
            --arg cp  "${NEW_PHASE}" \
            --arg now "${NOW}" \
            '{current_phase: $cp, review_revision_count: 0, last_warn_emitted_at: null, last_check_at: null, last_updated: $now}'
        )"
        state_update_field "${WORKER_STATE_PATH}" ". + ${ENTER_PATCH}"

        # Print instruction to load the new phase skill.
        printf 'phase: entering phase "%s" — load the %s phase skill now.\n' "${NEW_PHASE}" "${NEW_PHASE}"
        if [[ -n "${REVIEW_INTENSITY}" ]]; then
            # review_intensity is NOT a stored state field; print as an override note only.
            printf 'phase: review-intensity override: %s\n' "${REVIEW_INTENSITY}"
        fi
        if [[ "${SCRATCH_COUNT}" =~ ^[0-9]+$ ]] && (( SCRATCH_COUNT > 0 )); then
            printf 'phase: note: session_scratch holds %s item(s). It is session-scoped and cleared at session teardown (phase-cleanup); promote anything durable to an artifact (spec Decisions Log, backlog, or a doc) before then.\n' "${SCRATCH_COUNT}"
        fi
        exit 0
    fi

    # -----------------------------------------------------------------------
    # WORKER --complete
    # -----------------------------------------------------------------------
    if [[ "${SUBACTION}" == "complete" ]]; then

        CURRENT_STATE=""
        CURRENT_STATE="$(state_read "${WORKER_STATE_PATH}")"
        CUR_PHASE="$(printf '%s' "${CURRENT_STATE}" | jq -r '.current_phase // empty')"

        # Write handoff and signal compact if in a real phase.
        if [[ -n "${CUR_PHASE}" && "${CUR_PHASE}" != "idle" ]]; then
            dispatch_compact
            write_phase_handoff "${REPO_ROOT}" "${SLUG}" "${CUR_PHASE}"
        fi

        # Update own state: status=compacting.
        NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        state_update_field "${WORKER_STATE_PATH}" \
            ". + {status: \"compacting\", last_updated: \"${NOW}\"}"

        # Emit structural (content-less) phase-complete signal to inbox:orchestrator.
        # This is the structural signal; the content-carrying form is the separate
        # phase-complete subcommand (phase-complete.sh).
        MSG_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
        TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

        PHASE_SIGNAL_MSG="$(jq -cn \
            --arg id     "${MSG_ID}" \
            --arg type   "phase-complete" \
            --arg from   "worker" \
            --arg to     "orchestrator" \
            --arg ts     "${TIMESTAMP}" \
            --arg worker "${WORKER_NAME}" \
            --arg phase  "${CUR_PHASE}" \
            '{id: $id, type: $type, from: $from, to: $to, timestamp: $ts, worker: $worker, phase: $phase}'
        )"

        xfleet_redis XADD "inbox:orchestrator" MAXLEN "~" 200 "*" data "${PHASE_SIGNAL_MSG}" >/dev/null

        printf 'phase: complete signal sent to orchestrator (msg_id: %s, worker: %s, phase: %s, status: compacting)\n' \
            "${MSG_ID}" "${WORKER_NAME}" "${CUR_PHASE}"
        exit 0
    fi

fi

# ===========================================================================
# ORCHESTRATOR ROLE
# ===========================================================================
if [[ "${ROLE}" == "orchestrator" ]]; then

    # -----------------------------------------------------------------------
    # ORCHESTRATOR --enter <phase>
    # Orch has no current_phase to set. Phase-entry is a lightweight conceptual
    # setup step for the orchestrator; the actual phase gate fires on --complete.
    # No state writes here.
    # -----------------------------------------------------------------------
    if [[ "${SUBACTION}" == "enter" ]]; then
        if [[ -z "${NEW_PHASE}" ]]; then
            printf 'phase: --enter requires a phase name.\n' >&2
            exit 1
        fi
        printf 'phase: orchestrator acknowledged phase-entry for "%s" (no state write — gating fires on --complete).\n' \
            "${NEW_PHASE}"
        if [[ -n "${REVIEW_INTENSITY}" ]]; then
            printf 'phase: review-intensity note: %s\n' "${REVIEW_INTENSITY}"
        fi
        exit 0
    fi

    # -----------------------------------------------------------------------
    # ORCHESTRATOR --complete (gated emission — cluster 4a human gate)
    # -----------------------------------------------------------------------
    if [[ "${SUBACTION}" == "complete" ]]; then

        # --phase is required for orchestrator complete (orch has no current_phase).
        if [[ -z "${ORCH_PHASE}" ]]; then
            printf 'Error: orchestrator "phase --complete" requires --phase <P> (orchestrator has no current_phase field).\n' >&2
            exit 1
        fi

        COORD_ROOT="${XFLEET_COORDINATION_ROOT:-}"
        if [[ -z "${COORD_ROOT}" ]]; then
            printf 'Error: XFLEET_COORDINATION_ROOT is not set (required for orchestrator state writes).\n' >&2
            exit 1
        fi

        ORCH_STATE_PATH="${COORD_ROOT}/state/_orchestrator.json"

        # Read current orch state and check approved_by_human for (phase, signal).
        ORCH_STATE=""
        ORCH_STATE="$(state_read "${ORCH_STATE_PATH}")"

        APPROVED="$(printf '%s' "${ORCH_STATE}" | jq -r \
            --arg p "${ORCH_PHASE}" \
            --arg s "${SIGNAL}" \
            '.phase_emissions[$p][$s].approved_by_human // false'
        )"

        NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        EMISSION_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"

        # -------------------------------------------------------------------
        # NOT APPROVED: block, log the attempt, exit 0.
        # -------------------------------------------------------------------
        if [[ "${APPROVED}" != "true" ]]; then
            # Append emission_log entry with outcome=blocked.
            BLOCKED_LOG_ENTRY="$(jq -cn \
                --arg phase       "${ORCH_PHASE}" \
                --arg signal      "${SIGNAL}" \
                --arg attempted   "${NOW}" \
                --argjson approved false \
                --arg eid         "${EMISSION_ID}" \
                --arg outcome     "blocked" \
                '{phase: $phase, signal: $signal, attempted_at: $attempted, approved_by_human: $approved, emission_id: $eid, outcome: $outcome}'
            )"

            state_update_field "${ORCH_STATE_PATH}" \
                ". + {emission_log: ((.emission_log // []) + [${BLOCKED_LOG_ENTRY}])}"

            printf 'phase: BLOCKED — phase "%s" signal "%s" is awaiting human approval.\n' \
                "${ORCH_PHASE}" "${SIGNAL}"
            printf 'phase: to approve, set phase_emissions["%s"]["%s"].approved_by_human = true in _orchestrator.json.\n' \
                "${ORCH_PHASE}" "${SIGNAL}"
            printf 'phase: note: re-emission after a gate reopen requires re-approval.\n'
            exit 0
        fi

        # -------------------------------------------------------------------
        # APPROVED: build sent_to array, update phase_emissions, log, XADD.
        # -------------------------------------------------------------------

        # Build sent_to JSON array from TO_WORKERS (newline-separated string).
        if [[ -z "${TO_WORKERS}" ]]; then
            SENT_TO_JSON="[]"
        else
            SENT_TO_JSON="$(printf '%s' "${TO_WORKERS}" | jq -Rn '[inputs]')"
        fi

        TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

        # Build the approved emission record (required fields per schema).
        EMISSION_RECORD="$(jq -cn \
            --argjson approved true \
            --arg sent_at     "${TIMESTAMP}" \
            --argjson sent_to "${SENT_TO_JSON}" \
            --arg eid         "${EMISSION_ID}" \
            '{approved_by_human: $approved, sent_at: $sent_at, sent_to: $sent_to, emission_id: $eid}'
        )"

        # Approved log entry.
        SENT_LOG_ENTRY="$(jq -cn \
            --arg phase       "${ORCH_PHASE}" \
            --arg signal      "${SIGNAL}" \
            --arg attempted   "${TIMESTAMP}" \
            --argjson approved true \
            --arg eid         "${EMISSION_ID}" \
            --arg outcome     "sent" \
            '{phase: $phase, signal: $signal, attempted_at: $attempted, approved_by_human: $approved, emission_id: $eid, outcome: $outcome}'
        )"

        # Apply BOTH the nested phase_emissions[P][S] set and the emission_log append
        # in ONE atomic write. ORCH_PHASE / SIGNAL are passed via jq --arg (used as
        # map KEYS) so a phase/signal name with jq metacharacters cannot break the
        # program; the record/log objects are passed via --argjson. state_write_atomic
        # validates + tmp+mv exactly like state_update_field, but lets us pass --arg.
        UPDATED_ORCH_STATE="$(printf '%s' "${ORCH_STATE}" | jq \
            --arg p           "${ORCH_PHASE}" \
            --arg s           "${SIGNAL}" \
            --argjson rec     "${EMISSION_RECORD}" \
            --argjson logentry "${SENT_LOG_ENTRY}" \
            '.phase_emissions = ((.phase_emissions // {}) | .[$p] = ((.[$p] // {}) | .[$s] = $rec))
             | .emission_log = ((.emission_log // []) + [$logentry])'
        )"
        state_write_atomic "${ORCH_STATE_PATH}" "${UPDATED_ORCH_STATE}"

        # XADD to each --to worker (skip if none).
        if [[ -n "${TO_WORKERS}" ]]; then
            while IFS= read -r WORKER; do
                if [[ -z "${WORKER}" ]]; then
                    continue
                fi
                WORKER_MSG="$(jq -cn \
                    --arg id     "${EMISSION_ID}" \
                    --arg type   "${SIGNAL}" \
                    --arg from   "orchestrator" \
                    --arg to     "${WORKER}" \
                    --arg ts     "${TIMESTAMP}" \
                    --arg phase  "${ORCH_PHASE}" \
                    '{id: $id, type: $type, from: $from, to: $to, timestamp: $ts, phase: $phase}'
                )"
                xfleet_redis XADD "inbox:${WORKER}" MAXLEN "~" 200 "*" data "${WORKER_MSG}" >/dev/null
            done <<EOF
${TO_WORKERS}
EOF
        fi

        printf 'phase: emitted signal "%s" for phase "%s" (emission_id: %s, sent_to: %s)\n' \
            "${SIGNAL}" "${ORCH_PHASE}" "${EMISSION_ID}" "${SENT_TO_JSON}"
        exit 0
    fi

fi
