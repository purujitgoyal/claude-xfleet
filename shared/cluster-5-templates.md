# Cluster 5 Surface Templates

Three canonical surfaces the cluster 5 tooling reads. Template A and Template B
are **EXACT-FORMAT-CRITICAL** — Python tooling parses them; reproduce the
formats precisely.

---

## Template A — spec.md `## Integration Points` table

```markdown
## Integration Points

Vertical functional milestones; each IP gates a chunk of spec scope as testable
end-to-end. Contracts in scope detailed in [contracts.md](contracts.md).

| ID | Name | Repos | Contracts in scope | T4 Gate | Status |
|---|---|---|---|---|---|
| 1 | Document submission round-trip | server, web | C-1, C-2 | false | locked |
| 2 | Webhook + status polling | server, oracle | C-3 | true | locked |
```

**Authoring rules (parsed by `checklist.py`):**

- **Repos column** — MUST use each worker's canonical `$XFLEET_WORKER_NAME`
  token verbatim (no aliasing, no display names). The orchestrator's all-ready
  check compares these tokens against `integration_readiness` keys with no
  normalization; a mismatched token means the IP silently never reaches
  all-ready.
- **T4 Gate** — MUST be exactly `true` or `false` (lowercase). The checklist
  validator rejects any other casing, blank, or variant (`True`/`FALSE`/etc.).
- **Contracts in scope** — comma-separated `C-N` IDs; every ID must resolve to
  a `## C-N` section in `contracts.md` (no dangling refs, no orphan contracts).

---

## Template B — contracts.md atomic contract block

**EXACT FORMAT** — `tools/xfleet/lib/drift_check.py` and
`tools/xfleet/lib/checklist.py` parse this block. Do not alter heading names,
field order, or fence syntax.

````markdown
## C-1 — POST /v2/documents/extract

**Type:** HTTP API
**Direction:** ether-web-v1 → server
**Contributing repos:** server, ether-web-v1
**First introduced:** repo-spec phase
**Locked at:** IP-1 close
**Last amended:** —
**Change classification (since lock):** —

### Canonical shape (Pydantic, source of truth)

```python
from pydantic import BaseModel
from typing import Literal, Any

class DocumentExtractRequest(BaseModel):
    document_id: str
    extraction_mode: Literal["full", "summary"]
    options: dict[str, Any] | None = None
```

### Intent (human-authored)

- **Endpoint:** `POST /v2/documents/extract`
- **Error contract:** 400 invalid `document_id`; 404 not found; 422 extraction failure
- **Idempotency:** Yes — same `document_id` + `extraction_mode` returns existing extraction if complete.

### Verification at IP close (when in scope)

- **Drift check (deterministic, T1):**
  - server (`app.models.documents:DocumentExtractRequest`): `xfleet drift-check --contract C-1 --repo server`
- **Integration test (T2):**
  - server: `pytest tests/integration/test_document_extract.py`
- **Peer-review (T3):** orch dispatches `/xfleet:x-vergence-check` reading slices + drift reports + test results + intent prose.

### Amendments

_None yet._
````

**T1 Drift-check locator format (REQUIRED for every Python contributing repo):**

Each Python contributing repo MUST get a locator line of the exact form:

```
  - {repo} (`module.path:ModelName`): `xfleet drift-check --contract C-N --repo {repo}`
```

The backtick-wrapped `module.path:ModelName` coordinate is what
`drift_check.py`'s `find_locator()` function consumes — it looks for a line
matching `{repo} (` then extracts the first `` `module:Model` `` coordinate via
regex. The coordinate is used to import the model from the repo's live codebase
for comparison against the canonical shape. If this line is missing or
malformed, `drift_check.py` exits with a hard error.

**Non-Python repos (e.g. TypeScript frontends) get NO drift-check line and NO
locator.** Deterministic T1 drift checking requires a Pydantic model; TypeScript
repos have no equivalent. Cross-repo alignment for TS repos is covered by T3
(`x-vergence-check`), which reads code slices and contract intent via LLM
review — not by importing a model. This is the TS-dropped decision: omitting the
locator line for a TS repo is correct, not an oversight.

**`checklist.py` requires** (verified per contract section):
- `### Canonical shape` subsection with a ` ```python ` fence
- `### Intent` subsection
- `### Verification at IP close` subsection

---

## Template C — plan.md `## Epics` section (per-repo, worker-authored)

```markdown
## Epics

| Epic | Anchored IP | Test criteria |
|---|---|---|
| E-1 | IP-1 | Migration applied; auth tests pass |
| E-2 | IP-1 | C-1 contract diff clean; handler tests pass |
| E-3 | (internal) | Background job refactor; manual smoke test |

### E-2: Document extract endpoint

**Anchored IP:** IP-1
**Contracts in scope (from spec):** C-1
**Test criteria:** C-1 drift check clean; integration test green

#### Tasks
- [ ] Implement POST /v2/documents/extract handler
- [ ] Add Pydantic models matching C-1 canonical
- [ ] Run: `xfleet drift-check --contract C-1 --repo server`
```

**Plan-fold coverage rules:**

- Every IP this repo contributes to must have ≥1 anchored epic in the table
  (no contributed IP left without an epic).
- Every in-scope contract for a contributed IP must be touched by ≥1 anchored
  epic (no in-scope contract without a touching epic).
- An epic marked `(internal)` contributes no cross-repo contract and needs no
  anchored IP; it is still valid in the table.
- A plan is not mergeable while any contributed IP has no anchored epic or any
  in-scope contract has no touching epic.
