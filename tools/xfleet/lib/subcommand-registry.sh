#!/usr/bin/env bash
# subcommand-registry.sh — canonical subcommand list for the xfleet dispatcher.
#
# Source this file to get XFLEET_SUBCOMMANDS (array) and xfleet_subcommand_dir().
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/subcommand-registry.sh"
#   xfleet_subcommand_dir  # prints the subcommands/ directory path
#
# This is a SOURCED library — it intentionally does NOT set strict mode, so it
# does not mutate the caller's shell options. Entry points (bin/xfleet, the
# subcommand stubs) own `set -euo pipefail`.

# Canonical list of 25 user-facing subcommands.
# Reflexive auto-handler messages (directive-ack, task-response, etc.) are
# internal and intentionally absent from this list.
XFLEET_SUBCOMMANDS=(
    status
    peek
    listen
    ack
    question
    answer
    concern
    concern-reopen
    resolution
    directive
    task
    escalation
    phase
    engage
    disengage
    bootstrap
    resume
    continue
    phase-complete
    review
    drift-check
    checklist
    integration-ready
    # exploration mode (orchestrator-less; messaging.md section i)
    ask
    await
)

# Print the absolute path to the subcommands/ directory.
xfleet_subcommand_dir() {
    echo "$(cd "$(dirname "${BASH_SOURCE[0]}")/../subcommands" && pwd)"
}
