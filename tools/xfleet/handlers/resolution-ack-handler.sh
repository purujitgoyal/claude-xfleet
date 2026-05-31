#!/usr/bin/env bash
# resolution-ack-handler.sh — Reflexive handler for resolution-ack (Task 22).
#
# This script is NOT a user-facing subcommand. It is invoked internally by
# resolution.sh as part of the F-33 closure handshake. Per messaging.md (f),
# reflexive handlers are never user-invocable and never appear in the
# subcommand registry.
#
# Responsibilities (messaging.md e + f):
#   1. Emit a resolution-ack wire message to the peer worker (concern raiser).
#   2. Append the concern_id to the sender's confirmed_closed_concerns[] array
#      (deduped) via state_update_field.
#
# Usage (internal, called by resolution.sh):
#   resolution-ack-handler.sh <peer-worker> <concern-id> <resolution-msg-id> <content>
#
# Arguments:
#   peer-worker       — recipient of the resolution-ack (original concern raiser)
#   concern-id        — id of the concern being closed
#   resolution-msg-id — id of the originating resolution message (for correlation)
#   content           — resolution message content (forwarded to ack payload)
#
# Exit codes:
#   0 — resolution-ack published; state updated
#   1 — argument or Redis/state failure

_ACK_HANDLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_ACK_HANDLER_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/redis.sh
source "${_ACK_HANDLER_DIR}/../lib/redis.sh"
# shellcheck source=../lib/state-io.sh
source "${_ACK_HANDLER_DIR}/../lib/state-io.sh"

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

# ---------------------------------------------------------------------------
# Append concern_id to confirmed_closed_concerns[] in sender's worker state
# (messaging.md e step 3). Deduplicate via jq `unique`.
# State path is inherited from XFLEET_WORKER_STATE_PATH (set by resolution.sh's
# environment; this handler runs in the same process).
# ---------------------------------------------------------------------------
WORKER_STATE_PATH="${XFLEET_WORKER_STATE_PATH:-}"
if [[ -n "${WORKER_STATE_PATH}" ]]; then
    state_update_field "${WORKER_STATE_PATH}" \
        ". + {confirmed_closed_concerns: ((.confirmed_closed_concerns // []) + [\"${CONCERN_ID}\"] | unique)}"
fi
# If XFLEET_WORKER_STATE_PATH is unset we skip the state write — the handler
# still succeeds at emitting the ack. resolution.sh itself also writes the state,
# so closure is still recorded end-to-end.

printf 'resolution-ack-handler: ack sent to %s (ack_id: %s, concern_id: %s)\n' \
    "${PEER_WORKER}" "${ACK_MSG_ID}" "${CONCERN_ID}"
