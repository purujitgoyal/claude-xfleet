#!/usr/bin/env bash
# state-io.sh — Atomic state-file I/O helpers for xfleet (Task 19).
#
# Public API:
#   state_read <path>
#       Emit the contents of <path> to stdout. Exits non-zero if the file does
#       not exist or cannot be read.
#
#   state_write_atomic <path> <new-content>
#       Stage <new-content> to a temp file in the same directory as <path>
#       (same filesystem → mv is atomic), validate via validate-state.sh, then
#       atomically rename to <path> on success. On validation failure, remove
#       the temp file and return non-zero WITHOUT touching <path>.
#       Def (orchestrator|worker) is inferred from <path>'s basename:
#         _orchestrator.json → orchestrator; anything else → worker.
#       The explicit def is passed to validate-state.sh so it works on the
#       temp file (whose random basename would otherwise misfire inference).
#
#   state_update_field <path> <jq-expr>
#       Read current <path>, apply <jq-expr> via jq, write back via
#       state_write_atomic (inherits validation + atomicity).
#
#   state_migrate_if_needed <path>
#       Check schema_version in <path>:
#         "1"            → no-op (exit 0)
#         absent or other → error message + exit 1
#       Future versions register migration handlers here; for F-51 only v1
#       exists so any other value is unknown.
#
# Design notes:
#   - C2 last-write-wins: no lock primitives. Atomicity comes from tmp+mv only.
#   - mktemp staging is in the TARGET directory (not /tmp) to guarantee the
#     tmp and target are on the same filesystem, making mv atomic.
#   - validate-state.sh is called BEFORE the final mv; a failed write leaves
#     the target unchanged.
#   - bash-3.2 portable (macOS default): no bash-4 features.
#
# Usage (source, do not execute directly):
#   source tools/xfleet/lib/state-io.sh

# Strict mode must come first; sourcing scripts should already have it but
# we re-source strict-mode.sh to be safe.
_STATE_IO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=strict-mode.sh
source "${_STATE_IO_DIR}/strict-mode.sh"

# ---------------------------------------------------------------------------
# Resolve plugin root — same pattern as check-state-schema-drift.sh.
# ---------------------------------------------------------------------------
_STATE_IO_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${_STATE_IO_DIR}/../../.." && pwd)}"
_STATE_IO_VALIDATE_SH="${_STATE_IO_PLUGIN_ROOT}/tools/xfleet/validate-state.sh"

# ---------------------------------------------------------------------------
# state_read <path>
# ---------------------------------------------------------------------------
state_read() {
    local path="$1"
    if [[ ! -f "${path}" ]]; then
        printf 'state_read: file not found: %s\n' "${path}" >&2
        return 1
    fi
    cat "${path}"
}

# ---------------------------------------------------------------------------
# _infer_def <path>
# Returns "orchestrator" if basename is _orchestrator.json, else "worker".
# ---------------------------------------------------------------------------
_infer_def() {
    local path="$1"
    local base
    base="$(basename "${path}")"
    if [[ "${base}" = "_orchestrator.json" ]]; then
        printf 'orchestrator'
    else
        printf 'worker'
    fi
}

# ---------------------------------------------------------------------------
# state_write_atomic <path> <new-content>
# ---------------------------------------------------------------------------
state_write_atomic() {
    local target="$1"
    local content="$2"

    local target_dir
    target_dir="$(dirname "${target}")"

    # Ensure the target directory exists.
    mkdir -p "${target_dir}"

    # Stage to a temp file in the SAME directory as the target (same fs → atomic mv).
    local tmp
    tmp="$(mktemp "${target_dir}/.tmp.XXXXXX")"

    # Write content to temp file.
    printf '%s' "${content}" > "${tmp}"

    # Infer def from TARGET path's basename (not temp file's random name).
    local def
    def="$(_infer_def "${target}")"

    # Validate the temp file with the explicit def override so inference
    # on the random temp filename is bypassed.
    local validate_exit=0
    "${_STATE_IO_VALIDATE_SH}" "${tmp}" "${def}" >&2 || validate_exit=$?

    if [[ "${validate_exit}" -ne 0 ]]; then
        rm -f "${tmp}"
        printf 'state_write_atomic: validation failed (exit %d) for %s\n' \
            "${validate_exit}" "${target}" >&2
        return "${validate_exit}"
    fi

    # Validation passed — atomically replace the target.
    mv -f "${tmp}" "${target}"
}

# ---------------------------------------------------------------------------
# state_update_field <path> <jq-expr>
# ---------------------------------------------------------------------------
state_update_field() {
    local path="$1"
    local jq_expr="$2"

    # Read current content.
    local current
    current="$(state_read "${path}")"

    # Apply the jq expression.
    local updated
    updated="$(printf '%s' "${current}" | jq "${jq_expr}")"

    # Write back atomically (inherits validation).
    state_write_atomic "${path}" "${updated}"
}

# ---------------------------------------------------------------------------
# state_migrate_if_needed <path>
# ---------------------------------------------------------------------------
state_migrate_if_needed() {
    local path="$1"

    if [[ ! -f "${path}" ]]; then
        printf 'state_migrate_if_needed: file not found: %s\n' "${path}" >&2
        return 1
    fi

    # Extract schema_version using jq (not python3 -c, per house rules).
    local sv
    sv="$(jq -r '.schema_version // empty' "${path}" 2>/dev/null || true)"

    if [[ -z "${sv}" ]]; then
        printf 'state_migrate_if_needed: unknown or missing schema_version in %s; current plugin supports v1\n' \
            "${path}" >&2
        return 1
    fi

    if [[ "${sv}" = "1" ]]; then
        # v1 is the only supported version — no migration needed.
        return 0
    fi

    # Any other version is unknown.
    printf 'state_migrate_if_needed: unknown schema_version "%s" in %s; current plugin supports v1\n' \
        "${sv}" "${path}" >&2
    return 1
}
