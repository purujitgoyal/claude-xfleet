#!/usr/bin/env bash
# session-init.sh — xfleet session-init subcommand: orchestrator roster writer.
#
# Resolves repo names to absolute paths from the xfleet config registry and
# writes roster.json to the coordination root. Overwrites any existing roster
# (orchestrator owns it). roster.json is NOT validated by validate-state.sh
# (unschema'd); written via atomic mktemp+mv.
#
# Usage:
#   xfleet session-init --slug <slug> <name1,name2,...>
#
# Options:
#   --slug <slug>     (required) Slug shared by all repos in this session.
#   <names>           Comma-separated list of repo names from the config registry.
#
# Exit codes:
#   0 — roster.json written successfully
#   1 — role mismatch, missing required arg/env, or unregistered repo name

_SESSION_INIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_SESSION_INIT_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/sender-authority.sh
source "${_SESSION_INIT_DIR}/../lib/sender-authority.sh"

# ---------------------------------------------------------------------------
# Role gate — orchestrator only.
# ---------------------------------------------------------------------------
assert_role orchestrator

# ---------------------------------------------------------------------------
# Arg parsing — required --slug + one positional comma-separated names list.
# ---------------------------------------------------------------------------
SLUG=""
NAMES_RAW=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --slug)
            if [[ $# -lt 2 ]]; then
                printf 'session-init: --slug requires a value\n' >&2
                exit 1
            fi
            SLUG="$2"
            shift 2
            ;;
        --*)
            printf 'session-init: unknown option: %s\n' "$1" >&2
            exit 1
            ;;
        *)
            if [[ -n "${NAMES_RAW}" ]]; then
                printf 'session-init: unexpected extra argument: %s\n' "$1" >&2
                exit 1
            fi
            NAMES_RAW="$1"
            shift
            ;;
    esac
done

if [[ -z "${SLUG}" ]]; then
    printf 'Usage: xfleet session-init --slug <slug> <name1,name2,...>\n' >&2
    printf 'Error: --slug is required.\n' >&2
    exit 1
fi

if [[ -z "${NAMES_RAW}" ]]; then
    printf 'Usage: xfleet session-init --slug <slug> <name1,name2,...>\n' >&2
    printf 'Error: a comma-separated list of repo names is required.\n' >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Resolve config file from XFLEET_CONFIG_DIR.
# ---------------------------------------------------------------------------
CONFIG_DIR="${XFLEET_CONFIG_DIR:-${HOME}/.config/xfleet}"
CONFIG_FILE="${CONFIG_DIR}/config.json"

if [[ ! -f "${CONFIG_FILE}" ]]; then
    printf 'Error: config file not found: %s\n' "${CONFIG_FILE}" >&2
    printf '  Run the xfleet setup to create it. See SETUP.md.\n' >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Resolve coordination root.
# ---------------------------------------------------------------------------
COORD_ROOT="${XFLEET_COORDINATION_ROOT:-}"
if [[ -z "${COORD_ROOT}" ]]; then
    printf 'Error: XFLEET_COORDINATION_ROOT is not set (required to write roster.json).\n' >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Split names on comma and resolve each to an abs path via the registry.
# ---------------------------------------------------------------------------
IFS=',' read -r -a NAMES <<< "${NAMES_RAW}"

REGISTERED_NAMES="$(jq -r '.repos | keys[]' "${CONFIG_FILE}" 2>/dev/null | sort | tr '\n' ' ')"

REPO_NAMES=()
REPO_PATHS=()

for name in "${NAMES[@]}"; do
    repo_path="$(jq -r --arg n "${name}" '.repos[$n] // empty' "${CONFIG_FILE}")"
    if [[ -z "${repo_path}" ]]; then
        printf 'Error: repo "%s" is not registered in %s\n' "${name}" "${CONFIG_FILE}" >&2
        printf '  Registered repos: %s\n' "${REGISTERED_NAMES}" >&2
        printf '  To register a repo, see SETUP.md.\n' >&2
        exit 1
    fi
    REPO_NAMES+=("${name}")
    REPO_PATHS+=("${repo_path}")
done

# ---------------------------------------------------------------------------
# Assemble and atomic-write roster.json.
# ---------------------------------------------------------------------------
NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
COUNT="${#REPO_NAMES[@]}"

# Build the repos JSON array by accumulating entries one at a time.
REPOS_JSON='[]'
for (( i = 0; i < COUNT; i++ )); do
    REPOS_JSON="$(jq -n \
        --argjson arr "${REPOS_JSON}" \
        --arg name "${REPO_NAMES[$i]}" \
        --arg path "${REPO_PATHS[$i]}" \
        --arg slug "${SLUG}" \
        '$arr + [{name: $name, path: $path, slug: $slug}]')"
done

ROSTER_JSON="$(jq -n \
    --arg started_at "${NOW}" \
    --argjson repos "${REPOS_JSON}" \
    '{ started_at: $started_at, repos: $repos }')"

TMPFILE="$(mktemp "${COORD_ROOT}/.roster.XXXXXX")"
printf '%s\n' "${ROSTER_JSON}" > "${TMPFILE}"
mv -f "${TMPFILE}" "${COORD_ROOT}/roster.json"

printf 'session-init: roster.json written (slug=%s, repos=%d, started_at=%s)\n' \
    "${SLUG}" "${COUNT}" "${NOW}"
