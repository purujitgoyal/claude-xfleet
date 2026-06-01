#!/usr/bin/env bats
# ip-close-flow.bats — Integration test for the Cluster-5 IP-close path.
#
# DETERMINISTIC DISPATCH APPROACH:
#   Like e2e-flow.bats, this test drives dispatch_message SYNCHRONOUSLY after
#   each sender subcommand XADD's a message. This exercises the identical
#   dispatch path the real listener uses (dispatch.sh dispatch_message()) without
#   racing a background process.
#
# FLOW UNDER TEST:
#   (a) drift-check: run xfleet drift-check against a clean fixture contract;
#       assert ip_self_check["IP-1"]["C-1"] == "drift-clean".
#   (b) integration-ready: run xfleet integration-ready --ip 1 (worker role);
#       assert integration-ready message lands on inbox:orchestrator.
#   (c) dispatch: feed the message through dispatch_message (orch role);
#       assert _orchestrator.json integration_readiness["IP-1"][WORKER] == true.
#   (d) schema validity: both state files pass validate-state.sh.

bats_require_minimum_version 1.5.0

# ---------------------------------------------------------------------------
# Path constants
# ---------------------------------------------------------------------------
REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
SUBCOMMANDS="${REPO_ROOT}/tools/xfleet/subcommands"
LIB_DIR="${REPO_ROOT}/tools/xfleet/lib"
DISPATCH_SH="${LIB_DIR}/dispatch.sh"
VALIDATE_SH="${REPO_ROOT}/tools/xfleet/validate-state.sh"

# Worker name with PID suffix to avoid cross-run contamination.
WORKER_NAME="iptest_$$"

# ---------------------------------------------------------------------------
# setup / teardown
# ---------------------------------------------------------------------------

setup() {
    # Load redis guard helpers.
    load "../lib/redis-guard.bash"

    export XFLEET_PYTHON="/Users/purujit/.config/xfleet/venv/bin/python"
    export XFLEET_REDIS_URL="${XFLEET_REDIS_URL:-${XFLEET_TEST_REDIS_URL}}"
    export CLAUDE_PLUGIN_ROOT="${REPO_ROOT}"

    # Temp coordination root under BATS_TMPDIR.
    COORD_ROOT="${BATS_TMPDIR}/xfleet-ip-close-$$"
    mkdir -p "${COORD_ROOT}/state"
    export XFLEET_COORDINATION_ROOT="${COORD_ROOT}"

    # Seed schema-valid orchestrator state.
    cat > "${COORD_ROOT}/state/_orchestrator.json" <<'ORCH_JSON'
{"schema_version": "1"}
ORCH_JSON

    # Seed schema-valid worker state.
    local now
    now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    cat > "${COORD_ROOT}/state/${WORKER_NAME}.json" <<WORKER_JSON
{
  "schema_version": "1",
  "current_phase": "implement",
  "status": "working",
  "current_task": null,
  "last_updated": "${now}",
  "context_pct": 20
}
WORKER_JSON

    # Build a throwaway fixture module that MATCHES the canonical shape.
    # We put it in the temp coordination root so PYTHONPATH can find it.
    mkdir -p "${COORD_ROOT}/fixture"
    cat > "${COORD_ROOT}/fixture/ip_close_fixture.py" <<'FIXTURE_PY'
from pydantic import BaseModel
from typing import Optional

class IpCloseModel(BaseModel):
    item_id: str
    value: int
    label: Optional[str] = None
FIXTURE_PY

    # Build the contracts.md fixture using Template B format.
    # The canonical shape and the fixture module use the same field layout so
    # drift_check.py sees no diff.
    cat > "${COORD_ROOT}/contracts.md" <<CONTRACTS_MD
## C-1 — IP-close fixture contract

**Type:** Internal
**Direction:** ${WORKER_NAME} → orchestrator
**Contributing repos:** ${WORKER_NAME}
**First introduced:** test
**Locked at:** IP-1 close
**Last amended:** —
**Change classification (since lock):** —

### Canonical shape (Pydantic, source of truth)

\`\`\`python
from pydantic import BaseModel
from typing import Optional

class IpCloseModel(BaseModel):
    item_id: str
    value: int
    label: Optional[str] = None
\`\`\`

### Intent (human-authored)

- **Purpose:** throwaway fixture for ip-close-flow integration test.

### Verification at IP close (when in scope)

- **Drift check (deterministic, T1):**
  - ${WORKER_NAME} (\`ip_close_fixture:IpCloseModel\`): \`xfleet drift-check --contract C-1 --repo ${WORKER_NAME}\`

### Amendments

_None yet._
CONTRACTS_MD

    # Flush test inbox streams from any previous run.
    redis-cli -u "${XFLEET_REDIS_URL}" DEL "inbox:orchestrator" "inbox:${WORKER_NAME}" >/dev/null 2>&1 || true
}

teardown() {
    redis-cli -u "${XFLEET_REDIS_URL}" DEL "inbox:orchestrator" "inbox:${WORKER_NAME}" >/dev/null 2>&1 || true
    rm -rf "${COORD_ROOT}"
}

# ---------------------------------------------------------------------------
# Helpers (mirrored from e2e-flow.bats)
# ---------------------------------------------------------------------------
read_last_msg_of_type() {
    local stream="$1"
    local msg_type="$2"
    local raw
    raw="$(redis-cli -u "${XFLEET_REDIS_URL}" XRANGE "${stream}" - + 2>/dev/null)"
    printf '%s' "${raw}" | awk '/^\{/{print}' | while IFS= read -r line; do
        t="$(printf '%s' "${line}" | jq -r '.type // empty' 2>/dev/null)"
        if [[ "${t}" == "${msg_type}" ]]; then
            printf '%s' "${line}"
        fi
    done | tail -1
}

dispatch_as() {
    local role="$1"
    local worker_name="$2"
    local msg_json="$3"

    (
        export XFLEET_ROLE="${role}"
        export XFLEET_WORKER_NAME="${worker_name}"
        export XFLEET_COORDINATION_ROOT="${XFLEET_COORDINATION_ROOT}"
        export XFLEET_REDIS_URL="${XFLEET_REDIS_URL}"
        export XFLEET_PYTHON="${XFLEET_PYTHON}"
        export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"

        # shellcheck disable=SC1090
        source "${DISPATCH_SH}"
        dispatch_message "${msg_json}"
    )
}

# ===========================================================================
# STEP (a): drift-check against a CLEAN fixture contract
# ===========================================================================

@test "step_a: drift-check against clean fixture writes ip_self_check[IP-1][C-1]=drift-clean" {
    # No redis needed — drift-check is worker-local (reads contracts.md, writes state).

    export XFLEET_ROLE=worker
    export XFLEET_WORKER_NAME="${WORKER_NAME}"
    # Point repo root at the fixture dir so XFLEET_WORKER_REPO_ROOT is set.
    export XFLEET_WORKER_REPO_ROOT="${COORD_ROOT}/fixture"
    # Use the xfleet venv interpreter for both sides — the fixture only needs pydantic.
    export XFLEET_REPO_PYTHON="${XFLEET_PYTHON}"
    # Set PYTHONPATH so extract_repo_shape.py can import the throwaway module.
    export PYTHONPATH="${COORD_ROOT}/fixture${PYTHONPATH:+:${PYTHONPATH}}"

    run bash "${SUBCOMMANDS}/drift-check.sh" \
        --contract "C-1" \
        --repo "${WORKER_NAME}" \
        --ip "IP-1" \
        --contracts-file "${COORD_ROOT}/contracts.md"

    [ "$status" -eq 0 ]

    # Worker state must have ip_self_check["IP-1"]["C-1"] == "drift-clean".
    local check_val
    check_val="$(jq -r '.ip_self_check["IP-1"]["C-1"]' \
        "${COORD_ROOT}/state/${WORKER_NAME}.json")"
    [ "${check_val}" = "drift-clean" ]
}

# ===========================================================================
# STEP (b): integration-ready signal reaches inbox:orchestrator
# ===========================================================================

@test "step_b: integration-ready --ip 1 publishes integration-ready to inbox:orchestrator" {
    if ! redis_available; then
        skip "redis unavailable"
    fi

    export XFLEET_ROLE=worker
    export XFLEET_WORKER_NAME="${WORKER_NAME}"

    run bash "${SUBCOMMANDS}/integration-ready.sh" --ip 1

    [ "$status" -eq 0 ]

    # Message must have landed in inbox:orchestrator.
    local msg
    msg="$(read_last_msg_of_type "inbox:orchestrator" "integration-ready")"
    [ -n "${msg}" ]

    local msg_type
    msg_type="$(printf '%s' "${msg}" | jq -r '.type')"
    [ "${msg_type}" = "integration-ready" ]

    local msg_ip
    msg_ip="$(printf '%s' "${msg}" | jq -r '.ip')"
    [ "${msg_ip}" = "IP-1" ]

    local msg_repo
    msg_repo="$(printf '%s' "${msg}" | jq -r '.repo')"
    [ "${msg_repo}" = "${WORKER_NAME}" ]
}

# ===========================================================================
# STEP (c): dispatch_message(integration-ready) writes integration_readiness
# ===========================================================================
# dispatch_message takes the message as an argument (the real listener reads it
# from redis, but dispatch itself does not), so this step drives it with a
# synthetic integration-ready message and needs no redis. The redis XADD
# round-trip is covered by step (b).

@test "step_c: dispatch_message(integration-ready) as orchestrator sets integration_readiness[IP-1][WORKER]=true" {
    # Synthetic integration-ready message (same shape integration-ready.sh emits;
    # dispatch reads .type/.repo/.ip).
    local ir_msg
    ir_msg="$(jq -cn --arg w "${WORKER_NAME}" \
        '{type:"integration-ready", worker:$w, repo:$w, ip:"IP-1", id:"ip-close-test", timestamp:"2026-06-01T00:00:00Z"}')"

    # Orchestrator dispatches the message synchronously.
    dispatch_as "orchestrator" "" "${ir_msg}"

    # Assert: integration_readiness["IP-1"][WORKER_NAME] == true.
    local readiness_val
    readiness_val="$(jq -r --arg w "${WORKER_NAME}" \
        '.integration_readiness["IP-1"][$w]' \
        "${COORD_ROOT}/state/_orchestrator.json")"
    [ "${readiness_val}" = "true" ]
}

# ===========================================================================
# STEP (d): final state validity after the full IP-close flow
# ===========================================================================

@test "step_d: _orchestrator.json and WORKER.json both pass validate-state.sh after IP-close flow" {
    # Full IP-close flow end to end (drift-check + dispatch), redis-independent:
    # the dispatch step uses a synthetic message (step b covers the redis path).

    # (a) drift-check (writes ip_self_check on the worker state).
    export XFLEET_ROLE=worker
    export XFLEET_WORKER_NAME="${WORKER_NAME}"
    export XFLEET_WORKER_REPO_ROOT="${COORD_ROOT}/fixture"
    export XFLEET_REPO_PYTHON="${XFLEET_PYTHON}"
    export PYTHONPATH="${COORD_ROOT}/fixture${PYTHONPATH:+:${PYTHONPATH}}"
    bash "${SUBCOMMANDS}/drift-check.sh" \
        --contract "C-1" \
        --repo "${WORKER_NAME}" \
        --ip "IP-1" \
        --contracts-file "${COORD_ROOT}/contracts.md"

    # (c) orchestrator dispatches a synthetic integration-ready signal
    #     (writes integration_readiness on the orchestrator state).
    local ir_msg
    ir_msg="$(jq -cn --arg w "${WORKER_NAME}" \
        '{type:"integration-ready", worker:$w, repo:$w, ip:"IP-1", id:"ip-close-test", timestamp:"2026-06-01T00:00:00Z"}')"
    dispatch_as "orchestrator" "" "${ir_msg}"

    # (d) schema validation: both state files must pass.
    run bash "${VALIDATE_SH}" "${COORD_ROOT}/state/_orchestrator.json" "orchestrator"
    [ "$status" -eq 0 ]

    run bash "${VALIDATE_SH}" "${COORD_ROOT}/state/${WORKER_NAME}.json" "worker"
    [ "$status" -eq 0 ]
}
