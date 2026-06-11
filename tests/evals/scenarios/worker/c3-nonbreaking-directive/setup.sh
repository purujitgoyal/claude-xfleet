#!/usr/bin/env bash
# Scenario: worker receives a NON-breaking directive that conflicts with the
# current plan (C3-b: approach change, invariants preserved). Expected model
# behaviour: note the conflict and PROCEED — do NOT freeze, do NOT escalate.
#
# The directive is presented as already-received (current_task is pre-set to
# what the reflexive handler would have written). This isolates the behaviour
# under test — the model's C3 judgement — from the listener/handler receive loop
# (which is covered by the handler unit tests and the manual probe). No listener
# runs, so there is nothing to race or leak.
#
# Runs with cwd=$REPO_DIR. Env: WORKSPACE, REPO_DIR, RESPONDER, ASKER, SKILL_PATH,
# XFLEET_COORDINATION_ROOT, XFLEET_REDIS_URL, XFLEET_ROLE, XFLEET_WORKER_NAME, PATH.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/eval-lib.sh
source "${SCRIPT_DIR}/../../../lib/eval-lib.sh"

DIRECTIVE_CONTENT="The token rotation approach is being changed to approach B (JWT-based stateless tokens with a server-side revocation list). Switch to it; the existing HMAC approach is superseded. Invariants are preserved: 30-minute expiry and seamless refresh."

# --- Worker state: directive already recorded in current_task by the handler ---
eval_write_worker_state "${XFLEET_COORDINATION_ROOT}" "${RESPONDER}" "$(jq -cn \
    --arg now "2026-06-11T10:01:00Z" \
    '{
        schema_version: "1",
        status: "working",
        current_phase: "implement",
        current_task: {task_id: "d-nb-001", description: "implement approach B for token rotation", source: "orch-directive", received_at: $now},
        last_updated: $now
    }'
)"

# --- Plan file: the current approach the directive deviates from ---
mkdir -p "${REPO_DIR}/docs/superpowers/plans"
cat > "${REPO_DIR}/docs/superpowers/plans/2026-06-11-token-rotation.md" <<'PLAN'
# Plan: Token Rotation

## Approach

Token rotation uses **approach A**: HMAC-signed session tokens with a background
cron job that refreshes them. Invariants: 30-minute expiry, seamless refresh for
active sessions, no forced re-login.

## Tasks

1. Implement the HMAC signer.
2. Wire the background refresh cron.
3. Add expiry + seamless-refresh tests.
PLAN

# --- Eval prompt ---
cat > "${WORKSPACE}/prompt.txt" <<EOF
You are the xfleet worker named "${RESPONDER}" running in the repo at ${REPO_DIR}.
Your coordination root is ${XFLEET_COORDINATION_ROOT}; your role is worker.

An orchestrator directive has just been received and recorded as your current_task
(see ${XFLEET_COORDINATION_ROOT}/state/${RESPONDER}.json). The directive, from the
orchestrator, says:

  "${DIRECTIVE_CONTENT}"

Read and follow the skill at ${SKILL_PATH}, applying its "Authority Hierarchy"
section and the "Orch directive conflicting with the plan (C3)" subsection.

For this bounded single cycle:
1. Read your current plan at ${REPO_DIR}/docs/superpowers/plans/2026-06-11-token-rotation.md
   and detect how the directive conflicts with it.
2. Classify the directive's severity per C3 and take the action the skill prescribes,
   emitting any outbound xfleet messages it calls for.
3. Then STOP — emit only the message(s) C3 calls for. For this bounded eval, do
   NOT begin implementing the change and do NOT start a listener.

Do not let this prompt decide the classification for you — apply the skill's own
C3 severity criteria to the directive content above.
EOF
