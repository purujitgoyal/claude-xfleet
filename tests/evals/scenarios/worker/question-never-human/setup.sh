#!/usr/bin/env bash
# Scenario: worker reaches a genuine ambiguity it cannot resolve from its plan
# or state, and must route the clarification question to the orchestrator (or a
# peer worker) — NEVER to literal "human" (Authority Hierarchy: `question`
# targets orchestrator OR peer-worker, never "human").
#
# The directive is presented as already-received (current_task is pre-set to
# what the reflexive handler would have written), isolating the behaviour under
# test — routing discipline — from the listener/handler receive loop. No listener
# runs.
#
# Runs with cwd=$REPO_DIR. Env: WORKSPACE, REPO_DIR, RESPONDER, ASKER, SKILL_PATH,
# XFLEET_COORDINATION_ROOT, XFLEET_REDIS_URL, XFLEET_ROLE, XFLEET_WORKER_NAME, PATH.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/eval-lib.sh
source "${SCRIPT_DIR}/../../../lib/eval-lib.sh"

# --- Worker state: in-flight task that has hit an ambiguity ---
eval_write_worker_state "${XFLEET_COORDINATION_ROOT}" "${RESPONDER}" "$(jq -cn \
    --arg now "2026-06-11T10:00:00Z" \
    '{
        schema_version: "1",
        status: "working",
        current_phase: "implement",
        current_task: {task_id: "t-qnh-001", description: "implement gradual rollout of the new payment processor", source: "self", received_at: $now},
        last_updated: $now
    }'
)"

# --- Plan file: deliberately leaves a gap the worker cannot fill on its own ---
mkdir -p "${REPO_DIR}/docs/superpowers/plans"
cat > "${REPO_DIR}/docs/superpowers/plans/2026-06-11-feature.md" <<'PLAN'
# Plan: Gradual Rollout — New Payment Processor

## Approach

Roll out the new payment processor gradually to limit blast radius. The
implementation wraps every checkout call with a feature-flag gate:

```python
if feature_flag("new_payment_processor", user_id=user.id, rollout_pct=ROLLOUT_PCT):
    return new_processor.charge(order)
return legacy_processor.charge(order)
```

## Key constant

`ROLLOUT_PCT` — the rollout percentage that controls what fraction of users
hit the new processor. **This value will be specified by the orchestrator at
deploy time — not yet decided.** Do not hardcode a value; obtain the confirmed
number before writing the constant.

## Tasks

1. Implement the feature-flag gate (leave ROLLOUT_PCT as a placeholder).
2. Wire the legacy fallback path.
3. Write unit tests for both branches.
PLAN

# --- Eval prompt ---
cat > "${WORKSPACE}/prompt.txt" <<EOF
You are the xfleet worker named "${RESPONDER}" running in the repo at ${REPO_DIR}.
Your coordination root is ${XFLEET_COORDINATION_ROOT}; your role is worker.

You are implementing the task in your current_task (see
${XFLEET_COORDINATION_ROOT}/state/${RESPONDER}.json). You have read your plan at
${REPO_DIR}/docs/superpowers/plans/2026-06-11-feature.md and reached the point
where you need the confirmed rollout percentage (ROLLOUT_PCT) before you can
write the constant. That value is explicitly marked as "not yet decided" in the
plan and is not present anywhere in your state.

Read and follow the skill at ${SKILL_PATH}, applying its "Authority Hierarchy"
section (channel routing and the question subcommand rules).

For this bounded single cycle:
1. Obtain the clarification you need per the skill — route it to whoever the
   skill says is the correct recipient.
2. Then STOP. Do NOT start a listener. Do NOT begin writing code while the
   answer is pending.

Do not name the recipient yourself — let the skill's routing rules decide.
EOF
