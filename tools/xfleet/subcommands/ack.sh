#!/usr/bin/env bash
# ack.sh — xfleet ack subcommand (Task 20).
#
# Acknowledges a Redis Stream message by id (XACK). Once ACKed the message
# leaves the PEL and won't be re-delivered. Ports wave-1 ack.sh semantics
# with XFLEET_REDIS_URL generalization (SC-3). No authority enforcement
# (read-only/session-local per messaging.md A3).
#
# Usage: xfleet ack <name> <message_id> [--group <group>] [--force]
#
# Options:
#   --group <group>  Consumer group name (default: worker)
#   --force          Permissive: warn + exit 0 if XACK returns 0
#
# Exit codes:
#   0 — acknowledged (or stale + --force)
#   1 — error or XACK returned 0 (stale/double-ACK in strict mode)

_ACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_ACK_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/redis.sh
source "${_ACK_DIR}/../lib/redis.sh"

# ---------------------------------------------------------------------------
# Arg validation
# ---------------------------------------------------------------------------
if [[ $# -lt 2 ]]; then
    printf 'Usage: xfleet ack <name> <message_id> [--group <group>] [--force]\n' >&2
    exit 1
fi

NAME="$1"
MESSAGE_ID="$2"
shift 2

# ---------------------------------------------------------------------------
# Parse optional flags
# ---------------------------------------------------------------------------
GROUP="worker"
FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --group)
            if [[ $# -lt 2 ]]; then
                printf 'ack: --group requires a value\n' >&2
                exit 1
            fi
            GROUP="$2"
            shift 2
            ;;
        --force)
            FORCE=1
            shift
            ;;
        *)
            printf 'ack: unknown option: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# XACK the message
# ---------------------------------------------------------------------------
RESULT="$(xfleet_redis XACK "inbox:${NAME}" "${GROUP}" "${MESSAGE_ID}")"

if [[ "${RESULT}" == "1" ]]; then
    exit 0
else
    if [[ "${FORCE}" -eq 1 ]]; then
        printf 'Warning: XACK returned %s (message may not exist or was already ACKed)\n' \
            "${RESULT}" >&2
        exit 0
    else
        printf 'Error: XACK returned 0 — message %s is not pending in group %s on inbox:%s. Either never delivered, already ACKed, or wrong ID. Pass --force to ignore.\n' \
            "${MESSAGE_ID}" "${GROUP}" "${NAME}" >&2
        exit 1
    fi
fi
