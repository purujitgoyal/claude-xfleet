# xfleet skill evals

Behavioral-correctness + triggering-accuracy evals for the xfleet skills.

Unlike `tests/skills/*.bats` (static presence tests that `grep` SKILL.md), these
run a real headless Claude session against a skill and assert on its side effects
(Redis messages, state writes, refusals).

## Model

xfleet skills are **listen loops** (`xfleet await` → react → re-arm). To measure
one in a one-shot run, each eval is a **scenario fixture**:

1. **setup.sh** — flushes an isolated Redis DB, populates a throwaway repo dir,
   pre-seeds the inbox with the inbound message the scenario is about (so `await`
   returns immediately instead of idling), and writes the eval `prompt.txt`.
2. **run** — `claude -p` follows the skill, processes the one pending message,
   emits its reactions, exits. Bounded by a wall-clock `timeout`. The prompt
   instructs **single-cycle** (don't re-arm) so the run terminates.
3. **assert.sh** — inspects Redis streams + repo files; prints `PASS:`/`FAIL:`
   lines; non-zero exit if any assertion fails.

## Isolation

All runs point at `XFLEET_REDIS_URL=redis://127.0.0.1:6379/15` (a reserved
logical DB), `flushdb` before each scenario, run **serially**. Never run against
a live xfleet coordination session — DB 15 is the eval sandbox.

## Skill loading

Behavioral evals **inject** the skill ("read and follow this SKILL.md") rather
than relying on description-triggering — they test whether *following* the skill
produces correct behavior. Triggering accuracy is a separate eval set
(skill-creator's description-optimization loop).

## Run

```bash
bash tests/evals/run-evals.sh                       # all explore scenarios (default skill)
bash tests/evals/run-evals.sh --skill worker        # explore | worker | phase-cleanup | orchestrator
bash tests/evals/run-evals.sh --skill orchestrator --scenario strict-delegation
bash tests/evals/run-evals.sh --model claude-sonnet-4-6
```

`run-evals.sh` sets `XFLEET_ROLE` per skill (`orchestrator` for the orchestrator
skill, `worker` otherwise). Orchestrator scenarios pre-seed `_orchestrator.json`
via `eval_write_orch_state` (subcommands hard-error if it is absent).

Outputs land in `tests/evals/.work/<skill>/<scenario>/` (git-excluded).
