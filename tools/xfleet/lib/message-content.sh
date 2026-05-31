#!/usr/bin/env bash
# message-content.sh — --message / --message-file validator for xfleet (Task 21).
#
# Public API:
#   resolve_message_content <msg_var> <file_var> <subcommand_type>
#       Validates that exactly one of --message / --message-file is present.
#       For --message-file, enforces SC-5 strict path scoping: the resolved
#       (realpath) path must lie under $XFLEET_COORDINATION_ROOT.
#
#       Arguments:
#         msg_var    — name of the variable holding the --message text (may be "")
#         file_var   — name of the variable holding the --message-file path (may be "")
#         subcommand_type — subcommand name used in error messages (e.g. "question")
#
#       Sets MESSAGE_CONTENT (global) to the final text on success.
#       Exits 1 on any validation failure.
#
# Usage (source, do not execute directly):
#   source tools/xfleet/lib/message-content.sh

_MSG_CONTENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=strict-mode.sh
source "${_MSG_CONTENT_DIR}/strict-mode.sh"

# resolve_message_content <msg_var> <file_var> <subcommand_type>
resolve_message_content() {
    local msg_var="$1"
    local file_var="$2"
    local subtype="$3"

    # Dereference variable names (bash-3.2 portable: use eval)
    local msg_val
    local file_val
    eval "msg_val=\"\${${msg_var}:-}\""
    eval "file_val=\"\${${file_var}:-}\""

    # Exactly one of --message / --message-file must be present.
    if [[ -n "${msg_val}" && -n "${file_val}" ]]; then
        printf 'Error: %s requires exactly one of --message or --message-file, but both were provided.\n' \
            "${subtype}" >&2
        exit 1
    fi

    if [[ -z "${msg_val}" && -z "${file_val}" ]]; then
        printf 'Error: %s requires exactly one of --message or --message-file.\n' \
            "${subtype}" >&2
        exit 1
    fi

    if [[ -n "${msg_val}" ]]; then
        MESSAGE_CONTENT="${msg_val}"
        return 0
    fi

    # --message-file path: SC-5 strict path scoping.
    local coord_root="${XFLEET_COORDINATION_ROOT:-}"
    if [[ -z "${coord_root}" ]]; then
        printf 'Error: XFLEET_COORDINATION_ROOT is not set (required for --message-file path validation).\n' >&2
        exit 1
    fi

    # Resolve the file path to its canonical form (follow symlinks).
    local resolved
    if ! resolved="$(realpath "${file_val}" 2>/dev/null)"; then
        printf 'Error: --message-file path '\''%s'\'' could not be resolved (file may not exist).\n' \
            "${file_val}" >&2
        exit 1
    fi

    # Resolve the coordination root too (ensure no trailing slash trickery).
    local resolved_root
    resolved_root="$(realpath "${coord_root}" 2>/dev/null)" || resolved_root="${coord_root}"

    # Ensure resolved path lies under resolved_root.
    # Add a trailing slash to root so "prefix check" doesn't falsely match a
    # sibling directory that starts with the same characters.
    local root_prefix="${resolved_root}/"
    if [[ "${resolved}" != "${resolved_root}" && "${resolved}" != "${root_prefix}"* ]]; then
        printf "Error: --message-file path '%s' resolves outside allowed roots; copy the file under \$XFLEET_COORDINATION_ROOT first.\n" \
            "${file_val}" >&2
        exit 1
    fi

    # File must exist and be readable.
    if [[ ! -f "${resolved}" ]]; then
        printf 'Error: --message-file path '\''%s'\'' does not exist or is not a regular file.\n' \
            "${file_val}" >&2
        exit 1
    fi

    MESSAGE_CONTENT="$(cat "${resolved}")"
}
