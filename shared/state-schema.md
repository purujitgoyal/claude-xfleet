# xfleet State File Schema

> **Supersedes** the wave-1 personal-global `~/.claude/xfleet/shared/state-schema.md`
> (70 LOC prose-only doc). That doc was prose-only and not machine-enforced; this
> revision makes **`tools/xfleet/state-schema.json` the canonical source of truth
> for SHAPE** (sync-mechanism ADR, option 3). The wave-1 file is removed separately
> by the controller (SC-1); do not edit or delete it here.
>
> **This is the canonical reference for the two xfleet state files.** Path notation
> throughout uses `$XFLEET_COORDINATION_ROOT/...` (SC-2 G1); never hardcoded repo
> paths. The two state files live at:
>
> - `$XFLEET_COORDINATION_ROOT/state/_orchestrator.json` — orchestrator-private.
> - `$XFLEET_COORDINATION_ROOT/state/{worker}.json` — one per participating worker.
>
> Sibling docs in `shared/`: `messaging.md` (wire-message taxonomy),
> `design-principles.md` (F-35 + F-36), and `worker-config-schema.md`.

All timestamps are ISO-8601 UTC (e.g. `2026-05-30T10:45:00Z`). Both files carry a
required `schema_version` field whose value is the string `"1"` for this revision
(SC-6); the Task-18 validator and Task-19 migration helper key off it.

---

## Authoring layers

This doc has two layers, by design (sync-mechanism ADR, option 3):

1. **`tools/xfleet/state-schema.json`** — the JSON Schema validator. It is
   canonical for **shape**: field names, types, nullability, enums, required-ness,
   and the recursive `additionalProperties: false` strictness. It ships as a single
   artifact with two `$defs` — `orchestrator` (validates `_orchestrator.json`) and
   `worker` (validates `{worker}.json`). Each `$def` is self-contained so the
   Task-18 validator can select and validate against one without resolving the
   other.

2. **This Markdown doc** — owns what JSON Schema cannot express: lifecycle,
   cross-field invariants, writer/reader ownership, and worked examples. The
   **Field Reference** section below is **auto-generated** from the JSON Schema
   between the generated-block markers — do not hand-edit it. Regenerate with:

```
XFLEET_PYTHON=/path/to/venv/bin/python bash tools/xfleet/gen-state-schema-doc.sh
```

Every property in the JSON Schema MUST carry a `description:` keyword — the
generator and the Task-17b drift detector both depend on it. A property without a
description is a defect.

---

## Lifecycle

- **`_orchestrator.json`** is created lazily on first orchestrator write and must
  survive `/compact` on disk. It is orchestrator-private runtime bookkeeping.
- **`{worker}.json`** is written by the owning worker after every meaningful action
  (message handled, task started/completed, concern raised/resolved, pause/resume,
  context check). It always reflects the worker's current state.
- `review_revision_count`, `last_warn_emitted_at`, and `last_check_at` **reset on
  phase entry** (the warn/check debounce fields per cluster 4j). `last_warn_emitted_at`
  is additionally cleared when `context_pct` drops below the warn threshold.
- The append-only logs in `_orchestrator.json` (`emission_log`, `completion_log`,
  `directive_log`, `task_log`, `escalation_log`) grow monotonically across the
  session; they are audit trails, not live state.

### Derived — NOT stored

- **`prepare_compact_at`** is **not** a state field and is intentionally absent
  from the JSON Schema. It is **computed at read time** from the filesystem mtime
  of the most recent `handoff-{phase}.md`. Do not add it to either state file.

### Excluded — separate plan

The following fields belong to cluster 5 (a separate plan) and are intentionally
**not** part of this schema: `integration_readiness`, `ip_status`, `drift_log`,
`current_ip`, `ip_self_check`. Do not add them here.

---

## Cross-Field Invariants

These are contracts the JSON Schema cannot express; writers must uphold them.

- **`human_engaged.active` ⟺ engage-or-directive.** In `_orchestrator.json`,
  `human_engaged.active == true` **iff** `xfleet engage` was called OR a directive
  was dispatched (cluster 4a). It is auto-set on `xfleet directive` dispatch and is
  **never** auto-fired by escalation arrival; it is cleared by `xfleet disengage`.
  When `active == false`, `concern_id`, `set_at`, and `reason` are null.
- **`current_task` null ⟺ no active unit of work.** In `{worker}.json`,
  `current_task` is an object while a unit of work is in flight and `null`
  otherwise. A worker reporting `status == "working"` should carry a non-null
  `current_task`.
- **`emission_id` correlation.** Every `phase_emissions.{phase}.{signal}.emission_id`
  has a matching `emission_log[].emission_id` (and vice versa) for audit.
- **`escalation_log[].resolved_at`** is null while an escalation is open and set to
  the resolution timestamp once closed.

---

## Writer Ownership

| File | Writer | Readers |
|------|--------|---------|
| `_orchestrator.json` | the orchestrator session **only** | the orchestrator only (workers never read it) |
| `{worker}.json` | the owning worker session **only** (the worker whose short-name matches `{worker}`) | the owning worker (recovery after compact) and the orchestrator (via `xfleet status`: straggler check, all-idle check, routing) |

A worker never writes another worker's state file, and never writes
`_orchestrator.json`. The orchestrator never writes a worker's state file — it only
reads them through `xfleet status`.

---

## Field Reference

The table(s) below are generated from `tools/xfleet/state-schema.json`. One table
per top-level object (`_orchestrator.json`, then `{worker}.json`); nested object
fields are flattened with dotted paths and map-value keys shown as `{key}`. Do not
edit by hand — run `tools/xfleet/gen-state-schema-doc.sh` to regenerate.

<!-- BEGIN GENERATED -->
### `_orchestrator.json`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `schema_version` | const "1" | yes | State-file schema version (SC-6). Always the string "1" for this revision. The Task-18 validator and Task-19 migration helper key off this field; a missing or mismatched value is rejected. |
| `cycles` | integer | no | Count of approval-gate re-open cycles in this session. Incremented each time the human requests changes at a phase approval gate; drives convergence warnings. |
| `last_all_idle_notify` | string \| null | no | ISO-8601 timestamp of the most recent "all workers idle" Slack prompt, or null if never sent. Rate-limits re-sends of the all-idle nudge. |
| `last_round5_pause` | string \| null | no | ISO-8601 timestamp of the most recent round-5 hard-stop force-escalation pause, or null if never triggered. Rate-limits the round-5 disagreement flow. |
| `phase_emissions` | object | no | Map of phase name -> signal name -> emission record, tracking which gated phase signals the orchestrator has emitted (and whether human-approved). Arbitrary phase and signal names are allowed as map keys; the value object is strict. |
| `phase_emissions.{key}` | object | no | Map of signal name -> emission record for one phase. |
| `phase_emissions.{key}.{key}` | object | no | A single gated-emission record for one (phase, signal) pair. |
| `phase_emissions.{key}.{key}.approved_by_human` | boolean | yes | Whether a human approved this emission at the phase gate (F-17). |
| `phase_emissions.{key}.{key}.sent_at` | string | yes | ISO-8601 timestamp at which the signal was emitted. |
| `phase_emissions.{key}.{key}.sent_to` | array<string> | yes | Worker short-names the signal was sent to. |
| `phase_emissions.{key}.{key}.emission_id` | string | yes | Unique id for this emission; correlates with the emission_log entry. |
| `emission_log` | array<object> | no | Append-only log of every gated-emission attempt (successful or not), for audit. |
| `emission_log[].phase` | string | yes | Phase the emission was attempted for. |
| `emission_log[].signal` | string | yes | Signal name attempted (e.g. phase-complete). |
| `emission_log[].attempted_at` | string | yes | ISO-8601 timestamp of the attempt. |
| `emission_log[].approved_by_human` | boolean | yes | Whether the attempt was human-approved at the gate. |
| `emission_log[].emission_id` | string | yes | Unique id correlating with the phase_emissions record. |
| `emission_log[].outcome` | string | yes | Result of the attempt (e.g. sent, blocked, deferred). |
| `human_engaged` | object | no | Whether a human is actively engaged in the session. Cross-field invariant (sync-mechanism ADR): active=true iff `xfleet engage` was called OR a directive was dispatched; cleared by `xfleet disengage`. |
| `human_engaged.active` | boolean | yes | True when a human is engaged. Auto-set true on directive dispatch (cluster 4a); never auto-fired by escalation arrival. |
| `human_engaged.concern_id` | string \| null | yes | Concern id the human engagement is scoped to, or null if not concern-scoped. |
| `human_engaged.set_at` | string \| null | yes | ISO-8601 timestamp the engagement was set, or null when inactive. |
| `human_engaged.reason` | string \| null | yes | Human-readable reason engagement was set, or null when inactive. |
| `completion_log` | array<object> | no | Append-only log of phase-completion evaluations, recording which workers/signals were still missing at each check. |
| `completion_log[].evaluated_at` | string | yes | ISO-8601 timestamp of the evaluation. |
| `completion_log[].trigger_msg_type` | string | yes | Inbound message type that triggered the evaluation (e.g. phase-complete). |
| `completion_log[].outcome` | string | yes | Result of the evaluation (e.g. complete, incomplete). |
| `completion_log[].missing_workers` | array<string> | yes | Worker short-names that had not yet reported for the phase. |
| `completion_log[].missing_signals` | array<string> | yes | Signal names still outstanding for the phase. |
| `directive_log` | array<object> | no | Append-only log of directives the orchestrator dispatched to workers. |
| `directive_log[].directive_id` | string | yes | Unique id for the directive. |
| `directive_log[].target` | string | yes | Worker short-name the directive was dispatched to. |
| `directive_log[].concern_id` | string \| null | yes | Concern id the directive addresses, or null if not concern-driven. |
| `directive_log[].scope` | string | yes | Scope/subject of the directive. |
| `directive_log[].expected_action` | string | yes | Action the orchestrator expects the worker to take. |
| `directive_log[].dispatched_at` | string | yes | ISO-8601 timestamp the directive was dispatched. |
| `directive_log[].response_status` | string | yes | Current status of the worker's response (e.g. pending, acked, done). |
| `task_log` | array<object> | no | Append-only log of tasks the orchestrator dispatched to workers. |
| `task_log[].task_id` | string | yes | Unique id for the task. |
| `task_log[].target` | string | yes | Worker short-name the task was dispatched to. |
| `task_log[].task_kind` | string | yes | Category of task dispatched. |
| `task_log[].dispatched_at` | string | yes | ISO-8601 timestamp the task was dispatched. |
| `task_log[].response_status` | string | yes | Current status of the worker's response (e.g. pending, done). |
| `escalation_log` | array<object> | no | Append-only log of escalations received from workers and their surfacing/resolution lifecycle. |
| `escalation_log[].escalation_id` | string | yes | Unique id for the escalation. |
| `escalation_log[].source_worker` | string | yes | Worker short-name that raised the escalation. |
| `escalation_log[].reason` | string | yes | The --reason value (e.g. breaking, plan-deviation, judgment-finding). |
| `escalation_log[].path` | string | yes | Path to the escalation message body under $XFLEET_COORDINATION_ROOT. |
| `escalation_log[].priority` | string | yes | Routing class derived from reason; one of `urgent` or `non-urgent` per messaging.md section (c). |
| `escalation_log[].received_at` | string | yes | ISO-8601 timestamp the escalation was received. |
| `escalation_log[].surfaced_at` | string | yes | ISO-8601 timestamp the escalation was surfaced to the human. |
| `escalation_log[].resolved_at` | string \| null | yes | ISO-8601 timestamp the escalation was resolved, or null if still open. |

### `{worker}.json`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `schema_version` | const "1" | yes | State-file schema version (SC-6). Always the string "1" for this revision. The Task-18 validator and Task-19 migration helper key off this field; a missing or mismatched value is rejected. |
| `current_phase` | string | no | The phase skill the worker currently has loaded (e.g. idle, qa-spec, repo-spec, plan, implement, cross-review, alignment). |
| `status` | enum: working, idle, blocked, compacting | no | Authoritative busy/free signal, orthogonal to current_phase. working = mid-task; idle = reachable, no active task; blocked = waiting on an external decision; compacting = context near auto-compact threshold, handoff written, awaiting human /clear + resume. |
| `current_task` | object \| null | no | The in-flight unit of work, or null when the worker has no active task. |
| `current_task.task_id` | string | yes | Unique id for the in-flight task. |
| `current_task.description` | string | yes | Human-readable label for the task. |
| `current_task.source` | enum: self, orch-task, orch-directive | yes | Origin of the task: self (worker-initiated), orch-task (xfleet task), or orch-directive (xfleet directive). |
| `current_task.received_at` | string | yes | ISO-8601 timestamp the task was received/started. |
| `last_updated` | string | no | ISO-8601 timestamp of the most recent write to this file. The orchestrator's straggler detection reads this field. |
| `listen_bash_id` | string | no | Id of the background bash process running the worker's inbox listener. |
| `standby` | boolean | no | True when the worker is on standby (paused phase-specific handling while always-on handlers stay active). |
| `context_pct` | integer | no | Most recent context-window usage reading, 0-100. Drives warn/compact transitions. |
| `review_revision_count` | integer | no | Number of review/revision rounds completed in the current phase. Resets to 0 on phase entry. |
| `findings_status` | object | no | Map of finding id -> lifecycle status for findings the worker is tracking. Arbitrary finding ids are allowed as map keys; each value must be one of the enumerated statuses. |
| `findings_status.{key}` | enum: new, auto-revised, awaiting-review, resolved, escalated | no | Lifecycle status of one finding. |
| `confirmed_closed_concerns` | array<string> | no | Concern ids this worker has confirmed closed via the resolution closure handshake. |
| `last_warn_emitted_at` | string \| null | no | ISO-8601 timestamp the last context warn was emitted, or null. Debounces warn emissions (cluster 4j); resets on phase entry; cleared when context_pct drops below the warn threshold. |
| `last_check_at` | string \| null | no | ISO-8601 timestamp of the last context check, or null. Throttles below-warn context checks (cluster 4j). |
<!-- END GENERATED -->

---

## Examples

### `_orchestrator.json` (minimal)

```json
{
  "schema_version": "1",
  "cycles": 0,
  "last_all_idle_notify": null,
  "last_round5_pause": null,
  "phase_emissions": {},
  "emission_log": [],
  "human_engaged": {
    "active": false,
    "concern_id": null,
    "set_at": null,
    "reason": null
  },
  "completion_log": [],
  "directive_log": [],
  "task_log": [],
  "escalation_log": []
}
```

### `{worker}.json` (idle, no active task)

```json
{
  "schema_version": "1",
  "current_phase": "idle",
  "status": "idle",
  "current_task": null,
  "last_updated": "2026-05-30T10:45:00Z",
  "listen_bash_id": "bash-42",
  "standby": false,
  "context_pct": 12,
  "review_revision_count": 0,
  "findings_status": {},
  "confirmed_closed_concerns": [],
  "last_warn_emitted_at": null,
  "last_check_at": "2026-05-30T10:40:00Z"
}
```
