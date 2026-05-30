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
# status.md — invokes xfleet by BARE NAME (PATH-provided), not an absolute path.
#
# Claude Code permission rules do NOT expand env vars, so an allowed-tools entry
# scoped to ${CLAUDE_PLUGIN_ROOT}/bin/xfleet would never match the runtime
# command and would prompt on every use. The SessionStart hook puts bin/ on PATH
# and the manifest ships Bash(xfleet *), so bare `xfleet status` is the correct,
# auto-permitted invocation.
# ---------------------------------------------------------------------------

@test "status.md allowed-tools is scoped to Bash(xfleet:*)" {
    run grep -F 'allowed-tools: Bash(xfleet:*)' "${STATUS_CMD}"
    [ "$status" -eq 0 ]
}

@test "status.md does NOT invoke via an absolute \${CLAUDE_PLUGIN_ROOT}/bin path" {
    # Regression guard: the env-var path form is a permission defect; assert absence.
    run grep -F '${CLAUDE_PLUGIN_ROOT}/bin' "${STATUS_CMD}"
    [ "$status" -ne 0 ]
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
# status.md — uses the !`...` inline-bash execution pattern with bare xfleet
# ---------------------------------------------------------------------------

@test "status.md uses the backtick inline-bash execution pattern" {
    # Match the literal !` prefix that Claude Code uses for inline command output.
    run grep -F '!`' "${STATUS_CMD}"
    [ "$status" -eq 0 ]
}

@test "status.md inline-bash call invokes bare xfleet status" {
    run grep -F '!`xfleet status`' "${STATUS_CMD}"
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

@test "help.md covers negotiation subcommands (concern, concern-reopen, resolution)" {
    run grep -F 'concern' "${HELP_CMD}"
    [ "$status" -eq 0 ]
    run grep -F 'concern-reopen' "${HELP_CMD}"
    [ "$status" -eq 0 ]
    run grep -F 'resolution' "${HELP_CMD}"
    [ "$status" -eq 0 ]
}

@test "help.md covers orchestrator-to-worker subcommands (directive, task, escalation)" {
    run grep -F 'directive' "${HELP_CMD}"
    [ "$status" -eq 0 ]
    run grep -F 'task' "${HELP_CMD}"
    [ "$status" -eq 0 ]
    run grep -F 'escalation' "${HELP_CMD}"
    [ "$status" -eq 0 ]
}

@test "help.md covers lifecycle subcommands (phase, engage, disengage, resume, continue, phase-complete)" {
    run grep -F 'phase' "${HELP_CMD}"
    [ "$status" -eq 0 ]
    run grep -F 'engage' "${HELP_CMD}"
    [ "$status" -eq 0 ]
    run grep -F 'disengage' "${HELP_CMD}"
    [ "$status" -eq 0 ]
    run grep -F 'resume' "${HELP_CMD}"
    [ "$status" -eq 0 ]
    run grep -F 'continue' "${HELP_CMD}"
    [ "$status" -eq 0 ]
    run grep -F 'phase-complete' "${HELP_CMD}"
    [ "$status" -eq 0 ]
}

@test "help.md covers the review subcommand" {
    run grep -F 'review' "${HELP_CMD}"
    [ "$status" -eq 0 ]
}

@test "help.md notes operational groupings differ from messaging.md structural taxonomy" {
    run grep -Ei 'structural|message-type taxonomy|use-context' "${HELP_CMD}"
    [ "$status" -eq 0 ]
}

@test "help.md mentions that bin/ is on PATH via SessionStart hook" {
    run grep -Ei 'SessionStart|session.?start' "${HELP_CMD}"
    [ "$status" -eq 0 ]
}
