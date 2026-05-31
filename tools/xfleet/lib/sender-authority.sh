#!/usr/bin/env bash
# sender-authority.sh — Role-check helper for xfleet subcommands (Task 21).
#
# Public API:
#   assert_role <required-role>
#       Reads the caller's role from XFLEET_ROLE (values: "orchestrator" or
#       "worker"). Exits 1 with a friendly error if the role does not match.
#       Exits 1 with an error if XFLEET_ROLE is unset or holds an unknown value.
#
# Usage (source, do not execute directly):
#   source tools/xfleet/lib/sender-authority.sh

_SENDER_AUTHORITY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=strict-mode.sh
source "${_SENDER_AUTHORITY_DIR}/strict-mode.sh"

# assert_role <required-role>
# required-role: "orchestrator" or "worker"
assert_role() {
    local required="$1"
    local actual="${XFLEET_ROLE:-}"

    if [[ -z "${actual}" ]]; then
        printf 'Error: XFLEET_ROLE is not set. Export XFLEET_ROLE=orchestrator or XFLEET_ROLE=worker before running xfleet subcommands.\n' >&2
        exit 1
    fi

    if [[ "${actual}" != "orchestrator" && "${actual}" != "worker" ]]; then
        printf 'Error: XFLEET_ROLE has unknown value "%s". Valid values: orchestrator, worker.\n' "${actual}" >&2
        exit 1
    fi

    if [[ "${actual}" != "${required}" ]]; then
        printf 'Error: this subcommand requires role "%s" but XFLEET_ROLE="%s".\n' \
            "${required}" "${actual}" >&2
        exit 1
    fi
}
