#!/usr/bin/env bats
# Tests for the PostToolUse context-check hook scaffold (Task 5).
#
# Asserts:
#   1. hooks.json registers a PostToolUse key with matchers for
#      Agent|Task (regex), Read, Grep, and mcp__serena__.* (regex).
#   2. The mcp__serena__.* matcher uses REGEX syntax (. * meta-chars),
#      NOT a glob (mcp__serena__*).
#   3. Each matcher's hook command invokes
#      ${CLAUDE_PLUGIN_ROOT}/tools/xfleet/check-context.sh.
#   4. The stub check-context.sh exits 0 and produces no output.

bats_require_minimum_version 1.5.0

HOOKS_JSON="${BATS_TEST_DIRNAME}/../../hooks/hooks.json"
CHECK_CTX_SCRIPT="${BATS_TEST_DIRNAME}/../../tools/xfleet/check-context.sh"

# ---------------------------------------------------------------------------
# (a) hooks.json structure
# ---------------------------------------------------------------------------

@test "(a) hooks.json has a PostToolUse key" {
    jq -e '.hooks.PostToolUse' "${HOOKS_JSON}" > /dev/null
}

@test "(a) PostToolUse is a non-empty array" {
    count=$(jq '.hooks.PostToolUse | length' "${HOOKS_JSON}")
    [[ "$count" -gt 0 ]]
}

# ---------------------------------------------------------------------------
# (b) required matchers are present
# ---------------------------------------------------------------------------

@test "(b) PostToolUse has a matcher covering Agent and Task (regex Agent|Task)" {
    # At least one entry must have a matcher that matches both 'Agent' and 'Task'.
    # The canonical form is the regex "Agent|Task" (or "^(Agent|Task)$").
    # We check by looking for an entry whose matcher string contains both tokens.
    result=$(jq -r '
      .hooks.PostToolUse[]
      | select(
          (.matcher | test("Agent")) and
          (.matcher | test("Task"))
        )
      | .matcher
    ' "${HOOKS_JSON}")
    [[ -n "$result" ]]
}

@test "(b) PostToolUse has a matcher for Read" {
    result=$(jq -r '
      .hooks.PostToolUse[]
      | select(.matcher == "Read")
      | .matcher
    ' "${HOOKS_JSON}")
    [[ -n "$result" ]]
}

@test "(b) PostToolUse has a matcher for Grep" {
    result=$(jq -r '
      .hooks.PostToolUse[]
      | select(.matcher == "Grep")
      | .matcher
    ' "${HOOKS_JSON}")
    [[ -n "$result" ]]
}

@test "(b) PostToolUse has a matcher for mcp__serena__ tools (regex)" {
    result=$(jq -r '
      .hooks.PostToolUse[]
      | select(.matcher | test("mcp__serena__"))
      | .matcher
    ' "${HOOKS_JSON}")
    [[ -n "$result" ]]
}

# ---------------------------------------------------------------------------
# (c) mcp__serena__ matcher uses REGEX syntax, not glob
# ---------------------------------------------------------------------------

@test "(c) mcp__serena__ matcher contains regex meta-chars (. and *), not a glob star-only suffix" {
    # A regex matcher looks like "mcp__serena__.*" (dot-star).
    # A glob would be "mcp__serena__*" (star only, no dot).
    # We assert the matcher string contains ".*" (dot followed by star).
    result=$(jq -r '
      .hooks.PostToolUse[]
      | select(.matcher | test("mcp__serena__"))
      | .matcher
    ' "${HOOKS_JSON}")
    [[ "$result" == *".*"* ]]
}

# ---------------------------------------------------------------------------
# (d) each matcher's hook command references check-context.sh
# ---------------------------------------------------------------------------

@test "(d) every PostToolUse hook command references check-context.sh" {
    # All hook commands across all PostToolUse entries must mention check-context.sh.
    bad=$(jq -r '
      .hooks.PostToolUse[].hooks[]
      | select(.command | test("check-context\\.sh") | not)
      | .command
    ' "${HOOKS_JSON}")
    [[ -z "$bad" ]]
}

@test "(d) hook commands use \${CLAUDE_PLUGIN_ROOT}/tools/xfleet/check-context.sh" {
    # All commands must reference the canonical path under CLAUDE_PLUGIN_ROOT.
    all_match=$(jq '
      [ .hooks.PostToolUse[].hooks[] | .command ]
      | all(test("\\$\\{CLAUDE_PLUGIN_ROOT\\}/tools/xfleet/check-context\\.sh"))
    ' "${HOOKS_JSON}")
    [[ "$all_match" == "true" ]]
}

# ---------------------------------------------------------------------------
# (e) check-context.sh stub behavior
# ---------------------------------------------------------------------------

@test "(e) check-context.sh exists and is executable" {
    [[ -x "${CHECK_CTX_SCRIPT}" ]]
}

@test "(e) check-context.sh exits 0 (no-op stub)" {
    run "${CHECK_CTX_SCRIPT}"
    [ "$status" -eq 0 ]
}

@test "(e) check-context.sh produces no output (stub is silent)" {
    run "${CHECK_CTX_SCRIPT}"
    [ -z "$output" ]
}
