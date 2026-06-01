#!/usr/bin/env bash
# drift-check.sh — xfleet drift-check subcommand (Task 4).
#
# Worker-local: invokes drift_check.py to compare a contract's canonical shape
# against the repo's live Pydantic model, then writes the result to the worker
# state file. Sends NO wire message.
#
# Usage:
#   xfleet drift-check --contract <id> --repo <name> [--ip <addr>] [--contracts-file <path>]
#
# Options:
#   --contract <id>         Contract id to check (e.g. C-1) [required]
#   --repo <name>           Repo name to check against [required]
#   --ip <addr>             Worker IP for state key (default: worker's current_ip from state)
#   --contracts-file <path> Explicit contracts.md path (default: $XFLEET_CONTRACTS_FILE if set,
#                           else $XFLEET_COORDINATION_ROOT/contracts.md per coordination spec)
#
# Exit codes:
#   0 — drift check ran; state written (drift-clean or drift-detected)
#   1 — validation error, role rejection, or hard drift_check.py failure

_DRIFT_CHECK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_DRIFT_CHECK_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/sender-authority.sh
source "${_DRIFT_CHECK_DIR}/../lib/sender-authority.sh"
# shellcheck source=../lib/state-io.sh
source "${_DRIFT_CHECK_DIR}/../lib/state-io.sh"

# ---------------------------------------------------------------------------
# Role check — worker only
# ---------------------------------------------------------------------------
assert_role worker

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
CONTRACT=""
REPO=""
IP_ARG=""
CONTRACTS_FILE_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --contract)
            if [[ $# -lt 2 ]]; then
                printf 'drift-check: --contract requires a value\n' >&2
                exit 1
            fi
            CONTRACT="$2"
            shift 2
            ;;
        --repo)
            if [[ $# -lt 2 ]]; then
                printf 'drift-check: --repo requires a value\n' >&2
                exit 1
            fi
            REPO="$2"
            shift 2
            ;;
        --ip)
            if [[ $# -lt 2 ]]; then
                printf 'drift-check: --ip requires a value\n' >&2
                exit 1
            fi
            IP_ARG="$2"
            shift 2
            ;;
        --contracts-file)
            if [[ $# -lt 2 ]]; then
                printf 'drift-check: --contracts-file requires a value\n' >&2
                exit 1
            fi
            CONTRACTS_FILE_ARG="$2"
            shift 2
            ;;
        *)
            printf 'drift-check: unknown option: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

# Required flag validation
if [[ -z "${CONTRACT}" ]]; then
    printf 'Usage: xfleet drift-check --contract <id> --repo <name> [--ip <addr>] [--contracts-file <path>]\n' >&2
    printf 'Error: --contract is required.\n' >&2
    exit 1
fi

if [[ -z "${REPO}" ]]; then
    printf 'Usage: xfleet drift-check --contract <id> --repo <name> [--ip <addr>] [--contracts-file <path>]\n' >&2
    printf 'Error: --repo is required.\n' >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Resolve worker state file (same convention as phase-complete.sh / review.sh)
# ---------------------------------------------------------------------------
WORKER_NAME="${XFLEET_WORKER_NAME:-}"
if [[ -z "${WORKER_NAME}" ]]; then
    printf 'Error: XFLEET_WORKER_NAME is not set (required to locate worker state file).\n' >&2
    exit 1
fi

COORD_ROOT="${XFLEET_COORDINATION_ROOT:-}"
if [[ -z "${COORD_ROOT}" ]]; then
    printf 'Error: XFLEET_COORDINATION_ROOT is not set.\n' >&2
    exit 1
fi

WORKER_STATE="${COORD_ROOT}/state/${WORKER_NAME}.json"

# ---------------------------------------------------------------------------
# Resolve IP: --ip arg, else current_ip from state file
# ---------------------------------------------------------------------------
IP="${IP_ARG}"
if [[ -z "${IP}" ]]; then
    if [[ -f "${WORKER_STATE}" ]]; then
        IP="$(jq -r '.current_ip // empty' "${WORKER_STATE}" 2>/dev/null || true)"
    fi
fi
if [[ -z "${IP}" ]]; then
    printf 'Error: --ip not provided and current_ip not found in worker state.\n' >&2
    exit 1
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
    # Convention: contracts.md lives at the root of the coordination directory
    CONTRACTS_FILE="${COORD_ROOT}/contracts.md"
fi

if [[ ! -f "${CONTRACTS_FILE}" ]]; then
    printf 'Error: contracts file not found: %s\n' "${CONTRACTS_FILE}" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Resolve repo root from XFLEET_WORKER_* env
# ---------------------------------------------------------------------------
REPO_ROOT="${XFLEET_WORKER_REPO_ROOT:-}"
if [[ -z "${REPO_ROOT}" ]]; then
    printf 'Error: XFLEET_WORKER_REPO_ROOT is not set (required to locate the repo).\n' >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Resolve repo interpreter:
#   1. $XFLEET_REPO_PYTHON (explicit override)
#   2. repo venv: {repo-root}/.venv/bin/python (if it exists)
#   3. python3 (system fallback)
# The repo's interpreter — NOT $XFLEET_PYTHON — is what can import repo Pydantic models.
# ---------------------------------------------------------------------------
if [[ -n "${XFLEET_REPO_PYTHON:-}" ]]; then
    REPO_PYTHON="${XFLEET_REPO_PYTHON}"
elif [[ -x "${REPO_ROOT}/.venv/bin/python" ]]; then
    REPO_PYTHON="${REPO_ROOT}/.venv/bin/python"
else
    REPO_PYTHON="python3"
fi

# xfleet's own interpreter — runs drift_check.py (needs pydantic + deepdiff)
XFLEET_PYTHON="${XFLEET_PYTHON:-python3}"

# ---------------------------------------------------------------------------
# Locate drift_check.py (sibling of this script's lib directory)
# ---------------------------------------------------------------------------
DRIFT_CHECK_PY="${_DRIFT_CHECK_DIR}/../lib/drift_check.py"
if [[ ! -f "${DRIFT_CHECK_PY}" ]]; then
    printf 'Error: drift_check.py not found at %s\n' "${DRIFT_CHECK_PY}" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Invoke drift_check.py; capture JSON report
# ---------------------------------------------------------------------------
DRIFT_EXIT=0
REPORT="$("${XFLEET_PYTHON}" "${DRIFT_CHECK_PY}" \
    --contract "${CONTRACT}" \
    --repo "${REPO}" \
    --contracts-file "${CONTRACTS_FILE}" \
    --repo-python "${REPO_PYTHON}")" || DRIFT_EXIT=$?

if [[ "${DRIFT_EXIT}" -ne 0 ]]; then
    printf 'drift-check: drift_check.py exited with error (exit %d)\n' "${DRIFT_EXIT}" >&2
    printf '%s\n' "${REPORT}" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Parse report and print human-readable summary
# ---------------------------------------------------------------------------
DRIFT_BOOL="$(printf '%s' "${REPORT}" | jq -r '.drift // false')"

if [[ "${DRIFT_BOOL}" == "true" ]]; then
    SELF_CHECK="drift-detected"
    printf 'drift-check: contract=%s repo=%s result=DRIFT DETECTED\n' "${CONTRACT}" "${REPO}"
else
    SELF_CHECK="drift-clean"
    printf 'drift-check: contract=%s repo=%s result=clean\n' "${CONTRACT}" "${REPO}"
fi

# Print the full JSON report for caller visibility
printf '%s\n' "${REPORT}"

# ---------------------------------------------------------------------------
# Write worker state: ip_self_check[$ip][$contract] = $self_check_value
# state_update_field takes only (path, jq-expr) — no --arg passthrough.
# Build the expression using jq --arg binding to avoid injection on $IP / $CONTRACT.
# ---------------------------------------------------------------------------
if [[ ! -f "${WORKER_STATE}" ]]; then
    printf 'Error: worker state file not found: %s\n' "${WORKER_STATE}" >&2
    exit 1
fi

CURRENT_STATE="$(state_read "${WORKER_STATE}")"
UPDATED_STATE="$(printf '%s' "${CURRENT_STATE}" | jq \
    --arg ip       "${IP}" \
    --arg contract "${CONTRACT}" \
    --arg val      "${SELF_CHECK}" \
    '.ip_self_check[$ip][$contract] = $val')"
state_write_atomic "${WORKER_STATE}" "${UPDATED_STATE}"

printf 'drift-check: state written (ip=%s contract=%s check=%s)\n' \
    "${IP}" "${CONTRACT}" "${SELF_CHECK}"
