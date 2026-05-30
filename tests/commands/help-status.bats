#!/usr/bin/env bats
# Presence and format tests for commands/help.md and commands/status.md (Task 15b).
#
# tests/commands/ is two levels below the repo root, so:
#   BATS_TEST_DIRNAME = <repo>/tests/commands
#   ../../commands/help.md   = <repo>/commands/help.md
#   ../../commands/status.md = <repo>/commands/status.md
#
# Assertions:
#   (1) Both command files exist.
#   (2) Both have valid frontmatter: opening ---, a description: line, closing ---.
#   (3) status.md references ${CLAUDE_PLUGIN_ROOT} (not a relative path like ../bin).
#   (4) status.md uses the !`...` inline-bash execution pattern.
#   (5) help.md mentions the xfleet CLI and references shared/messaging.md.

bats_require_minimum_version 1.5.0

HELP_CMD="${BATS_TEST_DIRNAME}/../../commands/help.md"
STATUS_CMD="${BATS_TEST_DIRNAME}/../../commands/status.md"

# ---------------------------------------------------------------------------
# Existence
# ---------------------------------------------------------------------------

@test "commands/help.md exists" {
    [ -f "${HELP_CMD}" ]
}

@test "commands/status.md exists" {
    [ -f "${STATUS_CMD}" ]
}

# ---------------------------------------------------------------------------
# Frontmatter structure — must open with ---, contain description:, close with ---
# ---------------------------------------------------------------------------

@test "help.md has opening frontmatter delimiter" {
    run head -1 "${HELP_CMD}"
    [ "${output}" = "---" ]
}

@test "help.md has a description: field in frontmatter" {
    run grep -E "^description: .+" "${HELP_CMD}"
    [ "$status" -eq 0 ]
}

@test "help.md frontmatter closes with ---" {
    # The second occurrence of a bare --- line is the closing delimiter.
    run grep -c "^---$" "${HELP_CMD}"
    [ "$status" -eq 0 ]
    [ "$output" -ge 2 ]
}

@test "status.md has opening frontmatter delimiter" {
    run head -1 "${STATUS_CMD}"
    [ "${output}" = "---" ]
}

@test "status.md has a description: field in frontmatter" {
    run grep -E "^description: .+" "${STATUS_CMD}"
    [ "$status" -eq 0 ]
}

@test "status.md frontmatter closes with ---" {
    run grep -c "^---$" "${STATUS_CMD}"
    [ "$status" -eq 0 ]
    [ "$output" -ge 2 ]
}

# ---------------------------------------------------------------------------
# status.md — allowed-tools includes Bash permission
# ---------------------------------------------------------------------------

@test "status.md has an allowed-tools: line" {
    run grep -E "^allowed-tools: .+" "${STATUS_CMD}"
    [ "$status" -eq 0 ]
}

@test "status.md allowed-tools references Bash" {
    run grep -E "^allowed-tools:.*Bash" "${STATUS_CMD}"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# status.md — uses ${CLAUDE_PLUGIN_ROOT} (not a relative path)
# ---------------------------------------------------------------------------

@test "status.md references \${CLAUDE_PLUGIN_ROOT}" {
    run grep -F '${CLAUDE_PLUGIN_ROOT}' "${STATUS_CMD}"
    [ "$status" -eq 0 ]
}

@test "status.md does not use a relative ../bin path" {
    run grep -F '../bin' "${STATUS_CMD}"
    [ "$status" -ne 0 ]
}

@test "status.md does not use a relative ./bin path" {
    run grep -F './bin' "${STATUS_CMD}"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# status.md — uses the !`...` inline-bash execution pattern
# ---------------------------------------------------------------------------

@test "status.md uses the backtick inline-bash execution pattern" {
    # Match the literal !` prefix that Claude Code uses for inline command output.
    run grep -F '!`' "${STATUS_CMD}"
    [ "$status" -eq 0 ]
}

@test "status.md inline-bash call invokes xfleet status via CLAUDE_PLUGIN_ROOT" {
    run grep -F '${CLAUDE_PLUGIN_ROOT}/bin/xfleet status' "${STATUS_CMD}"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# help.md — content completeness
# ---------------------------------------------------------------------------

@test "help.md mentions the xfleet CLI by name" {
    run grep -F 'xfleet' "${HELP_CMD}"
    [ "$status" -eq 0 ]
}

@test "help.md references shared/messaging.md" {
    run grep -F 'shared/messaging.md' "${HELP_CMD}"
    [ "$status" -eq 0 ]
}

@test "help.md covers read-only/operational subcommands (status, peek, listen, ack)" {
    run grep -F 'status' "${HELP_CMD}"
    [ "$status" -eq 0 ]
    run grep -F 'peek' "${HELP_CMD}"
    [ "$status" -eq 0 ]
    run grep -F 'listen' "${HELP_CMD}"
    [ "$status" -eq 0 ]
    run grep -F 'ack' "${HELP_CMD}"
    [ "$status" -eq 0 ]
}

@test "help.md covers clarification subcommands (question, answer)" {
    run grep -F 'question' "${HELP_CMD}"
    [ "$status" -eq 0 ]
    run grep -F 'answer' "${HELP_CMD}"
    [ "$status" -eq 0 ]
}

@test "help.md covers negotiation subcommands (concern, resolution)" {
    run grep -F 'concern' "${HELP_CMD}"
    [ "$status" -eq 0 ]
    run grep -F 'resolution' "${HELP_CMD}"
    [ "$status" -eq 0 ]
}

@test "help.md covers lifecycle subcommands (phase, engage, disengage, resume)" {
    run grep -F 'phase' "${HELP_CMD}"
    [ "$status" -eq 0 ]
    run grep -F 'engage' "${HELP_CMD}"
    [ "$status" -eq 0 ]
    run grep -F 'disengage' "${HELP_CMD}"
    [ "$status" -eq 0 ]
    run grep -F 'resume' "${HELP_CMD}"
    [ "$status" -eq 0 ]
}

@test "help.md mentions that bin/ is on PATH via SessionStart hook" {
    run grep -Ei 'SessionStart|session.?start' "${HELP_CMD}"
    [ "$status" -eq 0 ]
}
