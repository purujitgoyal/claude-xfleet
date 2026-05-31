#!/usr/bin/env bash
# validate-state.sh — xfleet state-file JSON Schema validator (Task 18).
#
# Validates a state file against tools/xfleet/state-schema.json via a small
# Python wrapper (lib/validate-state.py) that uses the jsonschema API directly.
# On unknown-key failure, the Python wrapper emits Levenshtein "did you mean?"
# suggestions drawn from the known keys at that schema level.
#
# Usage:
#   bash tools/xfleet/validate-state.sh <state-file> [<schema-file>] [orchestrator|worker]
#
#   <state-file>            Path to the JSON state file to validate. Required.
#   <schema-file>           Path to the JSON Schema file (optional).
#                           Default: tools/xfleet/state-schema.json relative to
#                           the plugin root.
#   orchestrator|worker     Which $def to validate against (optional).
#                           Default: inferred from the state file's basename —
#                           "_orchestrator.json" → orchestrator; anything else → worker.
#                           Pass an explicit value to override inference (useful when
#                           the temp file has an arbitrary name, e.g. in BATS tests).
#
# Exit codes (from the Python wrapper):
#   0  valid
#   1  schema validation failure (unknown key, bad type, missing required, etc.)
#   2  malformed JSON or unreadable input
#   3  schema_version missing or not "1"
#
# Environment:
#   XFLEET_PYTHON       Python interpreter to use (default: python3).
#   CLAUDE_PLUGIN_ROOT  Plugin root directory (default: derived from BASH_SOURCE).
#
# The schema file default and the Python wrapper path are resolved relative to
# CLAUDE_PLUGIN_ROOT so the script works from any working directory.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
PYTHON="${XFLEET_PYTHON:-python3}"

# Parse positional arguments.
# Arg 1 is always state-file. Arg 2 is schema-file or type. Arg 3 is type.
STATE_FILE="${1:-}"
if [[ -z "${STATE_FILE}" ]]; then
    printf 'Usage: validate-state.sh <state-file> [<schema-file>] [orchestrator|worker]\n' >&2
    exit 2
fi

# Default schema path.
DEFAULT_SCHEMA="${PLUGIN_ROOT}/tools/xfleet/state-schema.json"

SCHEMA_FILE=""
DEF_NAME=""

# Arg 2: could be schema file or type override.
if [[ -n "${2:-}" ]]; then
    if [[ "${2}" == "orchestrator" || "${2}" == "worker" ]]; then
        DEF_NAME="${2}"
    else
        SCHEMA_FILE="${2}"
        # Arg 3: optional type override.
        if [[ -n "${3:-}" ]]; then
            DEF_NAME="${3}"
        fi
    fi
fi

if [[ -z "${SCHEMA_FILE}" ]]; then
    SCHEMA_FILE="${DEFAULT_SCHEMA}"
fi

# Infer def-name from the state file's basename if not explicitly provided.
if [[ -z "${DEF_NAME}" ]]; then
    BASENAME="$(basename "${STATE_FILE}")"
    if [[ "${BASENAME}" == "_orchestrator.json" ]]; then
        DEF_NAME="orchestrator"
    else
        DEF_NAME="worker"
    fi
fi

exec "${PYTHON}" "${PLUGIN_ROOT}/tools/xfleet/lib/validate-state.py" \
    "${STATE_FILE}" "${SCHEMA_FILE}" "${DEF_NAME}"
