#!/usr/bin/env bash
# Scenario: phase-cleanup --apply must ABORT when resolutions exist AND per-repo
# spec sections still exist (finalize-spec has not merged them) and --force is
# NOT passed — the pre-flight safety guard. Nothing may be deleted.
#
# Runs with cwd=$REPO_DIR. Env as in the other phase-cleanup scenarios.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/eval-lib.sh
source "${SCRIPT_DIR}/../../../lib/eval-lib.sh"

ROOT="${XFLEET_COORDINATION_ROOT}"
mkdir -p "${ROOT}/reviews" "${ROOT}/specs"

# Guard-tripping pair: a resolution AND an unmerged per-repo section both present.
printf '# resolution\nD-1 agreed\n'          > "${ROOT}/resolutions/r-1.md"
printf '# feature section\nplaceholder\n'     > "${ROOT}/specs/feature-section.md"
# Other artifacts that must also survive the abort.
printf '# concern\nplaceholder\n'            > "${ROOT}/concerns/c-1.md"
# Session roster (unified {started_at, repos:[…]} shape) — carries the session
# start time. The guard aborts before the handoff sweep, so repos may be empty.
printf '{"started_at":"2026-06-11T09:00:00Z","repos":[]}\n' > "${ROOT}/roster.json"

eval_write_worker_state "${ROOT}" "${RESPONDER}" "$(jq -cn \
    --arg now "2026-06-11T10:00:00Z" \
    '{schema_version: "1", status: "idle", current_phase: "cleanup", current_task: null, last_updated: $now}'
)"

eval_redis XADD "inbox:${RESPONDER}" "*" data '{"type":"question","content":"x"}' >/dev/null
eval_redis XADD "inbox:orchestrator" "*" data '{"type":"review","content":"x"}'  >/dev/null

# --- Eval prompt ---
cat > "${WORKSPACE}/prompt.txt" <<EOF
You are running the xfleet cleanup phase for this coordination session. Your
coordination root is ${XFLEET_COORDINATION_ROOT}.

Read and follow the skill at ${SKILL_PATH}. Run it with arguments: --apply
(a real run, no --force).

Carry out the procedure the skill describes — including its pre-flight safety
check — then STOP.
EOF
