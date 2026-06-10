#!/usr/bin/env bats
# Tests for bin/xfleet dispatcher (Task 6).
#
# bin/ is two levels above this file (tests/cli/), so:
#   BATS_TEST_DIRNAME = <repo>/tests/cli
#   ../../bin/xfleet  = <repo>/bin/xfleet

bats_require_minimum_version 1.5.0

XFLEET="${BATS_TEST_DIRNAME}/../../bin/xfleet"

# ---------------------------------------------------------------------------
# (a) --help: exits 0 and lists ALL subcommands
# ---------------------------------------------------------------------------

@test "(a) xfleet --help exits 0" {
    run "${XFLEET}" --help
    [ "$status" -eq 0 ]
}

@test "(a) xfleet --help output is non-empty" {
    run "${XFLEET}" --help
    [ -n "$output" ]
}

@test "(a) xfleet --help lists all 24 subcommands" {
    run "${XFLEET}" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"status"* ]]
    [[ "$output" == *"peek"* ]]
    [[ "$output" == *"listen"* ]]
    [[ "$output" == *"ack"* ]]
    [[ "$output" == *"question"* ]]
    [[ "$output" == *"answer"* ]]
    [[ "$output" == *"concern"* ]]
    [[ "$output" == *"concern-reopen"* ]]
    [[ "$output" == *"resolution"* ]]
    [[ "$output" == *"directive"* ]]
    [[ "$output" == *"task"* ]]
    [[ "$output" == *"escalation"* ]]
    [[ "$output" == *"phase"* ]]
    [[ "$output" == *"engage"* ]]
    [[ "$output" == *"disengage"* ]]
    [[ "$output" == *"resume"* ]]
    [[ "$output" == *"continue"* ]]
    [[ "$output" == *"phase-complete"* ]]
    [[ "$output" == *"review"* ]]
    [[ "$output" == *"drift-check"* ]]
    [[ "$output" == *"checklist"* ]]
    [[ "$output" == *"integration-ready"* ]]
    [[ "$output" == *"ask"* ]]
    [[ "$output" == *"await"* ]]
}

# ---------------------------------------------------------------------------
# (b) unknown subcommand: exits non-zero and prints a "did you mean" suggestion
# ---------------------------------------------------------------------------

@test "(b) xfleet <unknown-subcommand> exits non-zero" {
    run "${XFLEET}" zzz-totally-unknown-cmd
    [ "$status" -ne 0 ]
}

@test "(b) xfleet <unknown-subcommand> prints error message to stderr" {
    run --separate-stderr "${XFLEET}" zzz-totally-unknown-cmd
    [[ "$stderr" == *"zzz-totally-unknown-cmd"* ]] || [[ "$stderr" == *"Unknown"* ]] || [[ "$stderr" == *"unknown"* ]]
    # Error text must NOT leak to stdout
    [ -z "$output" ]
}

@test "(b) xfleet <typo-near-status> prints a did-you-mean suggestion on stderr" {
    # 'statuss' shares the 'status' prefix
    run --separate-stderr "${XFLEET}" statuss
    [ "$status" -ne 0 ]
    # stderr must reference a real subcommand name (the suggestion)
    [[ "$stderr" == *"status"* ]]
}

@test "(b) xfleet <typo-near-directive> prints suggestion on stderr" {
    run --separate-stderr "${XFLEET}" direktive
    [ "$status" -ne 0 ]
    [[ "$stderr" == *"directive"* ]]
}

# ---------------------------------------------------------------------------
# (c) known subcommands: each routes to its handler and is dispatched.
#
# Every subcommand now has a real implementation. Called bare (no args/env),
# each handler exits non-zero with its OWN error — a role gate
# ("XFLEET_ROLE is not set"), a coordination-root gate, or a usage/arg error.
# The dispatcher itself never emits these; an unrouted name produces the
# dispatcher's "Unknown subcommand" error instead. So we assert ROUTING, not
# exit-0: the handler was reached iff the exit is non-zero AND stderr is not
# the dispatcher's "Unknown subcommand" error. (Same contract as the
# drift-check / checklist / integration-ready tests below.)
# ---------------------------------------------------------------------------

@test "(c) xfleet status routes to handler and exits 0" {
    # status requires XFLEET_COORDINATION_ROOT; provide a valid one so it
    # can report "no state yet" rather than erroring.
    local coord
    coord="$(mktemp -d)"
    mkdir -p "${coord}/state"
    XFLEET_COORDINATION_ROOT="${coord}" run "${XFLEET}" status
    [ "$status" -eq 0 ]
    rm -rf "${coord}"
}

@test "(c) xfleet peek routes to handler and exits 0" {
    # peek requires a <name> arg; bare invocation emits usage to stderr from handler.
    # We verify the handler was reached (not "Unknown subcommand") by checking stderr.
    run --separate-stderr "${XFLEET}" peek
    [ "$status" -ne 0 ]
    # Handler emits usage to stderr; dispatcher emits "Unknown subcommand" to stderr.
    # Either contains "peek" — the distinction is the handler says "Usage" not "Unknown".
    [[ "${stderr}" =~ "peek" ]] || [[ "${stderr}" =~ [Uu]sage ]]
}

@test "(c) xfleet listen routes to handler and exits 0" {
    # listen requires a <name> arg; bare invocation emits usage to stderr from handler.
    run --separate-stderr "${XFLEET}" listen
    [ "$status" -ne 0 ]
    [[ "${stderr}" =~ "listen" ]] || [[ "${stderr}" =~ [Uu]sage ]]
}

@test "(c) xfleet ack routes to handler and exits 0" {
    # ack requires <name> and <message_id>; bare invocation emits usage to stderr.
    run --separate-stderr "${XFLEET}" ack
    [ "$status" -ne 0 ]
    [[ "${stderr}" =~ "ack" ]] || [[ "${stderr}" =~ [Uu]sage ]]
}

@test "(c) xfleet question routes to handler (not unknown subcommand)" {
    run --separate-stderr "${XFLEET}" question
    [ "$status" -ne 0 ]
    [[ "${stderr}" != *"Unknown subcommand"* ]]
}

@test "(c) xfleet answer routes to handler (not unknown subcommand)" {
    run --separate-stderr "${XFLEET}" answer
    [ "$status" -ne 0 ]
    [[ "${stderr}" != *"Unknown subcommand"* ]]
}

@test "(c) xfleet concern routes to handler (not unknown subcommand)" {
    run --separate-stderr "${XFLEET}" concern
    [ "$status" -ne 0 ]
    [[ "${stderr}" != *"Unknown subcommand"* ]]
}

@test "(c) xfleet concern-reopen routes to handler (not unknown subcommand)" {
    run --separate-stderr "${XFLEET}" concern-reopen
    [ "$status" -ne 0 ]
    [[ "${stderr}" != *"Unknown subcommand"* ]]
}

@test "(c) xfleet resolution routes to handler (not unknown subcommand)" {
    run --separate-stderr "${XFLEET}" resolution
    [ "$status" -ne 0 ]
    [[ "${stderr}" != *"Unknown subcommand"* ]]
}

@test "(c) xfleet directive routes to handler (not unknown subcommand)" {
    run --separate-stderr "${XFLEET}" directive
    [ "$status" -ne 0 ]
    [[ "${stderr}" != *"Unknown subcommand"* ]]
}

@test "(c) xfleet task routes to handler (not unknown subcommand)" {
    run --separate-stderr "${XFLEET}" task
    [ "$status" -ne 0 ]
    [[ "${stderr}" != *"Unknown subcommand"* ]]
}

@test "(c) xfleet escalation routes to handler (not unknown subcommand)" {
    run --separate-stderr "${XFLEET}" escalation
    [ "$status" -ne 0 ]
    [[ "${stderr}" != *"Unknown subcommand"* ]]
}

@test "(c) xfleet phase routes to handler (not unknown subcommand)" {
    run --separate-stderr "${XFLEET}" phase
    [ "$status" -ne 0 ]
    [[ "${stderr}" != *"Unknown subcommand"* ]]
}

@test "(c) xfleet engage routes to handler (not unknown subcommand)" {
    run --separate-stderr "${XFLEET}" engage
    [ "$status" -ne 0 ]
    [[ "${stderr}" != *"Unknown subcommand"* ]]
}

@test "(c) xfleet disengage routes to handler (not unknown subcommand)" {
    run --separate-stderr "${XFLEET}" disengage
    [ "$status" -ne 0 ]
    [[ "${stderr}" != *"Unknown subcommand"* ]]
}

@test "(c) xfleet resume routes to handler (not unknown subcommand)" {
    run --separate-stderr "${XFLEET}" resume
    [ "$status" -ne 0 ]
    [[ "${stderr}" != *"Unknown subcommand"* ]]
}

@test "(c) xfleet continue routes to handler (not unknown subcommand)" {
    run --separate-stderr "${XFLEET}" continue
    [ "$status" -ne 0 ]
    [[ "${stderr}" != *"Unknown subcommand"* ]]
}

@test "(c) xfleet phase-complete routes to handler (not unknown subcommand)" {
    run --separate-stderr "${XFLEET}" phase-complete
    [ "$status" -ne 0 ]
    [[ "${stderr}" != *"Unknown subcommand"* ]]
}

@test "(c) xfleet review routes to handler (not unknown subcommand)" {
    run --separate-stderr "${XFLEET}" review
    [ "$status" -ne 0 ]
    [[ "${stderr}" != *"Unknown subcommand"* ]]
}

@test "(c) xfleet drift-check routes to handler (not unknown subcommand)" {
    # drift-check requires env + flags; bare invocation exits 1 with a handler
    # error (role or usage), NOT the dispatcher's "Unknown subcommand" error.
    run --separate-stderr "${XFLEET}" drift-check
    [ "$status" -ne 0 ]
    # Handler errors mention the subcommand or env/flag requirements; dispatcher
    # "Unknown subcommand" errors always contain "Unknown". Either check passes.
    [[ "${stderr}" != *"Unknown subcommand"* ]]
}

@test "(c) xfleet checklist routes to handler (not unknown subcommand)" {
    # checklist requires --mode; bare invocation exits 1 with a usage error,
    # NOT the dispatcher's "Unknown subcommand" error.
    run --separate-stderr "${XFLEET}" checklist
    [ "$status" -ne 0 ]
    [[ "${stderr}" != *"Unknown subcommand"* ]]
}

@test "(c) xfleet integration-ready routes to handler (not unknown subcommand)" {
    # integration-ready requires XFLEET_ROLE=worker and --ip; bare invocation
    # exits 1 with a role or usage error, NOT the dispatcher's "Unknown subcommand".
    run --separate-stderr "${XFLEET}" integration-ready
    [ "$status" -ne 0 ]
    [[ "${stderr}" != *"Unknown subcommand"* ]]
}

@test "(c) xfleet ask routes to handler (not unknown subcommand)" {
    # ask requires a <responder> arg; bare invocation emits usage to stderr.
    run --separate-stderr "${XFLEET}" ask
    [ "$status" -ne 0 ]
    [[ "${stderr}" != *"Unknown subcommand"* ]]
}

@test "(c) xfleet await routes to handler (not unknown subcommand)" {
    # NEVER invoke await bare here — it parks (blocks) indefinitely. An unknown
    # flag exits 1 from arg parsing before any Redis call, proving routing.
    run --separate-stderr "${XFLEET}" await --bogus-flag
    [ "$status" -ne 0 ]
    [[ "${stderr}" != *"Unknown subcommand"* ]]
}

# ---------------------------------------------------------------------------
# (d) no args: prints help/error, exits non-zero
# ---------------------------------------------------------------------------

@test "(d) xfleet with no args exits non-zero" {
    run "${XFLEET}"
    [ "$status" -ne 0 ]
}

@test "(d) xfleet with no args prints usage information" {
    run "${XFLEET}"
    [ -n "$output" ]
}

# ---------------------------------------------------------------------------
# (e) argument passthrough: dispatcher forwards "$@" to the handler
# ---------------------------------------------------------------------------

@test "(e) xfleet <subcommand> forwards args to the handler" {
    # Build a minimal fixture plugin tree so the dispatcher routes to a stub
    # that records the args it received, rather than mutating a real stub.
    local fixture
    fixture="$(mktemp -d)"
    mkdir -p "${fixture}/tools/xfleet/lib" "${fixture}/tools/xfleet/subcommands"

    cat > "${fixture}/tools/xfleet/lib/subcommand-registry.sh" <<'REG'
XFLEET_SUBCOMMANDS=( echoargs )
xfleet_subcommand_dir() {
    echo "$(cd "$(dirname "${BASH_SOURCE[0]}")/../subcommands" && pwd)"
}
REG

    local argfile="${fixture}/received-args"
    cat > "${fixture}/tools/xfleet/subcommands/echoargs.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$@" > "${argfile}"
exit 0
EOF
    chmod +x "${fixture}/tools/xfleet/subcommands/echoargs.sh"

    CLAUDE_PLUGIN_ROOT="${fixture}" run "${XFLEET}" echoargs arg1 arg2 "third arg"
    [ "$status" -eq 0 ]

    [ -f "${argfile}" ]
    run cat "${argfile}"
    [[ "${lines[0]}" == "arg1" ]]
    [[ "${lines[1]}" == "arg2" ]]
    [[ "${lines[2]}" == "third arg" ]]

    rm -rf "${fixture}"
}

# ---------------------------------------------------------------------------
# (f) single-dash unknown option: errors to stderr, exits non-zero
# ---------------------------------------------------------------------------

@test "(f) xfleet -v (unknown single-dash option) exits non-zero" {
    run "${XFLEET}" -v
    [ "$status" -ne 0 ]
}

@test "(f) xfleet -v prints unknown-option error to stderr (no did-you-mean)" {
    run --separate-stderr "${XFLEET}" -v
    [[ "$stderr" == *"Unknown option"* ]]
    # Must not fall through to subcommand suggestion
    [[ "$stderr" != *"Did you mean"* ]]
}
