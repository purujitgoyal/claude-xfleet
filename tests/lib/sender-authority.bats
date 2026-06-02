#!/usr/bin/env bats
# sender-authority.bats — tests for tools/xfleet/lib/sender-authority.sh assert_role.
#
# Covers:
#   (a) XFLEET_ROLE unset            → exit 1 + "is not set" guidance
#   (b) XFLEET_ROLE unknown value    → exit 1 + "unknown value"
#   (c) role matches                 → exit 0, no output
#   (d) role mismatch + suggestion   → exit 1; names subcommand + required + actual
#                                      role, and prints the A3 near-miss suggestion
#   (e) role mismatch, no suggestion → exit 1; role error but no extra hint line
#   (f) subcommand name is derived from the calling script (BASH_SOURCE)
#
# assert_role exits, so each scenario runs a tiny fixture script (named to
# emulate a real subcommand) via `run`.

bats_require_minimum_version 1.5.0

LIB="${BATS_TEST_DIRNAME}/../../tools/xfleet/lib/sender-authority.sh"

setup() {
    # Fixture named "concern.sh" so the derived subcommand name is "concern".
    FIXTURE="${BATS_TEST_TMPDIR}/concern.sh"
    {
        printf '#!/usr/bin/env bash\n'
        printf 'source "%s"\n' "${LIB}"
        printf 'assert_role "$@"\n'
    } > "${FIXTURE}"
    chmod +x "${FIXTURE}"
}

@test "lib exists" {
    [ -f "${LIB}" ]
}

# (a) -----------------------------------------------------------------------
@test "(a) unset XFLEET_ROLE → exit 1 with not-set guidance" {
    run env -u XFLEET_ROLE bash "${FIXTURE}" worker
    [ "$status" -eq 1 ]
    [[ "$output" == *"XFLEET_ROLE is not set"* ]]
}

# (b) -----------------------------------------------------------------------
@test "(b) unknown XFLEET_ROLE → exit 1 with unknown-value message" {
    run env XFLEET_ROLE=captain bash "${FIXTURE}" worker
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown value"* ]]
    [[ "$output" == *"captain"* ]]
}

# (c) -----------------------------------------------------------------------
@test "(c) matching role → exit 0, no output" {
    run env XFLEET_ROLE=worker bash "${FIXTURE}" worker "should not print"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# (d) -----------------------------------------------------------------------
@test "(d) role mismatch with suggestion → names subcommand, roles, and hint" {
    run env XFLEET_ROLE=orchestrator bash "${FIXTURE}" worker \
        "concerns are peer-to-peer; from an orchestrator session use 'directive' instead."
    [ "$status" -eq 1 ]
    # Subcommand name derived from the fixture filename.
    [[ "$output" == *"'concern'"* ]]
    [[ "$output" == *'requires role "worker"'* ]]
    [[ "$output" == *'XFLEET_ROLE="orchestrator"'* ]]
    # The A3 near-miss suggestion is surfaced.
    [[ "$output" == *"use 'directive' instead"* ]]
}

# (e) -----------------------------------------------------------------------
@test "(e) role mismatch without suggestion → role error, no hint line" {
    run env XFLEET_ROLE=worker bash "${FIXTURE}" orchestrator
    [ "$status" -eq 1 ]
    [[ "$output" == *'requires role "orchestrator"'* ]]
    [[ "$output" == *'XFLEET_ROLE="worker"'* ]]
    # Exactly one line of output (no trailing suggestion line).
    [ "${#lines[@]}" -eq 1 ]
}

# (f) -----------------------------------------------------------------------
@test "(f) subcommand name tracks the calling script name" {
    other="${BATS_TEST_TMPDIR}/directive.sh"
    {
        printf '#!/usr/bin/env bash\n'
        printf 'source "%s"\n' "${LIB}"
        printf 'assert_role "$@"\n'
    } > "${other}"
    run env XFLEET_ROLE=worker bash "${other}" orchestrator "from a worker raise a 'concern'."
    [ "$status" -eq 1 ]
    [[ "$output" == *"'directive'"* ]]
    [[ "$output" == *"raise a 'concern'"* ]]
}
