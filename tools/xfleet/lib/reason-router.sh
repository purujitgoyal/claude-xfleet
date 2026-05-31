#!/usr/bin/env bash
# reason-router.sh — Per-reason routing table for xfleet escalation (Task 25).
#
# Defines the A2 routing rules for xfleet escalation --reason values and
# exposes helper functions that escalation.sh (and future handlers) use to
# make routing decisions without duplicating the table.
#
# Routing table (single source of truth — matches messaging.md section c):
#   breaking         → urgent    (bypass batching, slack-pair permitted)
#   plan-deviation   → urgent    (bypass batching, slack-pair permitted)
#   judgment-finding → non-urgent (batched, alert-only, no slack-pair)
#
# Public API (source this file; do NOT execute directly):
#   is_known_reason <reason>
#       Returns 0 if <reason> is in the routing table, 1 otherwise.
#
#   reason_priority <reason>
#       Prints "urgent" or "non-urgent". Exits 1 for unknown reasons.
#
#   reason_batched <reason>
#       Prints "yes" (non-urgent, batched) or "no" (urgent, bypass batching).
#       Exits 1 for unknown reasons.
#
#   reason_slack_pair <reason>
#       Prints "yes" (urgent, slack-pair signal permitted) or "no".
#       Exits 1 for unknown reasons.
#
# Bash-3.2 portable: uses case statements, no associative arrays.
#
# Usage (source, do not execute directly):
#   source tools/xfleet/lib/reason-router.sh

_REASON_ROUTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=strict-mode.sh
source "${_REASON_ROUTER_DIR}/strict-mode.sh"

# ---------------------------------------------------------------------------
# is_known_reason <reason>
# Returns 0 if the reason is in the routing table, 1 otherwise.
# ---------------------------------------------------------------------------
is_known_reason() {
    local reason="$1"
    case "${reason}" in
        breaking|plan-deviation|judgment-finding)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# reason_priority <reason>
# Prints "urgent" or "non-urgent". Exits 1 for unknown reasons.
# ---------------------------------------------------------------------------
reason_priority() {
    local reason="$1"
    case "${reason}" in
        breaking|plan-deviation)
            printf 'urgent'
            ;;
        judgment-finding)
            printf 'non-urgent'
            ;;
        *)
            printf 'reason-router: unknown reason "%s"\n' "${reason}" >&2
            exit 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# reason_batched <reason>
# Prints "yes" (non-urgent, batched) or "no" (urgent, bypass batching).
# Exits 1 for unknown reasons.
# ---------------------------------------------------------------------------
reason_batched() {
    local reason="$1"
    case "${reason}" in
        breaking|plan-deviation)
            printf 'no'
            ;;
        judgment-finding)
            printf 'yes'
            ;;
        *)
            printf 'reason-router: unknown reason "%s"\n' "${reason}" >&2
            exit 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# reason_slack_pair <reason>
# Prints "yes" (urgent, direct slack ping paired with escalation message
# is permitted) or "no". Exits 1 for unknown reasons.
# ---------------------------------------------------------------------------
reason_slack_pair() {
    local reason="$1"
    case "${reason}" in
        breaking|plan-deviation)
            printf 'yes'
            ;;
        judgment-finding)
            printf 'no'
            ;;
        *)
            printf 'reason-router: unknown reason "%s"\n' "${reason}" >&2
            exit 1
            ;;
    esac
}
