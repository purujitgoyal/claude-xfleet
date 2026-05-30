#!/usr/bin/env python3
"""Self-executing jsonschema tests for tools/xfleet/state-schema.json.

Invoked directly by tests/run-all.sh as `"$XFLEET_PYTHON" test_schema.py`
(NOT via pytest). Runs assertions under __main__, prints pass/fail per case,
and exits non-zero if any case fails.

The schema ships as a single artifact with two $defs: `orchestrator` (for
_orchestrator.json) and `worker` (for {worker}.json). Each $def is fully
self-contained (no cross-$def $ref), so each case validates against the relevant
$def subschema directly under Draft 2020-12.
"""

import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

SCHEMA_PATH = (
    Path(__file__).resolve().parent.parent.parent
    / "tools"
    / "xfleet"
    / "state-schema.json"
)


def load_schema():
    with SCHEMA_PATH.open() as fh:
        return json.load(fh)


def validator_for(schema, def_name):
    """Build a Draft202012Validator scoped to schema['$defs'][def_name].

    Each $def is self-contained, so it validates as a standalone subschema.
    """
    return Draft202012Validator(schema["$defs"][def_name])


def is_valid(validator, instance):
    return not list(validator.iter_errors(instance))


# ---- Fixtures: minimal-but-complete valid instances --------------------------

VALID_ORCHESTRATOR = {
    "schema_version": "1",
    "cycles": 0,
    "last_all_idle_notify": None,
    "last_round5_pause": "2026-05-30T10:45:00Z",
    "phase_emissions": {
        "plan": {
            "phase-complete": {
                "approved_by_human": True,
                "sent_at": "2026-05-30T10:45:00Z",
                "sent_to": ["server", "web"],
                "emission_id": "emit-abc-123",
            }
        }
    },
    "emission_log": [
        {
            "phase": "plan",
            "signal": "phase-complete",
            "attempted_at": "2026-05-30T10:45:00Z",
            "approved_by_human": True,
            "emission_id": "emit-abc-123",
            "outcome": "sent",
        }
    ],
    "human_engaged": {
        "active": True,
        "concern_id": "concern-1",
        "set_at": "2026-05-30T10:45:00Z",
        "reason": "directive dispatched",
    },
    "completion_log": [
        {
            "evaluated_at": "2026-05-30T10:45:00Z",
            "trigger_msg_type": "phase-complete",
            "outcome": "incomplete",
            "missing_workers": ["oracle"],
            "missing_signals": ["review"],
        }
    ],
    "directive_log": [
        {
            "directive_id": "dir-1",
            "target": "server",
            "concern_id": None,
            "scope": "schema-change",
            "expected_action": "update validator",
            "dispatched_at": "2026-05-30T10:45:00Z",
            "response_status": "pending",
        }
    ],
    "task_log": [
        {
            "task_id": "task-1",
            "target": "web",
            "task_kind": "implement",
            "dispatched_at": "2026-05-30T10:45:00Z",
            "response_status": "pending",
        }
    ],
    "escalation_log": [
        {
            "escalation_id": "esc-1",
            "source_worker": "server",
            "reason": "breaking",
            "path": "$XFLEET_COORDINATION_ROOT/escalations/esc-1.md",
            "priority": "urgent",
            "received_at": "2026-05-30T10:45:00Z",
            "surfaced_at": "2026-05-30T10:46:00Z",
            "resolved_at": None,
        }
    ],
}

VALID_WORKER = {
    "schema_version": "1",
    "current_phase": "plan",
    "status": "working",
    "current_task": {
        "task_id": "task-1",
        "description": "implement validator",
        "source": "orch-task",
        "received_at": "2026-05-30T10:45:00Z",
    },
    "last_updated": "2026-05-30T10:45:00Z",
    "listen_bash_id": "bash-42",
    "standby": False,
    "context_pct": 37,
    "review_revision_count": 0,
    "findings_status": {
        "finding-1": "new",
        "finding-2": "resolved",
    },
    "confirmed_closed_concerns": ["concern-1", "concern-2"],
    "last_warn_emitted_at": None,
    "last_check_at": "2026-05-30T10:40:00Z",
}


# ---- Test cases --------------------------------------------------------------


def run_cases():
    schema = load_schema()
    orch = validator_for(schema, "orchestrator")
    worker = validator_for(schema, "worker")

    results = []

    def check(name, condition):
        results.append((name, bool(condition)))

    # (a) valid _orchestrator.json passes
    check("(a) valid orchestrator instance passes", is_valid(orch, VALID_ORCHESTRATOR))

    # (b) valid {worker}.json passes
    check("(b) valid worker instance passes", is_valid(worker, VALID_WORKER))

    # (c) unknown key at top level -> fails (orchestrator)
    bad = dict(VALID_ORCHESTRATOR)
    bad["bogus_top_level"] = 1
    check("(c) unknown top-level key rejected (orchestrator)", not is_valid(orch, bad))

    # (c2) unknown key at top level -> fails (worker)
    bad = dict(VALID_WORKER)
    bad["bogus_top_level"] = 1
    check("(c2) unknown top-level key rejected (worker)", not is_valid(worker, bad))

    # (d) unknown key in a NESTED map-value object -> fails (recursive-strict)
    bad = json.loads(json.dumps(VALID_ORCHESTRATOR))
    bad["phase_emissions"]["plan"]["phase-complete"]["bogus"] = 1
    check(
        "(d) unknown nested key in phase_emissions value rejected",
        not is_valid(orch, bad),
    )

    # (d2) unknown key in a nested fixed-key object (human_engaged) -> fails
    bad = json.loads(json.dumps(VALID_ORCHESTRATOR))
    bad["human_engaged"]["bogus"] = 1
    check(
        "(d2) unknown nested key in human_engaged rejected",
        not is_valid(orch, bad),
    )

    # (d3) unknown key inside an array element object -> fails
    bad = json.loads(json.dumps(VALID_ORCHESTRATOR))
    bad["emission_log"][0]["bogus"] = 1
    check(
        "(d3) unknown key in emission_log element rejected",
        not is_valid(orch, bad),
    )

    # (e) wrong type for cycles (string) -> fails
    bad = dict(VALID_ORCHESTRATOR)
    bad["cycles"] = "0"
    check("(e) wrong type for cycles (string) rejected", not is_valid(orch, bad))

    # (e2) wrong type for worker context_pct (string) -> fails
    bad = dict(VALID_WORKER)
    bad["context_pct"] = "37"
    check("(e2) wrong type for context_pct (string) rejected", not is_valid(worker, bad))

    # (e3) context_pct above max (150) -> fails
    bad = dict(VALID_WORKER)
    bad["context_pct"] = 150
    check("(e3) context_pct above maximum (150) rejected", not is_valid(worker, bad))

    # (e4) context_pct below min (-1) -> fails
    bad = dict(VALID_WORKER)
    bad["context_pct"] = -1
    check("(e4) context_pct below minimum (-1) rejected", not is_valid(worker, bad))

    # (f) missing schema_version -> fails (both objects)
    bad = dict(VALID_ORCHESTRATOR)
    del bad["schema_version"]
    check("(f) missing schema_version rejected (orchestrator)", not is_valid(orch, bad))

    bad = dict(VALID_WORKER)
    del bad["schema_version"]
    check("(f2) missing schema_version rejected (worker)", not is_valid(worker, bad))

    # (g) schema_version wrong value -> fails (const "1")
    bad = dict(VALID_ORCHESTRATOR)
    bad["schema_version"] = "99"
    check("(g) wrong schema_version value rejected (orchestrator)", not is_valid(orch, bad))

    bad = dict(VALID_WORKER)
    bad["schema_version"] = "99"
    check("(g2) wrong schema_version value rejected (worker)", not is_valid(worker, bad))

    # extra: nullable field accepts the non-null form (resolved_at as ISO)
    ok = json.loads(json.dumps(VALID_ORCHESTRATOR))
    ok["escalation_log"][0]["resolved_at"] = "2026-05-30T11:00:00Z"
    check("(h) nullable resolved_at accepts ISO string", is_valid(orch, ok))

    # extra: current_task null is accepted
    ok = dict(VALID_WORKER)
    ok["current_task"] = None
    check("(h2) worker current_task null accepted", is_valid(worker, ok))

    # extra: bad findings_status enum value -> fails
    bad = json.loads(json.dumps(VALID_WORKER))
    bad["findings_status"]["finding-1"] = "bogus-status"
    check("(i) invalid findings_status enum value rejected", not is_valid(worker, bad))

    # extra: bad current_task.source enum -> fails
    bad = json.loads(json.dumps(VALID_WORKER))
    bad["current_task"]["source"] = "nope"
    check("(i2) invalid current_task.source enum rejected", not is_valid(worker, bad))

    # extra: bad worker status enum -> fails
    bad = dict(VALID_WORKER)
    bad["status"] = "not-a-status"
    check("(i3) invalid worker status enum rejected", not is_valid(worker, bad))

    return results


def main():
    try:
        results = run_cases()
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL: test harness raised: {exc!r}", file=sys.stderr)
        return 1

    failures = 0
    for name, passed in results:
        marker = "ok" if passed else "FAIL"
        print(f"  {marker}  {name}")
        if not passed:
            failures += 1

    print("")
    total = len(results)
    if failures:
        print(f"{failures}/{total} state-schema assertions FAILED.", file=sys.stderr)
        return 1
    print(f"All {total} state-schema assertions passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
