#!/usr/bin/env bash
# phase-complete.sh — xfleet phase-complete subcommand (Task 26).
#
# Content-carrying worker→orchestrator phase-complete signal. Informs the
# orchestrator that the worker has completed its current phase, carries a
# handoff message as resume instructions, writes a phase-exit handoff doc,
# and transitions the worker's own status to "compacting".
#
# Sender invariant: WORKER ONLY. This script writes ONLY the worker's own
# state file ({worker}.json). It NEVER writes _orchestrator.json — that is
# deferred to the listener (a later task). XADD to inbox:orchestrator only.
#
# Usage:
#   xfleet phase-complete --message <text>
#   xfleet phase-complete --message-file <path>
#   xfleet phase-complete --message <text> [--slug <s>] [--repo-root <path>]
#   xfleet phase-complete --message-file <path> [--slug <s>] [--repo-root <path>]
#
# Options:
#   --message <text>       Inline resume-instructions text (exactly one of --message/--message-file)
#   --message-file <path>  Path to a file with resume instructions (SC-5 scoped)
#   --slug <s>             Short project slug for the handoff subdirectory
#                          (default: $XFLEET_SLUG env if set, else "current")
#   --repo-root <path>     Repo root for writing the handoff doc (default: $PWD)
#
# Exit codes:
#   0 — phase-complete sent to inbox:orchestrator; worker status set to "compacting"
#   1 — validation error, role rejection, or Redis/state failure

_PHASE_COMPLETE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_PHASE_COMPLETE_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/redis.sh
source "${_PHASE_COMPLETE_DIR}/../lib/redis.sh"
# shellcheck source=../lib/sender-authority.sh
source "${_PHASE_COMPLETE_DIR}/../lib/sender-authority.sh"
# shellcheck source=../lib/message-content.sh
source "${_PHASE_COMPLETE_DIR}/../lib/message-content.sh"
# shellcheck source=../lib/state-io.sh
source "${_PHASE_COMPLETE_DIR}/../lib/state-io.sh"
# shellcheck source=../lib/handoff-writer.sh
source "${_PHASE_COMPLETE_DIR}/../lib/handoff-writer.sh"
# shellcheck source=../lib/compact-dispatcher.sh
source "${_PHASE_COMPLETE_DIR}/../lib/compact-dispatcher.sh"

# ---------------------------------------------------------------------------
# Role check — worker only
# ---------------------------------------------------------------------------
assert_role worker "workers signal phase-complete to the orchestrator; from an orchestrator session use 'phase --complete --phase <P>' to emit the gated signal instead."

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
MESSAGE_TEXT=""
MESSAGE_FILE=""
# Slug default: $XFLEET_SLUG env if set, else "current" (documented for callers).
SLUG="${XFLEET_SLUG:-current}"
REPO_ROOT="${PWD}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --message)
            if [[ $# -lt 2 ]]; then
                printf 'phase-complete: --message requires a value\n' >&2
                exit 1
            fi
            MESSAGE_TEXT="$2"
            shift 2
            ;;
        --message-file)
            if [[ $# -lt 2 ]]; then
                printf 'phase-complete: --message-file requires a value\n' >&2
                exit 1
            fi
            MESSAGE_FILE="$2"
            shift 2
            ;;
        --slug)
            if [[ $# -lt 2 ]]; then
                printf 'phase-complete: --slug requires a value\n' >&2
                exit 1
            fi
            SLUG="$2"
            shift 2
            ;;
        --repo-root)
            if [[ $# -lt 2 ]]; then
                printf 'phase-complete: --repo-root requires a value\n' >&2
                exit 1
            fi
            REPO_ROOT="$2"
            shift 2
            ;;
        *)
            printf 'phase-complete: unknown option: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Validate and resolve message content (exactly one of --message/--message-file)
# ---------------------------------------------------------------------------
MESSAGE_CONTENT=""
resolve_message_content MESSAGE_TEXT MESSAGE_FILE phase-complete

# ---------------------------------------------------------------------------
# Resolve worker state file path
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Read current_phase from worker state
# ---------------------------------------------------------------------------
CURRENT_STATE=""
CURRENT_STATE="$(state_read "${WORKER_STATE_PATH}")"
CURRENT_PHASE="$(printf '%s' "${CURRENT_STATE}" | jq -r '.current_phase // empty')"

# ---------------------------------------------------------------------------
# Write phase-exit handoff and signal compact if in a real phase
# ---------------------------------------------------------------------------
if [[ -n "${CURRENT_PHASE}" && "${CURRENT_PHASE}" != "idle" ]]; then
    dispatch_compact
    write_phase_handoff "${REPO_ROOT}" "${SLUG}" "${CURRENT_PHASE}" "${MESSAGE_CONTENT}"
fi

# ---------------------------------------------------------------------------
# Update worker's own state: status=compacting, last_updated=<now>
# (writer ownership: worker writes ONLY its own file)
# ---------------------------------------------------------------------------
NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
state_update_field "${WORKER_STATE_PATH}" \
    ". + {status: \"compacting\", last_updated: \"${NOW}\"}"

# ---------------------------------------------------------------------------
# Build and publish wire message to inbox:orchestrator
# phase-complete carries content (resume instructions) + worker + phase fields.
# Senders do NOT create consumer groups; listeners own that. No orch state writes.
# ---------------------------------------------------------------------------
MSG_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

PHASE_COMPLETE_MSG="$(jq -cn \
    --arg id      "${MSG_ID}" \
    --arg type    "phase-complete" \
    --arg from    "worker" \
    --arg to      "orchestrator" \
    --arg ts      "${TIMESTAMP}" \
    --arg content "${MESSAGE_CONTENT}" \
    --arg worker  "${WORKER_NAME}" \
    --arg phase   "${CURRENT_PHASE}" \
    '{id: $id, type: $type, from: $from, to: $to, timestamp: $ts, content: $content, worker: $worker, phase: $phase}'
)"

xfleet_redis XADD "inbox:orchestrator" MAXLEN "~" 200 "*" data "${PHASE_COMPLETE_MSG}" >/dev/null

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
printf 'phase-complete: sent to orchestrator (msg_id: %s, worker: %s, phase: %s, status: compacting)\n' \
    "${MSG_ID}" "${WORKER_NAME}" "${CURRENT_PHASE}"
