#!/usr/bin/env bash
# escalation.sh — xfleet escalation subcommand (Task 25).
#
# Sends a worker→orchestrator escalation. Per messaging.md (b) and section (c):
# sender must be worker; recipient is always orchestrator; routing is determined
# by --reason (see lib/reason-router.sh for the routing table).
#
# Ownership invariant: escalation.sh is a SENDER ONLY. It does NOT write
# _orchestrator.json (escalation_log[] append is orch-side, deferred to the
# listener task). It does NOT write the worker's own state file. XADD only.
#
# Routing per messaging.md section (c) / A2:
#   URGENT (breaking, plan-deviation):
#     - Bypasses batching; surfaces to human immediately.
#     - Content body IS carried on the wire (--message or --message-file required).
#     - slack_pair:true emitted in the wire message (signals a paired slack ping
#       is permitted, but the actual Slack ping is the caller's responsibility).
#   NON-URGENT (judgment-finding):
#     - Batched; alert-only — NO content body on the wire.
#     - --path <review-path> pointer is supported (optional); content is NOT copied.
#     - --message / --message-file are rejected (alert-not-content invariant).
#
# human_engaged is NOT auto-set by escalation arrival. That is an orch-side rule
# that fires only on directive dispatch (cluster 4a). escalation.sh touches no
# orch state.
#
# Usage:
#   xfleet escalation --reason <reason> --message <text>
#   xfleet escalation --reason <reason> --message-file <path>
#   xfleet escalation --reason judgment-finding [--path <review-path>]
#
# Options:
#   --reason <reason>      Required. One of: breaking, plan-deviation, judgment-finding.
#   --message <text>       Inline message text (urgent reasons only).
#   --message-file <path>  Path to a file with the message (urgent reasons only; SC-5 scoped).
#   --path <review-path>   Review-file path pointer (non-urgent only; alert-not-content).
#
# Exit codes:
#   0 — escalation sent to inbox:orchestrator
#   1 — validation error or Redis failure

_ESCALATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_ESCALATION_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/redis.sh
source "${_ESCALATION_DIR}/../lib/redis.sh"
# shellcheck source=../lib/sender-authority.sh
source "${_ESCALATION_DIR}/../lib/sender-authority.sh"
# shellcheck source=../lib/reason-router.sh
source "${_ESCALATION_DIR}/../lib/reason-router.sh"
# shellcheck source=../lib/listener.sh
source "${_ESCALATION_DIR}/../lib/listener.sh"

# ---------------------------------------------------------------------------
# Role check — worker only (messaging.md b)
# ---------------------------------------------------------------------------
assert_role worker "escalations are raised by a worker to the orchestrator; an orchestrator has nothing to escalate to itself — use 'directive' to act on it instead."

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
REASON=""
MESSAGE_TEXT=""
MESSAGE_FILE=""
REVIEW_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --reason)
            if [[ $# -lt 2 ]]; then
                printf 'escalation: --reason requires a value\n' >&2
                exit 1
            fi
            REASON="$2"
            shift 2
            ;;
        --message)
            if [[ $# -lt 2 ]]; then
                printf 'escalation: --message requires a value\n' >&2
                exit 1
            fi
            MESSAGE_TEXT="$2"
            shift 2
            ;;
        --message-file)
            if [[ $# -lt 2 ]]; then
                printf 'escalation: --message-file requires a value\n' >&2
                exit 1
            fi
            MESSAGE_FILE="$2"
            shift 2
            ;;
        --path)
            if [[ $# -lt 2 ]]; then
                printf 'escalation: --path requires a value\n' >&2
                exit 1
            fi
            REVIEW_PATH="$2"
            shift 2
            ;;
        *)
            printf 'escalation: unknown option: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Validate --reason (required; must be a known reason)
# ---------------------------------------------------------------------------
if [[ -z "${REASON}" ]]; then
    printf 'Usage: xfleet escalation --reason <reason> --message <text>\n' >&2
    printf '       xfleet escalation --reason <reason> --message-file <path>\n' >&2
    printf '       xfleet escalation --reason judgment-finding [--path <review-path>]\n' >&2
    printf 'Error: --reason is required.\n' >&2
    printf 'Valid reasons: breaking, plan-deviation, judgment-finding\n' >&2
    exit 1
fi

if ! is_known_reason "${REASON}"; then
    printf 'escalation: unknown --reason "%s".\n' "${REASON}" >&2
    printf 'Valid reasons: breaking, plan-deviation, judgment-finding\n' >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Resolve routing metadata from reason-router
# ---------------------------------------------------------------------------
PRIORITY="$(reason_priority "${REASON}")"
BATCHED="$(reason_batched "${REASON}")"
SLACK_PAIR="$(reason_slack_pair "${REASON}")"

# ---------------------------------------------------------------------------
# Content rules: urgent vs non-urgent (alert-not-content)
# ---------------------------------------------------------------------------
MESSAGE_CONTENT=""
RECIPIENT="orchestrator"

if [[ "${PRIORITY}" == "urgent" ]]; then
    # Urgent: exactly one of --message / --message-file is required.
    # --path is not applicable to urgent escalations.
    if [[ -n "${REVIEW_PATH}" ]]; then
        printf 'escalation: --path is only valid for non-urgent reasons (judgment-finding).\n' >&2
        exit 1
    fi

    if [[ -n "${MESSAGE_TEXT}" && -n "${MESSAGE_FILE}" ]]; then
        printf 'escalation: requires exactly one of --message or --message-file, but both were provided.\n' >&2
        exit 1
    fi

    if [[ -z "${MESSAGE_TEXT}" && -z "${MESSAGE_FILE}" ]]; then
        printf 'escalation: urgent reason "%s" requires exactly one of --message or --message-file.\n' \
            "${REASON}" >&2
        exit 1
    fi

    if [[ -n "${MESSAGE_TEXT}" ]]; then
        MESSAGE_CONTENT="${MESSAGE_TEXT}"
    else
        # --message-file: SC-5 strict path scoping (must resolve under XFLEET_COORDINATION_ROOT).
        COORD_ROOT="${XFLEET_COORDINATION_ROOT:-}"
        if [[ -z "${COORD_ROOT}" ]]; then
            printf 'Error: XFLEET_COORDINATION_ROOT is not set (required for --message-file path validation).\n' >&2
            exit 1
        fi

        RESOLVED_ROOT=""
        if ! RESOLVED_ROOT="$(realpath "${COORD_ROOT}" 2>/dev/null)"; then
            printf 'Error: XFLEET_COORDINATION_ROOT "%s" could not be resolved.\n' "${COORD_ROOT}" >&2
            exit 1
        fi

        RESOLVED_FILE=""
        if ! RESOLVED_FILE="$(realpath "${MESSAGE_FILE}" 2>/dev/null)"; then
            printf 'Error: --message-file path "%s" could not be resolved (file may not exist).\n' \
                "${MESSAGE_FILE}" >&2
            exit 1
        fi

        ROOT_PREFIX="${RESOLVED_ROOT}/"
        if [[ "${RESOLVED_FILE}" != "${RESOLVED_ROOT}" && "${RESOLVED_FILE}" != "${ROOT_PREFIX}"* ]]; then
            printf "Error: --message-file path '%s' resolves outside allowed roots; copy the file under \$XFLEET_COORDINATION_ROOT first.\n" \
                "${MESSAGE_FILE}" >&2
            exit 1
        fi

        if [[ ! -f "${RESOLVED_FILE}" ]]; then
            printf 'Error: --message-file path "%s" does not exist or is not a regular file.\n' \
                "${MESSAGE_FILE}" >&2
            exit 1
        fi

        MESSAGE_CONTENT="$(cat "${RESOLVED_FILE}")"
    fi

else
    # Non-urgent (judgment-finding): alert-only — no content body on the wire.
    if [[ -n "${MESSAGE_TEXT}" || -n "${MESSAGE_FILE}" ]]; then
        printf 'escalation: --reason "%s" is non-urgent (alert-only). Use --path for a review-file pointer; do not provide --message or --message-file.\n' \
            "${REASON}" >&2
        exit 1
    fi
    # MESSAGE_CONTENT stays empty for non-urgent (alert-not-content).
fi

# ---------------------------------------------------------------------------
# Build wire message
# ---------------------------------------------------------------------------
MSG_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
SENDER="${XFLEET_ROLE}"   # "worker" (already asserted)

if [[ "${PRIORITY}" == "urgent" ]]; then
    # Urgent: carry content body + slack_pair signal.
    # slack_pair:true signals a paired Slack ping is permitted (caller's responsibility).
    ESCALATION_MSG="$(jq -cn \
        --arg id         "${MSG_ID}" \
        --arg type       "escalation" \
        --arg from       "${SENDER}" \
        --arg to         "${RECIPIENT}" \
        --arg ts         "${TIMESTAMP}" \
        --arg reason     "${REASON}" \
        --arg priority   "${PRIORITY}" \
        --arg batched    "${BATCHED}" \
        --argjson slack_pair true \
        --arg content    "${MESSAGE_CONTENT}" \
        '{id: $id, type: $type, from: $from, to: $to, timestamp: $ts, reason: $reason, priority: $priority, batched: $batched, slack_pair: $slack_pair, content: $content}'
    )"
else
    # Non-urgent (judgment-finding): alert-only — no content body.
    # Carry --path pointer if provided; omit otherwise.
    if [[ -n "${REVIEW_PATH}" ]]; then
        ESCALATION_MSG="$(jq -cn \
            --arg id         "${MSG_ID}" \
            --arg type       "escalation" \
            --arg from       "${SENDER}" \
            --arg to         "${RECIPIENT}" \
            --arg ts         "${TIMESTAMP}" \
            --arg reason     "${REASON}" \
            --arg priority   "${PRIORITY}" \
            --arg batched    "${BATCHED}" \
            --argjson slack_pair false \
            --arg path       "${REVIEW_PATH}" \
            '{id: $id, type: $type, from: $from, to: $to, timestamp: $ts, reason: $reason, priority: $priority, batched: $batched, slack_pair: $slack_pair, path: $path}'
        )"
    else
        ESCALATION_MSG="$(jq -cn \
            --arg id         "${MSG_ID}" \
            --arg type       "escalation" \
            --arg from       "${SENDER}" \
            --arg to         "${RECIPIENT}" \
            --arg ts         "${TIMESTAMP}" \
            --arg reason     "${REASON}" \
            --arg priority   "${PRIORITY}" \
            --arg batched    "${BATCHED}" \
            --argjson slack_pair false \
            '{id: $id, type: $type, from: $from, to: $to, timestamp: $ts, reason: $reason, priority: $priority, batched: $batched, slack_pair: $slack_pair}'
        )"
    fi
fi

# ---------------------------------------------------------------------------
# Publish to orchestrator inbox.
# Senders do NOT create consumer groups; listeners own that. No state writes.
# ---------------------------------------------------------------------------
xfleet_redis XADD "inbox:${RECIPIENT}" MAXLEN "~" 200 "*" data "${ESCALATION_MSG}" >/dev/null

# F-42 two-call pattern: ensure our own listener is live so the response is not dropped.
send_with_verify "${XFLEET_WORKER_NAME}"

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
if [[ "${PRIORITY}" == "urgent" ]]; then
    printf 'escalation: sent to %s (msg_id: %s, reason: %s, priority: %s, batched: %s, slack_pair: true)\n' \
        "${RECIPIENT}" "${MSG_ID}" "${REASON}" "${PRIORITY}" "${BATCHED}"
else
    if [[ -n "${REVIEW_PATH}" ]]; then
        printf 'escalation: sent to %s (msg_id: %s, reason: %s, priority: %s, batched: %s, alert-only, path: %s)\n' \
            "${RECIPIENT}" "${MSG_ID}" "${REASON}" "${PRIORITY}" "${BATCHED}" "${REVIEW_PATH}"
    else
        printf 'escalation: sent to %s (msg_id: %s, reason: %s, priority: %s, batched: %s, alert-only)\n' \
            "${RECIPIENT}" "${MSG_ID}" "${REASON}" "${PRIORITY}" "${BATCHED}"
    fi
fi
