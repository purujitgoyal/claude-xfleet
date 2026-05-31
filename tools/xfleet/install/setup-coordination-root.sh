#!/usr/bin/env bash
# setup-coordination-root.sh — One-time operator setup for an xfleet coordination root.
#
# Usage:
#   bash setup-coordination-root.sh [<target-coordination-root-path>]
#
# Idempotent: safe to re-run. Re-running will not duplicate dirs, gitignore lines,
# config keys, permissions, or re-bootstrap a working venv.
#
# What it does:
#   A) Resolve TARGET (absolute path, default $PWD/.xfleet)
#   B) Create 6 required subdirectories under TARGET
#   C) Add .xfleet/ to the parent repo's .gitignore (if not already present)
#   D) Persist coordination_root into ~/.config/xfleet/config.json
#   E) Verify Redis is reachable at $XFLEET_REDIS_URL
#   F) Resolve/bootstrap Python + jsonschema; persist python_bin to config.json
#   G) Grant 3 path-scoped Claude Code permissions in settings.local.json
#   H) Print final summary

set -euo pipefail
IFS=$'\n\t'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_print_step() {
    printf '\n[xfleet setup] %s\n' "$1"
}

_die() {
    printf '\n[xfleet setup] ERROR: %s\n' "$1" >&2
    exit 1
}

# Atomic write: write to a temp file in the same directory, then mv.
# Usage: _atomic_write <dest_path> <content_string>
_atomic_write() {
    local dest="$1"
    local content="$2"
    local dest_dir
    dest_dir="$(dirname "$dest")"
    local tmp
    tmp="$(mktemp "${dest_dir}/.tmp.XXXXXX")"
    printf '%s' "$content" > "$tmp"
    mv "$tmp" "$dest"
}

# ---------------------------------------------------------------------------
# Step A — Resolve target root
# ---------------------------------------------------------------------------

_print_step "A) Resolving coordination root..."

TARGET="${1:-$PWD/.xfleet}"

mkdir -p "$TARGET"
TARGET="$(cd "$TARGET" && pwd)"

printf '    Coordination root: %s\n' "$TARGET"

# ---------------------------------------------------------------------------
# Step B — Create 6 subdirectories
# ---------------------------------------------------------------------------

_print_step "B) Creating subdirectories under TARGET..."

for subdir in state concerns resolutions directives tasks messages; do
    if [ ! -d "$TARGET/$subdir" ]; then
        mkdir -p "$TARGET/$subdir"
        printf '    Created: %s/%s\n' "$TARGET" "$subdir"
    else
        printf '    Already exists (skipped): %s/%s\n' "$TARGET" "$subdir"
    fi
done

# ---------------------------------------------------------------------------
# Step C — gitignore
# ---------------------------------------------------------------------------

_print_step "C) Updating .gitignore in parent directory..."

PARENT_DIR="$(dirname "$TARGET")"
GITIGNORE_PATH="${PARENT_DIR}/.gitignore"
GITIGNORE_LINE=".xfleet/"

if [ -f "$GITIGNORE_PATH" ]; then
    if grep -qxF "$GITIGNORE_LINE" "$GITIGNORE_PATH"; then
        printf '    Already present in %s (skipped): %s\n' "$GITIGNORE_PATH" "$GITIGNORE_LINE"
    else
        printf '\n%s\n' "$GITIGNORE_LINE" >> "$GITIGNORE_PATH"
        printf '    Appended to %s: %s\n' "$GITIGNORE_PATH" "$GITIGNORE_LINE"
    fi
else
    printf '%s\n' "$GITIGNORE_LINE" > "$GITIGNORE_PATH"
    printf '    Created %s with: %s\n' "$GITIGNORE_PATH" "$GITIGNORE_LINE"
fi

# ---------------------------------------------------------------------------
# Step D — Persist config
# ---------------------------------------------------------------------------

_print_step "D) Persisting coordination_root to config.json..."

XFLEET_CONFIG_DIR="${HOME}/.config/xfleet"
XFLEET_CONFIG_FILE="${XFLEET_CONFIG_DIR}/config.json"

mkdir -p "$XFLEET_CONFIG_DIR"

if [ -f "$XFLEET_CONFIG_FILE" ]; then
    existing_json="$(cat "$XFLEET_CONFIG_FILE")"
else
    existing_json="{}"
fi

updated_json="$(printf '%s' "$existing_json" | jq --arg v "$TARGET" '.coordination_root = $v')"
_atomic_write "$XFLEET_CONFIG_FILE" "$updated_json"

printf '    Wrote coordination_root = %s\n' "$TARGET"
printf '    Config file: %s\n' "$XFLEET_CONFIG_FILE"

# ---------------------------------------------------------------------------
# Step E — Redis check
# ---------------------------------------------------------------------------

_print_step "E) Verifying Redis connectivity..."

REDIS_URL="${XFLEET_REDIS_URL:-redis://127.0.0.1:6379}"

if ! command -v redis-cli > /dev/null 2>&1; then
    _die "redis-cli not found on PATH. Redis must be installed and reachable at ${REDIS_URL}.
  Install hint: brew install redis && redis-server
  Then re-run this script."
fi

PING_RESULT="$(redis-cli -u "$REDIS_URL" ping 2>&1 || true)"

if [ "$PING_RESULT" != "PONG" ]; then
    _die "Redis did not respond with PONG at ${REDIS_URL} (got: '${PING_RESULT}').
  Redis must be running and reachable before proceeding.
  Install hint: brew install redis && redis-server
  Or start your existing Redis instance, then re-run this script."
fi

printf '    Redis OK at %s\n' "$REDIS_URL"

# ---------------------------------------------------------------------------
# Step F — Resolve + persist Python with jsonschema
# ---------------------------------------------------------------------------

_print_step "F) Resolving Python interpreter with jsonschema..."

VENV_PYTHON="${HOME}/.config/xfleet/venv/bin/python"

# Read existing config for current python_bin (if any)
current_config_json="$(cat "$XFLEET_CONFIG_FILE")"
existing_python_bin="$(printf '%s' "$current_config_json" | jq -r '.python_bin // empty')"

RESOLVED_PYTHON=""

# Candidate 1: $XFLEET_PYTHON env var (if set)
if [ -n "${XFLEET_PYTHON:-}" ]; then
    if "$XFLEET_PYTHON" -c "import jsonschema" > /dev/null 2>&1; then
        RESOLVED_PYTHON="$XFLEET_PYTHON"
        printf '    Using $XFLEET_PYTHON: %s\n' "$RESOLVED_PYTHON"
    else
        printf '    $XFLEET_PYTHON is set (%s) but jsonschema import failed; trying next candidate.\n' "$XFLEET_PYTHON"
    fi
fi

# Candidate 2: existing python_bin in config.json
if [ -z "$RESOLVED_PYTHON" ] && [ -n "$existing_python_bin" ]; then
    if "$existing_python_bin" -c "import jsonschema" > /dev/null 2>&1; then
        RESOLVED_PYTHON="$existing_python_bin"
        printf '    Using existing python_bin from config: %s\n' "$RESOLVED_PYTHON"
    else
        printf '    Existing python_bin in config (%s) failed jsonschema import; trying next candidate.\n' "$existing_python_bin"
    fi
fi

# Candidate 3: system python3
if [ -z "$RESOLVED_PYTHON" ]; then
    if command -v python3 > /dev/null 2>&1; then
        if python3 -c "import jsonschema" > /dev/null 2>&1; then
            RESOLVED_PYTHON="$(command -v python3)"
            printf '    Using system python3: %s\n' "$RESOLVED_PYTHON"
        else
            printf '    System python3 found but jsonschema not available; trying next candidate.\n'
        fi
    fi
fi

# Candidate 4: venv python
if [ -z "$RESOLVED_PYTHON" ]; then
    if [ -x "$VENV_PYTHON" ]; then
        if "$VENV_PYTHON" -c "import jsonschema" > /dev/null 2>&1; then
            RESOLVED_PYTHON="$VENV_PYTHON"
            printf '    Using venv python: %s\n' "$RESOLVED_PYTHON"
        fi
    fi
fi

# Bootstrap venv if no candidate worked
if [ -z "$RESOLVED_PYTHON" ]; then
    printf '    No working Python+jsonschema found. Attempting bootstrap...\n'

    if command -v uv > /dev/null 2>&1; then
        printf '    Found uv; creating venv at ~/.config/xfleet/venv ...\n'
        uv venv "${HOME}/.config/xfleet/venv" --python 3.13
        uv pip install --python "$VENV_PYTHON" jsonschema
        if "$VENV_PYTHON" -c "import jsonschema" > /dev/null 2>&1; then
            RESOLVED_PYTHON="$VENV_PYTHON"
            printf '    Bootstrap succeeded: %s\n' "$RESOLVED_PYTHON"
        else
            _die "Bootstrap with uv completed but jsonschema import still fails at ${VENV_PYTHON}. Check uv output above."
        fi
    else
        _die "No working Python interpreter with jsonschema found, and 'uv' is not on PATH.
  Options:
    1. Install uv and re-run: brew install uv (then re-run this script)
    2. Install jsonschema into any Python 3 and set: export XFLEET_PYTHON=/path/to/that/python
       Then re-run this script."
    fi
fi

# Persist python_bin to config.json
current_config_json="$(cat "$XFLEET_CONFIG_FILE")"
updated_json="$(printf '%s' "$current_config_json" | jq --arg v "$RESOLVED_PYTHON" '.python_bin = $v')"
_atomic_write "$XFLEET_CONFIG_FILE" "$updated_json"

printf '    Wrote python_bin = %s\n' "$RESOLVED_PYTHON"

# ---------------------------------------------------------------------------
# Step G — Grant 3 path-scoped Claude Code permissions
# ---------------------------------------------------------------------------

_print_step "G) Granting path-scoped Claude Code permissions..."

SETTINGS_FILE="${XFLEET_SETTINGS_FILE:-${HOME}/.claude/settings.local.json}"

# CC permission absolute-path syntax: a rule matches an absolute path when its
# leading "/" is doubled to "//" (verified against code.claude.com/docs/en/permissions.md:
# `Read(//Users/alice/secrets/**)` matches `/Users/alice/secrets/**`). TARGET is
# already absolute (starts with "/"), so prepend exactly ONE "/" to get the "//"
# prefix — never two (that would yield "///" and match nothing). A single leading
# "/" would be project-relative, not absolute.
RULE_WRITE="Write(/${TARGET}/**)"
RULE_READ="Read(/${TARGET}/**)"
RULE_TASK_OUTPUT="Read(//private/tmp/claude-*/**/tasks/*.output)"

if [ ! -f "$SETTINGS_FILE" ]; then
    mkdir -p "$(dirname "$SETTINGS_FILE")"
    init_json="$(jq -n \
        --arg r1 "$RULE_WRITE" \
        --arg r2 "$RULE_READ" \
        --arg r3 "$RULE_TASK_OUTPUT" \
        '{"permissions":{"allow":[$r1,$r2,$r3]}}')"
    _atomic_write "$SETTINGS_FILE" "$init_json"
    printf '    Created %s\n' "$SETTINGS_FILE"
    printf '    Added: %s\n' "$RULE_WRITE"
    printf '    Added: %s\n' "$RULE_READ"
    printf '    Added: %s\n' "$RULE_TASK_OUTPUT"
else
    existing_settings="$(cat "$SETTINGS_FILE")"

    # Add each rule only if not already present
    new_settings="$existing_settings"
    added_rules=0

    for rule in "$RULE_WRITE" "$RULE_READ" "$RULE_TASK_OUTPUT"; do
        already_present="$(printf '%s' "$new_settings" | jq -r --arg r "$rule" '
            (.permissions.allow // []) | map(select(. == $r)) | length')"
        if [ "$already_present" -eq 0 ]; then
            new_settings="$(printf '%s' "$new_settings" | jq --arg r "$rule" '
                .permissions.allow = ((.permissions.allow // []) + [$r])')"
            printf '    Added: %s\n' "$rule"
            added_rules=$((added_rules + 1))
        else
            printf '    Already present (skipped): %s\n' "$rule"
        fi
    done

    if [ "$added_rules" -gt 0 ]; then
        _atomic_write "$SETTINGS_FILE" "$new_settings"
    fi
fi

printf '    Settings file: %s\n' "$SETTINGS_FILE"

# ---------------------------------------------------------------------------
# Step H — Final summary
# ---------------------------------------------------------------------------

printf '\n'
printf '=%.0s' {1..60}
printf '\n'
printf '[xfleet setup] Setup complete!\n'
printf '\n'
printf '  Coordination root : %s\n' "$TARGET"
printf '  Config file       : %s\n' "$XFLEET_CONFIG_FILE"
printf '  Python binary     : %s\n' "$RESOLVED_PYTHON"
printf '  Redis URL         : %s (OK)\n' "$REDIS_URL"
printf '  Settings file     : %s\n' "$SETTINGS_FILE"
printf '\n'
printf '  Permissions granted:\n'
printf '    %s\n' "$RULE_WRITE"
printf '    %s\n' "$RULE_READ"
printf '    %s\n' "$RULE_TASK_OUTPUT"
printf '\n'
printf '  Idempotent — safe to re-run.\n'
printf '=%.0s' {1..60}
printf '\n'
