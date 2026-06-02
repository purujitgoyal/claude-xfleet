#!/usr/bin/env bats
# dispatch-completion.bats — tests for _dispatch_check_phase_complete in
# tools/xfleet/lib/dispatch.sh (cluster 4a / F-13 completion mechanization).
#
# tests/lib/ is two levels below the repo root:
#   ../../tools/xfleet/lib/dispatch.sh = the lib under test
#
# The orchestrator phase-complete path is redis-free: it reads the worker
# state files under state/ to derive the expected-worker set, reconstructs the
# received set from prior completion_log entries (+ the triggering worker), and
# appends a real evaluation entry to _orchestrator.json. No XADD involved.
#
# "Complete" = every participating worker (one {worker}.json under state/,
# excluding _orchestrator.json) has signaled phase-complete for the phase.
#
# Scenarios:
#   (a) one of two workers signals          → incomplete, missing the other
#   (b) all workers signal                  → complete, no missing
#   (c) signal for a different phase         → does not satisfy the target phase
#   (d) single-worker roster                 → complete on first signal

bats_require_minimum_version 1.5.0

DISPATCH="${BATS_TEST_DIRNAME}/../../tools/xfleet/lib/dispatch.sh"

setup() {
    export CLAUDE_PLUGIN_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    export XFLEET_ROLE="orchestrator"
    COORD="${BATS_TMPDIR}/coord-$$-${BATS_TEST_NUMBER}"
    export XFLEET_COORDINATION_ROOT="${COORD}"
    mkdir -p "${COORD}/state"
    printf '{"schema_version": "1"}\n' > "${COORD}/state/_orchestrator.json"
}

teardown() {
    rm -rf "${COORD}"
}

# Write a worker state file (content is irrelevant — only the filename is read).
_mk_worker() {
    printf '{"schema_version": "1"}\n' > "${COORD}/state/$1.json"
}

_pc_msg() { # <worker> <phase>
    printf '{"id":"m-%s","type":"phase-complete","from":"worker","to":"orchestrator","worker":"%s","phase":"%s"}' "$1" "$1" "$2"
}

_dispatch() { # <message-json>
    run bash -c "source '${DISPATCH}'; dispatch_message '$1'"
    [ "$status" -eq 0 ]
}

_last() { # <jq-filter>
    jq -r ".completion_log[-1] | $1" "${COORD}/state/_orchestrator.json"
}

# ---------------------------------------------------------------------------

@test "dispatch.sh exists" {
    [ -f "${DISPATCH}" ]
}

# (a) one of two workers signals → incomplete, missing the other
@test "(a) incomplete while a worker is still outstanding" {
    _mk_worker alice
    _mk_worker bob

    _dispatch "$(_pc_msg alice repo-spec)"

    [ "$(_last '.outcome')" = "incomplete" ]
    [ "$(_last '.missing_workers | join(",")')" = "bob" ]
    [ "$(_last '.worker')" = "alice" ]
    [ "$(_last '.phase')" = "repo-spec" ]
    [ "$(_last '.trigger_msg_type')" = "phase-complete" ]
}

# (b) all workers signal → complete, no missing
@test "(b) complete once every worker has signaled" {
    _mk_worker alice
    _mk_worker bob

    _dispatch "$(_pc_msg alice repo-spec)"
    _dispatch "$(_pc_msg bob repo-spec)"

    [ "$(_last '.outcome')" = "complete" ]
    [ "$(_last '.missing_workers | length')" = "0" ]
    [ "$(_last '.worker')" = "bob" ]
}

# (c) a signal for a different phase does not satisfy the target phase
@test "(c) cross-phase signals do not count toward the current phase" {
    _mk_worker alice
    _mk_worker bob

    # alice completed an earlier phase; bob now completes repo-spec.
    _dispatch "$(_pc_msg alice plan)"
    _dispatch "$(_pc_msg bob repo-spec)"

    # repo-spec is NOT complete — only bob signaled for it; alice still missing.
    [ "$(_last '.outcome')" = "incomplete" ]
    [ "$(_last '.missing_workers | join(",")')" = "alice" ]
    [ "$(_last '.phase')" = "repo-spec" ]
}

# (d) single-worker roster → complete on the first signal
@test "(d) single-worker roster completes on first signal" {
    _mk_worker solo

    _dispatch "$(_pc_msg solo implement)"

    [ "$(_last '.outcome')" = "complete" ]
    [ "$(_last '.missing_workers | length')" = "0" ]
}
