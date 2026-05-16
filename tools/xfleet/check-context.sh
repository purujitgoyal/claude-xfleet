#!/usr/bin/env bash
# check-context.sh — PostToolUse hook helper for context-window monitoring.
#
# STUB: exits 0 with no output.
# Drains stdin so the CC hook runner does not get SIGPIPE/EPIPE when it writes
# the JSON payload to this script's stdin pipe. Task 30 will replace the drain
# with actual payload consumption (e.g. PAYLOAD=$(cat)) and real logic.
set -euo pipefail
exec < /dev/null
