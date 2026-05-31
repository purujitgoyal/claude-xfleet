#!/usr/bin/env bash
# strict-mode.sh — source this at the top of every xfleet Bash lib/script (Task 19, 4c).
# Enables strict mode: abort on error, unbound variable, or pipe failure.
set -euo pipefail
IFS=$'\n\t'
