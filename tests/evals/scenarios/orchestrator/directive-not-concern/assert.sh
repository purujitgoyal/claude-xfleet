#!/usr/bin/env bash
# Assertions for the orchestrator directive-not-concern scenario.
#
# Behaviour under test: an orch correcting a worker must use `xfleet directive`
# (orch-only sender) — never originate a concern/escalation (worker-only). The
# directive dispatch also auto-sets human_engaged (cluster 4a).
#
# Env: WORKSPACE, REPO_DIR, XFLEET_COORDINATION_ROOT, XFLEET_REDIS_URL, PATH.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/eval-lib.sh
source "${SCRIPT_DIR}/../../../lib/eval-lib.sh"

ROOT="${XFLEET_COORDINATION_ROOT}"

# Positive: a directive was dispatched to server.
d="$(eval_inbox_count server directive)"
[[ "${d}" -ge 1 ]]; eval_check $? \
    "correction sent to server via xfleet directive (directive in inbox:server)"

# Positive: directive dispatch auto-set human_engaged.active=true (cluster 4a).
he="$(jq -r '.human_engaged.active // false' "${ROOT}/state/_orchestrator.json" 2>/dev/null || echo "false")"
[[ "${he}" == "true" ]]; eval_check $? \
    "directive dispatch auto-set human_engaged.active=true"

# Positive: the directive was recorded in directive_log.
dl="$(jq -r '(.directive_log // []) | length' "${ROOT}/state/_orchestrator.json" 2>/dev/null || echo 0)"
[[ "${dl}" -ge 1 ]]; eval_check $? \
    "directive recorded in directive_log"

# Negative: orch did NOT originate a concern toward server (worker-only sender).
c="$(eval_inbox_count server concern)"
[[ "${c}" -eq 0 ]]; eval_check $? \
    "did not originate a concern (orch is not a concern sender)"

printf -- '--- %s assertion(s) failed ---\n' "${EVAL_FAILS}"
[[ "${EVAL_FAILS}" -eq 0 ]]
