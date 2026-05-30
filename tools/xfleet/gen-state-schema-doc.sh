#!/usr/bin/env bash
# gen-state-schema-doc.sh — regenerate the Field Reference table in
# shared/state-schema.md from tools/xfleet/state-schema.json.
#
# Thin wrapper around lib/gen-state-schema-doc.py. Operator/CI-run (not
# session-run), so CLAUDE_PLUGIN_ROOT may be unset; fall back to deriving the
# plugin root from this script's own location.
#
# Usage:
#   XFLEET_PYTHON=/path/to/venv/bin/python bash tools/xfleet/gen-state-schema-doc.sh
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
PYTHON="${XFLEET_PYTHON:-python3}"

exec "${PYTHON}" "${PLUGIN_ROOT}/tools/xfleet/lib/gen-state-schema-doc.py"
