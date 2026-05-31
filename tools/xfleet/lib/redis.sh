#!/usr/bin/env bash
# redis.sh — Minimal Redis CLI wrapper for xfleet (Task 20, SC-3 pattern).
#
# Public API:
#   xfleet_redis <redis-cli-args...>
#       Wraps redis-cli with -u "${XFLEET_REDIS_URL:-redis://127.0.0.1:6379}".
#       Callers never reference redis-cli directly; they call xfleet_redis.
#
# Usage (source, do not execute directly):
#   source tools/xfleet/lib/redis.sh

_REDIS_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=strict-mode.sh
source "${_REDIS_SH_DIR}/strict-mode.sh"

# xfleet_redis <redis-cli-args...>
xfleet_redis() {
    redis-cli -u "${XFLEET_REDIS_URL:-redis://localhost:6379}" "$@"
}
