#!/usr/bin/env bash
# Assertions for the question-never-human scenario.
#
# Behaviour under test: when the worker needs clarification it cannot resolve
# from its plan or state, it routes the question to the orchestrator (or a peer
# worker) via `xfleet question`. It must NEVER write to inbox:human directly
# (Authority Hierarchy: `question` targets orchestrator OR peer-worker, never
# "human"). Paired with the anti-bypass-directive scenario: only a model that
# routes questions through the hierarchy — not to human — passes both.
#
# Env: WORKSPACE, RESPONDER, ASKER, REPO_DIR, XFLEET_COORDINATION_ROOT,
#      XFLEET_REDIS_URL, PATH.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/eval-lib.sh
source "${SCRIPT_DIR}/../../../lib/eval-lib.sh"

# Positive: a question reached the orchestrator inbox.
q="$(eval_inbox_count orchestrator question)"
[[ "${q}" -ge 1 ]]; eval_check $? \
    "clarification question routed to orchestrator (question received in inbox:orchestrator)"

# Negative: nothing written to literal inbox:human (routing discipline).
h="$(eval_redis EXISTS inbox:human)"
[[ "${h}" -eq 0 ]]; eval_check $? \
    "no message addressed to literal inbox:human (question routed through hierarchy, not to human)"

printf -- '--- %s assertion(s) failed ---\n' "${EVAL_FAILS}"
[[ "${EVAL_FAILS}" -eq 0 ]]
