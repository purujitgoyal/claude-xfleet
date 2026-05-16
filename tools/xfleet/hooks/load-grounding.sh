#!/usr/bin/env bash
# load-grounding.sh — SessionStart grounding-loader hook for xfleet plugin.
#
# Fired on: startup / resume / clear / compact (all four SessionStart matchers).
#
# Responsibilities:
#   1. Resolve $XFLEET_COORDINATION_ROOT (env > config > .xfleet-marker walk).
#   2. Resolve $XFLEET_PYTHON (env > config python_bin > python3).
#   3. Validate that the resolved python can import jsonschema.
#   4. Read roster.json from the coordination root.
#   5. For each repo entry, emit === {repo} === marker + CLAUDE.md + grounding.md.
#   6. Export PATH (plugin bin/), XFLEET_COORDINATION_ROOT, XFLEET_PYTHON to
#      $CLAUDE_ENV_FILE (if set).
#
# "Errors loudly" means: prominent stderr warning + non-zero exit.
# SessionStart hooks do NOT block the session — non-zero exit is advisory.
#
# Test-override knobs (minimal, for testability):
#   XFLEET_CONFIG_FILE — override path to config JSON (default: ~/.config/xfleet/config.json)
#   --coordination-root <path> — CLI override for coordination root (highest priority in tests)

set -euo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

EVENT=""
CLI_COORDINATION_ROOT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --event)
            EVENT="$2"
            shift 2
            ;;
        --coordination-root)
            CLI_COORDINATION_ROOT="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

warn() {
    # Emit to both stderr and stdout so it surfaces in the session context.
    local msg="[xfleet/load-grounding] WARNING: $*"
    printf '%s\n' "$msg" >&2
    printf '%s\n' "$msg"
}

error_exit() {
    local msg="[xfleet/load-grounding] ERROR: $*"
    printf '%s\n' "$msg" >&2
    printf '%s\n' "$msg"
    exit 1
}

# ---------------------------------------------------------------------------
# Config file path (overridable for tests)
# ---------------------------------------------------------------------------

XFLEET_CONFIG_FILE="${XFLEET_CONFIG_FILE:-${HOME}/.config/xfleet/config.json}"

# ---------------------------------------------------------------------------
# (f) Resolve XFLEET_COORDINATION_ROOT
# Precedence: CLI flag (test use) > env var > config file > .xfleet-marker walk
# ---------------------------------------------------------------------------

resolve_coordination_root() {
    # CLI flag — highest priority (used by tests that pass --coordination-root)
    if [[ -n "${CLI_COORDINATION_ROOT}" ]]; then
        printf '%s' "${CLI_COORDINATION_ROOT}"
        return 0
    fi

    # Env var
    if [[ -n "${XFLEET_COORDINATION_ROOT:-}" ]]; then
        printf '%s' "${XFLEET_COORDINATION_ROOT}"
        return 0
    fi

    # Config file: ~/.config/xfleet/config.json (key: coordination_root)
    if [[ -f "${XFLEET_CONFIG_FILE}" ]]; then
        local from_cfg
        from_cfg="$(jq -r '.coordination_root // empty' "${XFLEET_CONFIG_FILE}" 2>/dev/null || true)"
        if [[ -n "${from_cfg}" ]]; then
            printf '%s' "${from_cfg}"
            return 0
        fi
    fi

    # .xfleet-marker walk: search CWD and each ancestor for a .xfleet-marker file.
    # The directory containing the marker IS the coordination root.
    local dir
    dir="$(pwd)"
    while true; do
        if [[ -f "${dir}/.xfleet-marker" ]]; then
            printf '%s' "${dir}"
            return 0
        fi
        local parent
        parent="$(dirname "${dir}")"
        if [[ "${parent}" == "${dir}" ]]; then
            # Reached filesystem root with no marker found
            break
        fi
        dir="${parent}"
    done

    # Nothing resolved
    return 1
}

COORDINATION_ROOT=""
if ! COORDINATION_ROOT="$(resolve_coordination_root)"; then
    error_exit "Cannot resolve XFLEET_COORDINATION_ROOT. Set the env var, add" \
        "coordination_root to ${XFLEET_CONFIG_FILE}, or place a .xfleet-marker" \
        "file in the coordination repository root."
fi

# ---------------------------------------------------------------------------
# (g) Resolve XFLEET_PYTHON
# Precedence: env var > config file python_bin > python3 (system default)
# ---------------------------------------------------------------------------

resolve_python() {
    # Env var
    if [[ -n "${XFLEET_PYTHON:-}" ]]; then
        printf '%s' "${XFLEET_PYTHON}"
        return 0
    fi

    # Config file: python_bin field
    if [[ -f "${XFLEET_CONFIG_FILE}" ]]; then
        local from_cfg
        from_cfg="$(jq -r '.python_bin // empty' "${XFLEET_CONFIG_FILE}" 2>/dev/null || true)"
        if [[ -n "${from_cfg}" ]]; then
            printf '%s' "${from_cfg}"
            return 0
        fi
    fi

    # System default
    printf 'python3'
}

RESOLVED_PYTHON="$(resolve_python)"

# Validate: resolved python must be able to import jsonschema.
if ! "${RESOLVED_PYTHON}" -c "import jsonschema" 2>/dev/null; then
    error_exit "Python at '${RESOLVED_PYTHON}' cannot import jsonschema." \
        "Install jsonschema (pip install jsonschema>=4) or point" \
        "XFLEET_PYTHON at a python that has it."
fi

# ---------------------------------------------------------------------------
# (d) Event handling — all four matchers behave identically
# ---------------------------------------------------------------------------
# No per-event branching needed; the grounding load is uniform.

# ---------------------------------------------------------------------------
# Read roster.json
# ---------------------------------------------------------------------------

ROSTER="${COORDINATION_ROOT}/roster.json"

if [[ ! -f "${ROSTER}" ]]; then
    warn "roster.json not found at '${ROSTER}'. No grounding context loaded."
    # (a) Exit 0 — non-fatal; session proceeds without grounding.

    # Still export env vars if CLAUDE_ENV_FILE is set (best effort).
    if [[ -n "${CLAUDE_ENV_FILE:-}" ]]; then
        {
            printf 'export XFLEET_COORDINATION_ROOT="%s"\n' "${COORDINATION_ROOT}"
            printf 'export XFLEET_PYTHON="%s"\n' "${RESOLVED_PYTHON}"
            if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
                printf 'export PATH="%s/bin:${PATH}"\n' "${CLAUDE_PLUGIN_ROOT}"
            fi
        } >> "${CLAUDE_ENV_FILE}"
    fi

    exit 0
fi

# ---------------------------------------------------------------------------
# Load grounding for each repo
# Roster schema: array of {"repo": "<path>", "slug": "<slug>"}
# ---------------------------------------------------------------------------

repo_count="$(jq 'length' "${ROSTER}")"

for (( i = 0; i < repo_count; i++ )); do
    repo_path="$(jq -r --argjson i "$i" '.[$i].repo' "${ROSTER}")"
    slug="$(jq -r --argjson i "$i" '.[$i].slug' "${ROSTER}")"

    printf '\n=== %s ===\n' "${repo_path}"

    # CLAUDE.md — expected to exist; warn + continue if missing
    claude_md="${repo_path}/CLAUDE.md"
    if [[ -f "${claude_md}" ]]; then
        cat "${claude_md}"
    else
        warn "CLAUDE.md not found for repo '${repo_path}'. Skipping."
    fi

    # grounding.md — optional; warn + skip (not a fatal error)
    grounding_md="${repo_path}/docs/superpowers/xfleet/${slug}/grounding.md"
    if [[ -f "${grounding_md}" ]]; then
        printf '\n--- grounding: %s/%s ---\n' "${repo_path}" "${slug}"
        cat "${grounding_md}"
    else
        warn "grounding.md not found for repo '${repo_path}' slug '${slug}'" \
            "(expected: ${grounding_md}). Skipping grounding block."
    fi
done

# ---------------------------------------------------------------------------
# (e) Export env vars to $CLAUDE_ENV_FILE
# ---------------------------------------------------------------------------

if [[ -n "${CLAUDE_ENV_FILE:-}" ]]; then
    {
        printf 'export XFLEET_COORDINATION_ROOT="%s"\n' "${COORDINATION_ROOT}"
        printf 'export XFLEET_PYTHON="%s"\n' "${RESOLVED_PYTHON}"
        if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
            printf 'export PATH="%s/bin:${PATH}"\n' "${CLAUDE_PLUGIN_ROOT}"
        fi
    } >> "${CLAUDE_ENV_FILE}"
fi

exit 0
