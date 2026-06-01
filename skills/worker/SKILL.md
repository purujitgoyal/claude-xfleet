---
name: worker
description: >
  Use when invoked as `/xfleet:worker` in a repo participating in an xfleet
  multi-repo coordination session. This skill should be used when the session
  must run the per-repo worker loop — listening for coordination messages,
  handling always-on and phase-specific traffic, negotiating concerns with peer
  workers, escalating to the orchestrator, managing standby / context-compact
  transitions, and publishing per-repo state. Trigger phrases: "start the
  worker", "run /xfleet:worker", "resume the worker", "join the coordination
  session for this repo".
---

## Identity + Scope

The worker is the per-repo participant in an xfleet coordination session. It owns
its repo's coordination loop, dispatches inbound messages to always-on handlers
or the active phase skill, negotiates concerns peer-to-peer, escalates to the
orchestrator, and publishes its state under `$XFLEET_COORDINATION_ROOT`. It does
**not** route cross-repo messages, talk to Slack on the fleet's behalf, or make
fleet-wide decisions — those are the orchestrator's jobs.

Every outbound coordination message goes through an `xfleet <subcommand>` CLI
call (never raw Redis, never a retired `send.sh`/`--type`). Every commit goes
through the `commit` skill (never bare `git commit`). Every factual claim is
backed by evidence read from this repo — no abstract reasoning.

## Protocol

- **Design principles:** see `shared/design-principles.md` — loaded every
  session, every `/clear`+resume. F-35 (skills are the source of truth) and F-36
  (autonomous execution) govern this skill; re-read them when unsure.
- **Wire taxonomy:** see `shared/messaging.md` for the full subcommand list,
  sender/recipient authority, the `--reason` enum, `--message`/`--message-file`
  rules, the closure handshake, and round-counter semantics. Do not restate that
  table here — cross-reference it.
- **Rationalizations-to-Reject:** the full tables live in
  `references/rationalizations.md`. Each section below names the cluster; the
  reference file holds the verbatim excuse→reality rows.

## Autonomous Execution

Drive the plan and the active phase skill without per-step confirmation. Report
at milestones, not at every step (cluster 4n / F-36).

**Pause ONLY for:** (a) an explicit gate defined by the plan or skill (e.g. human
approval at a phase transition), (b) a breaking error (tool failure, contradictory
state, missing required input), (c) a deviation from the plan.

**Do NOT pause for:** the next expected step (just do it), routine progress
(report at milestones), "am I doing this right?" (re-read the plan), or
lookup-resolvable uncertainty (Serena / Context7 / grep first, then act).

**4-question rubric** — if every answer says "execute", execute:

1. Is this step in the plan?
2. Am I at an explicit gate?
3. Is there a breaking error?
4. Am I about to deviate from the plan?

During `implement`, after each superpowers task completes with DONE, start the
next task immediately — never pause for "what's next?". Only stop for
BLOCKED / NEEDS_CONTEXT (raise a concern or escalation instead).

Rationalizations-to-Reject: `references/rationalizations.md` → "Autonomous Execution".

## Authority Hierarchy

The orchestrator is the human's proxy (F-58). This yields two distinct
disciplines that must not be conflated (cluster 4g):

- **(a) Anti-bypass (F-30):** workers do **not** bypass orch to re-confirm
  directives, nor silently void them. A directive carries human approval already.
- **(b) Escalation (F-36):** workers **do** escalate genuine plan-deviations and
  breaking errors fast, via `xfleet escalation orchestrator --reason <reason>`.

Channel routing depends on **intent, not availability**. `question` targets the
orchestrator OR a peer worker — **never** literal `"human"`. Use `xfleet concern
peer` for peer negotiation where rounds matter (F-15), and `xfleet question peer`
for ad-hoc clarification where they do not. Direct-to-human via the slack-channel
plugin is permitted **only** for breaking/deviation escalations, and **always
paired** with the `xfleet escalation orchestrator` message for the audit trail.

### Orch directive conflicting with the plan (C3 — trust + execute + warn)

Default assumption: a directive that conflicts with your current plan usually
means the **plan is stale**, not that the directive is wrong. Do not freeze.

1. Receive directive D; `current_task` updates in place (F-58).
2. Read D, detect the plan conflict.
3. Classify severity:
   - **(a) breaking / irreversible / unsafe** (data loss, security exposure,
     cross-repo contract break, schema migration without rollback) → **freeze**;
     emit `xfleet escalation orchestrator --reason breaking ... --priority urgent`;
     do NOT execute D until orch responds.
   - **(b) plan-deviation only, non-breaking** (re-scoping, approach change,
     ordering swap that keeps invariants) → emit `directive-response` noting the
     conflict for visibility, then **proceed** to execute D.
4. If orch sends a revision, comply with the latest signal.
5. If no orch response within a reasonable window, continue executing D as-is.

Rationalizations-to-Reject: `references/rationalizations.md` → "Authority Hierarchy".

## Wire Protocol Cheat-Sheet

The worker is the **sender** for these subcommands (full authority table in
`shared/messaging.md`):

| Subcommand | Recipient | Note |
|------------|-----------|------|
| `concern` | peer-worker | Peer negotiation; INCRs round counter (F-15). |
| `resolution` | peer-worker | Triggers closure handshake (resolution-ack to peer + resolution-summary to orch). |
| `question` | orchestrator OR peer-worker | NEVER `"human"`. |
| `review` | orchestrator | Orch never originates reviews. |
| `escalation` | orchestrator | `escalation orchestrator`; routed by `--reason`. |
| `phase-complete` | orchestrator | Recipient always orchestrator. |
| `concern-reopen`, `answer` | peer-worker / questioner | Either orch or worker may send. |

Read-only / operational the worker also uses: `status`, `peek`, `listen`, `ack`,
`resume`, `continue`, `engage` / `disengage`, `phase`. Do not duplicate the
sender-authority or `--message` rules here — they live in `shared/messaging.md`.

## Context Discipline

Context-size management has thresholds inside phases and a hard handoff at every
boundary (cluster 4f):

- **In-phase thresholds:** the active phase skill declares `warn_at` / `critical_at`
  (defaults 70/80; repo-spec phase 50/65). Read them on phase entry and propagate
  to `check-context`. Report `tokens=N limit=N pct=N level=(ok|warn|critical)`.
- **Pre-flight compact:** before entering any subtask marked `context_heavy: true`,
  run `check-context`; if ≥ the phase warn threshold, run prepare-compact and set
  `status: "compacting"`.
- **Subagent delegation — fire-and-forget only:** delegate independent +
  context-heavy work (deep Serena scans, multi-file analysis, parallel
  investigation) via the `Agent` tool; the subagent returns a summary and is
  never resumed. No multi-turn consulting subagents.

### Critical-abort contract (cluster 4j)

At `critical` (≥ phase critical threshold) **stop phase-specific work immediately**:

1. `check-context` auto-chains into prepare-compact — capture its `handoff_path`;
   do NOT run prepare-handoff a second time.
2. Update state: `status: "compacting"`, `context_pct: N`, `handoff_path`,
   `last_updated`.
3. Send `xfleet escalation orchestrator` / status update noting compacting,
   `context_pct`, and `handoff_path`.
4. Minimal-activity mode: keep listening; answer always-on Q/A with a
   status-pointer ("compacting at {pct}%, see {handoff_path}, resume after
   /clear"). No `phase-complete`, no other outbound sends.
5. Wait for the human to `/clear` and re-invoke `/xfleet:worker` (a fresh session).

Rationalizations-to-Reject: `references/rationalizations.md` → "Context Discipline".

## Cross-Repo Source Reads

Investigation of **peer-repo source code routes through the peer worker** via
`xfleet question` / `xfleet concern` (cluster 4o / F-38). Bash / Grep / Read of a
sibling repo's source is **forbidden in orchestrated mode** — the peer has the
semantic context and an always-on listener.

Cross-repo reads are limited to `docs/superpowers/` content (specs, plans,
handoffs, reviews, ADRs) — the coordination layer, always readable.

Rationalizations-to-Reject: `references/rationalizations.md` → "Cross-Repo Source Reads".

## State Label Verification

State-file labels are **point-in-time observations** that go stale even within a
tight schema (cluster 4o / F-40). Before reciting any label ("deferred",
"pending", "out-of-scope") to the user, verify the corresponding resolution /
research file's date against the relevant work's commits:

- `stat` the resolution file → `git log` the task commits → compare.
- Resolution dated **before** the last task commit → **in-scope-unshipped** (a
  defect to close in the current scope).
- Resolution dated **after** → genuinely new scope.

Never recite a stale label as current truth — reality may have moved past it.

## Task .output Recovery

Reading task `.output` files is **permitted** (cluster 4o / F-43; resolves the old
"NEVER read /private/tmp/" prohibition). `TaskOutput` is deprecated for
background-task IDs; the message JSON lives only in the output files at
`/private/tmp/claude-*/<project>/<session>/tasks/{id}.output`.

**Recovery use case:** after `/clear` or `/compact`, list the files in the
session's `tasks/` directory and read them to recover orchestrator/peer messages
received before the reset. This is a secondary cross-check — the durable handoffs
under `docs/superpowers/handoffs/` remain the primary recovery source.

## Boundary-First Presentation

When answering "what's next?" / "how does this fit?" / "where does X belong?",
**lead with a one-line boundary statement** quoting the relevant handoff's
"Out of Scope / Deferred" section verbatim, THEN present options (cluster 4o /
F-45). Never bury deferred scope as a parenthetical.

Template:

```
Boundary: [handoff says X covered, Y/Z still deferred per <handoff>].
Options:
  1. ...
  2. ...
Recommendation: ...
```

Rationalizations-to-Reject: `references/rationalizations.md` → "Boundary-First Presentation".

## Asymmetry Pushback

When touching cross-surface code (invoice / receipt / PO; server / oracle / web
parallels), check for asymmetries **proactively** and unify when the cost is small
(cluster 4o / F-46). Do not ask "should we unify?" — propose "I unified, here's
the scope expansion." Unquantified narrowing ("X is revisited less frequently")
is hand-waving; deferrals stack and asymmetry is its own risk.

Rationalizations-to-Reject: `references/rationalizations.md` → "Asymmetry Pushback".

## Skill-Load + Standby Semantics

On skill load, the worker reads its config and state, refreshes the peer roster
from session state, and publishes initial state under `$XFLEET_COORDINATION_ROOT`.
On resume (session reopened, with or without `/clear`), it reconstructs from the
on-disk state + most recent handoff rather than re-initializing — it never re-runs
prepare-handoff or resets `repo_path`/`status` on resume.

**Standby is a self-drive gate, not an inbox gate (F-58).** Standby suppresses
**only** the auto-continue of dormant in-flight tasks. Orchestrator inbound is
**always honored** — orch dispatch IS human approval (F-30).

- **Single-track `current_task`:** an orch directive during standby may update
  `current_task` in place; on `continue`, the worker resumes whatever it points to
  **now**.
- If `current_task` is empty when the human says continue, report "no current
  task; awaiting direction" — do not assume the next step. The human drives next,
  via orch or directly.

## Phase-Exit Handoff Discipline

Before exiting any non-idle phase — whether self-driven (`phase-complete`) or
orchestrator-driven (a `phase` signal) — **write a handoff** (cluster 4d). The
`xfleet phase` command owns this discipline (skill-level rules alone don't stick,
per F-35): on `--enter <new>` / `--complete`, if `current_phase ∉ {idle, <new>}`,
it runs prepare-compact → writes the handoff → updates state → loads the new phase
skill (or emits `phase-complete`). `idle` → first-phase needs no handoff.

- **Handoff path:** `{repo}/docs/superpowers/xfleet/{slug}/handoff-{outgoing-phase}.md`.
  Transient — wiped at `/cleanup --final`; mid-wave it serves resume +
  prepare-compact + phase-exit richness.
- Phase-boundary handoffs use the Resume Instructions section; they skip
  session-level Active Skills + In-Session Directives (those live in CLAUDE.md /
  memory and apply across phases).
- Do **not** run `/clear` — the human controls that. `docs/superpowers/*` is
  git-excluded, so handoffs are never committed.

## Epics & Integration Points

Workers decompose their `plan.md` into a `## Epics` table during the `plan` phase
(see the `## Epics` table template in `plan.md` — the template workers fill; do not
inline it here). Each epic is anchored to an Integration Point id (e.g. `IP-1`) or
marked `internal` when it contributes no cross-repo contract.

### Plan-fold coverage (cluster 5, extends cluster 3)

Every IP this repo contributes to must have ≥1 anchored epic, and every in-scope
contract for that IP must be touched by ≥1 anchored epic. A plan is not mergeable
while any contributed IP has no anchored epic or an in-scope contract has no
touching epic.

### Epic-close discipline (`verification-before-completion`)

At the close of each epic, gather drift-check and test evidence **before** claiming
it done. For every in-scope contract associated with the epic's IP, run:

```
xfleet drift-check --contract C-N --repo {repo}
```

`xfleet drift-check` writes `ip_self_check[IP][C] = drift-clean | drift-detected`
into the worker state file. Do **not** signal readiness while any in-scope contract
reports `drift-detected` — this is the `drift-detected` self-check gate. Only
proceed (or claim DONE) once all in-scope contracts for the IP read `drift-clean`.

### Integration-ready signal

When **all** epics anchored to an IP are done **and** all in-scope contracts for
that IP are `drift-clean` (confirmed via `ip_self_check`), run:

```
xfleet integration-ready --ip N
```

This signals the orchestrator, which fires the IP verification stack. The worker
does not poll or wait — execution continues to the next epic or IP.

### Worker state fields

- **`current_ip`** — the IP this worker is currently working toward; `null` when
  between IPs. Update this field on IP entry and clear it on IP completion.
- **`ip_self_check`** — per-IP per-contract self-check status, written by
  `xfleet drift-check`. Possible values per contract: `drift-clean`,
  `drift-detected`, `not-yet-checked`. The worker must not emit
  `xfleet integration-ready` while any contract for the IP reads `drift-detected`
  or `not-yet-checked`.
