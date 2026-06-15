# Orchestrator Rationalizations-to-Reject

Excuses the orchestrator will be tempted by, and the reality that overrides them.
Referenced from `skills/orchestrator/SKILL.md`. When a rationalization here
matches your current reasoning, the **Reality** column wins.

## Autonomous Execution (cluster 4n / F-36)

| Excuse | Reality |
|--------|---------|
| "This routing decision feels important — I should confirm with the human first." | Importance is not a gate. A gate is a phase-level emission or an escalation. Route inbound traffic without check-ins. |
| "There's some uncertainty about which worker owns this — let me ask the human." | Resolvable uncertainty is not pause-worthy. Read the roster / state files first, then route. |
| "The human seems available on Slack, might as well confirm." | REJECT — proactive check-ins break flow and re-train the human to babysit. Ping only at gates, escalations, and hard-stops. |
| "Several messages just arrived; let me surface each as it lands." | REJECT — accumulate handler outputs and surface ONCE per iteration (cluster 4k). Per-arrival surfacing IS the F-9 problem. |
| "A phase-complete arrived; I should advance the phase now." | REJECT — `check_phase_complete()` evaluating true does NOT auto-emit. Surface the gate summary and wait for human approval (cluster 4a). |

## Authority Hierarchy / Strict Delegation (cluster 4h)

| Excuse | Reality |
|--------|---------|
| "I'll just peek at the repo to find out X." | REJECT — ask the worker via `xfleet task <worker>` (orch→worker; `question` is worker-only). Orch never reads peer-repo source. |
| "I need to understand the repo structure before I can ask a sensible question." | REJECT — send a `task` asking the worker for the framing too. "How should I ask about <topic> in your repo?" is itself a valid `task`. Orch is the human's proxy and may also consult the human-in-the-loop. |
| "I just need a quick grep to know if X exists." | REJECT — `xfleet task <worker> --message "does X exist?"` does the same job without breaking the delegation invariant. |
| "Partial grounding left a gap; let me check the repo to fill it." | REJECT — even gap-filling is dialogue-driven. The worker is authoritative for its repo's current reality; a solo read would be stale or wrong and regresses F-1. |
| "It's a tiny coordination-root read, surely the repo source is fair game too." | REJECT — permitted reads are the coordination root (`$XFLEET_COORDINATION_ROOT`: spec.md, backlog, state files) + grounding files loaded by the SessionStart hook. Repo source is never on that list. |

## Digest table format (cluster 4k)

When a human-review batch carries **≥ 2 items**, surface with this table; a
single-item surface may be free-form. The human opens `path` for full content —
never dump finding bodies into the surface.

```
| source | type | status | summary | path |
|--------|------|--------|---------|------|
| server | review | 3 findings | auth-token reuse | <review-path> |
| oracle | review | 5 findings | schema drift | <review-path> |
```

Before surfacing, **group by `dispatched_id`** (read `directive_log[]` /
`task_log[]` / `concern_id` on the messages being surfaced). If 2+ share a
`dispatched_id`, group them and **flag disagreements explicitly at the top** of
the surface. Uniform agreement collapses to one line.
