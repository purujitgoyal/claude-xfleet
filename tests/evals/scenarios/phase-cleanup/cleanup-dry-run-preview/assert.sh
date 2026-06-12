#!/usr/bin/env bash
# Assertions for cleanup-dry-run-preview.
#
# Behaviour under test: the default (no-flag) cleanup is a read-only preview and
# must make NO changes. Every seeded artifact and Redis stream must survive.
#
# Env: WORKSPACE, RESPONDER, REPO_DIR, XFLEET_COORDINATION_ROOT, XFLEET_REDIS_URL, PATH.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/eval-lib.sh
source "${SCRIPT_DIR}/../../../lib/eval-lib.sh"

ROOT="${XFLEET_COORDINATION_ROOT}"

# Files must all survive a dry run.
[[ -f "${ROOT}/concerns/c-1.md" ]];        eval_check $? "dry-run preserved concerns/c-1.md"
[[ -f "${ROOT}/resolutions/r-1.md" ]];     eval_check $? "dry-run preserved resolutions/r-1.md"
[[ -f "${ROOT}/reviews/rv-1.md" ]];        eval_check $? "dry-run preserved reviews/rv-1.md"
[[ -f "${ROOT}/state/${RESPONDER}.json" ]]; eval_check $? "dry-run preserved state/${RESPONDER}.json"

# The session handoff under the roster repo's xfleet/{slug}/ dir must survive a dry run.
[[ -f "${REPO_DIR}/docs/superpowers/xfleet/evalwave/handoff-implement.md" ]]; eval_check $? "dry-run preserved the repo-local handoff"

# Redis streams + counter must all survive.
[[ "$(eval_redis EXISTS "inbox:${RESPONDER}")" -eq 1 ]];   eval_check $? "dry-run did not flush inbox:${RESPONDER}"
[[ "$(eval_redis EXISTS "inbox:orchestrator")" -eq 1 ]];   eval_check $? "dry-run did not flush inbox:orchestrator"
[[ "$(eval_redis EXISTS "concern:test-1:rounds")" -eq 1 ]]; eval_check $? "dry-run did not delete the round-counter key"

printf -- '--- %s assertion(s) failed ---\n' "${EVAL_FAILS}"
[[ "${EVAL_FAILS}" -eq 0 ]]
