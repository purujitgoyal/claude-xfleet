---
name: x-vergence-check
description: >
  Use at Integration Point close in an xfleet wave to verify cross-repo
  contract alignment post-code / pre-PR. The orchestrator dispatches this
  (parameterized Agent invocation) once all contributing repos signal
  integration-ready and T1 drift + T2 integration tests are in hand. Reads
  each repo's slice, T1 drift reports, T2 results, and locked contract intent;
  emits a 5-flag findings list. Invokable as `/xfleet:x-vergence-check`.
---

## Role

x-vergence-check is the T3 review surface at an xfleet Integration Point close.
It runs in the **orchestrator session** as a parameterized Agent invocation —
NOT as a registered agent type. It does not write code, modify specs, or send
coordination messages. It reads, classifies, and reports.

Workers gather evidence before signaling integration-ready (see the
`verification-before-completion` superpowers skill). x-vergence-check is the
review side: the orchestrator dispatches it after all workers are integration-ready
and deterministic T1 + T2 evidence is in hand.

## Inputs

The dispatching orchestrator supplies:

- **Per-repo code slice** — the code in each contributing repo that implements
  the in-scope contracts (routes, handlers, consumers, producers).
- **T1 drift reports** — per-repo per-contract output from `xfleet drift-check`.
- **T2 integration-test results** — test runner output for contracts touched by
  this wave.
- **Locked contract intent** — the Markdown intent blocks from `contracts.md`
  for each in-scope contract.
- **Actual handler / route / consumer code** — the live implementation for each
  contract in each repo, for semantic drift analysis.

## 5-Flag Mandate

Evaluate every in-scope contract against each flag. A contract may carry
multiple flags.

**F1 — API Evolve taxonomy.** Classify every contract change as one of:
additive / non-breaking / breaking / removal. Breaking or removal without a
matching migration note is a finding.

**F2 — Spec bypass.** A repo implements a different surface than the locked
contract (different path, different method, missing field, extra required field).
Any deviation from the locked contract that is not an explicitly additive
extension is a finding.

**F3 — Semantic drift.** Status-code shifts (200 → 202, 404 → 400), error-body
contract drift, idempotency violations, path drift. Compare the actual handler
behavior against the locked intent; flag any observed divergence.

**F4 — Cross-repo asymmetry.** One contributing repo's interpretation of the
contract diverges from another's — conflicting status codes, mismatched field
names, incompatible error shapes. Flag any pair where the two repos cannot
interoperate on the current contract surface.

**F5 — Intent gap.** The locked intent prose is underspecified — the wording is
ambiguous enough that drift cannot be conclusively classified as compliant or
non-compliant. Flag the specific clause and name the ambiguity; do not guess the
intent.

## Output

A structured findings list. Each finding: contract identifier, flag (F1–F5),
severity (breaking / non-breaking / informational), affected repo(s), evidence
(quote from the T1/T2 input or code slice), and a recommended resolution.

**Empty findings list = pass.** A pass is a positive signal — state it
explicitly so the orchestrator can gate the wave.

## Two-Side Composition

- **Worker side** (`verification-before-completion`): before signaling
  integration-ready, each worker gathers drift output, test output, and code
  evidence. Completion claims require evidence, not assertions.
- **Review side** (this skill): the orchestrator dispatches x-vergence-check
  once all workers have signaled and submitted their evidence bundles. It cannot
  run until T1 + T2 evidence exists; it does not replace them.

Neither side substitutes for the other. A clean T1 + T2 run does not waive the
T3 review; a clean T3 review does not waive T1 + T2.
