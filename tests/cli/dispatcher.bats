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

@test "(a) xfleet --help lists all 19 subcommands" {
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
}

# ---------------------------------------------------------------------------
# (b) unknown subcommand: exits non-zero and prints a "did you mean" suggestion
# ---------------------------------------------------------------------------

@test "(b) xfleet <unknown-subcommand> exits non-zero" {
    run "${XFLEET}" zzz-totally-unknown-cmd
    [ "$status" -ne 0 ]
}

@test "(b) xfleet <unknown-subcommand> prints error message" {
    run "${XFLEET}" zzz-totally-unknown-cmd
    [[ "$output" == *"zzz-totally-unknown-cmd"* ]] || [[ "$output" == *"Unknown"* ]] || [[ "$output" == *"unknown"* ]]
}

@test "(b) xfleet <typo-near-status> prints a did-you-mean suggestion with a real subcommand" {
    # 'statuss' is one edit away from 'status'
    run "${XFLEET}" statuss
    [ "$status" -ne 0 ]
    # Output must reference a real subcommand name (the suggestion)
    [[ "$output" == *"status"* ]]
}

@test "(b) xfleet <typo-near-directive> prints suggestion" {
    run "${XFLEET}" direktive
    [ "$status" -ne 0 ]
    [[ "$output" == *"directive"* ]]
}

# ---------------------------------------------------------------------------
# (c) known subcommands: each routes to its handler stub and exits 0
# ---------------------------------------------------------------------------

@test "(c) xfleet status routes to handler and exits 0" {
    run "${XFLEET}" status
    [ "$status" -eq 0 ]
}

@test "(c) xfleet peek routes to handler and exits 0" {
    run "${XFLEET}" peek
    [ "$status" -eq 0 ]
}

@test "(c) xfleet listen routes to handler and exits 0" {
    run "${XFLEET}" listen
    [ "$status" -eq 0 ]
}

@test "(c) xfleet ack routes to handler and exits 0" {
    run "${XFLEET}" ack
    [ "$status" -eq 0 ]
}

@test "(c) xfleet question routes to handler and exits 0" {
    run "${XFLEET}" question
    [ "$status" -eq 0 ]
}

@test "(c) xfleet answer routes to handler and exits 0" {
    run "${XFLEET}" answer
    [ "$status" -eq 0 ]
}

@test "(c) xfleet concern routes to handler and exits 0" {
    run "${XFLEET}" concern
    [ "$status" -eq 0 ]
}

@test "(c) xfleet concern-reopen routes to handler and exits 0" {
    run "${XFLEET}" concern-reopen
    [ "$status" -eq 0 ]
}

@test "(c) xfleet resolution routes to handler and exits 0" {
    run "${XFLEET}" resolution
    [ "$status" -eq 0 ]
}

@test "(c) xfleet directive routes to handler and exits 0" {
    run "${XFLEET}" directive
    [ "$status" -eq 0 ]
}

@test "(c) xfleet task routes to handler and exits 0" {
    run "${XFLEET}" task
    [ "$status" -eq 0 ]
}

@test "(c) xfleet escalation routes to handler and exits 0" {
    run "${XFLEET}" escalation
    [ "$status" -eq 0 ]
}

@test "(c) xfleet phase routes to handler and exits 0" {
    run "${XFLEET}" phase
    [ "$status" -eq 0 ]
}

@test "(c) xfleet engage routes to handler and exits 0" {
    run "${XFLEET}" engage
    [ "$status" -eq 0 ]
}

@test "(c) xfleet disengage routes to handler and exits 0" {
    run "${XFLEET}" disengage
    [ "$status" -eq 0 ]
}

@test "(c) xfleet resume routes to handler and exits 0" {
    run "${XFLEET}" resume
    [ "$status" -eq 0 ]
}

@test "(c) xfleet continue routes to handler and exits 0" {
    run "${XFLEET}" continue
    [ "$status" -eq 0 ]
}

@test "(c) xfleet phase-complete routes to handler and exits 0" {
    run "${XFLEET}" phase-complete
    [ "$status" -eq 0 ]
}

@test "(c) xfleet review routes to handler and exits 0" {
    run "${XFLEET}" review
    [ "$status" -eq 0 ]
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
