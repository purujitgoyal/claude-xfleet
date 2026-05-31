#!/usr/bin/env bash
# resolution-ack-handler.sh — Reflexive handler for resolution-ack (Task 22).
#
# This script is NOT a user-facing subcommand. It is invoked internally by
# resolution.sh as part of the F-33 closure handshake. Per messaging.md (f),
# reflexive handlers are never user-invocable and never appear in the
# subcommand registry.
#
# Responsibilities (messaging.md e + f):
#   Emit the resolution-ack wire message to the peer worker (concern raiser).
#   The state write (marking the concern in confirmed_closed_concerns[]) is owned
#   by the user-facing resolution.sh, NOT this reflexive handler.
#
# Usage (internal, called by resolution.sh):
#   resolution-ack-handler.sh <peer-worker> <concern-id> <resolution-msg-id> <content>
#
# Arguments (all required, all non-empty):
#   peer-worker       — recipient of the resolution-ack (original concern raiser)
#   concern-id        — id of the concern being closed
#   resolution-msg-id — id of the originating resolution message (for correlation)
#   content           — resolution message content (forwarded to ack payload)
#
# Exit codes:
#   0 — resolution-ack published
#   1 — argument or Redis failure

_ACK_HANDLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_ACK_HANDLER_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/redis.sh
source "${_ACK_HANDLER_DIR}/../lib/redis.sh"

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------
if [[ $# -lt 4 ]]; then
    printf 'resolution-ack-handler: expected 4 arguments: <peer-worker> <concern-id> <resolution-msg-id> <content>\n' >&2
    exit 1
fi

PEER_WORKER="$1"
CONCERN_ID="$2"
RESOLUTION_MSG_ID="$3"
CONTENT="$4"

if [[ -z "${PEER_WORKER}" ]]; then
    printf 'resolution-ack-handler: peer-worker argument is empty.\n' >&2
    exit 1
fi

if [[ -z "${CONCERN_ID}" ]]; then
    printf 'resolution-ack-handler: concern-id argument is empty.\n' >&2
    exit 1
fi

if [[ -z "${RESOLUTION_MSG_ID}" ]]; then
    printf 'resolution-ack-handler: resolution-msg-id argument is empty.\n' >&2
    exit 1
fi

if [[ -z "${CONTENT}" ]]; then
    printf 'resolution-ack-handler: content argument is empty.\n' >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Build and publish resolution-ack to peer worker (messaging.md e step 1)
# ---------------------------------------------------------------------------
SENDER="${XFLEET_ROLE:-worker}"   # reflexive handler inherits role from resolution.sh
ACK_MSG_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

ACK_MSG="$(jq -cn \
    --arg id              "${ACK_MSG_ID}" \
    --arg type            "resolution-ack" \
    --arg from            "${SENDER}" \
    --arg to              "${PEER_WORKER}" \
    --arg ts              "${TIMESTAMP}" \
    --arg content         "${CONTENT}" \
    --arg concern_id      "${CONCERN_ID}" \
    --arg resolution_id   "${RESOLUTION_MSG_ID}" \
    '{id: $id, type: $type, from: $from, to: $to, timestamp: $ts, content: $content, concern_id: $concern_id, resolution_id: $resolution_id}'
)"

xfleet_redis XADD "inbox:${PEER_WORKER}" MAXLEN "~" 200 "*" data "${ACK_MSG}" >/dev/null

# The state write (confirmed_closed_concerns[]) is owned by resolution.sh, not
# this reflexive handler — this handler only emits the resolution-ack message.

printf 'resolution-ack-handler: ack sent to %s (ack_id: %s, concern_id: %s)\n' \
    "${PEER_WORKER}" "${ACK_MSG_ID}" "${CONCERN_ID}"
