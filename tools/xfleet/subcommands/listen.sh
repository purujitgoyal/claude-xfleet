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
# shellcheck source=../lib/listener.sh
source "${_LISTEN_DIR}/../lib/listener.sh"

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
# Reap this session's own prior listener before starting a fresh one (F-8:
# never run two own-listeners for the same worker). Stops ONLY the recorded
# listen_bash_id — never pgrep-kills peer sessions' listeners (F-37).
# ---------------------------------------------------------------------------
listener_stop_own "${NAME}"

# ---------------------------------------------------------------------------
# Background listener loop: XREADGROUP in a truly-detached process group.
# Basic surface only — Task 26 handles atomic restart + send-with-verify.
#
# We write the listener body to a temp script and launch it via `setsid bash`
# so the listener becomes its own process-group leader (PGID == its PID). This
# lets a caller kill the WHOLE subtree (the listener bash + its forked
# `redis-cli BLOCK` child) with a single process-group signal `kill -- -PGID`,
# preventing leaked Redis connections. The listener also installs a TERM/EXIT
# trap that reaps its redis-cli child as belt-and-suspenders.
#
# setsid additionally detaches stdin/stdout/stderr from the caller so BATS (or
# any other caller) never inherits the listener's fds and never waits on it.
# ---------------------------------------------------------------------------
LISTENER_SCRIPT="$(mktemp "${TMPDIR:-/tmp}/xfleet-listen-XXXXXX")"

# Resolve plugin root here in the parent process so we can embed it into the
# temp script as CLAUDE_PLUGIN_ROOT (dispatch.sh uses this to find handlers).
_LISTEN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${_LISTEN_DIR}/../../.." && pwd)}"

# Capture env vars for the listener script (bash-3.2 portable: no heredoc with
# complex quoting — write each piece separately).
printf '#!/usr/bin/env bash\n' > "${LISTENER_SCRIPT}"
printf 'set -euo pipefail\n' >> "${LISTENER_SCRIPT}"
# Reap the redis-cli child when this listener bash is signalled/exits, so the
# inner BLOCK call never survives a process-group kill of the leader.
printf "trap 'pkill -P \$\$ 2>/dev/null || true' TERM EXIT\n" >> "${LISTENER_SCRIPT}"
# Embed the env vars and arguments as shell assignments. Single-quote all values
# so special characters (e.g. passwords in URLs, paths with spaces) are safe;
# escape any embedded single quotes the bash-3.2-safe way.
printf "export XFLEET_REDIS_URL='%s'\n" "$(printf '%s' "${XFLEET_REDIS_URL:-redis://127.0.0.1:6379}" | sed "s/'/'\\\\''/g")" >> "${LISTENER_SCRIPT}"
printf "export XFLEET_ROLE='%s'\n" "$(printf '%s' "${XFLEET_ROLE:-}" | sed "s/'/'\\\\''/g")" >> "${LISTENER_SCRIPT}"
printf "export XFLEET_WORKER_NAME='%s'\n" "$(printf '%s' "${XFLEET_WORKER_NAME:-}" | sed "s/'/'\\\\''/g")" >> "${LISTENER_SCRIPT}"
printf "export XFLEET_COORDINATION_ROOT='%s'\n" "$(printf '%s' "${XFLEET_COORDINATION_ROOT:-}" | sed "s/'/'\\\\''/g")" >> "${LISTENER_SCRIPT}"
printf "export CLAUDE_PLUGIN_ROOT='%s'\n" "$(printf '%s' "${PLUGIN_ROOT}" | sed "s/'/'\\\\''/g")" >> "${LISTENER_SCRIPT}"
printf 'STREAM=%s\n' "${STREAM}" >> "${LISTENER_SCRIPT}"
printf 'GROUP=%s\n' "${GROUP}" >> "${LISTENER_SCRIPT}"
printf 'CONSUMER=%s\n' "${CONSUMER}" >> "${LISTENER_SCRIPT}"
printf 'CYCLE_MS=300000\n' >> "${LISTENER_SCRIPT}"
# Write the listener body (pending recovery + blocking loop).
cat >> "${LISTENER_SCRIPT}" << 'LISTENER_EOF'
xfleet_redis() { redis-cli -u "${XFLEET_REDIS_URL}" "$@"; }

# Source dispatch lib (needs XFLEET_REDIS_URL already exported above so
# redis.sh picks it up; CLAUDE_PLUGIN_ROOT is also exported above).
# shellcheck source=../lib/dispatch.sh
source "${CLAUDE_PLUGIN_ROOT}/tools/xfleet/lib/dispatch.sh"

# Pending recovery
while true; do
    PENDING="$(xfleet_redis XREADGROUP GROUP "${GROUP}" "${CONSUMER}" COUNT 1 STREAMS "${STREAM}" 0 2>/dev/null)" || true
    if [[ -n "${PENDING}" ]]; then
        # wc -l counts newlines; command substitution strips trailing newline, so
        # a 4-line redis-cli reply arrives as 3 newlines → wc -l = 3. Threshold is 3.
        line_count="$(printf '%s' "${PENDING}" | wc -l | tr -d ' ')"
        if [[ "${line_count}" -ge 3 ]]; then
            stream_id="$(printf '%s' "${PENDING}" | sed -n '2p')"
            data_value="$(printf '%s' "${PENDING}" | sed -n '4p')"
            enriched="$(printf '%s' "${data_value}" | jq --arg sid "${stream_id}" '. + {_stream_id: $sid}' 2>/dev/null)" || true
            dispatch_message "${data_value}" || { printf 'listen: dispatch failed for pending stream_id %s; leaving unacked\n' "${stream_id}" >&2; continue; }
            xfleet_redis XACK "${STREAM}" "${GROUP}" "${stream_id}" >/dev/null
            printf '%s\n' "${enriched}"
            continue
        fi
    fi
    break
done

# Blocking read loop
while true; do
    rc=0
    RESULT="$(xfleet_redis XREADGROUP GROUP "${GROUP}" "${CONSUMER}" BLOCK "${CYCLE_MS}" COUNT 1 STREAMS "${STREAM}" '>' 2>/dev/null)" || rc=$?
    if [[ ${rc} -ne 0 ]]; then
        # XREADGROUP errored — redis unreachable, or NOGROUP after the consumer
        # group was destroyed (e.g. on test teardown). Without a backoff the
        # BLOCK returns instantly and this loop busy-spins, spawning a redis-cli
        # per iteration; that exhausts ephemeral ports and saturates CPU. Back
        # off before retrying so a stray/leaked listener idles cheaply.
        sleep 1
        continue
    fi
    if [[ -n "${RESULT}" ]]; then
        # Same threshold rationale as the pending-recovery branch above.
        line_count="$(printf '%s' "${RESULT}" | wc -l | tr -d ' ')"
        if [[ "${line_count}" -ge 3 ]]; then
            stream_id="$(printf '%s' "${RESULT}" | sed -n '2p')"
            data_value="$(printf '%s' "${RESULT}" | sed -n '4p')"
            enriched="$(printf '%s' "${data_value}" | jq --arg sid "${stream_id}" '. + {_stream_id: $sid}' 2>/dev/null)" || true
            dispatch_message "${data_value}" || { printf 'listen: dispatch failed for stream_id %s; leaving unacked\n' "${stream_id}" >&2; continue; }
            xfleet_redis XACK "${STREAM}" "${GROUP}" "${stream_id}" >/dev/null
            printf '%s\n' "${enriched}"
        fi
    fi
done
LISTENER_EOF

chmod +x "${LISTENER_SCRIPT}"

# Launch as its own session/process-group leader when setsid is available, so
# the recorded PID == its PGID and a caller can kill the whole subtree
# (listener bash + its redis-cli BLOCK child) with one `kill -- -PGID` signal.
# When setsid is absent (plain macOS without util-linux), fall back to a normal
# background launch — the listener's TERM/EXIT trap still reaps its redis-cli
# child, so no connection leaks either way. stdin/stdout/stderr are redirected
# so BATS (or any caller) never inherits the listener's fds and never waits.
if command -v setsid >/dev/null 2>&1; then
    setsid bash "${LISTENER_SCRIPT}" </dev/null >/dev/null 2>&1 &
else
    bash "${LISTENER_SCRIPT}" </dev/null >/dev/null 2>&1 &
fi
LISTENER_PID=$!
disown "${LISTENER_PID}" 2>/dev/null || true

# Clean up the temp script after a brief moment (listener has read it by then).
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
