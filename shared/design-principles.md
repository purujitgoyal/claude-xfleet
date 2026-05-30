# xfleet Design Principles

> The **design-principles meta-layer** for xfleet. Every xfleet skill loads this
> doc via a one-line reference in its `## Protocol` section, so the principles
> below are re-established every session and every `/clear`+resume — the same way
> skills already reference `shared/messaging.md`.
>
> **Scope: xfleet-only.** These principles are deliberately **xfleet-scoped** and
> are **not** duplicated into `~/.claude/CLAUDE.md`. Outside xfleet there is no
> phase-skill defining a protocol-bound workflow, so the "skills are the source of
> truth" problem is far more acute *inside* orchestrated sessions. For non-xfleet
> sessions, F-53's prepare-compact format (Active Skills + In-Session Directives +
> Resume Instructions) is the durability mechanism — different problem, different
> fix; the two compose without duplication (cluster 4n #5).
>
> Sibling docs in `shared/`: `messaging.md` (wire-message taxonomy),
> `state-schema.md` (forthcoming, Task 17), and a future `reviewer-contract.md`.
> Coordination path notation follows `$XFLEET_COORDINATION_ROOT/...` (SC-2 G1) —
> never hardcoded repo paths.

Inaugural principles: **F-35** (skills are the source of truth) and **F-36**
(autonomous execution). The remaining principles invoked as rationale across the
shakedown clusters are collected as named placeholders at the end for
discoverability; they are expanded here as they crystallize.

---

## Principle: F-35 — Skills are the source of truth

> **Skills are the source of truth for agent behavior. Discipline that must
> survive session boundaries belongs in skill bodies, not in memories or
> in-session reminders.**

Memories complement skills (user identity, preferences, project-state snapshots)
but cannot replace them for behavior rules. When a behavior keeps drifting
despite correction, the fix is almost always "update the skill," not "remember
harder." The recurring failure mode: a user corrects a behavior in-session, the
agent commits it to memory, and the next session (or the same session after a
`/clear` or compact) drifts back — because in-session corrections and memories do
not durably encode behavior. Skills do.

### Corollaries

1. **Skills-first correction.** When the user corrects a drift, the response is:
   (a) acknowledge, (b) identify which skill owns the behavior, (c) update that
   skill — not just a user memory, not just a worker memory. The memory update is
   *additional*, never a substitute.

2. **Memory-as-signal.** A correction saved to memory *without* a skill update is
   a signal the fix will recur. Treat memory-only corrections as incomplete —
   drift-waiting-to-happen. Sessions where the user says "remember to X" should
   usually end with "…and let's also update the {skill} to encode it."

3. **Durability test.** For any corrective guidance, ask: *"If the next session
   starts with a fresh context and no memories loaded, would this behavior still
   be correct?"* If no, the fix is incomplete — the skill must be updated.

4. **Memory-appropriate scope.** Memories durably hold: user identity, project
   context, collaboration preferences, fact snapshots at a point in time.
   Memories should **not** hold: xfleet protocol rules, phase-handler sequences,
   message-type contracts, tool-invocation conventions. Those belong in skills.

5. **Review guard.** When code-reviewing xfleet changes, check: if behavior rules
   appear in the change but the relevant skill file was **not** updated, that is a
   drift-waiting-to-happen. Flag it.

F-35 explains why so many shakedown clusters needed *structural* fixes (plugin
commands, hooks, Authority Hierarchy sections) instead of memory-based
corrections. Locking the principle here closes the loop on those clusters'
rationale — the corrective workflow now terminates in a skill update instead of a
memory entry that fades.

---

## Principle: F-36 — Autonomous execution

> **Agents execute the plan and the skill-defined handler flow without pausing
> for human confirmation between steps.** Drive the documented path; report at
> milestones, not at every step.

### Pause ONLY for

1. **An explicit gate** defined by the plan or skill — e.g., human approval at a
   phase transition (F-17), `approval_by_human`.
2. **A breaking error** — tool failure, a contradiction in state, or a missing
   required input that cannot be obtained without human input.
3. **A deviation from the plan** — before executing a step that was not in the
   plan, or before skipping a planned step, check in.

### Don't pause for

- The next expected step — just do it.
- Routine progress — just report at milestones.
- "Am I doing this right?" — re-read the plan; if it answers, act.
- Uncertainty a Serena / Context7 / grep lookup could resolve — look it up, act.

### The 4-question decision rubric

When unsure whether to pause, ask:

1. **Is this step in the plan?** → Yes: execute. No: check in.
2. **Is there a gate defined here?** → Yes, I'm at it: pause. No: execute.
3. **Did I hit an error that breaks progress?** → Yes: pause with the specific
   error. No: execute.
4. **Am I about to deviate from the plan?** → Yes: check in first. No: execute.

If all four answers are "execute," execute. Do **not** pause merely because the
step feels important or you want reassurance.

### Rationalizations-to-Reject

| Excuse | Reality |
|--------|---------|
| "This step seems important — I should confirm before doing it." | Importance isn't a gate. Gates are defined in the plan or skill. If it's not a gate, execute. |
| "I'm not 100% sure this is right — safer to ask." | Uncertainty that a grep / Serena / plan re-read can resolve is not pause-worthy. Resolve, then act. |
| "Last time I didn't check, the user was annoyed." | That was a different situation — check the pattern, not the instance. If it wasn't a gate, executing was correct. |
| "The human seems busy/happy — might as well confirm while they're around." | Proactive check-ins break flow. Report at milestones, not at every step. |
| "This is a multi-step chain — let me confirm before the next one." | If the chain is in the plan, execute. Milestone-level reporting is enough. |
| "I might cause something irreversible." | Then the plan should have marked it as a gate. If it didn't, it's not intended as one. If you think it should be, raise the design issue *after* executing the current step. |

**Milestone-level reporting, not step-level confirmation.** Report after a
meaningful chunk completes ("Section written and reviewed, no blocking findings,
sending phase-complete now"), not after each sub-step ("Reading config…
Checking state file… Preparing to write section…"). Reporting is for the human's
visibility, not for permission.

F-36 is triple-redundant on purpose: it appears here, in `## Autonomous
Execution` sections of the worker and orchestrator skills, and is referenced from
every other xfleet skill. High-impact behavior rules with a single mention
historically drift.

---

## Placeholder principles (collected for discoverability)

These principles are invoked as rationale across the shakedown clusters and are
mostly locked elsewhere; they are collected here so the design-principles doc is
the single discoverability hub. Each is a named stub to be expanded as it
crystallizes.

- **Coordination-vs-durability split** — locked in: F-19 / cluster 4c. Global
  `$XFLEET_COORDINATION_ROOT` holds transient coordination state; per-repo
  `docs/superpowers/` holds durable artifacts (specs, plans, handoffs, reviews,
  ADRs).
- **Content-hygiene voice** — locked in: F-19 / cluster 4l (Decisions Log). Clean
  artifacts are forward-looking; history lives in sibling bundles, not inline.
- **Authority hierarchy** — locked in: F-30 / cluster 4g. The orchestrator speaks
  for the human; workers execute relays without second-guessing.
- **Atomic state transitions** — locked in: cluster 1 / F-32, F-33. Critical
  sequences (ACK→listen, write-resolution→peer-ack) must be indivisible in the
  skill instructions.
- **Verify-before-claim** — locked in: cluster 1 / F-32. A worker's state-of-mind
  about listen / task state must be verified against actual state before it is
  reported.
- **Observe-first + over-engineering aversion** — pattern across the shakedown.
  Recognize small scope rather than inventing structure; defer mechanisms until
  an observed need materializes.
- **Strict delegation** — locked in: cluster 4h. Cross-repo source investigation
  routes through the owning peer worker; direct reads of sibling-repo source are
  forbidden in orchestrated mode (cross-repo reads limited to
  `docs/superpowers/` content).
- **File-primary message convention** — locked in: cluster 4i. Message bodies are
  file-primary; scoped permissions follow the file-based transport pattern.

**Worker-conduct rules (cluster 4o)** — forthcoming placeholders; cluster 4o
designates this doc as their discoverability hub. They will be expanded as their
skill-text lands: cross-repo source-reads forbidden (F-38), verify state labels
before reciting (F-40), reading task `.output` files is permitted (F-43),
boundary-first presentation (F-45), and asymmetry pushback (F-46).
