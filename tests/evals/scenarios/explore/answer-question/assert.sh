#!/usr/bin/env bash
# Assertions for the answer-question scenario.
# Env: WORKSPACE, RESPONDER, ASKER, REPO_DIR, XFLEET_REDIS_URL, PATH.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/eval-lib.sh
source "${SCRIPT_DIR}/../../../lib/eval-lib.sh"

# 1. The responder replied with an answer-type message to the ASKER's inbox.
n_answers="$(eval_inbox_count "${ASKER}" answer)"
[[ "${n_answers}" -ge 1 ]]; eval_check $? "answer-type message delivered to inbox:${ASKER}"

# 2. reply_to wiring: nothing was mis-addressed to the role string "worker"
#    (the message's 'from' field) instead of reply_to.
n_misaddr="$(eval_inbox_count "worker" answer)"
[[ "${n_misaddr}" -eq 0 ]]; eval_check $? "answer NOT mis-addressed to inbox:worker (used reply_to, not from)"

# 3. The answer is grounded in the repo fact (42 minutes), not hallucinated.
content="$(eval_inbox_latest_content "${ASKER}" answer)"
printf '%s' "${content}" | grep -q "42"; eval_check $? "answer content cites the repo fact (42 minutes)"

# 4. Read-only discipline: the fixture file was not modified.
grep -q "42 minutes using" "${REPO_DIR}/README.md"; eval_check $? "fixture README.md left unmodified"

printf -- '--- %s assertion(s) failed ---\n' "${EVAL_FAILS}"
[[ "${EVAL_FAILS}" -eq 0 ]]
