#!/usr/bin/env bash
# Assertions for cleanup-apply-executes.
#
# Behaviour under test: with the guard not tripped, `--apply` removes the
# intermediate artifacts and flushes the Redis streams + round-counter.
#
# Env: WORKSPACE, RESPONDER, REPO_DIR, XFLEET_COORDINATION_ROOT, XFLEET_REDIS_URL, PATH.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/eval-lib.sh
source "${SCRIPT_DIR}/../../../lib/eval-lib.sh"

ROOT="${XFLEET_COORDINATION_ROOT}"

# Intermediate artifacts must be gone.
[[ ! -f "${ROOT}/concerns/c-1.md" ]];        eval_check $? "apply removed concerns/c-1.md"
[[ ! -f "${ROOT}/resolutions/r-1.md" ]];     eval_check $? "apply removed resolutions/r-1.md"
[[ ! -f "${ROOT}/reviews/rv-1.md" ]];        eval_check $? "apply removed reviews/rv-1.md"
[[ ! -f "${ROOT}/state/${RESPONDER}.json" ]]; eval_check $? "apply removed state/${RESPONDER}.json"

# Redis streams + counter must be flushed.
[[ "$(eval_redis EXISTS "inbox:${RESPONDER}")" -eq 0 ]];   eval_check $? "apply flushed inbox:${RESPONDER}"
[[ "$(eval_redis EXISTS "inbox:orchestrator")" -eq 0 ]];   eval_check $? "apply flushed inbox:orchestrator"
[[ "$(eval_redis EXISTS "concern:test-1:rounds")" -eq 0 ]]; eval_check $? "apply deleted the round-counter key"

printf -- '--- %s assertion(s) failed ---\n' "${EVAL_FAILS}"
[[ "${EVAL_FAILS}" -eq 0 ]]
