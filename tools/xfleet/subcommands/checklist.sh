#!/usr/bin/env bash
# checklist.sh — xfleet checklist subcommand (Task 6).
#
# Orchestrator-run validator: invokes checklist.py to check spec.md +
# contracts.md structural integrity. Sends NO wire message; writes no state.
# Not role-gated (read-only/operational, like status/peek).
#
# Usage:
#   xfleet checklist --mode repo-spec [--spec-file <path>] [--contracts-file <path>]
#
# Options:
#   --mode <mode>           Validation mode (only 'repo-spec' supported) [required]
#   --spec-file <path>      Explicit spec.md path (default: $XFLEET_SPEC_FILE if set,
#                           else $XFLEET_COORDINATION_ROOT/spec.md)
#   --contracts-file <path> Explicit contracts.md path (default: $XFLEET_CONTRACTS_FILE if set,
#                           else $XFLEET_COORDINATION_ROOT/contracts.md)
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more errors, bad mode, missing flags, or checklist.py failure
#   2 — bad arguments or unreadable input files (propagated from checklist.py)

_CHECKLIST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_CHECKLIST_DIR}/../lib/strict-mode.sh"

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
MODE=""
SPEC_FILE_ARG=""
CONTRACTS_FILE_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            if [[ $# -lt 2 ]]; then
                printf 'checklist: --mode requires a value\n' >&2
                exit 1
            fi
            MODE="$2"
            shift 2
            ;;
        --spec-file)
            if [[ $# -lt 2 ]]; then
                printf 'checklist: --spec-file requires a value\n' >&2
                exit 1
            fi
            SPEC_FILE_ARG="$2"
            shift 2
            ;;
        --contracts-file)
            if [[ $# -lt 2 ]]; then
                printf 'checklist: --contracts-file requires a value\n' >&2
                exit 1
            fi
            CONTRACTS_FILE_ARG="$2"
            shift 2
            ;;
        *)
            printf 'checklist: unknown option: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

# Required flag validation
if [[ -z "${MODE}" ]]; then
    printf 'Usage: xfleet checklist --mode repo-spec [--spec-file <path>] [--contracts-file <path>]\n' >&2
    printf 'Error: --mode is required.\n' >&2
    exit 1
fi

if [[ "${MODE}" != "repo-spec" ]]; then
    printf 'checklist: unsupported mode: %s (only repo-spec is supported)\n' "${MODE}" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Resolve spec.md path:
#   1. --spec-file flag (explicit)
#   2. $XFLEET_SPEC_FILE env var
#   3. $XFLEET_COORDINATION_ROOT/spec.md (coordination spec convention)
# ---------------------------------------------------------------------------
COORD_ROOT="${XFLEET_COORDINATION_ROOT:-}"

if [[ -n "${SPEC_FILE_ARG}" ]]; then
    SPEC_FILE="${SPEC_FILE_ARG}"
elif [[ -n "${XFLEET_SPEC_FILE:-}" ]]; then
    SPEC_FILE="${XFLEET_SPEC_FILE}"
else
    if [[ -z "${COORD_ROOT}" ]]; then
        printf 'Error: XFLEET_COORDINATION_ROOT is not set (needed to derive spec.md path).\n' >&2
        exit 1
    fi
    SPEC_FILE="${COORD_ROOT}/spec.md"
fi

# ---------------------------------------------------------------------------
# Resolve contracts.md path:
#   1. --contracts-file flag (explicit)
#   2. $XFLEET_CONTRACTS_FILE env var
#   3. $XFLEET_COORDINATION_ROOT/contracts.md (coordination spec convention)
# ---------------------------------------------------------------------------
if [[ -n "${CONTRACTS_FILE_ARG}" ]]; then
    CONTRACTS_FILE="${CONTRACTS_FILE_ARG}"
elif [[ -n "${XFLEET_CONTRACTS_FILE:-}" ]]; then
    CONTRACTS_FILE="${XFLEET_CONTRACTS_FILE}"
else
    if [[ -z "${COORD_ROOT}" ]]; then
        printf 'Error: XFLEET_COORDINATION_ROOT is not set (needed to derive contracts.md path).\n' >&2
        exit 1
    fi
    CONTRACTS_FILE="${COORD_ROOT}/contracts.md"
fi

# ---------------------------------------------------------------------------
# Locate checklist.py (sibling of this script's lib directory)
# ---------------------------------------------------------------------------
CHECKLIST_PY="${_CHECKLIST_DIR}/../lib/checklist.py"
if [[ ! -f "${CHECKLIST_PY}" ]]; then
    printf 'Error: checklist.py not found at %s\n' "${CHECKLIST_PY}" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Invoke checklist.py; propagate its exit code
# ---------------------------------------------------------------------------
XFLEET_PYTHON="${XFLEET_PYTHON:-python3}"
"${XFLEET_PYTHON}" "${CHECKLIST_PY}" \
    --mode "${MODE}" \
    --spec-file "${SPEC_FILE}" \
    --contracts-file "${CONTRACTS_FILE}"
exit $?
