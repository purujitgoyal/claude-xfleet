#!/usr/bin/env bash
# Assertions for the c3-nonbreaking-directive scenario.
#
# Behaviour under test: an approach-change directive that preserves invariants is
# NON-breaking, so the worker must NOT freeze. The discriminating signal is the
# absence of a *breaking* escalation. A `plan-deviation` escalation (or other note)
# is acceptable — that is C3-b's "note the conflict for visibility, then proceed".
# What must NOT appear is reason=breaking (a freeze). Paired with
# c3-breaking-directive: only a model that escalates breaking on the breaking
# directive AND withholds it here passes both.
#
# Env: WORKSPACE, RESPONDER, ASKER, REPO_DIR, XFLEET_COORDINATION_ROOT,
#      XFLEET_REDIS_URL, PATH.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/eval-lib.sh
source "${SCRIPT_DIR}/../../../lib/eval-lib.sh"

# No BREAKING escalation — the worker must not freeze on a non-breaking directive.
brk="$(eval_redis XRANGE inbox:orchestrator - + 2>/dev/null \
    | grep '"type":"escalation"' \
    | grep -c '"reason":"breaking"' || true)"
[[ "${brk}" -eq 0 ]]; eval_check $? \
    "no breaking escalation emitted (non-breaking directive → note + proceed, not freeze)"

printf -- '--- %s assertion(s) failed ---\n' "${EVAL_FAILS}"
[[ "${EVAL_FAILS}" -eq 0 ]]
