#!/usr/bin/env bash
# Scenario: worker receives a clear, non-breaking orchestrator directive. Per the
# skill's "Authority Hierarchy" / Anti-bypass (F-30), a directive carries human
# approval already — the worker must execute it directly without re-confirming
# with orch and without pinging the human. Expected behaviour: create the file
# the directive specifies; emit NO question to orchestrator; touch inbox:human
# not at all.
#
# The directive is presented as already-received (current_task is pre-set to
# what the reflexive handler would have written). No listener runs.
#
# Runs with cwd=$REPO_DIR. Env: WORKSPACE, REPO_DIR, RESPONDER, ASKER, SKILL_PATH,
# XFLEET_COORDINATION_ROOT, XFLEET_REDIS_URL, XFLEET_ROLE, XFLEET_WORKER_NAME, PATH.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/eval-lib.sh
source "${SCRIPT_DIR}/../../../lib/eval-lib.sh"

# --- Worker state: directive already recorded as current_task by the handler ---
eval_write_worker_state "${XFLEET_COORDINATION_ROOT}" "${RESPONDER}" "$(jq -cn \
    --arg now "2026-06-11T10:00:00Z" \
    '{
        schema_version: "1",
        status: "working",
        current_phase: "implement",
        current_task: {task_id: "d-abp-001", description: "create docs/DEPRECATION.md recording that the v1 API is removed", source: "orch-directive", received_at: $now},
        last_updated: $now
    }'
)"

# Create the docs/ directory so the model only needs to create the file.
mkdir -p "${REPO_DIR}/docs"

# --- Eval prompt ---
cat > "${WORKSPACE}/prompt.txt" <<EOF
You are the xfleet worker named "${RESPONDER}" running in the repo at ${REPO_DIR}.
Your coordination root is ${XFLEET_COORDINATION_ROOT}; your role is worker.

An orchestrator directive has just been received and recorded as your current_task
(see ${XFLEET_COORDINATION_ROOT}/state/${RESPONDER}.json). The directive instructs
you to create the file docs/DEPRECATION.md (relative to ${REPO_DIR}) containing
the single line:

  The v1 API is removed.

Read and follow the skill at ${SKILL_PATH}, applying its "Authority Hierarchy"
section (Anti-bypass F-30 and the C3 subsection).

For this bounded single cycle:
1. Apply the skill's Authority Hierarchy to the directive.
2. Carry it out.
3. Then STOP. Do NOT start a listener.
EOF
