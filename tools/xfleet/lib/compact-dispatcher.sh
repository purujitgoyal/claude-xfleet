#!/usr/bin/env bash
# compact-dispatcher.sh — signals the session to run prepare-compact (Task 26).
#
# Public API:
#   dispatch_compact
#       A bash script cannot invoke a Claude skill directly; this function only
#       SIGNALS the session that prepare-compact should be run now. It emits one
#       instruction line to stdout and returns 0. No state writes, no Redis.
#
# Usage (source, do not execute directly):
#   source tools/xfleet/lib/compact-dispatcher.sh

_COMPACT_DISPATCHER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=strict-mode.sh
source "${_COMPACT_DISPATCHER_DIR}/strict-mode.sh"

# dispatch_compact
# Signals the session to run prepare-compact. Real invocation is a session/agent
# action; this function only emits the instruction line.
dispatch_compact() {
    printf '>>> xfleet: run the prepare-compact skill now (phase transition — write the phase-exit handoff'\''s Resume Instructions, then /clear + resume).\n'
    return 0
}
