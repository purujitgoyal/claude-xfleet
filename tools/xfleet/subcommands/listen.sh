#!/usr/bin/env bash
# listen.sh — xfleet listen subcommand (Task 20).
#
# Starts a background XREADGROUP listener on inbox:{name} and records its
# process id in the worker state file's listen_bash_id field. Basic CLI
# surface only — Task 26 adds atomic restart + send-with-verify robustness.
#
# Usage: xfleet listen <name> [--group <group>] [--consumer <consumer>]
#
# Exit codes:
#   0 — background listener started, listen_bash_id written to worker state
#   1 — error (missing arg, state file not found, etc.)

_LISTEN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/strict-mode.sh
source "${_LISTEN_DIR}/../lib/strict-mode.sh"
# shellcheck source=../lib/redis.sh
source "${_LISTEN_DIR}/../lib/redis.sh"
# shellcheck source=../lib/state-io.sh
source "${_LISTEN_DIR}/../lib/state-io.sh"

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
    printf 'Usage: xfleet listen <name> [--group <group>] [--consumer <consumer>]\n' >&2
    exit 1
fi

NAME="$1"
shift

GROUP="worker"
CONSUMER="${NAME}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --group)
            GROUP="$2"
            shift 2
            ;;
        --consumer)
            CONSUMER="$2"
            shift 2
            ;;
        *)
            printf 'listen: unknown option: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

STREAM="inbox:${NAME}"
COORD_ROOT="${XFLEET_COORDINATION_ROOT:-}"
if [[ -z "${COORD_ROOT}" ]]; then
    printf 'listen: XFLEET_COORDINATION_ROOT is not set\n' >&2
    exit 1
fi

WORKER_STATE="${COORD_ROOT}/state/${NAME}.json"
if [[ ! -f "${WORKER_STATE}" ]]; then
    printf 'listen: worker state file not found: %s\n' "${WORKER_STATE}" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Ensure consumer group exists (idempotent)
# ---------------------------------------------------------------------------
xfleet_redis XGROUP CREATE "${STREAM}" "${GROUP}" 0 MKSTREAM >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# Background listener loop: XREADGROUP in a truly-detached process.
# Basic surface only — Task 26 handles atomic restart + send-with-verify.
#
# We write the listener body to a temp script and launch it via `nohup bash`
# so the process is fully detached (no inherited fds from the caller).
# This is required for BATS test isolation: without true detachment, BATS
# waits indefinitely for the background process to exit.
# ---------------------------------------------------------------------------
LISTENER_SCRIPT="$(mktemp "${TMPDIR:-/tmp}/xfleet-listen-XXXXXX")"

# Capture env vars for the listener script (bash-3.2 portable: no heredoc with
# complex quoting — write each piece separately).
printf '#!/usr/bin/env bash\n' > "${LISTENER_SCRIPT}"
printf 'set -euo pipefail\n' >> "${LISTENER_SCRIPT}"
# Embed the env vars and arguments as shell assignments.
printf 'XFLEET_REDIS_URL=%s\n' "$(printf '%s' "${XFLEET_REDIS_URL:-redis://127.0.0.1:6379}" | sed "s/'/'\\\\''/g")" >> "${LISTENER_SCRIPT}"
printf 'STREAM=%s\n' "${STREAM}" >> "${LISTENER_SCRIPT}"
printf 'GROUP=%s\n' "${GROUP}" >> "${LISTENER_SCRIPT}"
printf 'CONSUMER=%s\n' "${CONSUMER}" >> "${LISTENER_SCRIPT}"
printf 'CYCLE_MS=300000\n' >> "${LISTENER_SCRIPT}"
# Write the listener body (pending recovery + blocking loop).
cat >> "${LISTENER_SCRIPT}" << 'LISTENER_EOF'
xfleet_redis() { redis-cli -u "${XFLEET_REDIS_URL}" "$@"; }

# Pending recovery
while true; do
    PENDING="$(xfleet_redis XREADGROUP GROUP "${GROUP}" "${CONSUMER}" COUNT 1 STREAMS "${STREAM}" 0 2>/dev/null)" || true
    if [[ -n "${PENDING}" ]]; then
        line_count="$(printf '%s' "${PENDING}" | wc -l | tr -d ' ')"
        if [[ "${line_count}" -ge 4 ]]; then
            stream_id="$(printf '%s' "${PENDING}" | sed -n '2p')"
            data_value="$(printf '%s' "${PENDING}" | sed -n '4p')"
            printf '%s' "${data_value}" | jq --arg sid "${stream_id}" '. + {_stream_id: $sid}' 2>/dev/null || true
            continue
        fi
    fi
    break
done

# Blocking read loop
while true; do
    RESULT="$(xfleet_redis XREADGROUP GROUP "${GROUP}" "${CONSUMER}" BLOCK "${CYCLE_MS}" COUNT 1 STREAMS "${STREAM}" '>' 2>/dev/null)" || true
    if [[ -n "${RESULT}" ]]; then
        line_count="$(printf '%s' "${RESULT}" | wc -l | tr -d ' ')"
        if [[ "${line_count}" -ge 4 ]]; then
            stream_id="$(printf '%s' "${RESULT}" | sed -n '2p')"
            data_value="$(printf '%s' "${RESULT}" | sed -n '4p')"
            printf '%s' "${data_value}" | jq --arg sid "${stream_id}" '. + {_stream_id: $sid}' 2>/dev/null || true
        fi
    fi
done
LISTENER_EOF

chmod +x "${LISTENER_SCRIPT}"

# nohup launches the listener with stdin/stdout/stderr all redirected away from
# the parent shell, so BATS (or any other caller) never inherits our listener's
# fds and never waits on it.
nohup bash "${LISTENER_SCRIPT}" </dev/null >/dev/null 2>&1 &
LISTENER_PID=$!
disown "${LISTENER_PID}" 2>/dev/null || true

# Clean up the temp script after a brief moment (listener has exec'd by then).
( sleep 2 && rm -f "${LISTENER_SCRIPT}" ) </dev/null >/dev/null 2>&1 &
disown $! 2>/dev/null || true

# ---------------------------------------------------------------------------
# Record the background PID in the worker state file.
# Use "bash-NNN" format as exemplified in state-schema.md examples.
# ---------------------------------------------------------------------------
BID="bash-${LISTENER_PID}"
state_update_field "${WORKER_STATE}" ".listen_bash_id = \"${BID}\""

printf 'listen: started background listener PID %s for %s (listen_bash_id: %s)\n' \
    "${LISTENER_PID}" "${STREAM}" "${BID}"
