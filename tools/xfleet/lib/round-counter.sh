#!/usr/bin/env bash
# round-counter.sh — Round-counter helper for xfleet concern negotiation (Task 22).
#
# Public API:
#   incr_round <concern-id>
#       Increments the Redis round counter for the given concern id.
#       Key: xfleet:{slug}:concern:{id}:rounds
#       where {slug} is a stable cksum-based hash of realpath($XFLEET_COORDINATION_ROOT).
#
#       Per messaging.md (g) and F-15:
#         - Only `concern` calls incr_round; `concern-reopen` does NOT.
#         - The counter is never reset — concern-reopen continues the same key.
#         - Returns the new counter value on stdout.
#
# Usage (source, do not execute directly):
#   source tools/xfleet/lib/round-counter.sh

_ROUND_COUNTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=strict-mode.sh
source "${_ROUND_COUNTER_DIR}/strict-mode.sh"
# shellcheck source=redis.sh
source "${_ROUND_COUNTER_DIR}/redis.sh"

# _coordination_root_slug
# Derives a stable short slug from realpath($XFLEET_COORDINATION_ROOT).
# Uses cksum (POSIX, available on bash-3.2 macOS) — picks the numeric checksum
# field so the slug is digits-only and safe in Redis key names.
_coordination_root_slug() {
    local coord_root="${XFLEET_COORDINATION_ROOT:-}"
    if [[ -z "${coord_root}" ]]; then
        printf 'Error: XFLEET_COORDINATION_ROOT is not set (required for round-counter namespacing).\n' >&2
        return 1
    fi

    local resolved
    if ! resolved="$(realpath "${coord_root}" 2>/dev/null)"; then
        printf 'Error: XFLEET_COORDINATION_ROOT "%s" could not be resolved.\n' "${coord_root}" >&2
        return 1
    fi

    # cksum outputs "<checksum> <bytecount> <filename>" — take the first field.
    printf '%s' "${resolved}" | cksum | cut -d' ' -f1
}

# incr_round <concern-id>
# Increments xfleet:{slug}:concern:{id}:rounds and prints the new value.
incr_round() {
    local concern_id="$1"
    if [[ -z "${concern_id}" ]]; then
        printf 'Error: incr_round requires a concern-id argument.\n' >&2
        return 1
    fi

    local slug
    slug="$(_coordination_root_slug)"

    local key="xfleet:${slug}:concern:${concern_id}:rounds"
    xfleet_redis INCR "${key}"
}
