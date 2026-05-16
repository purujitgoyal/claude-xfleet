#!/usr/bin/env bats
# Tests for plugin.json permissions block.
# Verifies: (1) Bash(xfleet *) is present under settings.permissions.allow;
#           (2) no Write( or Read( path-scoped rules exist in the allow array
#               (those belong to the Task 31 setup script, not the manifest).

set -euo pipefail

MANIFEST="${BATS_TEST_DIRNAME}/../../.claude-plugin/plugin.json"

@test "plugin.json exists" {
    [ -f "${MANIFEST}" ]
}

@test "settings.permissions.allow contains Bash(xfleet *)" {
    run jq -e '
      .settings.permissions.allow
      | if type != "array" then error("not an array") else . end
      | map(select(. == "Bash(xfleet *)"))
      | length == 1
    ' "${MANIFEST}"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "settings.permissions.allow contains exactly one entry (no Write or Read path rules)" {
    run jq -e '
      .settings.permissions.allow
      | if type != "array" then error("not an array") else . end
      | length == 1
    ' "${MANIFEST}"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "manifest does not contain any Write( permission rules" {
    run jq -e '
      [.settings.permissions.allow // [] | .[] | select(startswith("Write("))]
      | length == 0
    ' "${MANIFEST}"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

@test "manifest does not contain any Read( permission rules" {
    run jq -e '
      [.settings.permissions.allow // [] | .[] | select(startswith("Read("))]
      | length == 0
    ' "${MANIFEST}"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}
