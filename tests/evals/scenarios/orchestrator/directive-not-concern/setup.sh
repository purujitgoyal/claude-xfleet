#!/usr/bin/env bash
# Scenario: a worker's task-response reveals it is about to deviate from a locked
# cross-repo decision. The orch wants to correct it. Per the Wire Protocol
# cheat-sheet, orch NEVER originates concern/escalation/question — "if tempted to
# raise a concern, send a directive instead" (A3). The correct corrective channel
# is `xfleet directive <worker>`, which also auto-sets human_engaged (cluster 4a).
#
# Listener-free; single cycle. Orch state pre-seeded (subcommands hard-error if
# _orchestrator.json is absent).
#
# Runs with cwd=$REPO_DIR. Env: WORKSPACE, REPO_DIR, RESPONDER, SKILL_PATH,
# XFLEET_COORDINATION_ROOT, XFLEET_REDIS_URL, XFLEET_ROLE=orchestrator, PATH.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/eval-lib.sh
source "${SCRIPT_DIR}/../../../lib/eval-lib.sh"

ROOT="${XFLEET_COORDINATION_ROOT}"

eval_write_worker_state "${ROOT}" "server" "$(jq -cn \
    --arg now "2026-06-12T10:00:00Z" \
    '{schema_version: "1", status: "working", current_phase: "implement", current_task: null, last_updated: $now}'
)"

eval_write_orch_state "${ROOT}" '{"schema_version":"1","directive_log":[],"task_log":[],"human_engaged":{"active":false,"concern_id":null,"set_at":null,"reason":null}}'

# --- Eval prompt ---
cat > "${WORKSPACE}/prompt.txt" <<EOF
You are the xfleet ORCHESTRATOR for this coordination session. Your coordination
root is ${XFLEET_COORDINATION_ROOT}; your role is orchestrator.

The worker "server" just reported (task-response) that it intends to drop the
shared idempotency-key header from its API — but that header is a LOCKED
cross-repo decision other workers depend on. You need server to NOT drop it and
to keep the header per the locked decision.

Read and follow the skill at ${SKILL_PATH}, applying its "Wire Protocol —
Orch-as-Sender" rules (which channels an orchestrator may originate).

For this bounded single cycle:
1. Take the corrective action toward server that the skill prescribes for an
   orchestrator in this situation, emitting the appropriate xfleet message.
2. Then STOP. Do NOT start a listener.

Let the skill's sender-authority rules drive which channel you use — do not pick
one because this prompt named it.
EOF
