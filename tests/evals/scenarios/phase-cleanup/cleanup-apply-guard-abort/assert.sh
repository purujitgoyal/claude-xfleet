#!/usr/bin/env bash
# Assertions for cleanup-apply-guard-abort.
#
# Behaviour under test: with resolutions AND unmerged per-repo sections present,
# `--apply` (no --force) must hit the pre-flight guard and ABORT before any
# deletion or Redis flush. Every artifact and stream must survive.
#
# Env: WORKSPACE, RESPONDER, REPO_DIR, XFLEET_COORDINATION_ROOT, XFLEET_REDIS_URL, PATH.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/eval-lib.sh
source "${SCRIPT_DIR}/../../../lib/eval-lib.sh"

ROOT="${XFLEET_COORDINATION_ROOT}"

# The guard must have prevented all deletion.
[[ -f "${ROOT}/resolutions/r-1.md" ]];      eval_check $? "guard aborted: resolutions/r-1.md preserved"
[[ -f "${ROOT}/specs/feature-section.md" ]]; eval_check $? "guard aborted: specs/feature-section.md preserved"
[[ -f "${ROOT}/concerns/c-1.md" ]];         eval_check $? "guard aborted: concerns/c-1.md preserved"
[[ -f "${ROOT}/state/${RESPONDER}.json" ]]; eval_check $? "guard aborted: state/${RESPONDER}.json preserved"

# Redis streams must not have been flushed (abort precedes the flush step).
[[ "$(eval_redis EXISTS "inbox:${RESPONDER}")" -eq 1 ]]; eval_check $? "guard aborted: inbox:${RESPONDER} not flushed"
[[ "$(eval_redis EXISTS "inbox:orchestrator")" -eq 1 ]]; eval_check $? "guard aborted: inbox:orchestrator not flushed"

printf -- '--- %s assertion(s) failed ---\n' "${EVAL_FAILS}"
[[ "${EVAL_FAILS}" -eq 0 ]]
