#!/usr/bin/env bash
# eval-lib.sh — shared helpers for xfleet skill evals.
# Source this; do not execute directly.

# Reserved logical DB for the eval sandbox — NEVER a live coordination session.
: "${EVAL_REDIS_DB:=15}"
export XFLEET_REDIS_URL="redis://127.0.0.1:6379/${EVAL_REDIS_DB}"

EVAL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVAL_REPO_ROOT="$(cd "${EVAL_LIB_DIR}/../../.." && pwd)"
export EVAL_REPO_ROOT
export XFLEET_BIN="${EVAL_REPO_ROOT}/bin/xfleet"

# Put the repo's xfleet on PATH so `xfleet ...` resolves the way the skill expects.
export PATH="${EVAL_REPO_ROOT}/bin:${PATH}"

# State-writing skills (worker, phase, orchestrator) need these. Inert for the
# rootless explore skill. CLAUDE_PLUGIN_ROOT lets validate-state.sh find the schema.
export CLAUDE_PLUGIN_ROOT="${EVAL_REPO_ROOT}"
: "${XFLEET_PYTHON:=python3}"
export XFLEET_PYTHON

eval_redis() { redis-cli -u "${XFLEET_REDIS_URL}" "$@"; }

# Wipe the sandbox DB. Guard: refuse to flush anything but the reserved eval DB.
eval_flush() {
    case "${XFLEET_REDIS_URL}" in
        */"${EVAL_REDIS_DB}") eval_redis FLUSHDB >/dev/null ;;
        *) printf 'eval-lib: refusing to flush non-sandbox DB %s\n' "${XFLEET_REDIS_URL}" >&2; return 1 ;;
    esac
}

# Count messages of a given type sitting in an inbox stream.
# Usage: eval_inbox_count <inbox-name> <type>
eval_inbox_count() {
    local name="$1" type="$2"
    eval_redis XRANGE "inbox:${name}" - + 2>/dev/null \
        | grep -c "\"type\":\"${type}\"" || true
}

# Print the content field of the latest message of <type> in <inbox>.
# Usage: eval_inbox_latest_content <inbox-name> <type>
eval_inbox_latest_content() {
    local name="$1" type="$2"
    eval_redis XREVRANGE "inbox:${name}" + - 2>/dev/null \
        | grep "\"type\":\"${type}\"" | head -1 \
        | jq -r '.content // empty' 2>/dev/null || true
}

# Assertion helpers — print PASS:/FAIL: and accumulate failures in EVAL_FAILS.
EVAL_FAILS=0
eval_pass() { printf 'PASS: %s\n' "$1"; }
eval_fail() { printf 'FAIL: %s\n' "$1"; EVAL_FAILS=$((EVAL_FAILS + 1)); }
eval_check() { # <condition-already-evaluated:0/1> <description>
    if [[ "$1" -eq 0 ]]; then eval_pass "$2"; else eval_fail "$2"; fi
}

# --- Worker / coordination-root helpers ------------------------------------

# Create the 6 coordination-root subdirs under <root>.
# Usage: eval_build_coord_root <root>
eval_build_coord_root() {
    mkdir -p "$1"/{state,concerns,resolutions,directives,tasks,messages}
}

# Write a worker state file and fail loudly if it does not pass the schema.
# Usage: eval_write_worker_state <root> <worker-name> <json>
eval_write_worker_state() {
    local root="$1" name="$2" json="$3"
    printf '%s' "${json}" > "${root}/state/${name}.json"
    bash "${EVAL_REPO_ROOT}/tools/xfleet/validate-state.sh" \
        "${root}/state/${name}.json" worker >&2
}

# Seed a raw wire message into a worker inbox (creates the group so a listener
# started later still sees it; XADD-before-group is fine with group id 0).
# Usage: eval_seed_inbox <inbox-name> <json-message>
eval_seed_inbox() {
    local name="$1" msg="$2"
    eval_redis XGROUP CREATE "inbox:${name}" worker 0 MKSTREAM >/dev/null 2>&1 || true
    eval_redis XADD "inbox:${name}" MAXLEN "~" 200 "*" data "${msg}" >/dev/null
}

# Assert a jq expression over a worker state file equals an expected value.
# Usage: eval_check_state_field <root> <worker-name> <jq-expr> <expected> <desc>
eval_check_state_field() {
    local root="$1" name="$2" expr="$3" expected="$4" desc="$5" actual
    actual="$(jq -r "${expr}" "${root}/state/${name}.json" 2>/dev/null || true)"
    [[ "${actual}" = "${expected}" ]]; eval_check $? "${desc} (got: ${actual})"
}
