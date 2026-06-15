#!/usr/bin/env bash
# Scenario: phase-cleanup --apply, with the guard NOT tripped (resolutions exist
# but there are no unmerged per-repo sections — finalize-spec is effectively
# done), must EXECUTE: remove intermediate artifacts and flush the Redis streams.
#
# Safe on DB 15: the cleanup skill now routes redis-cli through $XFLEET_REDIS_URL,
# so the flush targets the sandbox DB, not the default instance.
#
# Runs with cwd=$REPO_DIR. Env as in the other phase-cleanup scenarios.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/eval-lib.sh
source "${SCRIPT_DIR}/../../../lib/eval-lib.sh"

ROOT="${XFLEET_COORDINATION_ROOT}"
mkdir -p "${ROOT}/reviews" "${ROOT}/specs"

# Resolutions present but NO specs/*-section.md → guard condition 2 is false →
# guard does not trip → --apply proceeds.
printf '# concern\nplaceholder\n'            > "${ROOT}/concerns/c-1.md"
printf '# resolution\nD-1 agreed\n'          > "${ROOT}/resolutions/r-1.md"
printf '# review\nplaceholder\n'             > "${ROOT}/reviews/rv-1.md"

eval_write_worker_state "${ROOT}" "${RESPONDER}" "$(jq -cn \
    --arg now "2026-06-11T10:00:00Z" \
    '{schema_version: "1", status: "idle", current_phase: "cleanup", current_task: null, last_updated: $now}'
)"

# Session roster (canonical repo-path + session-start source) in the unified
# {started_at, repos:[{name,path,slug}]} shape + a real phase-exit handoff at
# {path}/docs/superpowers/xfleet/{slug}/handoff-*.md for the sweep to remove.
SLUG="evalwave"
jq -cn --arg repo "${REPO_DIR}" --arg slug "${SLUG}" \
    '{started_at: "2026-06-11T09:00:00Z", repos: [{name: ($repo | split("/") | last), path: $repo, slug: $slug}]}' \
    > "${ROOT}/roster.json"
HANDOFF_DIR="${REPO_DIR}/docs/superpowers/xfleet/${SLUG}"
mkdir -p "${HANDOFF_DIR}"
printf '# handoff\nplaceholder\n' > "${HANDOFF_DIR}/handoff-implement.md"
# A non-handoff sibling in the same dir must be LEFT untouched (selective sweep).
printf '# section\nplaceholder\n' > "${HANDOFF_DIR}/section.md"

eval_redis XADD "inbox:${RESPONDER}" "*" data '{"type":"question","content":"x"}' >/dev/null
eval_redis XADD "inbox:orchestrator" "*" data '{"type":"review","content":"x"}'  >/dev/null
eval_redis SET "concern:test-1:rounds" 3 >/dev/null

# --- Eval prompt ---
cat > "${WORKSPACE}/prompt.txt" <<EOF
You are running the xfleet cleanup phase for this coordination session. Your
coordination root is ${XFLEET_COORDINATION_ROOT}.

Read and follow the skill at ${SKILL_PATH}. Run it with arguments: --apply
(a real run, no --force).

Carry out the procedure the skill describes — including its pre-flight safety
check — then STOP.
EOF
