#!/usr/bin/env bash
# handoff-writer.sh — writes phase-boundary handoff markdown docs (Task 26).
#
# Public API:
#   write_phase_handoff <repo_root> <slug> <outgoing_phase> [resume_instructions_text]
#       Writes a phase-exit handoff file to:
#         ${repo_root}/docs/superpowers/xfleet/${slug}/handoff-${outgoing_phase}.md
#       Directory is created with mkdir -p. File is OVERWRITTEN (latest-only;
#       transient — per cluster 4d + Open Q #5). Write is NOT atomic (plain
#       printf redirect is fine; these are markdown docs, not schema-validated
#       state files).
#
#       Phase-boundary handoffs contain ONLY the Resume Instructions section
#       (per cluster 4d — F-53's "Active Skills" and "In-Session Directives"
#       sections are session-level, not phase-level, so they are omitted here).
#
#       Arguments:
#         repo_root              — repo root directory path (required)
#         slug                   — short project slug used as subdirectory (required)
#         outgoing_phase         — name of the phase that is ending (required)
#         resume_instructions_text — (optional) body for the Resume Instructions section;
#                                    if absent or empty a template placeholder is written
#
#       Returns 0 on success; non-zero + stderr message if required args are missing.
#
# Usage (source, do not execute directly):
#   source tools/xfleet/lib/handoff-writer.sh

_HANDOFF_WRITER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=strict-mode.sh
source "${_HANDOFF_WRITER_DIR}/strict-mode.sh"

# write_phase_handoff <repo_root> <slug> <outgoing_phase> [resume_instructions_text]
write_phase_handoff() {
    local repo_root="$1"
    local slug="$2"
    local outgoing_phase="$3"
    local resume_text="${4:-}"

    if [[ -z "${repo_root}" ]]; then
        printf 'write_phase_handoff: repo_root is required\n' >&2
        return 1
    fi
    if [[ -z "${slug}" ]]; then
        printf 'write_phase_handoff: slug is required\n' >&2
        return 1
    fi
    if [[ -z "${outgoing_phase}" ]]; then
        printf 'write_phase_handoff: outgoing_phase is required\n' >&2
        return 1
    fi

    local outdir="${repo_root}/docs/superpowers/xfleet/${slug}"
    local outpath="${outdir}/handoff-${outgoing_phase}.md"
    local timestamp
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    mkdir -p "${outdir}"

    local resume_body
    if [[ -n "${resume_text}" ]]; then
        resume_body="${resume_text}"
    else
        resume_body="_(no resume instructions supplied; fill in before resuming)_"
    fi

    printf '# Phase-exit handoff: %s\n\n' "${outgoing_phase}" > "${outpath}"
    printf 'outgoing_phase: %s | written_at: %s\n\n' "${outgoing_phase}" "${timestamp}" >> "${outpath}"
    printf '## Resume Instructions\n\n' >> "${outpath}"
    printf '%s\n' "${resume_body}" >> "${outpath}"

    return 0
}
