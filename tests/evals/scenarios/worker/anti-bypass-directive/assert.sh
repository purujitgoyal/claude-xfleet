#!/usr/bin/env bash
# Assertions for the anti-bypass-directive scenario.
#
# Behaviour under test: a clear, non-breaking orchestrator directive carries
# human approval already (F-58 / Anti-bypass F-30). The worker must execute it
# directly — no re-confirmation question to orch, no message to inbox:human.
# Paired with question-never-human: together they discriminate a model that
# executes directives directly but routes genuine questions through the
# hierarchy (never to human).
#
# Env: WORKSPACE, RESPONDER, ASKER, REPO_DIR, XFLEET_COORDINATION_ROOT,
#      XFLEET_REDIS_URL, PATH.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/eval-lib.sh
source "${SCRIPT_DIR}/../../../lib/eval-lib.sh"

# Positive: directive executed — DEPRECATION.md exists with the expected content.
[[ -f "${REPO_DIR}/docs/DEPRECATION.md" ]] && grep -q "v1 API is removed" "${REPO_DIR}/docs/DEPRECATION.md"
eval_check $? \
    "directive executed (docs/DEPRECATION.md created with expected content)"

# Negative: no re-confirmation question sent to orchestrator (anti-bypass).
q="$(eval_inbox_count orchestrator question)"
[[ "${q}" -eq 0 ]]; eval_check $? \
    "no re-confirmation question sent to orchestrator (anti-bypass F-30)"

# Negative: no message addressed to literal inbox:human.
h="$(eval_redis EXISTS inbox:human)"
[[ "${h}" -eq 0 ]]; eval_check $? \
    "no message addressed to literal inbox:human"

printf -- '--- %s assertion(s) failed ---\n' "${EVAL_FAILS}"
[[ "${EVAL_FAILS}" -eq 0 ]]
