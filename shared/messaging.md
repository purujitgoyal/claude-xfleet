# xfleet Wire-Message Taxonomy

> **Supersedes** the wave-1 personal-global `~/.claude/xfleet/shared/messaging.md`
> (SC-1 + SC-2). That doc's `send.sh` / `--type` model is **retired** (cluster 4e):
> there is no `xfleet send` and no `--type` flag — message type is **structural**,
> carried by the subcommand name itself. The wave-1 file is removed separately by
> the controller; do not edit or delete it here.
>
> **This is the canonical reference for all Phase B subcommand validators.** It is
> the single source of truth for subcommand names, sender authority, recipient
> validity, the `--reason` enum, `--message`/`--message-file` rules, the closure
> handshake, and round-counter semantics. Path notation throughout uses
> `$XFLEET_COORDINATION_ROOT/...` (SC-2 G1); never hardcoded repo paths.

---

## (a) Wire-message types overview

Every coordination message is dispatched as `xfleet <subcommand> [recipient] [flags]`.
There are three structural categories:

| Category | Examples | Notes |
|----------|----------|-------|
| **Content-carrying** | `directive`, `task`, `concern`, `concern-reopen`, `resolution`, `question`, `answer`, `escalation`, `phase-complete` | Each carries exactly one of `--message` / `--message-file` (section d). `escalation` carries content only for urgent reasons; `judgment-finding` is alert-only. |
| **State-mutating** | `engage`, `disengage`, `phase` | Mutate state files (`_orchestrator.json`, session-local `current_phase`). |
| **Read-only / session-local** | `status`, `peek`, `listen`, `ack`, `resume`, `continue` | No authority enforcement; auto-allowed. |
| **Signal-only** | `integration-ready`, `review` | Worker→orch signals; no `--message` body, no rounds, no response. `integration-ready` requires `--ip`; `review` carries `--path` to the review file + optional `--finding` (alert-not-content). |

Type is determined by the subcommand — never by a `--type` flag.

A fourth, orthogonal group is **exploration mode** (`ask`, `await`): orchestrator-less,
peer-to-peer Q/A between an active session and parked read-only responders. See
section (i).

**Role detection.** Each session's role (orchestrator vs worker) is resolved
**role-based**: inferred via state-file ownership or the `XFLEET_ROLE` env var
exported at skill-load time. The exact mechanism is finalized in Phase B; validators
treat role as an authoritative input.

**Validator behavior on rejection.** Reject with a clear error that names the
offending role, lists the valid sender(s), and suggests the correct subcommand on
near-misses — e.g. orch attempting `concern` →
*"concerns are peer-to-peer; from orch use `directive` instead."*

---

## (b) Sender-authority table

Verbatim mapping (A3). "Sender" = which session role may originate the subcommand.

| Subcommand | Authorized sender(s) | Recipient | Notes |
|------------|----------------------|-----------|-------|
| `directive` | **orchestrator only** | worker | Reject if not orch session. Auto-sets `human_engaged` (cluster 4a). |
| `task` | **orchestrator only** | worker | Reject if not orch session. |
| `concern` | **worker only** | peer-worker | Peer-to-peer. INCRs round counter (section g). |
| `resolution` | **worker only** | peer-worker | worker→worker; triggers closure handshake (section e). |
| `question` | **worker only** | orchestrator OR peer-worker | NEVER literal `"human"` (cluster 4g #1). |
| `review` | **worker only** | orchestrator | Orch never originates reviews (F-1 / F-2). |
| `escalation` | **worker only** | orchestrator | `xfleet escalation --reason <reason>` (recipient always orchestrator — no positional); routed by `--reason` (section c). |
| `phase-complete` | **worker only** | orchestrator | Recipient always orchestrator. |
| `concern-reopen` | **orchestrator or worker** | peer-worker | Orch reopens after human review; worker reopens on new findings (peer-symmetry). Continues round counter. |
| `answer` | **orchestrator or worker** | original questioner | Orch-as-sender is the rare directive-clarification path (kept open; observe before tightening). |
| `engage` | **any session** | — | Writes `_orchestrator.json:human_engaged`. |
| `disengage` | **any session** | — | Writes `_orchestrator.json:human_engaged`. |
| `phase` | **self-session** | — | `phase --enter` / `phase --complete`; each session manages its own `current_phase`. Orch's call also gates emissions (cluster 4a). |
| `ask` | **any session** (self-bootstraps worker identity; exploration mode, section i) | explore responder | No role assertion — zero-setup by design. |
| `await` | **responder self-session** (exploration mode, section i) | — | Blocks on own inbox; no authority enforcement. |
| `status` | any (read-only) | — | No authority enforcement. |
| `peek` | any (read-only) | — | No authority enforcement. |
| `listen` | any (read-only) | — | No authority enforcement. |
| `ack` | any (read-only) | — | No authority enforcement. |
| `resume` | any (read-only) | — | No authority enforcement. |
| `continue` | any (read-only) | — | No authority enforcement. |

---

## (c) `--reason` enum + per-reason routing

Single rule for `xfleet escalation` (recipient always orchestrator), routed by `--reason` (A2). This
table is the **single source of truth** for the Phase B escalation handler.
**Unknown `--reason` values are rejected.**

| `--reason` | Class | Routing |
|------------|-------|---------|
| `breaking` | urgent | Bypass batching; surface to human immediately. Worker-direct slack ping permitted, but **always** paired with the `xfleet escalation` message for the audit trail. |
| `plan-deviation` | urgent | Same as `breaking`: bypass batching, immediate human surface, paired slack-ping allowed + always paired with the escalation message. |
| `judgment-finding` | non-urgent | **Batched.** Alert-only payload: finding count + review-path. **No content body.** |

**Invariants.**
- All escalations append to `escalation_log[]`.
- `human_engaged` is **NOT** auto-fired by escalation arrival. It is auto-set
  **only** on `xfleet directive` dispatch (cluster 4a's rule wins).

---

## (d) `--message` vs `--message-file` rules

Applies to the content-carrying subcommands (cluster 4i): `directive`, `task`,
`concern`, `concern-reopen`, `resolution`, `question`, `answer`, `review`,
`escalation` (orchestrator), `phase-complete`.

- **`--message-file <path>` is the primary documented path.** Agents naturally
  draft to files. Convention: `$XFLEET_COORDINATION_ROOT/{type}/{uuid}.md`
  — e.g. `$XFLEET_COORDINATION_ROOT/directives/abc-123.md`,
  `$XFLEET_COORDINATION_ROOT/concerns/abc-123.md`.
- **`--message "<text>"`** is the escape valve for genuine one-liners (acks,
  toggles, simple yes/no).
- **Validator rule:** exactly one of `--message` / `--message-file` is required for
  every content-carrying subcommand. Reject if **both** or **neither** are present.
  No length-threshold rejection.

> Forward reference: strict path-scoping of `--message-file` (must resolve under
> `$XFLEET_COORDINATION_ROOT`) is enforced in **Phase B Task 21** per ADR SC-5. Not
> part of this doc.

---

## (e) Closure handshake (`resolution-ack` + `resolution-summary`)

Fixed per **F-33**. When a worker sends `resolution` (worker→worker) to close a
concern:

1. The resolution handler reflexively emits **`resolution-ack`** to the peer worker
   (the original concern raiser).
2. It reflexively emits **`resolution-summary`** to the orchestrator.
3. The sending worker marks the concern **closed-acked**, recorded in its
   `confirmed_closed_concerns[]`.

`resolution-ack` and `resolution-summary` are **reflexive handler emissions**
(section f) — they are NOT user subcommands and never appear in the section (h)
table.

---

## (f) Reflexive auto-handler emissions (NOT user-invocable)

These messages are emitted **internally by handlers**, reflexively, in response to
an inbound message. They are **never** CLI subcommands and **never** appear in the
section (h) subcommand table or the canonical `XFLEET_SUBCOMMANDS` registry.

| Reflexive message | Emitted by handler for | To |
|-------------------|------------------------|----|
| `directive-ack` | inbound `directive` | originating orchestrator |
| `directive-response` | inbound `directive` (worker reply) | orchestrator |
| `task-response` | inbound `task` | orchestrator |
| `resolution-ack` | inbound `resolution` | peer worker (concern raiser) |
| `resolution-summary` | inbound `resolution` | orchestrator |
| `escalation-response` | inbound `escalation` | originating worker |

Do not add any of these as subcommand rows in section (h); validators do not
authority-check them because they are not user-facing.

---

## (g) Round-counter semantics

Per **F-15**:

- INCR the round counter **only on `concern`** (a statement / counter-statement),
  **NOT** on a response.
- One round = peer-A statement + peer-B response (= 2 sends).
- The **round-5 hard-stop** fires at 5 actual rounds of disagreement.
- `concern-reopen` **continues** the counter — it does **not** reset.

**Redis key (ADR SC-3).** Namespaced per coordination root:

```
xfleet:{coordination_root_slug}:concern:{id}:rounds
```

`{coordination_root_slug}` is derived from a stable hash of the realpath of
`$XFLEET_COORDINATION_ROOT`, so concurrent coordination sessions on different roots
never collide on counter keys.

---

## (h) Subcommand table  <!-- SECTION-H-SUBCOMMAND-TABLE -->

Canonical 5-column reference. Contains a row for **every** name in
`tools/xfleet/lib/subcommand-registry.sh` (`XFLEET_SUBCOMMANDS`, exactly 24) and
**only** those names. Reflexive handlers (section f) are intentionally excluded.
The consistency test (`tests/docs/messaging-consistency.bats`) asserts this table
and the registry stay in lockstep. The **emits reflexive?** column records whether
invoking the subcommand triggers reflexive auto-handler emissions (section f).

| subcommand | sender | recipient | --message rules | emits reflexive? |
|------------|--------|-----------|-----------------|------------------|
| `status` | any (read-only) | — | none | no |
| `peek` | any (read-only) | — | none | no |
| `listen` | any (read-only) | — | none | no |
| `ack` | any (read-only) | — | none | no |
| `question` | worker only | orchestrator OR peer-worker (never `"human"`) | exactly one of `--message` / `--message-file` | no |
| `answer` | orchestrator or worker | original questioner | exactly one of `--message` / `--message-file` | no |
| `concern` | worker only | peer-worker | exactly one of `--message` / `--message-file` | no |
| `concern-reopen` | orchestrator or worker | peer-worker | exactly one of `--message` / `--message-file` | no |
| `resolution` | worker only | peer-worker | exactly one of `--message` / `--message-file` | yes (resolution-ack to peer + resolution-summary to orch) |
| `directive` | orchestrator only | worker | exactly one of `--message` / `--message-file` | yes (directive-ack + directive-response) |
| `task` | orchestrator only | worker | exactly one of `--message` / `--message-file` | yes (task-response) |
| `escalation` | worker only | orchestrator (always; no positional) | urgent reasons carry one of `--message` / `--message-file`; `judgment-finding` is alert-only (no body); routed by `--reason` (section c) | yes (escalation-response) |
| `phase` | self-session | — | none (`--enter` / `--complete`) | no |
| `engage` | any session | — | none | no |
| `disengage` | any session | — | none | no |
| `resume` | any (read-only) | — | none | no |
| `continue` | any (read-only) | — | none | no |
| `phase-complete` | worker only | orchestrator | exactly one of `--message` / `--message-file` | no |
| `review` | worker only | orchestrator | `--path` to review file + optional `--finding` (alert-not-content; no message body) | no |
| `drift-check` | worker only | — | none | no |
| `checklist` | orchestrator (in finalize-spec) | — | none | no |
| `integration-ready` | worker only | orchestrator | none (`--ip` required) | no |
| `ask` | any session (exploration mode, section i) | explore responder | exactly one of `--message` / `--message-file` (`--message-file` requires a coordination root per SC-5) | no |
| `await` | responder self-session (exploration mode, section i) | — | none (`--name` / `--timeout` / `--unpark`) | no |

---

## (i) Exploration mode (`ask` / `await`)

Orchestrator-less, peer-to-peer Q/A. An active session asks a question about a
peer repo; a **parked, read-only responder** session in that repo answers using
its own tools. Design rationale lives in
`docs/superpowers/specs/2026-06-10-xfleet-explore-mode-design.md`.

**Semantics (all deliberate omissions):** no orchestrator, no rounds, no
reflexive emissions, no coordination root, no state files, no roster. The wire
types are the existing `question` / `answer`; only the transport conventions
below are new.

- **Identity is self-bootstrapped.** Both sides default their name to
  `$XFLEET_WORKER_NAME`, else `basename "$PWD"`. `ask` performs no
  `assert_role` — exploration mode is zero-setup.
- **`reply_to` field.** `ask`'s question message carries
  `reply_to: <asker-name>` in addition to the standard fields, because `from`
  carries the role string (`"worker"`), not a name. The responder answers via
  plain `xfleet answer <reply_to> --message "..."`.
- **Presence keys.** A parked responder maintains
  `xfleet:explore:presence:{name}` (value: JSON with `repo` + `parked_at`,
  TTL 900s, refreshed each `await` cycle). `xfleet ask --list` scans this
  prefix; `xfleet await --unpark` deletes the key.
- **Consumer group.** `await` reads `inbox:{name}` via group `explore`
  (never `worker`), keeping explore delivery position separate from any
  orchestrated listener. `ask`'s blocking wait uses plain `XREAD`
  (non-consuming) on the asker's own inbox, from the pre-send high-water mark.
- **Read-only is behavioral.** Responders refuse mutation requests by
  convention (see the `/xfleet:explore` skill); the wire layer does not
  enforce it.

**Limitations (documented, not engineered around):** do not park a responder
under the same name as an active coordination-session worker (shared
`inbox:{name}` stream); one shared Redis means one shared presence namespace;
no question/answer correlation IDs in v1 (one question in flight per asker —
the next `answer` after the send wins).
