#!/usr/bin/env bats
# Smoke tests for bin/xfleet dispatcher.
# These tests intentionally FAIL until Task 6 lands bin/xfleet.
# This is the TDD red for Task 6.

XFLEET="${BATS_TEST_DIRNAME}/../bin/xfleet"

@test "bin/xfleet is executable" {
    [ -x "${XFLEET}" ]
}

@test "bin/xfleet --help exits 0 and emits non-empty output" {
    run "${XFLEET}" --help
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}
