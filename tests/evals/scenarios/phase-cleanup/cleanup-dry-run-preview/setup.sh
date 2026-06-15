#!/usr/bin/env bash
# Scenario: phase-cleanup in DEFAULT (dry-run) mode must preview only — it makes
# NO changes. Seed a populated coordination root + Redis streams; after a no-flag
# run every artifact and stream must still be present.
#
# Runs with cwd=$REPO_DIR. Env: WORKSPACE, REPO_DIR, RESPONDER, ASKER, SKILL_PATH,
# XFLEET_COORDINATION_ROOT, XFLEET_REDIS_URL (DB 15), XFLEET_ROLE, XFLEET_WORKER_NAME, PATH.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/eval-lib.sh
source "${SCRIPT_DIR}/../../../lib/eval-lib.sh"

ROOT="${XFLEET_COORDINATION_ROOT}"
mkdir -p "${ROOT}/reviews" "${ROOT}/specs"

# --- Coordination artifacts that a real session would have accumulated ---
printf '# concern\nplaceholder\n'    > "${ROOT}/concerns/c-1.md"
printf '# resolution\nplaceholder\n' > "${ROOT}/resolutions/r-1.md"
printf '# review\nplaceholder\n'     > "${ROOT}/reviews/rv-1.md"

# Worker state (schema-valid; repo paths live in roster.json, not state).
eval_write_worker_state "${ROOT}" "${RESPONDER}" "$(jq -cn \
    --arg now "2026-06-11T10:00:00Z" \
    '{schema_version: "1", status: "idle", current_phase: "cleanup", current_task: null, last_updated: $now}'
)"

# Session roster (canonical source of repo paths + session start time for the
# handoff sweep) in the unified {started_at, repos:[{name,path,slug}]} shape + a real
# phase-exit handoff at {path}/docs/superpowers/xfleet/{slug}/handoff-*.md. Created
# now (mtime >> session start), so the sweep's mtime floor includes it.
SLUG="evalwave"
jq -cn --arg repo "${REPO_DIR}" --arg slug "${SLUG}" \
    '{started_at: "2026-06-11T09:00:00Z", repos: [{name: ($repo | split("/") | last), path: $repo, slug: $slug}]}' \
    > "${ROOT}/roster.json"
HANDOFF_DIR="${REPO_DIR}/docs/superpowers/xfleet/${SLUG}"
mkdir -p "${HANDOFF_DIR}"
printf '# handoff\nplaceholder\n' > "${HANDOFF_DIR}/handoff-implement.md"

# --- Redis streams + a round-counter key (DB 15 sandbox) ---
eval_redis XADD "inbox:${RESPONDER}" "*" data '{"type":"question","content":"x"}' >/dev/null
eval_redis XADD "inbox:orchestrator" "*" data '{"type":"review","content":"x"}'  >/dev/null
eval_redis SET "concern:test-1:rounds" 3 >/dev/null

# --- Eval prompt ---
cat > "${WORKSPACE}/prompt.txt" <<EOF
You are running the xfleet cleanup phase for this coordination session. Your
coordination root is ${XFLEET_COORDINATION_ROOT}.

Read and follow the skill at ${SKILL_PATH}. Run it with NO arguments — i.e. its
DEFAULT dry-run mode (a read-only preview).

Carry out the procedure the skill describes for dry-run mode, then STOP.
EOF
