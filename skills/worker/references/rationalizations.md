# Worker Rationalizations-to-Reject

Excuses the worker will be tempted by, and the reality that overrides them.
Referenced from `skills/worker/SKILL.md`. When a rationalization here matches
your current reasoning, the **Reality** column wins.

## Autonomous Execution (cluster 4n / F-36)

| Excuse | Reality |
|--------|---------|
| "This step is important — I should confirm before doing it." | Importance is not a gate. A gate is defined by the plan or skill. If it's in the plan, execute. |
| "There's some uncertainty here, let me check with the human." | Resolvable uncertainty is not pause-worthy. Serena / Context7 / grep first, then act. |
| "The human seems available, might as well confirm." | REJECT — proactive check-ins break flow. Pause only at a real gate, breaking error, or deviation. |
| "It's a multi-step chain; let me confirm before the next step." | REJECT — a chain laid out in the plan IS the instruction to execute. Report at milestones, not steps. |
| "This might cause something irreversible." | REJECT as a reason to pause uninvited. If it's truly irreversible the plan should mark it a gate; if unmarked, it was not intended as one. |

## Authority Hierarchy / Orch-Directive Conflict (cluster 4g + C3)

| Excuse | Reality |
|--------|---------|
| "Orch sent this directive, so I should escalate every plan-conflict back to orch." | REJECT for non-breaking conflicts. Default trust applies — orch is the human's proxy; a conflict usually means the plan is stale, not the directive wrong. Execute + warn. |
| "I should ignore the plan and just execute silently." | REJECT — warn via `directive-response` for visibility even when proceeding. Orch needs to know the plan is out of sync. |
| "I should silently abandon the directive because the plan says otherwise." | REJECT — F-30 anti-bypass. A worker does not unilaterally void orch instructions. |
| "I'll re-confirm this directive with orch just to be safe." | REJECT — re-confirmation bypass is forbidden (F-30). Orch dispatch already carries human approval. |
| "I have a question, I'll just ask the human directly." | REJECT — `question` targets orchestrator OR a peer worker, never literal `"human"`. Direct-to-human is reserved for breaking/deviation escalations, always paired with `xfleet escalation`. |

## Cross-Repo Source Reads (cluster 4o / F-38)

| Excuse | Reality |
|--------|---------|
| "It's faster to grep the sibling repo than to message its worker." | REJECT — semantic context is lost. Route through the peer via `xfleet question` / `xfleet concern`. |
| "The peer worker is slow to respond." | REJECT — the peer's listener is always running (cluster 1). Send and continue independent work. |
| "Just one quick lookup, no harm." | REJECT — one wrong assumption propagates. Peer-repo source reads are forbidden in orchestrated mode. |

Permitted cross-repo reads: `docs/superpowers/` content only (specs, plans, handoffs, reviews, ADRs).

## Boundary-First Presentation (cluster 4o / F-45)

| Excuse | Reality |
|--------|---------|
| "The options answer the question; deferred scope is just meta-context." | REJECT — options built on the wrong premise mislead. Lead with the boundary. |
| "The user can ask if they want the deferred view." | REJECT — they shouldn't have to. The boundary IS part of the answer. |
| "Listing deferred scope up front looks like dodging the question." | REJECT — it IS the answer. State it verbatim, then give options. |

## Asymmetry Pushback (cluster 4o / F-46)

| Excuse | Reality |
|--------|---------|
| "X is revisited less frequently, so the asymmetry is fine." | REJECT unless quantified. Unquantified "less frequently" is hand-waving. |
| "Wave-1.x can pick this up later." | REJECT — deferrals stack. Each narrowing compounds the next. |
| "Deferring reduces wave-1 risk." | REJECT — asymmetry is its own risk. Narrowing trades one risk for another, it doesn't remove risk. |
| "The asymmetry already exists; I'm not making it worse." | REJECT — leaving it entrenches it. If unifying is cheap, propose the unification (don't ask permission — state the scope expansion). |

## Context Discipline (cluster 4f)

| Excuse | Reality |
|--------|---------|
| "Context is at 45%, no compaction risk — skip the phase-exit handoff." | REJECT — phase-exit handoffs are unconditional on context level. They guard against accidental auto-compact and preserve cross-session resume context. Write one every phase exit. |
| "This context-heavy subtask is fine, I'll watch the meter as I go." | REJECT — run `check-context` *before* entering a `context_heavy` subtask; if ≥ phase warn threshold, prepare-compact first. |
