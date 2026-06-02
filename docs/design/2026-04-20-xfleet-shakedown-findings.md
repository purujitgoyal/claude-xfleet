# xfleet shakedown run — pain points

Running log of issues observed during the 2026-04-20 integration shakedown (Task 26 of v2-fixes plan). Collecting before proposing fixes — do not jump to solutions yet.

## Format
Each entry: **short title** — what happened, why it's a problem. Add severity/tag later.

## Consolidation map (2026-05-04)
Findings are numbered F-1 through F-50 with stable IDs (cross-references rely on these). Some findings were consolidated as merges or sub-findings to reduce redundancy:

| Parent | Sub / merged | Relationship |
|--------|--------------|--------------|
| F-6 | F-48 | mechanism (F-6) vs discipline (F-48) — distinct fix surfaces |
| F-7 | F-11 | same root (no `xfleet` wrapper); F-11 is hallucination symptom, F-7 is permission symptom |
| F-8 | **F-37 merged in** | F-37 was an amendment to F-8's fix #1 (PID cleanup unsafe across parallel sessions) |
| F-12 | F-47 | both are resume incompleteness; F-12 = task continuation, F-47 = phase-discipline skill loading |
| F-19 | F-26, F-27 | F-26 (init-vs-clean) and F-27 (finalize-section + versioning) elaborate on F-19's per-repo durability + content hygiene |
| F-29 | F-31, F-39 | F-31 (revisions integrated + re-reviewed) and F-39 (folds enumerate scope) are sub-rules of F-29's plan-phase discipline umbrella |
| F-32 | F-42 | F-32 inbound (atomic ACK→restart), F-42 outbound (two-call pattern post-send) — listener-state verification, two surfaces |
| F-25 | F-52 | F-25 orchestrator-side schema drift; F-52 same pattern across all worker state files — same fix vehicle |

All other findings are standalone. The consolidation is structural (banners + cross-refs), not content-destructive — each finding's body is preserved in place.

## Decisions Log
Resolutions reached during fix-discussion passes. Each entry points to the findings it closes and the fix vehicle.

| Date | Cluster / Findings | Decision | Rationale |
|---|---|---|---|
| 2026-05-04 | **Cluster 1 — Listener Lifecycle** (F-8 incl. F-37 amendment, F-32 incl. F-42 sub, F-41) | Fix vehicle is **F-51 Phase B** — plugin commands carry the discipline (atomic state writes, baked-in restart, send-with-verify, hook-based check-context injection). No standalone skill-level fixes. | F-35: skill-rule fixes won't stick. Plugin is the structural enforcement layer. Listener cluster collapses to one implementation thread inside Phase B. |
| 2026-05-04 | F-51 (plugin transformation) | Plugin is the right vehicle. **Defer Phase A kickoff** until all clusters have been discussed — later clusters may surface more plugin requirements. | Avoid premature interface freeze; let cluster 2–4 discussions inform the plugin's command/hook surface before building. |
| 2026-05-04 | F-52 (state ad-hoc growth) | Roll into F-25 as sub-finding. Same fix vehicle (plugin state helpers + JSON Schema). | Single fix surface; same root cause at orchestrator and worker layers. |
| 2026-05-04 | **Cluster 2 — Resume Completeness** (F-12 incl. F-47 sub) | Fix vehicle splits: (a) **F-51 Phase B** — `xfleet resume` Bash command bundles full resume sequence (state load, listener restart, auto-continue logic, `--standby` flag); (b) **F-53** — local `prepare-compact` skill (`~/.claude/skills/prepare-compact/`) gains Active-Skills + In-Session-Directives + Resume-Instructions sections; resume flow reads them and re-engages. **F-47 collapses into F-53.** | F-53 generalizes the fix beyond xfleet — every `/clear`+resume flow benefits. Cleaner than hook-based skill loading (which plugin survey confirmed isn't possible today). |
| 2026-05-04 | Plugin survey | Capability reference card at `~/workspace/docs/superpowers/research/2026-05-04-xfleet-plugin-capability-card.md`. Key constraints: hooks can't dispatch agents/skills; plugins don't auto-add permissions (but ship default settings); distribution via marketplace.json. | Verified before finalizing cluster 2; surfaces F-47's enforcement gap. |
| 2026-05-04 | F-51 Phase C (MCP) | Demoted from "deferred conditional" to **"deferred with strong preference against"**. Operator pushback: active running processes have lifecycle costs (slack-channel WebSocket cycle issues). MCP for xfleet is not pursued; benefits substituted via SessionStart hooks (protocol primer injection) + bash_id ownership tracking + diagnostic-only foreign-process detection. Conditions to revisit set to high bar (3 conjunctive criteria). | xfleet ops are stateless local Redis; persistent process gives little benefit relative to operational risk. |
| 2026-05-04 | **Cluster 3 — Plan-phase discipline** (F-29 incl. F-31 + F-39 subs, F-34) | Plan phase becomes structurally symmetric with repo-spec. Fix split: (a) **F-51 Phase A** bundles updated `plan.md` phase skill (xrepo negotiation + plan_reviewers + findings-triage loop + re-emit phase-complete) and new `/finalize-plan` skill; (b) **F-51 Phase B** — `xfleet-finalize-plan` and reviewer-dispatch tools manage timestamps atomically; `xfleet phase-complete --phase plan` refuses if `last_reviewed_at < last_revised_at`; (c) **CLAUDE.md "Plan editing rules" addition** — durable rule "always invoke `superpowers:writing-plans` for plan edits (F-34); produce coverage table per `/plan-fold` before folding (F-39)"; (d) **new local `plan-fold` skill** at `~/.claude/skills/plan-fold/` — provides F-39 coverage-table procedure + F-34 Rationalizations table; generic (applies beyond xfleet); (e) **PostToolUse hook on Edit/Write to `**/docs/superpowers/plans/*.md`** — soft nudge "produce coverage table / re-run reviewers"; default `plan_reviewers:` = `architect-review`. | Multi-layer auto-load reliability: CLAUDE.md durable rule + local skill for procedure + hook reinforcement + F-53 handoff capture. |
| 2026-05-04 | Cluster 3 dependencies | **Upstream: F-19 path migration** — plans must move from `~/.claude/plans/` to `{repo}/docs/superpowers/plans/` for the PostToolUse hook to fire on a durable path. **Downstream: `/cleanup` skill update** — must not sweep repo-local plan paths (now durable, not transient); existing global-only sweep behavior preserved for coordination scratch. Both belong in cluster 4 / durability work. | Hook reliability + cleanup correctness depend on F-19 landing first or alongside. |
| 2026-05-04 | **Cluster 4b — State schema discipline** (F-25 incl. F-52 sub) | Principle: **state files are for state**. Bloat reflects misclassification — backlog/deferred/decisions/commits all belong elsewhere. Fix shape: (a) tight durable schema, mostly tool-managed (agent doesn't classify; tools route by purpose); (b) narrow opt-in scratch (`--scratch` flag; default refusal on unknown keys); (c) first-class artifacts get their own homes — `xfleet/{slug}/backlog.md` (orch-level, single source of truth), spec's Decisions Log + Deferred section for spec-time deferrals, existing decisions/handoff docs for the rest; (d) `/cleanup` gains **three modes**: `--session` (graceful exit: prepare-compact + listener-stop + state-validate; preserves everything), `--phase` (sort scratch into artifacts; preserves state/Redis/artifacts; wipes only scratch), `--final` (existing destructive cleanup with sort-first pass; preserves only repo-local durable artifacts); (e) Python-in-bin for validation when shell becomes insufficient (jsonschema lib); MCP parked per F-51 Phase C. Path convention: artifacts move to `{repo}/docs/superpowers/xfleet/{slug}/` (renamed from `branches/`); xfleet artifacts NOT mixed with regular `plans/specs/research/handoffs/` dirs. Wikilinks `[[name]]` adopted as free baseline (zero infra cost, pure convention) — added when authoring; index.md remains trigger-gated upgrade. | Field list deferred to implementation step — derived from principle, not designed standalone. F-56 (master index) and graphify-research (2026-05-04) confirm: skip discovery infrastructure; wikilinks free, index.md when pain hits. |
| 2026-05-04 | F-56 + graphify research | Discovery layer for cross-repo artifacts: validated against Karpathy's LLM Wiki gist + Graphify analysis. Outcome: **stick with grep + fixed paths today; wikilinks `[[name]]` as free baseline (zero infra, pure convention); auto-generated `xfleet/{slug}/index.md` when concrete trigger hits (>20 grep hits / agent can't find known artifact / 2+ misfind incidents per wave); Graphify and embeddings explicitly out of scope.** Research saved at `docs/superpowers/research/2026-05-04-doc-discovery-research.md`. | xfleet's 30-50 files/wave at fixed paths is well below the threshold where graph/embedding infra pays off. Karpathy's own recommendation is grep + index, not graphs. |
| 2026-05-04 | **Cluster 4c — Per-repo durability + path migration** (F-19 incl. F-26 + F-27 subs; F-54 closed) | Path convention: `{repo}/docs/superpowers/xfleet/{slug}/` for per-repo work; `workspace/docs/superpowers/xfleet/{slug}/` for cross-repo work. xfleet artifacts NOT mixed with regular `plans/specs/research/handoffs/`. Two-tier durability: (a) **durable through `--final`** = ~~per-repo `section.md` + `plan.md` + `handoff-{phase}.md`; cross-repo `spec.md` + `backlog.md` + `README.md` (these support ongoing backlog/deferred tracking + post-merge audit)~~ — **SUPERSEDED 2026-05-10 by cleanup-model revision**. Current durable list: cross-repo `spec.md`, per-repo `section.md`, per-repo ADRs at `{repo}/docs/adr/NNN-{slug}.md`, existing repo-resident architecture docs. `plan.md`, `handoff-{phase}.md`, `README.md`, `backlog.md` are now transient (see cleanup-model-revision row); (b) **transient (wiped at `--final`)** = `section-vN.md` snapshots (v0 = `section-v0.md`, the spec-distribution seed; renamed from former `section-init.md` for naming consistency), concerns.md, reviews.md, alignment.md, intermediate decisions.md, prd-reviews/. Review/concern/alignment findings BAKE INTO durable files at finalize (plan revisions, spec Decisions Log, spec Deferred section, backlog entries) before transient wipe. **Versioning without git: manual `section-vN.md` snapshots created by `/finalize-section` at each milestone; reviewers diff `section.md` vs `section-v{max}.md`; F-54 closed (git tracking rejected — would pollute repo history with PR-irrelevant changes).** **Snapshot mechanic (Model A):** `/finalize-section` applies pending revisions to `section.md` first, then copies `section.md` → `section-v{N+1}.md` where N = max version among existing `section-vN.md` files (N=0 if only the v0 seed exists). Filesystem is the source of truth for the version counter — no stateful counter elsewhere. v0 is `section-v0.md` (immutable seed written by the spec-distribution step; semantic equivalent of the former `section-init.md`). Mid-session re-distribute: subdir versioning (`xfleet/{slug}-v1/`, `xfleet/{slug}-v2/`); BMAD epics (F-49) likely make this rare. Global transient state moves to `workspace/.xfleet/{state,concerns,resolutions,directives}/` (NOT `~/.claude/`) — single coordination root, plugin pre-allows once, gitignored, wiped at `--final`. Existing wave-1 artifacts grandfathered (no migration). | Field-level decisions (canonical worker schema fields, etc.) deferred to implementation; principles + path convention locked. |
| 2026-05-04 | **Cluster 4d — Phase-transition handoffs (F-10)** | Universal rule: before exiting any non-idle phase (self-driven `phase-complete` OR orchestrator-driven `phase` signal), write a handoff. Implemented in **F-51 Phase B `xfleet phase` command** (`--enter <new>` / `--complete`): if `current_phase ∉ {idle, <new>}`, run prepare-compact → write handoff → update state → load new phase skill (or emit phase-complete). idle → first-phase: no handoff. **Handoff path:** `{repo}/docs/superpowers/xfleet/{slug}/handoff-{outgoing-phase}.md` (~~durable through `--final`, per cluster 4c~~ — superseded 2026-05-10 by cleanup-model revision: handoff-{phase}.md is now **transient**, wiped at `/cleanup --final`. Mid-wave the handoff still serves resume + prepare-compact + phase-exit-richness; post-wave audit is covered by spec.md + ADRs + git history per cleanup-model revision). **Section selection is xfleet's responsibility, not prepare-compact's:** prepare-compact stays generic per F-53; xfleet phase skill instructions dictate that phase-boundary handoffs use the Resume Instructions section and skip F-53's Active Skills + In-Session Directives (those are session-level, not phase-level; durable directives live in CLAUDE.md/memory and apply across phases anyway). **Edge cases need no special handling:** cancelled exits write anyway (no downside); phase signal during resume processes immediately (per F-58: standby is a self-drive gate, not an inbox gate; orch dispatch IS human approval). Closes F-12 fix #3 (orchestrator-driven transitions get the same handoff richness as self-driven). | Phase B command owns the discipline (skill-level rules don't stick — F-35); per-phase handoff is a first-class durable artifact (cluster 4c); section selection in the caller keeps prepare-compact generic. |
| 2026-05-07 | **F-58 — Worker `standby` mode is a self-drive gate, not an inbox gate** (closes cluster 2's open scope) | Standby suppresses ONLY F-12 fix #1's auto-continue of dormant in-flight tasks. Orchestrator inbound is always honored — orch dispatch IS human approval per F-30. **Single-track `current_task`:** orch directives during standby may update `current_task` in place; on continue, worker resumes whatever it points to NOW. If `current_task` is empty when human says continue, worker reports "no current task; awaiting direction" — human drives next steps via orch or directly, worker does not assume. Vehicle: cluster 2's `xfleet resume --standby` already provides this if scoped correctly + new `xfleet continue` Phase B command for explicit unpause; `messaging.md` documents the semantics. State schema (cluster 4b): `standby: bool`. | The inverse drift (worker queues orch inbound during standby) is a real failure mode — codifying scope forecloses it. Single-track avoids inverting F-30. |
| 2026-05-07 | **Cluster 4e — Message taxonomy extension** (F-22, F-23, F-33; F-55 folded) | Three new wire-message types: (a) **`directive` + `directive-ack` + `directive-response`** (orch (human-sourced) → worker; no rounds; auto-fires `human_engaged`; closes F-22). (b) **`task` + `task-response`** (orch → worker procedural; no rounds; closes F-23 taxonomy gap). (c) **`resolution-ack`** (worker → worker terminal handshake; closes F-33's missing peer-notify). Vehicle: **F-51 Phase A** — messaging.md taxonomy table + closure-handshake doc + **single `xfleet` binary with subcommand-per-message-type CLI** (mirrors `git`/`kubectl`/`docker`): `xfleet directive`, `xfleet task`, `xfleet concern`, `xfleet concern-reopen` (originated in cluster 4a; sender authority extended to orch-OR-worker per A3 2026-05-10 amendment), `xfleet resolution`, `xfleet escalation` (added by cluster 4g), `xfleet phase-complete`, `xfleet question`, `xfleet answer`, `xfleet review` etc. Recipient stays positional. **`--type` flag eliminated entirely; `xfleet send` retired** — type is structural, no memorization burden, validator at each subcommand enforces type-specific required flags up-front (closes F-55). Auto-handler messages (`directive-ack`, `task-response`, `resolution-ack`, `resolution-summary`) are internal helpers inside the wrapper — not user-facing subcommands; emitted reflexively by handlers. Allow-list collapses to single line `Bash(xfleet *)`. Operational subcommands from F-7 (`xfleet status`, `xfleet listen`, `xfleet peek`, `xfleet ack`, `xfleet resume`, `xfleet continue`, `xfleet phase`) share the same wrapper. Final user-facing surface: ~12-15 subcommands. **F-51 Phase B** — orchestrator `xfleet directive` and `xfleet task` commands handle atomic state updates. **Worker handler additions** (always-on): directive (read `--path`, ACK, execute per `--expected_action`, respond), task (read `--path`, execute, respond), resolution (FIXED per F-33 — now sends resolution-ack to peer + resolution-summary to orch), resolution-ack (mark concern closed-acked). **State schema** (cluster 4b): `_orchestrator.json:directive_log[]`, `_orchestrator.json:task_log[]`, worker `confirmed_closed_concerns[]`. **Acks are wire-only** — no `--path`, never written to files. F-23 audit (2026-05-07) confirmed 3 existing `*-ack.md` files as misuse. **Internal-procedures rule:** orchestrator-internal checklists live in skill content + skill state, never as messages or in `concerns/`. **F-23 audit findings** (2026-05-07): ~54% of `~/.claude/concerns/` is misclassified — ~26 directive-shape, ~17 task-shape, ~3 ack-shape misfiles, 1 mixed orch-internal+task. Wave-1 grandfathered per cluster 4c — no in-place migration; new wave starts with correct types. **Forward reference:** volume expected to decrease materially once cluster 5 (F-49 BMAD epic decomposition + F-50 contract-reconciliation skill) lands — most ad-hoc directive/task dispatches were symptoms of unbounded mid-implementation drift. F-58 confirms orch-authority framing (workers execute directive/task per F-30, no second-guessing). | Three protocol additions; bulk is taxonomy doc + validators + handlers. Audit's ~54% misuse rate gives empirical weight — taxonomy cleanup is overdue, not theoretical. |
| 2026-05-07 | **Cluster 4g — Authority hierarchy enforcement** (F-30) | F-58 already encodes the principle (orch is human's proxy). Cluster 4g adds **structural enforcement at the protocol layer** + clarifies the breaking/deviation escape valve so F-30's discipline doesn't over-block F-36's legitimate escalations. **Two distinct disciplines:** (a) workers don't bypass orch to RE-CONFIRM directives (F-30 — re-confirmation bypass forbidden); (b) workers DO escalate genuine plan-deviations / breaking errors fast (F-36 — escalation required). Channel routing depends on intent, not channel availability. **Fix shape:** (1) F-51 Phase A — `xfleet question` validator: target = orchestrator OR peer-worker, never literal "human"; routine path structurally constrained. (2) New **`xfleet escalation orchestrator --reason <reason> --path ... [--priority urgent]`** subcommand (folded retroactively into cluster 4e taxonomy): orch handler routes per `--reason` — **urgent reasons** (`breaking`, `plan-deviation`) bypass F-9 batching, surface to human immediately, may be paired with direct slack ping per #3 below; **non-urgent reasons** (`judgment-finding` per cluster 4a) batch per F-9 and carry alert-only payload (finding count + review-path; no content). All escalations append to `escalation_log[]`. **`human_engaged` is NOT auto-fired by escalation arrival** — auto-set only on `xfleet directive` dispatch per cluster 4a; human decides per escalation whether to engage. Validator (Phase A `messaging.md`) declares `--reason` enum + per-reason routing table; rejects unknown reasons. (3) **Direct-to-human via slack-channel plugin permitted in worker sessions** for breaking/deviation escalations only — **always paired** with `xfleet escalation orchestrator` in parallel for audit trail (non-negotiable invariant; orch must know an escalation occurred even when human was pinged via slack). (4) **No hooks on slack-channel plugin tools** — discipline lives in skill text + Rationalizations-to-Reject table, not in PreToolUse/PostToolUse blocks. F-35 acknowledged ("skill-rule fixes won't stick"), but blunt structural blocks are worse here — they over-constrain F-36 escalation. (5) **Authority Hierarchy section** in CLAUDE.md / worker skill codifies the intent distinction with examples. **Worker-to-worker channel is valid** with disambiguation: `xfleet concern peer` for peer negotiation (rounds matter, F-15 semantics) vs `xfleet question peer` for ad-hoc clarification (no rounds). Skill text must call out the difference so workers don't conflate the two types. (6) **Slack-channel plugin support for worker-direct-replies is a precondition** — cluster 4g assumes the plugin ships and works correctly for secondary sessions; without it, escalations fall back to orch-only. **Closes:** F-30. | F-58 set the principle; cluster 4g is enforcement + escape-valve clarification. Hybrid routing (orch default + slack-direct-for-escalation) preserves F-30's anti-bypass discipline while honoring F-36's escalation requirement. No structural blocks on slack tools — overcautious; cultural discipline + audit invariant suffice. |
| 2026-05-07 | **Cluster 4f — Compaction policy** (F-16 + F-44) | Five components managing context size: (1) **Phase-aware in-phase thresholds (F-16 #1)** — phase skill frontmatter declares `warn_at` / `critical_at`; defaults 70/80; repo-spec=50/65 (write+review burst-heavy; manually validated 2026-04-22); other phases default until observed data tunes them. Worker base loop reads on phase entry, propagates to `check-context`. (2) **Pre-flight compact before write-heavy subtasks (F-16 #2)** — phase skills mark specific subtasks as `context_heavy: true`; worker runs `check-context` before entering such a subtask; if ≥ phase warn threshold, runs `prepare-compact`, sets `status: "compacting"`. (3) **Suggested (not auto) compaction at human gates (F-16 #3)** — orchestrator surfaces "compact before <gate>?" suggestion at F-14's `negotiation-complete` and similar gates; human decides. Suggest-not-auto prevents surprise compact during human's unrelated review. (4) **Always-compact at phase transitions (F-44 simplified)** — universal: every phase transition runs prepare-compact + clear + resume + dispatch. Pattern (b) is the only flow (hold + wait + dispatch); pattern (a) (dispatch + queue in inbox) survives only as emergency fallback. Cluster 4d's universal phase-exit handoff IS the compact artifact — no threshold check at boundaries; threshold reasoning applies only inside a phase. `prepare_compact_at` state field simplifies — always equal to the most recent phase-exit handoff timestamp. (5) **Subagent delegation for independent context-heavy work — fire-and-forget only.** When a subtask is independent (clear input → output, no shared state needed) AND context-heavy (deep Serena scans, multi-file analysis, audit-style work, parallel investigation), delegate via the `Agent` tool. Subagent returns summary; parent does NOT resume the subagent later. **No multi-turn consulting subagents** — agents struggle to reason about prompt-cache TTLs and time windows; keep the discipline simple to follow. Re-evaluate after observation if multi-turn nuance becomes warranted. Reviewers already follow this pattern; extend to other independent context-heavy operations. **State schema additions (cluster 4b):** `context_pct: int` (worker self-reports, updated periodically and on handler exits), `prepare_compact_at: ISO timestamp` (read from filesystem mtime of most recent phase-exit handoff). **Vehicle:** F-51 Phase A — phase-skill metadata fields (`warn_at` / `critical_at` / `context_heavy` subtask markers); `check-context` skill gains optional `--warn-at` / `--critical-at` override args. F-51 Phase B — `xfleet phase --enter` pre-flight gate runs prepare-compact dispatch automatically; `xfleet status` shows `context_pct` per worker for orch's gating logic. **Composes with:** Cluster 4d (phase-exit handoff IS the compact artifact); Cluster 4b (`context_pct` + `prepare_compact_at` state fields); F-58 (standby covers the clear+resume window between phases); Cluster 4a (upcoming) — F-14's gate is the suggest-compact anchor. **Closes:** F-16, F-44. | Threshold reasoning lives inside phases; phase boundaries always compact (universal rule, not threshold-gated). Subagent fire-and-forget keeps the discipline simple to follow — observe before adding multi-turn nuance. |
| 2026-05-08 | **Cluster 4a — Orchestrator completion gating** (F-13, F-14, F-17, F-21; F-15 round-counter fix bundled) | Six integrated mechanisms composing every prior cluster lock. (1) **Event-driven completion check (F-13):** orch runs `check_phase_complete()` after every state-changing inbound (`review`, `resolution`, `resolution-summary`, `task-response`, `directive-response`, `escalation-response`). Not timer-driven. Each evaluation logged to `_orchestrator.json:completion_log[]` for debuggability. (2) **Reviewer-findings gating (F-21) — alert, not content dump:** worker triages findings locally per intensity. **LOOKUP/PATTERN:** worker auto-revises + re-runs reviewers, looped up to convergence counter (default **3 passes**); on overflow, auto-escalate to JUDGMENT (safety valve). **JUDGMENT:** worker emits **alert-only** escalation via `xfleet escalation orchestrator --reason judgment-finding --finding-count N --review-path {path}` — minimal payload, NO content; full details stay in the review file. Optionally direct slack-ping (cluster 4g routing). Orch batches alerts per F-9; surfaces clean list ("server: 3 findings; oracle: 5 findings — engage which?"); user decides per case (engage via orch / direct worker / drop entire batch as over-engineering). Reviewer perfectionism stays contained unless user opts in. **Graduated intensity per phase:** qa-spec=critical (initial authoring; perfectionism warranted), repo-spec first-pass=high, repo-spec re-finalize / post-implementation=standard, implement=standard. Override at invocation: `xfleet phase --enter <phase> --review-intensity <level>`. (3) **Human gate before phase-level emissions (F-14 A + F-17 one-shot auth):** F-13's check evaluating true does NOT auto-emit. Gate surfaces summary to human (combined with cluster 4f's suggest-compact at gate). State: `phase_emissions.{phase}.{signal} = {approved_by_human, sent_at, sent_to, emission_id}`. Human approve sets `approved_by_human=true` → emit fires → flag clears + `sent_at` records. Re-emission after reopen requires re-approval (F-17 #3). Idempotency via UUID `emission_id` on the wire — workers track last-handled per phase, duplicate/older=no-op (session-restart-safe). Audit log per emission attempt. (4) **`human_engaged` flag (F-14 B) — simplified per observe-first discipline:** state field per cluster 4b: `{active, concern_id, set_at, reason}`. Suppressions when active: round-5 hard-stop, straggler warnings (scoped), all-idle prompts. **Toggling:** `xfleet engage [concern_id]` / `xfleet disengage` Phase B commands, any-session writable (writes to shared orch state). **Auto-set only on `xfleet directive` dispatch** — orch knows it just relayed a human-sourced directive; unambiguous. NO worker-side direct-input detection, NO slack-reply auto-trigger, NO elaborate intervention-aware logic — observe before adding machinery. Direct interventions surface friction as new findings if the autopilot misbehaves. (5) **`concern-reopen` message** (F-14 C; designed in this cluster, registered into cluster 4e's taxonomy as a retroactive entry): `xfleet concern-reopen <worker> --concern_id X --round-note "..." [--alignment-hint "..."]` (orch → workers). Workers reopen local state, re-investigate, respond per normal flow. **Round counter continues, not resets** — round 5 reopened to round 6 doesn't trigger escalation because `human_engaged.active=true`. (6) **F-15 round-counter fix** (folded in): INCR `concern:{id}:rounds` only on `--type concern` (statement/counter), NOT on `--type response`. Round = peer-A statement + peer-B response = 1 round. Round-5 hard-stop fires at 5 actual rounds of disagreement (10 sends). **State schema additions (cluster 4b):** `_orchestrator.json:phase_emissions`, `emission_log[]`, `human_engaged`, `completion_log[]`; worker `review_revision_count`, `findings_status: {finding_id: state}`. **Vehicle:** F-51 Phase A — messaging.md taxonomy adds `concern-reopen` + `review-reopen` (a `directive` variant); phase-skill metadata adds `review_intensity` field (graduated defaults); convergence-counter default. F-51 Phase B — `xfleet phase --enter/--complete` (cluster 4d) wires the human gate; `xfleet engage`/`disengage` commands; orch runs completion-check after every inbound handler. **Closes:** F-13, F-14, F-15, F-17, F-21. | Composes every prior cluster lock (4b state, 4d emission, 4e taxonomy + escalation, 4f suggest-compact, 4g escalation_log, F-58 standby). Alert-not-content escalation is the F-9 win — preserves user's choice of channel + engagement intensity rather than forcing perfectionist details into the main thread. Observe-first discipline on engagement detection. |
| 2026-05-10 | **A1 — State-schema consolidation** (resolves consistency-audit BLOCKER A1; supersedes F-25 body's "Fields proposed by open findings" subsection; closes M4 + M5 + M6 from same audit) | Single ratified field list across cluster 4a/4b/4d/4e/4f/4g/F-58 — Phase A validator's source of truth. **`_orchestrator.json` (orch-only writes):** `cycles` (existing int), `last_all_idle_notify` (existing ISO\|null), `last_round5_pause` (existing ISO\|null), `phase_emissions: {phase: {signal: {approved_by_human, sent_at, sent_to[], emission_id}}}` (4a), `emission_log[]: {phase, signal, attempted_at, approved_by_human, emission_id, outcome}` (4a), `human_engaged: {active, concern_id\|null, set_at\|null, reason\|null}` (4a, F-58), `completion_log[]: {evaluated_at, trigger_msg_type, outcome, missing_workers[], missing_signals[]}` (4a), `directive_log[]: {directive_id, target, concern_id\|null, scope, expected_action, dispatched_at, response_status}` (4e), `task_log[]: {task_id, target, task_kind, dispatched_at, response_status}` (4e), `escalation_log[]: {escalation_id, source_worker, reason, path, priority, received_at, surfaced_at, resolved_at\|null}` (4g). All state-schema additions live at the top level of `_orchestrator.json` (closes M6 — explicit field paths for validator). **`{worker}.json` (worker-only writes; orch reads via `xfleet status`):** `current_phase` (existing string), `status` (existing enum), `current_task: {task_id, description, source: 'self'\|'orch-task'\|'orch-directive', received_at}\|null` (F-58 single-track; in-place update by orch task or directive-with-`--expected_action`), `last_updated` (existing ISO), `listen_bash_id` (F-8 amendment string), `standby: bool` (F-58), `context_pct: int` (4f; STORED — worker self-reports on handler exit + periodically), `review_revision_count: int` (4a; resets on phase entry), `findings_status: {finding_id: 'new'\|'auto-revised'\|'awaiting-review'\|'resolved'\|'escalated'}` (4a), `confirmed_closed_concerns[]: [concern_id]` (4e from resolution-ack handler). **Derived (NOT stored — closes M4):** `prepare_compact_at` is computed from filesystem mtime of the most recent `{repo}/docs/superpowers/xfleet/{slug}/handoff-{phase}.md` — not a state field. **`current_task` write rules (closes M5):** `xfleet task` ALWAYS overwrites `current_task` (assignment is the message's purpose); `xfleet directive --expected_action <X>` overwrites with `source='orch-directive'`; `xfleet directive` without `--expected_action` is informational — `directive_log[]` only, `current_task` untouched. **F-25 collisions resolved in 4a's favor:** F-25's proposed `completion_conditions` (per-phase tracker) → 4a's `completion_log[]` (event log; debuggable + idempotent across re-evaluations, no invalidation logic); F-25's proposed `review_findings` (per-worker rollup on orch) → 4a's worker-side `review_revision_count` + `findings_status` (keeps reviewer perfectionism contained per 4a's alert-only invariant; orch never sees content). **Validator rules (cluster 4b):** strict refusal on unknown keys, **recursively** (rejection extends into nested objects like `phase_emissions.{phase}.{signal}.{field}`). Premise: tool-mediated writes — agents call `xfleet` subcommands rather than hand-editing JSON; tools always emit well-formed keys; retry rate on tool-mediated paths = 0. Validator MUST emit Levenshtein "did you mean X?" suggestions on unknown-key rejection so emergency raw edits self-correct in one retry. `--scratch` opt-in preserved as escape valve for genuinely unstructured stash. **Source-of-truth split:** prose layer at `{repo}/docs/superpowers/xfleet/shared/state-schema.md` owns lifecycle, cross-field invariants ("`human_engaged.active=true` ⟺ `xfleet engage` called OR directive dispatched"), writer ownership, examples; validator layer in plugin (Phase A; embedded JSON Schema) owns types, required/optional, enums. Prose doc cross-references the JSON Schema location. Specific plugin-internal JSON Schema layout deferred to Phase A implementation — principle (separate prose vs validator artifact) is what's locked here. **Vehicle:** Phase A day-one deliverable — `messaging.md` references this schema; `tools/xfleet/validate-state.sh` reads JSON Schema and emits did-you-mean errors; CI/precommit may diff field names between prose doc and JSON Schema if drift becomes observed (premature today). **Closes:** consistency-audit BLOCKER A1, MINOR M4, MINOR M5, MINOR M6. | F-25's tracker shapes superseded — event logs are debuggable without invalidation logic; worker-side findings_status keeps reviewer perfectionism contained per 4a's alert-only escalation invariant. Recursive strict is safe given tool-mediated discipline; main retry risk is emergency raw edits where retry-and-fix is acceptable. Splitting prose vs validator layers gives each consumer the right artifact — prose for humans, JSON Schema for runtime validators. Ratifying the field list before Phase A means the validator can ship without re-litigating field shapes mid-implementation. |
| 2026-05-10 | **A1 addendum — Cluster 4j worker fields** (resolves audit CL4 — cluster 4j locked 2 new fields after A1's table; recursive-strict validator needs them enumerated explicitly) | Two worker-state fields added by cluster 4j (PostToolUse context-check hook), to be merged into A1's `{worker}.json` top-level field list at Phase A JSON-Schema authoring time: `last_warn_emitted_at: ISO\|null` (warn-emit debounce; nullable; resets on phase entry; cleared whenever `context_pct < warn` per cluster 4j #2) and `last_check_at: ISO\|null` (below-warn throttle; updated on every script run that progresses past the early-exit gate per cluster 4j #1). **Both are STORED** (not derived) — script writes them. Validator's recursive-strict rule (A1) honors them once enumerated; without explicit addendum, strict-on-unknown-keys would reject. **Vehicle:** Phase A `state-schema.md` prose layer + JSON Schema both include these fields alongside A1's original list. **Closes:** consistency-audit CL4. | Strict validator can't honor implicit supplements; explicit > implicit per A1's own discipline. Two fields, one short row keeps the schema source-of-truth single. |
| 2026-05-10 | **A2 — Escalation routing reconciliation** (resolves consistency-audit BLOCKER A2; amends Cluster 4g row above to remove direct contradiction with Cluster 4a) | Single rule for `xfleet escalation orchestrator` handler: routing by `--reason`. **Urgent reasons** (`breaking`, `plan-deviation` — cluster 4g): bypass F-9 batching, surface to human immediately, slack-pair permitted per 4g's #3 (worker-direct ping always paired with the escalation message for audit). **Non-urgent reasons** (`judgment-finding` — cluster 4a): batched per F-9; alert-only payload (finding count + review-path; no content; reviewer perfectionism stays contained at the worker per 4a). All escalations append to `escalation_log[]`. **`human_engaged` is NOT auto-fired by escalation arrival** — cluster 4a's rule wins: `human_engaged` auto-set ONLY on `xfleet directive` dispatch. Human reviews escalation batch and decides per case whether to engage (per 4a's "engage via orch / direct worker / drop entire batch as over-engineering" framing). **Validator (Phase A `messaging.md`):** declares `--reason` enum + per-reason routing table; rejects unknown reasons; routing table is the single source of truth for handler behavior. Cluster 4g's row above has been updated in place to reflect this rule (no separate amendment row); cluster 4a's row is unchanged (already correct). **Closes:** consistency-audit BLOCKER A2. | Cluster 4g's "skip batching + auto-engage" was over-broad — covered judgment-finding which 4a deliberately keeps batched + contained. The `--reason` axis was already in 4g's CLI surface; routing by it eliminates the contradiction without inventing new structure. Auto-engage on every escalation would over-trigger `human_engaged` (every reviewer-finding burst would engage); 4a's "engage on directive" framing is the intentional discipline — escalation alerts surface, human chooses whether engagement is warranted. |
| 2026-05-10 | **A3 — Per-subcommand sender authority** (resolves consistency-audit BLOCKER A3) | Sender authority table for Phase A `messaging.md` validator — each subcommand's valid sender role (orch / worker / any) declared explicitly so the validator can reject mis-routed sends rather than letting them succeed silently. **Orch-only senders** (reject if not orch session): `directive`, `task`. **Worker-only senders** (reject if not worker session): `concern`, `resolution`, `question` (recipient = orch OR peer-worker, never literal "human" per 4g #1), `review` (orch never originates reviews per F-1/F-2 grounding), `escalation orchestrator` (recipient always `orchestrator`; routed by `--reason` per A2), `phase-complete` (recipient always orch). **Either-orch-or-worker senders** (any participant in the original concern can revisit; no orch-monopoly per user clarification 2026-05-10): `concern-reopen` — orch reopens after human review; worker reopens when new findings warrant revisiting a previously-closed concern (peer-symmetry with original `concern` flow). **Either-orch-or-worker senders** (recipient determines validity): `answer` (target = original questioner; orch-as-sender is the rare directive-clarification path — keep open, observe before tightening). **Any-session state mutations**: `engage`, `disengage` (write `_orchestrator.json:human_engaged`; smallest necessary escape valve for slack-direct-toggle scenarios). **Reflexive auto-set note (audit CL1, 2026-05-10):** `human_engaged.active=true` is ALSO auto-set as a handler-internal side-effect of `xfleet directive` dispatch per cluster 4a #4. This is NOT a CLI invocation of `xfleet engage` — the directive handler writes the field directly. Validator does not see it (no sender-authority check fires). Mentioned here for completeness; the only CLI-invocable writers remain `engage` / `disengage`. **Self-session local state**: `phase --enter`/`--complete` (each session manages its own `current_phase`; orch's call also gates emissions per 4a). **Read-only / session-local** (no authority enforcement; auto-allowed): `status`, `peek`, `listen`, `ack`, `resume`, `continue`. **Reflexive auto-handler emissions** (NOT user-invocable; emitted by handlers reflexively, never as CLI subcommands): `directive-ack`, `directive-response`, `task-response`, `resolution-ack`, `resolution-summary`, `escalation-response`. **Validator behavior on rejection:** clear error naming the offending role + valid sender(s) + suggesting correct subcommand on near-misses (e.g., orch attempting `concern` → "concerns are peer-to-peer; from orch use `directive` instead"). **Role detection:** session role inferred via state-file ownership or `XFLEET_ROLE` env exported at skill-load time; specific mechanism deferred to Phase A implementation. **Vehicle:** Phase A — sender-authority column added to `messaging.md` taxonomy table; validator at each `xfleet` subcommand entry-point reads it. **Closes:** consistency-audit BLOCKER A3. | Per-subcommand authority makes the orch/worker channel asymmetry explicit + machine-checkable. Without it, the implicit rules in cluster bodies would re-fragment as new subcommands land. The "any-session" tier (engage/disengage) is the smallest necessary escape valve — broader would weaken orch-only authority on the directive path. `answer` kept as orch-OR-worker per observe-first discipline (F-58 framing); orch-as-sender is the rare directive-clarification path with concrete use case (worker asks orch for scope clarification on a received directive without bypassing to slack); collapse to worker-only later if behavior shows orch never legitimately answers. Friendly-error guidance keeps agents productive on rejection — opaque "permission denied" wastes retries. |
| 2026-05-10 | **C1 — Phase boundary tooling: `xfleet phase` vs `/cleanup --phase`** (resolves consistency-audit CLARIFICATION C1) | The two are orthogonal. **`/cleanup --phase`** (cluster 4b) = optional housekeeping (sort scratch → artifacts; user-discretionary; preserves state/Redis/artifacts). **`xfleet phase --enter <new>` / `--complete`** (cluster 4d) = required state-machine transition (write phase-exit handoff, run prepare-compact, update state, load new phase skill or emit phase-complete signal). `xfleet phase` does NOT auto-invoke `/cleanup --phase`; on entry it surfaces a suggestion if non-empty scratch is detected ("non-empty scratch detected — `/cleanup --phase` to sort first, or proceed and lose"), suggest-not-auto. **Recommended user flow at phase boundaries:** (1) optional `/cleanup --phase` to sort scratch into durable artifacts, (2) `xfleet phase --complete` (worker-self) or orch-dispatched phase-complete signal — handoff + prepare-compact runs in this step, (3) `xfleet phase --enter <new>` on receiving worker — loads new phase skill, ready. **Closes:** consistency-audit CLARIFICATION C1. | `/cleanup --phase` has user-judgment elements (which scratch is artifact-worthy vs disposable); auto-running risks bad sorts. Keeping it discretionary preserves cluster 4b's "agent doesn't classify; tools route by purpose" — the agent calling /cleanup is making an explicit classification choice, not getting it free from a state transition. Suggest-not-auto matches the established discipline (cluster 4f #3, 4a #4). |
| 2026-05-10 | **C2 — `xfleet engage`/`disengage` concurrency model** (resolves consistency-audit CLARIFICATION C2) | Accept last-write-wins for `_orchestrator.json:human_engaged`. Three concurrent writer paths (orch directive auto-set per 4a, orch explicit `disengage`, worker `xfleet engage` triggered by slack-direct ping per 4g) each issue independent atomic writes via tmp + mv pattern (prevents torn reads). Race outcome: latest intent wins; brief windows of stale `active=true/false` are tolerable because human-engagement is a coarse gate (suppresses round-5 stop, straggler warnings, all-idle prompts — none catastrophic if delayed by ~1s). `concern_id` metadata similarly resolves last-write-wins; specific concern_id is informational, not gating. **No lock primitive added.** Observe-first: if real races cause observable misbehavior, revisit with CAS (e.g., `xfleet engage --if-not-engaged`) or per-session staging — premature today. **Document in prose `xfleet/shared/state-schema.md`** (per A1's source-of-truth split): "`human_engaged` is any-session writable; concurrent writes resolve last-write-wins; this is intentional simplification — engage/disengage is a coarse gate, not a critical-section primitive." **Closes:** consistency-audit CLARIFICATION C2. | Blast radius of last-write-wins on `human_engaged` is small — the field gates coarse behaviors (suppression flags) where brief staleness doesn't cascade. CAS primitives add complexity for a problem not yet observed; keep simple. Atomic-write pattern (already convention) handles the only real correctness risk (torn reads). Observe-first matches established discipline (4a engagement-detection, 4f subagent multi-turn). |
| 2026-05-10 | **C3 — Worker handling an orch-issued directive that conflicts with current plan** (resolves consistency-audit CLARIFICATION C3) | Procedure walk-through for skill text — addresses the conceptual freeze when an orch directive appears to deviate from the worker's current plan. **Default assumption:** orch is human's proxy (F-58); a directive that conflicts with the plan most likely reflects a human-led decision to override the plan via orch — the plan is the thing that's out of date, not the directive. Worker should NOT default to escalate-and-freeze; the default is **trust + execute, warn for visibility**. Escalate-and-freeze only on genuinely breaking/unsafe conditions. **Procedure:** (1) Worker receives directive D, `current_task` updated per F-58 + A1 write rules. (2) Worker reads D, detects plan conflict. (3) Worker classifies severity: **(a) breaking / irreversible / unsafe** (data loss, security exposure, cross-repo contract break, schema migration without rollback) → freeze; emit `xfleet escalation orchestrator --reason breaking --path <details> --priority urgent`; do NOT execute D until orch responds; orch routes urgent per A2 (bypass batch, surface to human, slack-pair permitted). **(b) plan-deviation only, non-breaking** (re-scoping, approach change, ordering swap that doesn't break invariants) → emit `directive-response --note "plan conflict acknowledged: <details>; proceeding unless orch revises"` for visibility; PROCEED to execute D. (4) If orch sends a new directive in response (revision/override), worker complies with latest signal — `current_task` updated again per A1 rules. (5) If no orch response within reasonable window, worker continues executing D as-is. **Skill-text additions** (worker skill + Authority Hierarchy section in CLAUDE.md per cluster 4g #5): worked example of the (a)/(b) classification with concrete cases. **Rationalizations-to-Reject rows:** "Orch sent this directive, so I should escalate every plan-conflict back to orch" → REJECT for non-breaking conflicts; default trust applies (orch is human's proxy; conflict likely means plan is stale, not directive is wrong). "I should ignore the plan and just execute silently" → REJECT; warn via directive-response for visibility even when proceeding (orch needs to know the plan is out of sync). "I should silently abandon the directive because the plan says otherwise" → REJECT; F-30 anti-bypass applies — worker doesn't unilaterally void orch instructions. **Vehicle:** Phase A worker skill text + Authority Hierarchy section in CLAUDE.md (cluster 4g #5 placement). **Closes:** consistency-audit CLARIFICATION C3. | The audit framed this as a F-30/F-36 tension assuming workers should escalate plan-deviations always. Reframing: orch directives carry F-58's "human's proxy" weight; the plan is mutable, the directive is authoritative for that moment. Worker's job is execute + warn, not escalate-and-freeze. Escalate-and-freeze is reserved for genuinely breaking conditions (a/b classification) where executing first would cause irreversible damage. This preserves orch authority + worker velocity while still surfacing plan-staleness for human/orch attention via directive-response. |
| 2026-05-10 | **Cluster 4h — Orchestrator grounding** (F-1, F-2) | Two grounding sources loaded into orch session context, plus strict delegation discipline in skill text. **Sources:** (a) `{repo}/CLAUDE.md` — baseline (always-resident; not wave-specific). (b) `{repo}/docs/superpowers/xfleet/{slug}/grounding.md` — wave-specific, produced by worker during qa-spec onboarding. `grounding.md` is curated, ~50-100 lines (purpose, scope-of-this-wave, key abstractions, common pitfalls). MAY include a `## Serena memory titles` section (paste of `list_memories` output — titles + descriptions only, no bodies) when the repo has Serena memories; MAY omit when repo has none. No separate `serena-memory-titles.md` file — keep one grounding artifact per wave per repo. **SessionStart hook** at orch session start reads both files for each involved repo (paths from `workspace/.xfleet/roster.json`), concatenates with `=== {repo} ===` markers, injects as system context. Missing files → hook logs warning + proceeds (CLAUDE.md missing is unusual but tolerable; grounding.md missing means worker hasn't completed onboarding — surface as startup warning). **Hook re-fires on session resume** (fresh launch, `/clear`+resume, harness restart) per Claude Code's SessionStart semantics — re-grounding is automatic; composes cleanly with F-53 (handoff captures Active Skills + In-Session Directives; SessionStart re-loads grounding on top). No manual re-load step. **qa-spec phase skill gains an onboarding step:** each worker produces/refreshes `grounding.md` at qa-spec entry. Re-runnable across waves (file is per-slug). **Orchestrator skill — strict delegation discipline** in skill text + Authority Hierarchy section (cluster 4g #5 placement) + Rationalizations-to-Reject table. **Permitted orch reads:** `workspace/` (coordination root including spec.md, backlog.md, state files) + grounding files loaded via hook. **Rationalizations to reject:** "I'll just peek at the repo to find out X" → REJECT; ask worker via `xfleet question <worker>` or `xfleet task <worker>`. "I need to understand the repo structure before I can ask a sensible question" → REJECT; ask worker for the framing too — "how should I ask about <topic> in your repo?" is itself a valid question; orch is the human's proxy and may consult human-in-the-loop. "I just need a quick grep to know if X exists" → REJECT; `xfleet question <worker> --about "does X exist?"` does the same job without breaking the delegation invariant. **Discipline core:** even framing questions is dialogue-driven (consult human or worker), never solo investigation. **No PreToolUse block on Read/Grep/Serena** — over-aggressive; would block legitimate coordination-root reads; matches 4g's "no slack hooks — cultural discipline + audit invariant" pattern. Grounding-loaded context + Rationalizations table make the right path the easy path. **State schema:** none. **KG / structured grounding explicitly Out-of-Scope:** Knowledge graphs (entity + typed-relationship structured representation; distinct from Serena's LSP+memories surface) would solve the wrong problem here — strict delegation means orch doesn't need queryable repo data, just delegation prep. Same reasoning as cluster 4b's graphify decision: 3-4 repos at fixed paths well below KG-pays-off threshold; infra-heavy build+maintain cost; workers are authoritative for their repo's current reality (a KG would be stale or incomplete; would tempt orch to query directly, regressing F-1). Revisit only if observed friction shows worker dialogue is genuinely insufficient (signals: orch repeatedly tasks 5+ workers in parallel for the same coordination question; cross-repo coordination overhead dominates). **Vehicle:** F-51 Phase A — SessionStart hook scaffold; orchestrator skill text update with Authority Hierarchy section + Rationalizations table; qa-spec phase skill onboarding step. F-51 Phase B — `xfleet onboard` subcommand (or fold into qa-spec phase entry) that scaffolds `grounding.md` template for worker. **Composes with:** Cluster 4c (path convention `xfleet/{slug}/`); Cluster 4g (Authority Hierarchy section in CLAUDE.md / worker skill — orch skill gains its own section here); F-53 (SessionStart re-fires on `/clear`+resume; grounding re-loaded automatically). **Closes:** F-1, F-2. | F-2 (no grounding) is the root cause of F-1 (orch peeks at repos). Fix grounding + the path-of-least-resistance for peeking disappears. The strict-delegation discipline is necessary because partial grounding could still tempt "let me check the repo to fill the gap." Even framing-questions discipline is the strongest interpretation: orch is a coordinator, not an investigator; uncertainty resolves via dialogue with human or worker, never via solo read. KG deferred per established graphify-skipped pattern (cluster 4b) — worker dialogue is the authoritative answer source, KG would be a stale shortcut tempting regression on F-1. Hook re-fires on resume aligns with F-53's session-recovery story — single mechanism, no special-casing. |
| 2026-05-10 | **Cluster 4i — Permission model for message content** (F-3) | Two content-passing flags on every content-carrying wire subcommand (`directive`, `task`, `concern`, `concern-reopen`, `resolution`, `question`, `answer`, `review`, `escalation orchestrator`, `phase-complete`), mutually exclusive. **`--message-file <path>` is the primary documented path** (matches observed reducto-session behavior — agents naturally draft to files for review-before-send). Path convention: under `workspace/.xfleet/{type}/{uuid}.md` (e.g., `directives/abc-123.md`, `concerns/...`) — nests under cluster 4b's existing `workspace/.xfleet/{state,concerns,resolutions,directives}/` layout, no new top-level dir. **`--message "<text>"`** stays as escape valve for genuine one-liners (acks, toggles, simple yes/no responses). **CLI validator:** exactly one of `--message` / `--message-file` required for content-carrying subcommands; reject if both or neither. **No length-threshold rejection** — convention + skill text guide; threshold adds friction without observed benefit. **`tools/xfleet/send.sh` retired** (already implied by cluster 4e's `xfleet send` retirement). **Plugin default permission settings:** `Write(workspace/.xfleet/**)` + `Read(workspace/.xfleet/**)` pre-allowed via plugin install; `Bash(xfleet *)` already locked by 4e. Eliminates per-message permission prompts without over-granting Write at session level. **State schema:** no additions. **Vehicle:** F-51 Phase A (CLI flag definitions + validator on each subcommand) + Phase B (plugin scaffolds `workspace/.xfleet/{type}/` dirs at install time + default permission settings ship with plugin manifest). **Composes with:** cluster 4e (subcommand-per-type already established); cluster 4b (path under `workspace/.xfleet/` already convention); 2026-05-10 cleanup-model revision below (transient — wiped at `/cleanup --final` per `workspace/.xfleet/` convention). **Audit-trail follow-up:** dispatched directive bodies wiped at /cleanup --final per cleanup-model revision; post-wave audit relies on spec + ADRs + architecture docs + git history. Mid-wave forensics unrecoverable post-final — accepted trade. **Closes:** F-3. | File-primary matches observed agent behavior (reducto sessions). Inline flag preserves quick path for genuine one-liners. Path scoping under `workspace/.xfleet/**` aligns with established cluster 4b layout — no new conventions. CLI validator's exactly-one-required eliminates ambiguity at dispatch time. Plugin-shipped default permissions remove the F-3 over-grant pattern entirely without pushing scoped-Write decisions onto end users. |
| 2026-05-10 | **Cleanup model revision — durability shrink** (amends cluster 4c durability lock; emerged during cluster 4i discussion of post-wave audit scope) | Cluster 4c's durable-through-`--final` list narrows to the wave's actual deliverables. **Durable through `--final`:** (a) cross-repo `spec.md` (combined cross-repo spec); (b) per-repo `section.md` (per-repo spec slice); (c) per-repo ADRs at `{repo}/docs/adr/NNN-{slug}.md` — extracted during spec/planning via the existing `capture-decision` skill; specific extraction triggers + ADR refinement DEFERRED to a separate "reviewer refinement session" cluster (out of scope here per user); (d) existing repo-resident architecture docs (not wave-specific; predate xfleet, untouched by /cleanup). **Now transient (was durable in 4c):** per-repo `plan.md` — once implemented and reviewed, the code is the source of truth; plan.md becomes historical scratch. Per-repo `handoff-{phase}.md` — transition aids; value diminishes once the wave is complete. Cross-repo `README.md` — session metadata redundant with spec.md's own header. Cross-repo `backlog.md` — handling explicitly UNRESOLVED (see follow-ups below). **Already transient per 4c (unchanged):** `section-vN.md` snapshots, concerns.md, reviews.md, alignment.md, intermediate decisions.md, prd-reviews/, all `workspace/.xfleet/{state,concerns,resolutions,directives,messages}/` content. **Audit scope post-final:** spec.md + ADRs + architecture docs + git history capture everything that matters. Mid-wave forensics — dispatched directive bodies, intermediate decisions before they made the spec, handoff-by-handoff trail — unrecoverable post-final. Accepted trade per principle: transient artifacts serve the wave; durable artifacts are the wave's deliverables. **Vehicle:** F-51 Phase B `/cleanup --final` enforces the new list (drops plan.md, handoff-{phase}.md, README.md, backlog.md from preservation). **Composes with:** cluster 4c (amends durability lock); cluster 4i (transient message content fits this model); existing `capture-decision` skill (ADR creation tool — present, refinement deferred). **Open follow-ups (NOT blocking this entry):** (1) **`backlog.md` handling — UNRESOLVED.** Past waves had ad-hoc handling — wave-1.x/wave-2 saw items combined into repo specs after the fact; could equally live as a standalone doc; could migrate to Linear. Real candidates: (a) backlog → Linear at /cleanup --final, (b) backlog → standalone durable doc, (c) backlog → folded into next wave's spec. Worth its own future discussion when use case clarifies. (2) **ADR extraction refinement — DEFERRED to reviewer-refinement session.** Triggers, tagging, capture-decision integration with cluster 4a's reviewer-findings flow — all out of scope for this entry. (3) **Plan-as-historical-scratch implication.** Post-merge, plan.md is gone; if anyone wants "what was the plan?" later, code + git log + spec.md are the trail. Aligns with cluster 3's plan-discipline (plans drive implementation, not durable artifacts). | Cluster 4c's durability list overshot — many artifacts that felt durable in initial design are actually transient (handoffs, plans, session-metadata READMEs). User's revised model: spec + ADRs + code + architecture docs = the wave's durable record; everything else served the process. README.md was redundant with spec headers. Backlog is a known unsolved area worth its own discussion when use cases clarify — flagging here keeps it visible without forcing a premature lock. ADR refinement is a separate scope (reviewer refinement session) acknowledged-and-deferred — not litigating extraction triggers / capture-decision integration / per-ADR review intensity here. |
| 2026-05-10 | **Cluster 4j — Context-check injection mechanism** (F-6, F-48; locks the SHAPE of "hook-based check-context injection" that cluster 1 nominated as F-51 Phase B vehicle on 2026-05-04) | F-6 = mechanism gap (long mid-message ops push past scheduled checks); F-48 = discipline gap (between-task checks skipped without reminder). Same end-result; one mechanism solves both. **PostToolUse hook on expensive tools** — plugin scaffolds hook firing after `Agent`, `Read` (filtered: result-size threshold to avoid trivial reads), `Grep`, `mcp__serena__*`. Hook invokes a shell-level helper at `tools/xfleet/check-context.sh` (hooks can't call skills per plugin capability card; shell helper is the bridge). Shell-level helper reads `context_pct` from harness (or transcript-byte estimate fallback if no direct API), reads current phase from `{worker}.json:current_phase` (or `_orchestrator.json` for orch session), looks up phase-specific warn/critical thresholds (per cluster 4f's phase metadata; default 70/80, repo-spec 50/65). **Threshold-gated emission** (script-level, not hook-level): `context_pct < warn` → exit silently with no output (hook overhead = cheap script run only); `warn ≤ context_pct < critical` → emit warn `<system-reminder>`; `context_pct ≥ critical` → emit critical `<system-reminder>`. Avoids spamming the agent with "context at 30%" reminders on every tool call; injection only happens at threshold crossings. **System-reminder content:** *Warn* — `Context at {pct}% (warn for {phase}). Plan to run prepare-compact at next safe boundary; consider delegating context-heavy subtasks via Agent fire-and-forget per cluster 4f.` *Critical* — `Context at {pct}% (critical for {phase}). HALT current task. Run prepare-compact + write handoff immediately. Do NOT continue.` **Critical-abort contract:** any agent receiving the critical system-reminder MUST stop immediately, run prepare-compact, write handoff, surface to orch/human. Encoded in CLAUDE.md / worker skill text + Rationalizations-to-Reject table: "I just need to finish this one tool call" → REJECT (HALT means HALT); "It's only critical because I'm about to compress; I can keep going" → REJECT (thresholds exist for headroom). **Two-level debounce + critical-always-re-emit + below-warn debounce reset (Phase A implementation note, NOT blocking lock):** (i) **Below-warn throttle via `last_check_at`** — even below warn, hook firing on every Agent/Read/Grep/Serena call would run the full script every time; instead, script exits early if `last_check_at < N seconds ago` (cheap timestamp check; defers full context_pct read). Hook overhead is essentially free below warn. (ii) **Warn-emit debounce via `last_warn_emitted_at`** — once warn-reminder fires, don't re-fire on every subsequent tool call; re-emit only on N-minute elapsed OR warn→critical transition. **Debounce resets when context drops below warn**: script clears `last_warn_emitted_at` whenever `context_pct < warn` (typical compact cycle: 70% → warn fires → compact runs → 30% → debounce clears → next 70%-cross fires fresh, not silently debounced from prior cycle). Critical always re-emits (no debounce — halt-now needs to be loud until handled). **Implementation detail — transcript-path discovery:** existing `check-context` skill uses a UUID-grep trick (`uuidgen` planted in jsonl as tool_use record → grep for UUID locates this session's transcript) — this is conversation-internal and **does NOT translate to PostToolUse hooks** (hooks aren't tool_use calls, no UUID record written). Hook needs alternative path: (a) Claude Code hook env vars (e.g., `CLAUDE_TRANSCRIPT_PATH` / `CLAUDE_SESSION_ID` / `CLAUDE_PROJECT_DIR`) if available, (b) statusline-equivalent mechanism (statusline reads context info somehow; mirror whatever it does), (c) byte-count estimate of transcript file as a last-resort fallback. Verify available APIs at Phase A; the locked principle (script-level threshold gate + debounce) is independent of which discovery path is used. **State schema additions (cluster 4b; supplements A1's consolidated table; see also A1-addendum row 2026-05-10 below):** worker `last_warn_emitted_at: ISO\|null` (warn-emit debounce; nullable; resets on phase entry; cleared whenever `context_pct < warn`); worker `last_check_at: ISO\|null` (below-warn throttle; updated on every script run that progresses past the early-exit gate). **Phase-entry re-emit window (intent declaration per audit M5):** on phase entry, `last_warn_emitted_at` resets but worker's `context_pct` may still read ≥ warn until the next worker self-report (per cluster 4f's "self-reports on handler exit + periodically"). The first PostToolUse fire after phase entry will re-emit a warn `<system-reminder>`. **This is intentional**, not a race bug — a fresh warn-prompt at a phase boundary is genuinely useful (compact-at-boundary nudge composes with cluster 4f #4's always-compact-at-phase-transition rule). Don't optimize away. All other state fields already locked elsewhere (`context_pct` from 4f). **Composes with cluster 4f #2 pre-flight check** — different mechanisms, both fire: pre-flight is opt-in (skill marks subtasks `context_heavy: true`, worker checks before entering); post-hook is automatic (every expensive tool call). Both desirable; no overlap-conflict — pre-flight handles known-heavy subtasks, post-hook handles ad-hoc/cumulative drift. **Vehicle:** F-51 Phase A (PostToolUse hook scaffold registered in plugin manifest + critical-abort discipline in skill text + Rationalizations-to-Reject rows + `last_warn_emitted_at` field in state schema) + Phase B (`tools/xfleet/check-context.sh` shell-level helper that hooks invoke). **Composes with:** cluster 1 (this is the shape that cluster 1 nominated as a Phase B vehicle); cluster 4f (thresholds source + pre-flight composition + fire-and-forget); cluster 4g (Authority Hierarchy + Rationalizations-to-Reject table format); F-53 (handoff format triggered when prepare-compact fires from critical-abort path). **Known gap (not blocking; deferred):** PostToolUse fires AFTER the tool call. Single giant Read pushing safe→critical in one shot would arrive after damage; system-reminder still prevents further damage but can't undo the one tool call. PreToolUse hook on `Agent` (heaviest) could pre-check with cost estimate, but estimating tool-result size is fuzzy; complexity not justified by observed frequency (single-call blowouts rare; typical drift is incremental across many calls). Revisit only if observed friction. **`/loop` is the wrong layer for this** (agent-level periodic turns vs. harness-level event-driven; can't preempt mid-tool-call) — orch-side periodic worker-state monitoring via /loop is a different / separate concern, currently overkill given worker self-detection + state-file polling already covers it. **Closes:** F-6, F-48. | Single mechanism solves both F-6 and F-48 (mechanism + discipline). Threshold-gated script-level emission keeps hook overhead minimal (cheap script run on every fire, injection only at threshold crossings). Critical-abort contract is the cultural layer on top of the structural hook — without the contract, agents could rationalize "one more call"; with it, the rule is HALT. Pre-flight (4f #2) + post-hook (4j) compose cleanly: pre-flight handles known-heavy-subtask preemption; post-hook handles ad-hoc + cumulative drift. Cluster 1 nominated the vehicle 2026-05-04 without locking shape; this entry locks shape. |
| 2026-05-10 | **Cluster 4k — Human-review batching + presentation** (F-9; minimal — uses existing loop+Redis machinery, no new buffering layer) | F-9's interruption pattern emerges from per-arrival surfacing. Fix uses what's already there. **(1) Iteration-level batching — discipline only.** Orch's listen-and-handle loop already drains-then-processes; rule: **don't surface mid-iteration; accumulate handler outputs and surface ONCE when the iteration completes.** While orch awaits human reply, no iteration runs → new messages queue in Redis PEL → next iteration drains them. "Quiet-during-review" emerges automatically from the loop structure; nothing to track. **(2) Digest table format when batch ≥ 2 items** — presentation rule in orch skill text: `\| source \| type \| status \| summary \| path \|` columns; human opens path for full content; free-form fine for single-item surfaces. **(3) Cross-worker grouping at surface-time** — synthesis-only, no state. Before surfacing a batch, orch reads `directive_log[]` / `task_log[]` / concern_id from the messages being surfaced; if 2+ share a `dispatched_id`, groups them and flags disagreements explicitly at top of surface. Uniform agreement collapses to one line. Skill-text rule: "before surfacing, group by dispatched_id; flag disagreements at top." **State schema:** none — earlier draft had `incoming_batch_buffer[]` + `review_pending`; both dropped because Redis PEL + loop semantics already provide them. **Deferred (per F-9's body recommendation + observe-first):** phase-aware timeouts (qa-spec=30s etc.), explicit `review_pending` state, stale-round handling (round-counter filter), progressive disclosure (#5), explicit checkpoint gates (#6). Revisit only if iteration-level batching shows observed gaps. **Vehicle:** F-51 Phase A — orch skill text describes the iteration-batching discipline + digest format + cross-worker grouping rule. No new bash/hook scaffolding; no new state fields. **Composes with:** Cluster 4a (urgent escalations bypass batching via A2 `--reason` routing — same as before; this generalizes 4a's "batch alerts per F-9" framing to all incoming results, not just judgment-finding alerts); Cluster 4h (cross-worker synthesis depends on grounding loaded by SessionStart hook). **Closes:** F-9. | Earlier draft invented a parallel buffering layer (timeouts, buffer state, quiet-mode tracking, stale-round filtering) duplicating what the loop + Redis PEL already provide. Stripped to discipline + presentation; no new machinery. The actual scope of F-9's complaint is "presentation timing"; the minimum that addresses it is iteration-batching discipline + digest format. Phase timeouts and edge cases stay deferred until observed friction shows the natural loop rhythm isn't enough — observe-first per established pattern. |
| 2026-05-10 | **Cluster 4l — Spec/finalize flow** (F-18, F-24, F-28; composes with cluster 4b's Decisions Log nomination + cluster 4c's snapshot Model A + cluster 4d's `xfleet phase --complete` hook) | Three findings cluster around finalize-spec + spec-evolution. **(1) finalize-spec multi-mode (F-24):** two modes, auto-detected from `current_phase` + inputs, with explicit `--mode` override. **qa-spec mode** — inputs = worker answers + drafted sections + captured decisions; output = cross-repo `spec.md` (the PRD that drives repo-spec). **repo-spec mode** — inputs = per-repo `section.md` files + `workspace/.xfleet/resolutions/*.md`; output = updated cross-repo `spec.md` with sections merged + `## Decisions Log` populated. **Post-impl section template only (F-24 #3 trimmed)** — finalize-spec output in any mode includes an empty `## Post-Implementation Resolution` section template at the end; populating is manual / future-tooling; **NOT a full mode today** (no clear single agent runs it; iterative implementation has no natural trigger). Defer the full post-impl mode until concrete tooling demand surfaces. **(2) Phase-skill integration (F-24):** each phase's `xfleet phase --complete` (per cluster 4d) invokes finalize-spec in the appropriate mode before emitting phase-complete; phase-complete blocks until finalize succeeds. qa-spec exit → finalize-spec qa-spec mode → PRD seed. repo-spec exit → finalize-spec repo-spec mode → final cross-repo spec. **Session-role clarification (audit CL3, 2026-05-10):** finalize-spec runs in the **orch session**, not the worker session. Worker emits `xfleet phase-complete` (per A3 — worker-only sender, recipient = orch); orch handler receives, runs completion-check (cluster 4a), then orch invokes finalize-spec locally before re-emitting downstream phase signals. The worker's `xfleet phase --complete` is the SIGNAL; the actual cross-repo synthesis is orch-side. This preserves "spec.md write authority is orch only" while honoring A3's sender table. **(3) spec.md write authority + snapshot cadence:** **spec.md write authority is orch only.** Workers do NOT edit spec.md directly; they write to their `section.md` + concerns; orch's finalize-spec synthesizes during phase exits. Mid-phase orch edits to spec.md are permitted but rare — only when cross-cutting decisions need immediate recording before phase exit. **Snapshots happen at phase exits only:** `spec-v0.md` after qa-spec, `spec-v1.md` after repo-spec, etc. Mid-phase orch edits don't trigger new snapshots; they land in current spec.md until next phase-exit snapshot. This is stricter than per-repo `section.md` (which is continuously evolving + snapshotted via Model A whenever finalize-section runs) — asymmetric on purpose: cross-repo synthesis is heavyweight + happens at milestones; per-repo evolution is incremental + happens within phases. **(4) `## Decisions Log` section (F-28 + cluster 4b nomination — locks shape):** finalize-spec emits a structured Decisions Log section. Format: `### D-N: <title>` / `**Decision:** <forward-looking statement>` / `**Rationale:** <one paragraph why>` / `**Resolved in:** <phase + round + ref to resolution file>`. Forward-looking voice — sister to ADRs but lighter (per-spec session-scoped, NOT cross-project; cross-project decisions go to repo-local ADRs per the cleanup-model revision). Populated from `workspace/.xfleet/resolutions/*.md` summaries during finalize. **(5) prd-review consumes prior decisions (F-28 #2):** prd-review skill (existing) reads spec's `## Decisions Log` + prior prd-review findings files for the same slug, passes "prior decisions" context block to each dim agent. Dim agents instructed: if a finding maps to a resolved decision, skip or reference explicitly — no re-raise without strong new evidence. **(6) F-18 largely obsoleted by cluster 4c.** No `-final.md` suffix, no `status: finalized` frontmatter. Snapshot mechanic gives spec.md (always current) + spec-v{N}.md (immutable phase-exit milestones). Reviewers consume spec.md against the latest snapshot. F-18's "distinct file for review" need is met by snapshot diff, not by a separate "final" filename. **State schema:** no additions (spec content is files; no state field changes). **Vehicle:** F-51 Phase A — finalize-spec skill rewrite to multi-mode; Decisions Log + Post-Impl Resolution templates; phase-skill integration (`xfleet phase --complete` invokes finalize); prd-review skill update reads spec Decisions Log + prior findings; injects as dim-agent context. F-51 Phase B — `xfleet phase --complete` (cluster 4d) wires the finalize call as part of the phase-exit sequence. **Composes with:** Cluster 4b (Decisions Log nomination + Deferred section); Cluster 4c (snapshot Model A; v0 seed pattern; per-repo section.md continuous-evolution model); Cluster 4d (phase-exit hook is the integration point); Cleanup-model revision (durable = spec.md + section.md + ADRs; ADRs are repo-local cross-project; spec's Decisions Log is session-scoped). **Closes:** F-18, F-24, F-28. | F-18 mostly subsumed by cluster 4c's snapshot mechanic — no separate finalized state needed; current spec.md vs latest snapshot diff covers the use case. F-24's three modes simplify to two (qa-spec, repo-spec); post-impl deferred because the trigger is undefined. F-28's Decisions Log is the high-ROI piece — preserves "what's settled" signal in a forward-looking voice without polluting the spec body. spec.md write-authority asymmetry (orch-only) reflects observed behavior — workers naturally focus on section.md during repo-spec, orch synthesizes at phase exit. Phase-exit-only snapshots are tighter than per-section continuous snapshots — cross-repo spec milestones are more meaningful than each mid-phase edit. |
| 2026-05-10 | **Cluster 4m — Reviewer-intensity unification** (F-20; minimal — most work already done by architect-review intensity support + cluster 4a per-phase policy) | **(1) architect-review is the canonical reviewer for xfleet phase reviews.** Don't maintain a separate per-repo reviewer agent ecosystem (e.g., product-manager's reviewers). architect-review already supports the intensity contract (`standard` / `high` / `critical`). **(2) prd-review stays separate** for cross-repo PRD review with its 4 dim agents (risk / boundaries / distributability / adversarial). Already supports intensity. Different shape from architect-review (multi-dimensional cross-repo synthesis vs single-dimension plan/spec/section review) — keeps its dim agents. **(3) `/code-review` left as-is.** Third-party skill; can't directly extend the intensity contract. xfleet treats it as a separate review surface running post-implementation; no unification attempt — code review's vocabulary stays whatever the third-party skill ships with. **(4) `worker-config.md:reviewers:` simplification.** Default reviewer = architect-review. Workers declare `reviewers: - agent: architect-review intensity: high` (worker default; overrideable per-phase). Phase skills override per cluster 4a's already-locked graduated policy (qa-spec=critical, repo-spec first-pass=high, re-finalize=standard, implement=standard). **(5) Per-phase intensity already locked by cluster 4a** — `xfleet phase --enter <phase> --review-intensity <level>` override; phase-skill metadata adds `review_intensity` field. No new mechanism in 4m. **(6) Terminology:** keep `critical` (matches existing skills + cluster 4a's locked vocabulary). F-20 mentioned "extreme" informally; staying with `critical` for consistency. **State schema:** none (intensity declarations live in worker-config.md + phase metadata; no new state fields). **Vehicle:** F-51 Phase A — worker-config.md schema simplification (reviewers default to architect-review; explicit note that /code-review stays separate; explicit note that prd-review keeps its dim agents). Phase-skill metadata already done by cluster 4a. **Composes with:** Cluster 4a (graduated intensity per phase — already locks the policy 4m points at); F-51 Phase A (configuration surface). **Net new work:** documentation cleanup only — no new mechanisms, no new state, no new commands. **Closes:** F-20. | The bulk of F-20's request was already done before cluster 4m: architect-review has intensity, prd-review has intensity, cluster 4a locked per-phase policy. 4m's lock is the consolidation decision — "use architect-review uniformly for xfleet phase reviews; drop the parallel per-repo reviewer agent ecosystem; leave /code-review alone as third-party." Recognizing the small scope rather than inventing structure honors observe-first / over-engineering-aversion (per cluster 4k discussion). |
| 2026-05-10 | **Cluster 4n — Design principles meta-layer** (F-35, F-36; xfleet-scoped — F-35 deliberately not exported project-wide because non-xfleet sessions rely on F-53's generic recovery instead) | Both findings are meta-principles invoked as rationale across many earlier clusters; locking them as durable, with a canonical home and skill-load discipline. **(1) Create `design-principles.md`** in plugin shared/ dir (sibling to `messaging.md`, `state-schema.md`, future `reviewer-contract.md`). Loaded by every xfleet skill via a one-line reference in its Protocol section — re-established every session, every /clear+resume. **(2) F-35 — Skills as source of truth.** Locked principle: skills hold behavior rules; memories hold context / preferences / fact snapshots. Discipline that must survive session boundaries belongs in skill bodies, not memories. Corollaries: **skills-first correction workflow** (acknowledge → identify owning skill → update skill → optionally save context to memory; memory update is additional, not substitute); **memory-as-signal** (memory-only correction is incomplete — flag as drift-waiting-to-happen); **durability test** ("if next session starts fresh with no memories, would behavior still be correct?"); **memory-appropriate scope** (identity, preferences, fact snapshots = yes; protocol rules, handler sequences, message contracts = no); **review guard** (behavior changes without skill updates flag drift). **(3) F-36 — Autonomous execution.** Locked principle: agents drive the plan + skill flow without per-step confirmation. Pause ONLY for: (a) explicit gate defined by plan/skill (e.g., human approval at phase transition per F-17), (b) breaking error (tool failure, contradictory state, missing required input), (c) deviation from plan. **Don't pause for:** next expected step (just do it), routine progress (report at milestones), "am I doing this right?" (re-read the plan), lookup-resolvable uncertainty (Serena/Context7/grep first then act). **4-question rubric:** in plan? at gate? breaking error? about to deviate? — all "execute" → execute. **Rationalizations-to-Reject table** (per F-36): importance ≠ gate; resolvable uncertainty ≠ pause-worthy; "human seems available, might as well confirm" → REJECT (proactive check-ins break flow); "multi-step chain, let me confirm before next" → REJECT (chain in plan = execute); "might cause something irreversible" → REJECT (if irreversible, plan should mark as gate; if not marked, not intended as gate). **Milestone-level reporting**, not step-level confirmation. **(4) Other principles to collect in same doc** (placeholders; many already locked elsewhere; collecting for discoverability): coordination-vs-durability split (F-19 / cluster 4c); content hygiene voice (F-19 / cluster 4l Decisions Log); authority hierarchy (F-30 / cluster 4g); atomic state transitions (F-32, F-33 / cluster 1); verify-before-claim (F-32 / cluster 1); observe-first + over-engineering aversion (pattern); strict delegation (cluster 4h); file-primary message convention (cluster 4i). **(5) F-35 stays xfleet-scoped.** Not duplicated in `~/.claude/CLAUDE.md`. Outside xfleet there's no specific phase-skill defining workflow; the "skills as source of truth" issue is far more acute inside protocol-bound xfleet sessions. For non-xfleet sessions, F-53's prepare-compact format (Active Skills + In-Session Directives + Resume Instructions) IS the durability mechanism — different problem, different fix; the two compose without duplication. **(6) F-36 elevated in worker/orchestrator SKILL.md.** Per F-36 #1, #2: prominent `## Autonomous Execution` section near the top of each skill body (NOT buried at line 201 in worker/SKILL.md as today) with the principle + 4-question rubric + Rationalizations-to-Reject. Plus design-principles.md cross-reference. Triple-redundant on purpose: worker skill, orchestrator skill, and shared principles doc all carry it. **(7) Skill loading discipline:** every xfleet skill (worker, orchestrator, finalize-spec, finalize-section, capture-decision) gets `Design principles: see shared/design-principles.md` in its Protocol section. Loaded into context whenever the skill loads. **State schema:** none. **Vehicle:** F-51 Phase A — create `design-principles.md`; F-35 + F-36 as inaugural principles; placeholders for the others; references from every xfleet skill. F-51 Phase A — worker/SKILL.md + orchestrator/SKILL.md gain prominent `## Autonomous Execution` sections (rule promoted from buried line to top-level section). **Composes with:** Cluster 4g (Authority Hierarchy section in CLAUDE.md / worker skill — sibling principle); Cluster 4h (orch Authority Hierarchy + Rationalizations-to-Reject pattern; same template); F-53 (Active Skills + In-Session Directives capture is the cross-session durability for non-xfleet sessions; complements design-principles.md inside xfleet). **Closes:** F-35, F-36. | F-35 explains why so many earlier clusters needed structural fixes (plugin commands, hooks, Authority Hierarchy sections) instead of memory-based corrections. Locking the principle as durable closes the loop on those clusters' rationale. F-36's autonomous-execution principle counterbalances the F-9-batching / cluster 4k discipline (no per-step pauses; iteration-level surfacing) and matches the broader observe-first / no-over-engineering preference seen across this session. Triple-redundancy (skill body + design-principles.md + xfleet README mention) is intentional for high-impact behavior rules — single-mention rules historically drift. xfleet-scoped (no CLAUDE.md duplication) keeps the principles where they're most acute and lets F-53 handle the generic case. |
| 2026-05-10 | **Cluster 4o — Worker conduct rules** (F-38, F-40, F-43, F-45, F-46; all F-35 instances — memory captured the rules but skills drifted; locking as skill-text additions) | Five skill-level discipline gaps. Bulk = skill-text + Rationalizations-to-Reject tables; minimal new mechanism. **F-40 verification (handoff flag):** F-40 is NOT subsumed by cluster 4b. 4b is schema-level discipline (tools route by purpose; refuse unknown keys); F-40 is temporal-trust discipline (label VALUES go stale even within a tight schema). Different layer. Keeping F-40 in 4o. **(1) F-38 — Cross-repo source reads forbidden** (worker analog of cluster 4h orch discipline). Worker skill rule: "Investigation of peer-repo source code routes through peer worker via `xfleet question` / `xfleet concern`. Bash/Grep/Read of sibling repo source forbidden in orchestrated mode. Cross-repo reads limited to `docs/superpowers/` content (specs, plans, handoffs, reviews, ADRs)." Plus Rationalizations-to-Reject ("it's faster to grep than message" → REJECT, semantic context lost; "peer is slow" → REJECT, listener always running per cluster 1; "just one quick lookup" → REJECT, propagates wrong assumptions). Composes with cluster 4h (orchestrator-side analog — same discipline at orch level). **(2) F-40 — Verify state labels before reciting.** Worker skill rule: "Before reciting any state-file label ('deferred', 'pending', 'out-of-scope') to user, verify the corresponding resolution / research file's date against relevant work's commits. Resolution dated BEFORE last task commit → in-scope-unshipped (defect to close in current scope); AFTER → genuinely new scope. State labels are point-in-time observations; reality may have moved." Self-check rubric: stat resolution file → git log task commits → compare. F-25/cluster 4b state-schema implication: `since` + `verified_at` timestamps on label fields deferred to observed need; not adding now, revisit if pain materializes (observe-first per established pattern). **(3) F-43 — Read task `.output` files is permitted** (resolves protocol contradiction). Update worker skill: replace "NEVER read /private/tmp/" prohibition with permit + recovery use case. `TaskOutput` is deprecated for `listen.sh` background task IDs; output files at `/private/tmp/claude-*/.../tasks/{id}.output` are the only place message JSON lives. Per cluster 4i pattern: plugin default permissions add `Read(/private/tmp/claude-*/.../tasks/*.output)`. messaging.md documents this as canonical method, not as override. Recovery use case explicit: after `/clear` or `/compact`, list files in `/private/tmp/claude-*/<project>/<session>/tasks/` and read them to recover orchestrator messages received before the reset (secondary cross-check; durable handoffs at `docs/superpowers/handoffs/` remain primary). **(4) F-45 — Boundary-first presentation.** Skill rule for both worker + orchestrator: "When answering 'what's next?' / 'how does this fit?' / 'where does X belong?', LEAD with one-line boundary statement quoting the relevant handoff's 'Out of Scope / Deferred' section verbatim, THEN present options. Never bury deferred-scope as parenthetical." Concrete template: `Boundary: [handoff says X covered, Y/Z still deferred per ...]. Options: 1. ... 2. ... Recommendation: ...`. Rationalizations-to-Reject ("Options answer the question; deferred is meta-context" → REJECT, options on wrong premise; "User can ask if they want deferred view" → REJECT, they shouldn't have to; "Listing deferred up front looks like dodging" → REJECT, IS the answer). Pairs with F-39 plan-fold coverage table (same discipline, different surface — fold-time vs status-check-time). **(5) F-46 — Asymmetry pushback.** Three surfaces. **Worker-side:** when touching cross-surface code (invoice/receipt/PO; server/oracle/web parallels), workers check for asymmetries proactively and unify if cost is small. Don't ask "should we unify?" — propose "I unified, here's the scope expansion." Skill text rule. **Reviewer-side:** prd-review's boundaries dim agent gains asymmetry-detection (or new dim added): scans resolutions for narrowing language ("KEEP X untouched", "defer to wave-N", "leave alone", "no change") and surfaces as JUDGMENT findings: "is this a product call or convenience?". **Resolution-drafting:** when orchestrator drafts a resolution that narrows scope, template requires a "Why narrowed" field — hand-wave entries ("X is revisited less frequently" without quantification) get caught by F-21 reviewer loop. Rationalizations-to-Reject ("X revisited less frequently" → REJECT unless quantified; "Wave-1.x can pick this up" → REJECT, deferrals stack; "Defer reduces wave-1 risk" → REJECT, asymmetry is its own risk; "Asymmetry already exists, not making worse" → REJECT, entrenching it). **State schema:** none added (F-40's `since`/`verified_at` deferred per observe-first). **Vehicle:** F-51 Phase A — worker/SKILL.md + orchestrator/SKILL.md gain new sections + Rationalizations-to-Reject rows (mirrors cluster 4n's `## Autonomous Execution` section pattern); plugin default permissions add `Read(/private/tmp/claude-*/.../tasks/*.output)` per F-43 (composes with cluster 4i scoped-permission pattern). F-51 Phase A — `prd-review` skill gains asymmetry-detection in boundaries dim (or new dim). F-51 Phase A — resolution drafting template gains "Why narrowed" field. `design-principles.md` (cluster 4n) gets placeholders for these conduct rules as discoverability hub. **Composes with:** Cluster 4h (orch source-read prohibition; F-38 is worker analog of same rule — same skill-text template); Cluster 4i (file-primary + scoped permissions; F-43's allow-list extension follows same pattern); Cluster 4n (skills-as-source-of-truth meta-principle; these are specific applications); Cluster 4l (Decisions Log records narrowing decisions per F-46; "Why narrowed" surfaces as Decision rationale); Cluster 4m (prd-review keeps dim agents; F-46 extends boundaries dim). **Closes:** F-38, F-40, F-43, F-45, F-46. | All five findings have been operational pain points captured as memories across multiple workers; F-35 says memory-only is incomplete fix. Locking as skill-text additions makes them survive session boundaries. F-40 deliberately kept separate from 4b — different layer of state-file integrity (temporal-trust vs schema-tightness). F-43's protocol contradiction was the most repetitive friction (worker tries TaskOutput, fails, escalates, told "just read") — single skill-text update eliminates the cycle. F-46's three-surface fix (worker proactive + reviewer detection + resolution template) catches asymmetry-as-convenience at every stage, not just at review. Bulk of work is documentation; minimal mechanism additions follow established cluster patterns (4h, 4i, 4m, 4n). |
| 2026-05-10 | **Plugin default permissions inventory** (consolidates per-cluster permission additions for Phase A authoring; resolves audit MINOR M4 — inventory was scattered across 4 rows) | Single source of truth for plugin-shipped default `permissions:` settings (auto-applied on plugin install per F-51 Phase B; eliminates per-message + per-tool approval prompts without over-granting at session level). **Inventory:** (1) `Bash(xfleet *)` — collapses CLI surface to one line per cluster 4e (single `xfleet` binary; subcommand-per-message-type); (2) `Write(workspace/.xfleet/**)` — message content + scratch + transient state per cluster 4i (composes with cluster 4b's `workspace/.xfleet/{state,concerns,resolutions,directives,messages}/` layout); (3) `Read(workspace/.xfleet/**)` — symmetric read for worker handlers consuming inbound message-file content per cluster 4i; (4) `Read(/private/tmp/claude-*/**/tasks/*.output)` — task notification output-files per cluster 4o (F-43 protocol-contradiction fix); reads `listen.sh` background-task notification JSON. **Hook registrations** (also in plugin manifest, separate concern from `permissions:` block but shipped together): (5) `SessionStart` hook — orch grounding loader per cluster 4h (reads `workspace/.xfleet/roster.json` + `{repo}/CLAUDE.md` + `{repo}/docs/superpowers/xfleet/{slug}/grounding.md`; injects as system context); (6) `PostToolUse` hook on `Agent` / `Read` (filtered) / `Grep` / `mcp__serena__*` — context-check injection per cluster 4j (calls `tools/xfleet/check-context.sh` shell helper; threshold-gated `<system-reminder>` injection). **Vehicle:** F-51 Phase A plugin manifest scaffold; this row is the consolidated inventory Phase A authors reference rather than re-deriving from scattered cluster bodies. **State schema:** none. **Composes with:** Cluster 4e (Bash), Cluster 4i (workspace/.xfleet/** Read+Write), Cluster 4o + F-43 (task output Read), Cluster 4h (SessionStart hook), Cluster 4j (PostToolUse hook). **Closes:** consistency-audit MINOR M4. | Phase A authors need the full plugin-permissions surface in one place, not assembled from 4-5 cluster bodies. Audit-trail risk if any one is forgotten — small consolidation row eliminates that risk. No new permissions added; this is a documentation consolidation only. |
| 2026-05-11 | **Cluster 5 — Epic decomposition + Integration Points + Contract reconciliation** (F-49, F-50) | Two-layer cadence for mid-implementation drift detection. **Layer 1 (per-repo epics — BMAD-style, F-49):** each repo decomposes plan.md into epics with local test breakpoints via `## Epics` section template; plan-fold (cluster 3) coverage extended with IP coverage rows; backend repos hit these often, frontend rarely. **Layer 2 (cross-repo Integration Points — F-49 + F-50):** vertical functional milestones in spec.md `## Integration Points` table; each IP has 1+ contracts in scope; contracts are atomic API artifacts in new durable `contracts.md` (extends cluster 4c durable list); same contract can be in scope for multiple IPs (re-verified each time — catches post-lock implementation drift). **Drift framing (user):** drift-1 = spec interpretation drift (governance — fixed by IP/contract authoring forcing cross-worker agreement at repo-spec phase); drift-2 = implementation drift (tooling — fixed by Layer 2 verification stack). **Contract format:** Pydantic as canonical lingua franca + Markdown intent; each repo derives language-specific representation; locked at first IP that scopes the contract. **Authoring lifecycle:** IPs proposed during qa-spec → refined during repo-spec → locked at end of repo-spec phase (rides cluster 4l snapshot mechanic; produces `spec-v{N+1}.md` + parallel `contracts-v{N+1}.md`). **Checklist gate** (absorbed from `/speckit.checklist` pattern): `xfleet checklist --mode repo-spec` runs inside `finalize-spec --mode repo-spec` before snapshot; validates structural completeness (no dangling IP/contract refs, no orphan contracts, all required fields populated, T4 flag explicit); finalize-spec refuses snapshot on non-zero exit. **Authority:** spec.md + contracts.md orch-only-write (cluster 4l + 4h); plan.md `## Epics` worker-write (cluster 3 + F-34 writing-plans discipline). **Verification stack at IP close (T1+T2+T3+T4):** **T1 — Deterministic drift check** per contract per repo: `xfleet drift-check --contract C-N --repo {repo}` extracts current Pydantic/TypeScript shape via `model_json_schema()` / `ts-json-schema-generator`, normalizes to JSON Schema, structural diff vs locked canonical; two-pass discipline (worker self-check at epic close via `verification-before-completion`; orch independent re-run at IP dispatch). **T2 — Integration test** per IP: orch sends `task` (cluster 4e) to each contributing worker; commands sourced from contracts.md verification block. **T3 — Cross-source verification via new `x-vergence-check` skill** (sibling to `verification-before-completion`; "vergence" = Star Wars term for convergence-of-multiple-paths): orch dispatches parameterized Agent invocation (promote to registered agent type once pattern proves out); reads each contributing repo's slice + T1 drift reports + T2 results + locked Markdown intent + actual handler code; 5-flag mandate — (a) classify contract changes per **API Evolve taxonomy** absorbed from Spec Kit (additive / non-breaking / breaking / removal), (b) flag spec bypass, (c) flag semantic drift (status code shifts, error contract drift, idempotency violations, path drift), (d) flag asymmetries between contributing repos (codified version of cluster 4o-F-46 manual cross-worker review), (e) flag intent gaps. **T4 — Conditional human gate** (per-IP `human_gate: bool` set at authoring): if true AND T1+T2+T3 clean, escalate via cluster 4g (Slack-pair); if false, auto-close. **Wire taxonomy extension (cluster 4e):** new `integration-ready` type (worker → orch, no rounds, signal-only); state schema (cluster 4b/A1 — see cluster 5 A1 addendum row): `_orchestrator.json:integration_readiness`, `ip_status`, `drift_log`; worker state: `current_ip`, `ip_self_check`. **Result aggregation:** all clean → IP status flips `locked` → `verified`; any layer fail → concern via cluster 4a/4e, resolution loop, verification re-runs after fix. **Resolution loop (light vs heavy paths):** **Light path** (existing contract amendment — refine error contract, rename field, fix mismatch): concern → resolution → orch amends contracts.md in place + classification per API Evolve taxonomy + bump `Last amended`; propagation = `directive` to contributing workers to re-derive language-specific representation; drift check at next IP close confirms. **Heavy path** (new contract emerges mid-implementation OR new IP needed OR IP scope change — anti-pattern signaling spec/plan incompleteness): concern → resolution → orch amends spec.md + Decisions Log entry on why missed + new contract block + spec-v{N+1}.md/contracts-v{N+1}.md snapshot bump; propagation = `task` to each contributing worker to plan-fold (cluster 3 / F-34) and update epic-to-IP anchoring. **Code-update authority always worker** (cluster 4h: orch never writes repo code; orch only writes cross-repo artifacts). **IP re-opening (post-verified):** cluster 4a `concern-reopen` applied to IPs — status `verified` → `re-opened`, full T1+T2+T3+T4 re-runs. **F-51 plugin placement:** Cluster 5 is **mostly Phase A** — 3 new wrapper subcommands (`drift-check`, `integration-ready`, `checklist`) following cluster 4e Phase A packaging pattern; `x-vergence-check` skill bundled with plugin in Phase A; minor Phase B touch (integration-ready inherits Phase B's atomic state-write helpers); no new hooks (cluster 5 doesn't extend cluster 4j/4h hook surface). **Plan size (writing-plans phase):** ~7 areas — x-vergence-check skill body, 3 new xfleet subcommands, Pydantic/TS extractors + JSON Schema diff tooling, surface templates (spec.md/contracts.md/plan.md), skill body updates (worker/orchestrator/finalize-spec), state schema additions per A1, plan-fold extension + messaging.md taxonomy. Final plan warrants architect-review per cluster 4m before execution. **Anti-pattern + forcing functions:** new-contract-mid-implementation = signal spec was incomplete; cost of heavy path is intentional friction; `First introduced: implement phase` field on contracts is post-wave quality metric. **Spec written:** `docs/superpowers/specs/2026-05-11-cluster-5-epics-integration-points-design.md`. **Composes with:** Cluster 2 (prepare-handoff renamed; F-53 handoff sections); Cluster 3 (plan-fold extension); Cluster 4a (IP-close as completion gate; concern-reopen for IPs); Cluster 4b (state schema discipline); Cluster 4c (durable list extends with contracts.md); Cluster 4d (no per-IP handoff — intra-phase event); Cluster 4e (wire taxonomy extension); Cluster 4g (T4 escalation routing); Cluster 4h (orch never writes repo code); Cluster 4i (file-primary + permission model); Cluster 4l (spec authority + snapshots + Decisions Log entries on amendments); Cluster 4m (x-vergence-check as new reviewer surface — IP close distinct from architect-review/prd-review/code-review surfaces); Cluster 4o-F-46 (asymmetry pushback — T3 codifies the manual cross-worker review pattern). **Closes:** F-49, F-50. | F-49 + F-50 are the highest-leverage wave-quality findings — user's Reducto wave-1 pain ("multiple rounds of reconciliation and refactoring in middle of implementation") motivates the design's "spend time on this early" stance. Two-layer cadence is intentional: per-repo epics give backend the breakpoint they need; cross-repo IPs are the integration verification moments. Per-IP T4 opt-in (vs default human gate at every IP) avoids the cluster 4k over-engineering trap. Pydantic-as-canonical chosen over OpenAPI per user preference (codebase doesn't use OpenAPI today; Pydantic-as-lingua-franca + per-language derivation matches existing practice). Heavy/light asymmetry on resolution paths makes new-contract-mid-implementation a forcing function for spec completeness at repo-spec phase. `x-vergence-check` as new skill (vs reusing architect-review which is plan-critique-pre-code, wrong stage; or /code-review which is PR-stage, wrong timing) reflects the genuinely distinct verification surface — cross-source alignment post-code, pre-PR. Builds on `verification-before-completion` principle (evidence-before-claims) extended to cross-source scope. Net new infrastructure is small (3 subcommands + 1 skill + templates + state fields); composes with existing locked clusters; allow-list impact zero (`Bash(xfleet *)` covers). |
| 2026-05-11 | **F-57 close-out — OUT-OF-SCOPE** (compound bash command permission prompts) | General agent-infra problem, not xfleet-solvable. No xfleet-shaped fix exists — real solution paths are skill-text / global discipline at the agent-behavior level, not xfleet infrastructure. **Local mitigation:** added rule to `~/.claude/CLAUDE.md` Workflow Rules section extending the existing "No `git -C`" pattern — "Avoid compound bash commands; prefer sequential single-purpose commands; compound OK only when the chain is the atomic unit." **Closes:** F-57. | Compound-bash discipline mirrors the existing `git -C` discipline — same root cause (compound forms bypass allow-list patterns), same fix shape (sequential singles). Mitigation lives in CLAUDE.md not xfleet skills because the problem is general, not xfleet-specific. |
| 2026-05-11 | **A1 addendum — Cluster 5 IP/drift fields** (recursive-strict validator needs cluster 5's new state fields enumerated explicitly per A1 discipline; parallel to cluster 4j A1 addendum) | Following A1's state-schema discipline, these fields added by cluster 5 must be merged into the canonical field list at Phase A JSON-Schema authoring time. **`_orchestrator.json` additions:** (1) `integration_readiness: map<string, map<string, bool>>` — per-IP per-repo readiness flags; outer key = `IP-{N}`, inner key = repo name, value = signaled-ready bool; populated when worker emits `xfleet integration-ready`; reset on IP amendment/reopen. (2) `ip_status: map<string, {status: enum, verified_at: ISO\|null, version: int}>` — per-IP lifecycle state; status ∈ {proposed, locked-pending, locked, verified, re-opened}; `verified_at` set on T4 close (or auto-close when T4=false); `version` bumped on amendment-via-resolution-loop. (3) `drift_log: list<{ip: string, contract: string, repo: string, classification: enum, resolved_at: ISO}>` — append-only log of drift detections per IP close; classification ∈ {additive, non-breaking, breaking, removal} per API Evolve taxonomy; populated from `x-vergence-check` output. **`{worker}.json` additions:** (4) `current_ip: string\|null` — IP this worker is currently working toward; null when between IPs or no IP work pending. (5) `ip_self_check: map<string, map<string, enum>>` — per-IP per-contract self-check status from `verification-before-completion` discipline at epic close; outer key = `IP-{N}`, inner key = contract ID (e.g., `C-1`), value ∈ {drift-clean, drift-detected, not-yet-checked}. **All STORED** (not derived) — `xfleet drift-check` writes `ip_self_check`; `xfleet integration-ready` writes `integration_readiness`; orch handlers write `ip_status` + `drift_log`. **Vehicle:** F-51 Phase A `state-schema.md` prose layer + JSON Schema both include these fields alongside A1's original list + cluster 4j addendum. **Closes:** cluster 5 state-schema enumeration (no separate finding). | Same logic as cluster 4j A1 addendum: strict validator can't honor implicit supplements; explicit > implicit per A1's own discipline. Five new fields across two state files; one short addendum row keeps the schema source-of-truth single. |
| 2026-05-14 | **F-59 — architect-review consolidation** (closes F-59) | Adopted prd-* pattern: full 10-dim review content moves to new global agent `~/.claude/agents/architect-reviewer.md` (single source of truth); existing global skill `~/.claude/skills/architect-review/SKILL.md` rewritten as thin dispatcher (parses args, Task-dispatches the agent, returns output verbatim) preserving the `/architect-review` slash-command surface. Repo-local committed `oracle/.claude/agents/architect-reviewer.md` (worktree-shared with sidekick) **deleted**; other devs lose this file on pull — intentional, since the underlying skill is personal and cannot be assumed present. Committed `oracle/.claude/rules/planning-workflow.md` (oracle/sidekick) made tool-agnostic — step 4 changes from "Run architect-reviewer agent as a background task" to "Run an architectural review on the finished plan"; closing line from "Always run architect-reviewer..." to "Always perform an architectural review..." — so other devs without the personal global agent aren't told to run a missing tool; fall back to inline Claude review. Per-dev `worker-config.md` updates (personal, not committed): oracle's `architect-reviewer` entry now points at `~/.claude/agents/architect-reviewer.md` (drops the repo-local `.claude/agents/architect-reviewer` path); server's `worker-config.md` gains an `architect-reviewer` entry as "additional default" alongside `tech-architect`/`integration-architect`/`mongodb-architect` (per-case decision which to use, per cluster 4m); web's `worker-config.md` gains an `architect-reviewer` entry alongside `architect-pm` (`architect-pm` vs `architect-review` direct comparison still deferred per locked F-59 decision). References files at `~/.claude/skills/architect-review/references/{risk,reuse-first,adversarial}.md` unchanged — agent reads them at runtime. **Solution-explorer.md untouched** (separate scope; oracle-only usage so far). **Server's specialized-agents → `convention_files:` migration explicitly out of scope.** Multi-model cross-model variant DROPPED (no Codex CLI). Sharing the new agent + skill content with other devs handled separately, out-of-repo (e.g., team onboarding / personal-tooling channel). **Closes:** F-59. | prd-* pattern (standalone agent + dispatcher skill) is the existing convention for global review agents (`prd-reviewer`, `prd-risk-analyst`, `prd-boundaries-reviewer`, etc.) — F-59 brings architect-review into the same shape, eliminating the `worker-config.md` described-vs-actual drift. Single source of truth in the agent body; skill dispatching the agent (rather than wrapper-invokes-skill) keeps the slash-command surface working with one fewer indirection layer. Committed-vs-personal split honored: repo-committed `planning-workflow.md` doesn't reference an agent other devs lack; personal `worker-config.md` (not committed) is the right surface to declare each dev's preferred reviewer. F-35 invariant restored: described behavior (`worker-config.md` text) now matches actual implementation (the global agent body). Sharing the agent + skill with teammates out-of-repo preserves the "no committed wrapper" property while letting interested devs adopt the tooling. |

---

## Findings

### F-1. Orchestrator reads repos directly during qa-spec — RESOLVED via cluster 4h (SessionStart hook loads CLAUDE.md + per-wave `grounding.md`; strict delegation discipline + Rationalizations-to-Reject table; KG deferred Out-of-Scope)
Orchestrator, on entering `qa-spec`, used Read/Grep/Serena against involved repos instead of delegating investigation to workers. Violates the multi-repo design — workers exist because each has repo-local MCP/Serena access the orchestrator lacks.
Details: `2026-04-20-xfleet-qa-spec-delegation.md`.

### F-2. Orchestrator has no grounding in per-repo architecture or tooling — RESOLVED via cluster 4h (root cause of F-1; fixed by SessionStart-loaded CLAUDE.md + per-wave `grounding.md` produced during qa-spec onboarding)
Even if orchestrator wanted to delegate properly, it has no baseline knowledge of each repo's purpose, tech stack, or available tools. No CLAUDE.md, no Serena memories, no familiarity. This is part of why F-1 happens — "I need to peek at the repo to know what to ask" becomes the path of least resistance.

### F-3. Permission model is all-or-nothing for message sending — RESOLVED via cluster 4i (`--message-file <path>` + `--message "<text>"` flags on every wire subcommand; plugin pre-allows `Write/Read(workspace/.xfleet/**)`; `tools/xfleet/send.sh` retired)
Sending an xfleet message currently requires writing the message body to a tmp file and then invoking `send.sh`. Approving `Write` for the tmp-file step also grants Write broadly — there's no way to allow "write to tmp + send.sh" as a scoped capability without opening up general file-edit permissions in the session. Every message exchange triggers an approval prompt or forces the user to over-grant.

### F-4. Session-restart silently breaks the listen loop — RESOLVED inline (2026-04-20; `--resume` flag added to `/worker` and `/orchestrator` skills)
Closing and reopening the Claude Code session (with OR without `/clear`) kills the background `listen.sh` task from the prior process. Redis consumer group / pending list is intact, state files intact, but nothing is reading the inbox until a new background listen starts. Skills had no re-entry path that distinguished "fresh start" from "resume after restart" — users had to manually drain + re-listen or silently miss messages.
**Resolution (applied mid-session 2026-04-20, process drift — should have been captured here first):** added `--resume` flag to `/worker` and `/orchestrator` skills. Requires existing state/roster file (errors out if missing), skips cold-start side-effects, branches on `status` (compacting → load handoff), drains pending inbox, restarts blocking listen. Docs updated in `~/.claude/xfleet/README.md`. Status: FIXED.

### F-5. Nested Task agents cannot dispatch their own subagents — RESOLVED inline (2026-04-20; `prd-review` skill restructured to top-level dispatch; constraint captured as feedback memory)
Claude Code harness constraint — an agent invoked as a Task cannot itself spawn Agent/Task subagents, even with `tools: [..., Agent]` declared. Surfaced during the Reducto PRD dry-run: `prd-reviewer` agent was designed to dispatch 4 dim subagents (risk / boundaries / distributability / adversarial) after being invoked by the `/prd-review` skill — the nested Agent calls failed.
**Resolution (applied mid-session 2026-04-20, same process drift):** restructured `prd-review` — skill now dispatches the 4 dims in parallel from the top-level session, then hands results to `prd-reviewer` as a pure synthesizer (or synthesizes inline as a valid fallback). `prd-reviewer` agent rewritten without `Agent` tool. Constraint captured as feedback memory `feedback_nested_agent_constraint.md` so future agent architectures use top-level-only dispatch. `~/.claude/xfleet/phases/qa-spec.md` Step 7 updated to reflect the flow. Status: FIXED.

### F-6. Context-check injection is gap-prone during long operations (2026-04-21) — RESOLVED via cluster 4j (PostToolUse hook on expensive tools + threshold-gated script-level emission + critical-abort contract; locks the shape that cluster 1 nominated)
**Sub-findings (consolidated 2026-05-04):** F-48 (discipline skipped — between-task checks not honored without reminders) — see F-48 below.

Current `check-context` invocation is at message boundaries: between implement-phase tasks, after handling any inbound message. Long mid-message operations — 4 parallel Agent dispatches, deep Serena scans, large Reads — can push context from safe to critical with nothing watching. By the time the next pause point fires, handoff may get written at 95%+ with no headroom, or auto-compact may already be imminent.
Options under consideration: (a) PostToolUse hook filtered to expensive tools (`Agent`, `Read`, `Grep`, `mcp__serena__*`) that runs check-context automatically and injects a system-reminder at warn/critical; (b) skill-level pre-flight check before known-expensive operations with critical-aborts; (c) post-operation checks after any tool return >N tokens; (d) cross-cutting "critical-abort contract" — any skill observing critical must abort, write handoff, stop. Leaning toward (a) + (d). Not yet implemented.

### F-7. Bash allow-list patterns for xfleet scripts (2026-04-21) — RESOLVED via cluster 4e (single `xfleet` binary; `Bash(xfleet *)` one-line allow-list)
**Sub-findings (consolidated 2026-05-04):** F-11 (script-path hallucination — same root cause: no `xfleet` wrapper) — see F-11 below.

Permission prompts on every `send.sh` / `listen.sh` / `ack.sh` / `peek.sh` / `concern-append.sh` invocation are friction during active sessions. Need to identify the narrowest patterns that allow these scripts to run without prompting, without opening up general Bash execution.

**Code-smell observed (2026-04-21):** current invocation pattern prepends a PATH export:
```
export PATH="~/workspace/tools/xfleet:$PATH" && listen.sh server 0
```
Shell state mutation per command is the wrong layer — belongs in user env setup, not the agent. It also breaks allow-list matching (compound `export && cmd` strings are hard to match without over-scoping).

**Second compound-form case (2026-04-21):** `concern-append.sh` reads stdin by design, so it's structurally invoked via heredoc pipe:
```
cat <<'EOF' | ~/workspace/tools/xfleet/concern-append.sh ~/.claude/concerns/server-1.md
...content...
EOF
```
The command-string match is `cat <<'EOF' | /abs/path/concern-append.sh ...` — a bare `concern-append.sh *` allow pattern won't match. Can't be fixed by PATH setup (the prefix is `cat`, not `concern-append.sh`). Real fix: reshape the interface so content is a file arg or flag value, not stdin: `concern-append.sh <concern-file> --from-file <content-file>` or `concern-append.sh <concern-file> --message "..."`. Wrapper from #3 below can normalize this.

**Third compound-form case — orchestrator state polling (2026-04-22):** orchestrator routinely needs to read all worker state files at once. Natural shell idiom:
```
for r in server oracle web; do
  echo "=== $r ==="
  cat ~/.claude/state/$r.json 2>/dev/null | jq '{phase, status, current_task, last_updated}'
done
```
Hits the compound-form problem at multiple layers: shell `for` loop + `echo` + `cat` + `|` + `jq`. Permission prompt fires on every invocation; a broad allow pattern would grant far more than the polling use case justifies. This is a high-frequency orchestrator operation — every completion-check (F-13), every straggler-check cycle, every human-gate surfacing wants a "what's each worker doing right now?" snapshot. Ad-hoc bash for this is the wrong interface.

**Fix — this maps to a subcommand of the `xfleet` wrapper (#3 below):**
```
xfleet status               # All workers' snapshot, jq-filtered output
xfleet status --full        # Full state contents
xfleet status {name}        # Single worker
```
Allow pattern: `xfleet status *`. One line in permissions config; eliminates the compound-form entirely. Same applies to other common polling operations (pending counts, concern state, review state) — each gets an `xfleet <noun>` subcommand.

**Parser-level blocker (2026-04-22):** Claude Code's command parser itself errors on pipeline constructs:
```
cat <<'EOF' | ~/workspace/tools/xfleet/concern-append.sh
   ~/.claude/concerns/server-10.md
   ...content...
EOF

Error: Unhandled node type: pipeline
```
This is **not** an allow-list matching failure — the parser rejects the shell structure before allow-list matching even gets a chance. Every `cat <<EOF | cmd` invocation needs manual approval (or fails entirely in some modes). Confirms that pipeline-shaped invocations are a dead end regardless of permission config. The fix must eliminate the pipeline at the call site — reshape `concern-append.sh` to accept content via file arg or `--message` flag, OR route all invocations through the `xfleet` wrapper (#3 below) which never uses pipelines externally.

**Recommended direction — single `xfleet` wrapper** (cleanest long-term):
- Install a single `xfleet` entry-point script to a PATH location already available (`/usr/local/bin/xfleet` or `~/bin/xfleet`).
- Dispatches to subcommands: `xfleet send ...`, `xfleet listen server 0`, `xfleet ack ...`, `xfleet peek ...`, `xfleet concern-append ...`.
- Skills invoke bare `xfleet <sub> ...` — no export, no absolute paths, portable across machines (each user installs the wrapper once).
- Allow-list becomes a single line: `xfleet *` (or scoped like `xfleet listen *`, `xfleet send *`, etc., if finer grain wanted).

**Interim (no refactor):** one-time user setup — add `~/workspace/tools/xfleet` to PATH in `.zshrc` (or equivalent). Skills then invoke bare `listen.sh`, `send.sh`, etc., no export. Allow-list: `listen.sh *`, `send.sh *`, `ack.sh *`, `peek.sh *`, `concern-append.sh *`. Requires: stop generating the `export PATH=... && ...` prefix anywhere in skills.

**Not recommended — match the compound form.** Allowing `export PATH="/Users/..." && listen.sh * *` is verbose and entrenches the code smell.

Related to F-3 (approving `Write` for the send.sh tmp-file step also grants Write broadly). If we can allow the xfleet scripts AND a narrow tmp-file write pattern (`/tmp/xfleet-*.json` or similar), message exchange becomes approval-free without opening general Write. Not yet investigated — needs Claude Code `permissions` documentation review + testing.

**Action items (not yet done):**
- Write the `xfleet` wrapper script (thin dispatch layer over existing `*.sh` scripts).
- Scrub skill bodies / xfleet README for any `export PATH=...` patterns and remove.
- Add wrapper install step to xfleet README's setup section.
- Investigate Claude Code permission patterns for scoped Write (`/tmp/xfleet-*`).

### F-8. Duplicate `listen.sh` processes observed (2026-04-21) — RESOLVED via F-51 Phase B
Violation of the "one listener per worker at a time" rule (documented in `worker/SKILL.md` and xfleet README). Sometimes two `listen.sh {name}` processes run concurrently for the same worker. Since `listen.sh` uses `{name}` as both stream key and consumer identity, two listeners with the same consumer name compete for messages via Redis XREADGROUP — some messages get delivered to one process, some to the other, and the pending list (PEL) fragments. Symptoms: messages appearing handled-but-not-acked, missed handlers, stream state diverging from what either session "knows".

**Suspected root causes** (need confirmation):
1. **Session restart without clean process kill.** Prior session's `run_in_background: true` listen task outlives the session, new /worker starts another. Harness ideally cleans up on session end; need to verify.
2. **Re-invoking `/worker` without `--resume`** on an already-running session — second invocation cold-starts (writes state, starts listen) without detecting the first listener.
3. **Skill flow gaps.** A skill path that doesn't ACK a prior listen before starting a new one (e.g., after a phase transition or handoff reconstruction).
4. **Multiple Claude Code windows in same repo.** Each starts its own listen, both identify as the same consumer.

**Confirmed observation (2026-04-22):** multiple dangling `listen.sh` processes seen running after `/clear` and after Claude Code session close+reopen. Harness does NOT reliably kill prior session's `run_in_background` bash tasks. Every `/worker` or `/worker --resume` after a session break silently adds a new listener on top of the zombies. PEL fragmentation across N consumers explains intermittent message loss.

**Fix directions (not yet implemented):**

1. **Active cleanup in /worker and /worker --resume (not just detection).** On entry, before starting any listen, the skill:
   ```
   pids=$(pgrep -f "listen\.sh +{NAME}( |$)")
   if [ -n "$pids" ]; then
     echo "Killing $(echo $pids | wc -w) stale listen.sh processes for {NAME}: $pids"
     kill $pids
     sleep 0.5  # let redis consumer-group clean up PEL reassignment
   fi
   ```
   Then proceeds with the normal flow (drain for resume; fresh listen for cold start). Active cleanup > detection-and-abort because the alternative is the human running `pkill` manually every time — friction.

2. **Fail loudly if cleanup fails.** If `kill` doesn't reap the processes within a timeout (e.g., 2 seconds), error out: "Could not kill stale listener(s) for {NAME}. Run `ps aux | grep listen.sh` and clean manually before retrying." Prevents silently starting a second listener on top of a stubborn zombie.

3. **Use distinct consumer names per session** (e.g., `{name}-{session-id}`) so accidental duplicate listens are non-destructive (each gets its own PEL). But this complicates PEL recovery — drain on resume would need to union across consumer ids. Probably worse trade-off than #1.

4. **Harness-side bug report.** `run_in_background: true` tasks should die with the session that spawned them. File an upstream report; until fixed, worker skill's active cleanup (#1) is the mitigation.

5. **Document a manual recovery** in xfleet README: `pkill -f "listen.sh {NAME}"` + `/worker --resume` to get back to a known-good state. Short-term until #1 lands.

**⚠️ Critical amendment to fix #1 (consolidated from F-37, 2026-05-04):** the `pgrep -f "listen.sh +{NAME}" | kill` approach is **unsafe across parallel sessions**. Multiple concurrent Claude Code sessions running the same worker (e.g., orchestrator-driven `/worker` plus a side-channel debug session, or two humans pairing) all spawn `listen.sh server 0` with byte-identical command lines. `pgrep -f` matches them all; `kill` would silently break the peer session's inbox consumption. The user has caught this exact pattern (server memory `feedback_listener_processes_are_shared.md`, 2026-04-09).

Revised fix #1 (own-listener-only cleanup):
- **Track listener ownership by harness `bash_id`, not process command line.** Worker writes `listen_bash_id` into `~/.claude/state/{NAME}.json` on every spawn. On resume / cleanup, the worker only acts on its own recorded bash_id.
- **TaskStop > kill for own listeners.** Use the harness's TaskStop on the recorded bash_id rather than OS-level `kill`. TaskStop is harness-aware; `kill` bypasses harness state.
- **Diagnostic only — never destructive — for foreign processes.** If pgrep finds `listen.sh {NAME}` PIDs that don't match the recorded bash_id, surface to the human ("N foreign listen.sh server processes detected — run `ps`/`pkill` manually if these are stale") rather than auto-killing.
- Fix #3 (distinct consumer names per session) becomes more attractive given this constraint — re-evaluate if the bash_id approach proves insufficient.

**Recommendation:** revised #1 + #2 immediately — track-by-bash_id, TaskStop-only-own, fail-loud, never-reap-foreign. #4 (upstream report) in parallel. #3 promoted from "avoid" to "consider" given the parallel-session constraint. #5 in the README as an interim escape hatch.

Related to F-4 (--resume mechanics): the --resume flag assumes the prior listen is dead. Active cleanup makes that assumption enforced rather than hopeful. F-12 (resume leaves in-flight work dormant): a cleanup+resume path that reliably has exactly one listener is a precondition for trusting state to drive task continuation. F-32 (verify-before-claim): the `bash_id` ownership tracking required here is the same field F-32's listener-liveness verification reads.

### F-9. Concurrent worker results interrupt human review (2026-04-21) — RESOLVED via cluster 4k (iteration-level batching discipline + digest table format + cross-worker grouping at surface-time; uses existing loop+Redis PEL, no new state)
Workers investigate in parallel; their `answer` / `response` / `review` messages arrive at the orchestrator in bursts. The problem isn't just volume — it's **timing during active human review**:

- T=0 — Worker 1 answers. Orchestrator surfaces findings/open questions to human.
- T=5 — Human starts reviewing worker 1's output.
- T=10 — Worker 2's answer arrives. Orchestrator surfaces it *while human is mid-review* of worker 1.
- T=15 — Worker 3's answer arrives. Same interruption.

Human now has 3 partially-reviewed batches, forced context switches, and loses the through-line of the current review. Findings/open questions blur across workers.

**Fix directions (not yet implemented):**

1. **Hold-until-batch-ready (primary).** Orchestrator does NOT surface per-arrival. Instead, wait for either (a) all outstanding responses from the current round to arrive, or (b) a timeout (configurable — e.g., 30s in qa-spec, tighter in implement), whichever first. Then surface the whole batch as one coherent message. Newcomers during human review are queued, not shown, until human replies.

2. **Human-review quiet mode.** While human is actively replying (detected by: orchestrator has surfaced a batch and is waiting for human input), incoming results are queued silently. On human reply, orchestrator shows: "Batch 2 queued while you were reviewing (server answer + web answer) — surfacing now." Prevents mid-review interruption. Pairs with #1.

3. **Digest/table format instead of inline content.** Orchestrator emits a scannable summary table — `repo | question/concern | status | one-line finding | file path` — rather than dumping the full answer content. Human opens the file when they want details. Keeps the session output dense and navigable. Dovetails with existing file-based answer convention (`~/.claude/concerns/{...}.md`).

4. **Cross-worker pattern detection.** Within a batch (from #1), if the same question went to multiple workers, orchestrator groups their answers together and flags disagreements explicitly. Highest-signal moment; shouldn't blend into the stream.

5. **Progressive disclosure.** Headline first (`3 answers in: server APPROVED, oracle BLOCKED on F-3, web APPROVED`). Details only on request or for items flagged as needing action. Slack/terminal isn't great for interactive disclosure — may work better as a reply-threading pattern.

6. **Explicit checkpoint gates.** Orchestrator pauses at deliberate points (e.g., after dispatching all LOOKUP/PATTERN findings, wait for all to return before surfacing JUDGMENT) instead of interleaving. Predictable rhythm. Heavier; #1+#2 likely cover most of the benefit without the new gates.

**Recommendation:** #1 (hold-until-batch) + #2 (quiet during review) are the core — they directly eliminate the interruption pattern. #3 (digest) + #4 (cross-worker grouping) complement by making batches scannable and highlighting the actionable cross-cutting insights. #5/#6 are nice-to-haves, defer.

Related to F-1/F-2 (orchestrator grounding): batched digests also require the orchestrator to synthesize a point-of-view across worker results, which depends on the grounding F-1/F-2 call out as missing.

### F-10. Workers skip prepare-compact on orchestrator-driven phase transitions (2026-04-21) — RESOLVED via cluster 4d (F-51 Phase B `xfleet phase`)
Worker skill convention: run `prepare-compact` before every outbound `phase-complete` signal, writing a handoff to `{REPO_PATH}/docs/superpowers/handoffs/xfleet-{branch-slug}-{phase}.md`. This guards against accidental auto-compact during phase transitions and preserves resume context.

**Gap observed:** the qa-spec → repo-spec transition is **orchestrator-driven** (orchestrator sends `{type:"phase", name:"repo-spec"}` to each worker). Workers don't emit `phase-complete` for qa-spec — they just receive the new phase signal and pivot. Result: workers accumulate substantial context through qa-spec (Serena scans, answers, review-triggered investigations) with NO handoff write at the boundary, then start repo-spec still carrying all of it. Auto-compact risk is live.

The handoff rule was written around worker-driven transitions (worker decides phase is done, emits phase-complete). Orchestrator-driven transitions bypass it entirely.

**Fix directions (not yet implemented):**

1. **Add prepare-compact to the `phase` inbound handler.** In the worker's always-on handler table, the `phase` handler action becomes: (a) if `current_phase != "idle"` AND `current_phase != incoming_phase`, invoke `prepare-compact` first to write a handoff for the outgoing phase; (b) then load the new phase skill's on-entry section. Cheap, covers all orchestrator-driven transitions, no protocol change.

2. **Orchestrator requests explicit phase-complete before sending new phase.** Orchestrator sends a "wind down {phase}" signal, workers emit phase-complete (which triggers their existing handoff path), then orchestrator sends the new phase. More ceremony, more round-trips.

3. **Phase-exit handoff as a universal rule.** Rewrite the convention from "before phase-complete" to "before exiting any non-idle phase, regardless of how it terminates." Worker skill enforces this at every phase boundary, whether exit was self-driven (phase-complete) or orchestrator-driven (phase signal). Clean principle; may require touching several places in worker/SKILL.md.

**Recommendation:** #1 (handler-level hook) is the smallest change and covers the observed gap. #3 is the clean long-term framing — worth doing if other similar gaps surface. #2 adds coordination overhead for no clear benefit over #1.

Related to F-4 (session restart): handoffs are what make resume-after-restart viable. Every missed handoff is a potential context loss event.
Related to F-6 (context-check injection): a well-placed context-check at phase boundaries would also catch this — if context is already warn/critical on entry to repo-spec, force a compact-and-resume.

### F-11. Agent hallucinates wrong script paths (2026-04-21) — RESOLVED via cluster 4e (subcommand surface eliminates path construction; bare `xfleet <subcommand>` always works)
**Sub-finding of F-7 (consolidated 2026-05-04).** Same root cause (no `xfleet` wrapper); F-11 is the hallucination symptom, F-7 is the permission-scope symptom. Same fix #1 in both.

Observed failures during resume attempts:
```
Bash(bash ~/.claude/xfleet/shared/listen.sh web --drain)
 ⎿ Error: Exit code 127
    bash: ~/.claude/xfleet/shared/listen.sh: No such file or directory

Bash(~/.claude/xfleet/shared/listen.sh oracle --drain)
 ⎿ Error: Exit code 127
    (eval):1: no such file or directory: ~/.claude/xfleet/shared/listen.sh
```

The actual scripts live at `~/workspace/tools/xfleet/`. `~/.claude/xfleet/shared/` contains only protocol docs (`messaging.md`, `state-schema.md`) — no scripts.

**Why the hallucination:** `messaging.md:3` defines `TOOLS = ~/workspace/tools/xfleet` as a variable, but the rest of the doc (and skill bodies) invoke scripts bare: "run `listen.sh {name} --drain`" without a `$TOOLS/` prefix. When the agent needs to construct the actual path, it pattern-matches "I read this instruction from `~/.claude/xfleet/shared/messaging.md`" → assumes scripts live alongside the doc → fabricates `~/.claude/xfleet/shared/listen.sh`.

**Fix directions (not yet implemented):**

1. **Land the `xfleet` wrapper from F-7.** Once installed on PATH, skills invoke bare `xfleet listen oracle --drain` and ambiguity vanishes. Single fix covers this + the allow-list issue.

2. **Interim: add explicit path guidance in skill bodies.** Update worker/orchestrator skills' Protocol sections to say: "Scripts are invoked by bare name; they must be on PATH. If not on PATH, add `~/workspace/tools/xfleet` to it (one-time .zshrc setup)." Reduces but doesn't fully eliminate the hallucination — agents still sometimes construct paths defensively.

3. **Interim: rewrite messaging.md to always show `$TOOLS/<script>` form.** Replace bare `listen.sh {name}` examples with `$TOOLS/listen.sh {name}` (or hardcoded absolute path) throughout. Forces a consistent mental model — either the user set `$TOOLS` or the absolute path works. Uglier docs but less ambiguous.

4. **Immediate workaround (no code change):** when the error surfaces, re-invoke with the absolute path (`~/workspace/tools/xfleet/listen.sh {name} --drain`).

**Recommendation:** #1 is the real fix; every other F-7-related issue lands with it. #3 is worth doing regardless — keeps docs honest about path requirements. #2 adds guidance but leaves the underlying ambiguity.

Related to F-7 (allow-list patterns) — same root cause, same fix. Related to F-4 (`--resume`) — the hallucinated path makes resume fail loudly, which is better than silent failure, but still a paper cut every time it happens.

**Persistence confirmed (2026-05-04):** the pattern is still observed routinely — workers try 2-3 different candidate paths (`~/.claude/xfleet/shared/`, `~/.claude/skills/.../`, `workspace/tools/xfleet/`) before landing on the correct location. The wrapper (#1) hasn't shipped; the workaround (absolute paths in skill bodies, per `feedback_xfleet_tools_absolute_paths.md` in server memory) is partial and still leaves room for the agent to re-derive a wrong path. Until #1 lands, every new session pays the same friction.

### F-12. Resume leaves in-flight work dormant (2026-04-21) — RESOLVED via cluster 2 + cluster 4d + F-58 (composite: `xfleet resume --standby` flag, universal phase-boundary handoffs, standby-as-self-drive-gate scope)
**Sub-findings (consolidated 2026-05-04):** F-47 (phase skill / `subagent-driven-development` not auto-engaged after `--resume`) — different facet of the same resume-incompleteness problem.

After `/clear` + `/worker --resume`, worker correctly rehydrates state and starts listen loop, but does NOT actively resume in-flight task work:
```
Resumed web: phase=repo-spec, status=working, drained=0, listen started (bash_id=...).

  Current task per state: reviewing approved v2.1.3 cross-repo spec for web-owned sections.
  No pending messages, no open concerns, not paused. Listen loop active —
  waiting for inbound messages or continuing review work.
```

The worker knows it was `status=working` on a specific task, yet just parks on the listen loop instead of continuing. "Waiting for inbound messages or continuing review work" — but it's not continuing.

**Root cause:** the resume-mode flow I wrote only restores *operational state* (config, state file, roster, phase skill, listener). It doesn't say "if status == working and current_task is populated, actively resume that task." Loading the phase skill loads instructions, not an in-flight task context.

This is compounded by F-10 (no handoff on orchestrator-driven phase transitions): qa-spec → repo-spec was orchestrator-driven, so no handoff file was written at the boundary. The worker has state-file breadcrumbs (phase, current_task) but no reconstruction notes — nothing that says "you were at step N of task X, here's what you'd already decided."

For `status=compacting`, resume loads `handoff_path` which contains Resume Instructions. For `status=working`, there's no equivalent — just the state file's `current_task` field.

**Fix directions (not yet implemented):**

1. **Resume mode actively continues working tasks.** Worker skill Resume Mode gains a step: after listen starts, if `status == "working"` AND `current_task` is non-empty, the worker proactively resumes that task — loads the phase skill's on-entry section, reads any in-progress artifacts (review file, spec section), and continues work without waiting for inbound. Same branch can also re-check for unACKed messages in pending list before presuming idle.

2. **State file carries `resume_note` field.** Worker writes a brief "what I was doing and where I left off" note into `~/.claude/state/{NAME}.json` alongside `current_task` whenever the task is active. On resume-to-working, the worker reads this note to reconstruct the micro-context. Cheaper than a full handoff, richer than a bare task name.

3. **Phase-boundary handoffs (from F-10).** If orchestrator-driven transitions wrote handoffs (F-10 fix #1), a `status=working` resume would have a handoff to read, same path as `status=compacting`. Unifies the resume code path.

4. **Drop-dead simple: announce and wait.** Keep current behavior but change the summary line from the wishy-washy "waiting for inbound messages or continuing review work" to a decisive "⚠️ in-flight task detected but NOT auto-resumed — run `/continue` or re-engage manually." At least the human knows the worker isn't self-driving anymore.

**Recommendation:** #1 + #3 together. #3 makes resume-to-working symmetrical with resume-from-compacting (both have handoff files); #1 makes the resume step actually drive forward progress. #2 is an interim if #3 proves too invasive. #4 is a band-aid — only useful while the real fix is pending.

Related to F-10 (no handoff on orchestrator-driven transitions — same root cause of missing reconstruction context), F-4 (resume mechanics).

### F-13. Orchestrator stalls instead of emitting `negotiation-complete` at repo-spec close (2026-04-21) — RESOLVED via cluster 4a (event-driven completion check after every state-changing inbound)
In repo-spec phase, after all workers submitted `review` results and all raised concerns reached `resolution` state, orchestrator did NOT emit `negotiation-complete` to the workers. Expected flow at repo-spec close:
1. All workers review → `{type:"review", status:"approved"}` (or approved-with-conditions)
2. Any concerns raised get negotiated to `resolution`
3. Orchestrator sees: reviews ∈ approved + concerns ∈ resolved for all workers
4. Orchestrator sends `{type:"negotiation-complete"}` to each worker → workers finalize their spec sections → phase transition (or human gate)

Step 3 → 4 didn't fire. Orchestrator held at the listen loop without emitting negotiation-complete. Workers waited for the signal that never came; session effectively stalled.

**Possible root causes** (need confirmation via state files / logs):
1. **Trigger not wired.** Orchestrator's repo-spec phase skill has no explicit "check for completion after each state-changing inbound" step — completion detection is implicit. The orchestrator skill body may only check completion at specific timeouts (straggler/all-idle checks) rather than on each signal that could tip state into "complete."
2. **Straggler filter excluded the wrong workers.** If a worker was mid-transition (`status=compacting` or stale `last_updated`), completion check may have skipped it and never re-tested once it updated.
3. **State-schema mismatch.** Orchestrator may be reading an older schema where `review.status` values don't include the specific string the worker emitted (e.g., `"approved"` vs `"approved-with-conditions"`). Completion-check gates on exact-match and fails silently.
4. **Concern-resolution not tracked as "closed".** `resolution-summary` from a worker signals the negotiation wrapped, but if orchestrator doesn't mark the concern as closed in `_orchestrator.json` (or wherever it tracks triage state), the completion gate keeps seeing open concerns.
5. **F-12 echo.** If the orchestrator session itself was resumed and its listen loop is active but internal task-tracking state wasn't reloaded (only the inbox was drained), it may have lost track of "what phase am I gating and what's the completion condition." Resume mode for orchestrator currently doesn't reload triage state — it just restarts listen.

**Fix directions (not yet implemented):**

1. **Explicit completion check on every state-changing inbound.** In orchestrator's repo-spec handler table, after handling each `review`, `resolution`, `resolution-summary`, or `pause-ack`/`continue-ack`, run a `check_negotiation_complete()` pass that inspects all tracked workers and emits `negotiation-complete` when conditions are met. Not bound to a timer.
2. **Completion-condition logged explicitly.** Orchestrator writes the current completion condition to a log/Slack line every time it's re-evaluated ("checking: web approved ✓, oracle approved-with-conditions ✓, server pending, concern abc ✓, concern xyz ✓"). If the gate never passes, the log shows why — makes silent stalls debuggable.
3. **Resume reloads triage state.** Orchestrator `--resume` (from F-4) gains a step: re-read all `~/.claude/state/{repo}.json`, all concern/resolution files, all review files in the current session to rebuild in-memory completion tracker. Without this, a mid-phase orchestrator resume is blind to pending work. Ties to F-4.
4. **Human-callable `/xfleet-status` command.** Read-only: lists workers with phase/status, pending concerns with round counts, review status, and the current completion condition + whether it evaluates true. Lets the human diagnose stalls like this without reading state files manually.

**Recommendation:** #1 is the correctness fix (completion becomes event-driven, not implicit). #2 is the observability layer that makes future stalls self-explaining. #3 pairs with F-4 — resume shouldn't be "just restart listen." #4 is broader tooling; standalone value.

Related to F-4 (resume mechanics), F-9 (batching — if completion emission gets batched with result surfacing, both arrive at the human together), F-10 (phase-boundary handoffs would include completion-tracker state).

### F-14. Need human gate before `negotiation-complete` + "human-engaged" flag to suppress auto-escalation (2026-04-22) — RESOLVED via cluster 4a (human gate + `human_engaged` flag + `concern-reopen` message + `xfleet engage`/`disengage` commands)
Scenario: during concern resolution, human is actively engaged — reviewing resolution content, talking to workers directly (via send.sh or Slack relay), potentially reopening a concern to steer toward a different alignment. Two gaps surface when the human is this active:

1. **Auto `negotiation-complete` is premature.** Orchestrator's completion-check (F-13) may fire the moment all reviews + resolutions are in, sending `negotiation-complete` before human has reviewed the resolutions. Once workers receive it, they finalize sections — reopening is expensive. Human needs a checkpoint to say "yes, close it out" or "reopen F-3 with this new direction."

2. **Auto-escalation fights active human engagement.** If human has been in-thread discussing a concern, the orchestrator's round-5 hard-stop and straggler timeouts keep firing as if nobody's home. The "please decide" Slack posts stack on top of the human who is *already deciding*. Noise, and worse: if the escalation blows out to a new thread or stale reply form, the human's in-progress alignment fragments.

**Proposed additions:**

**A. Human gate before `negotiation-complete`.** Orchestrator's repo-spec (and any analogous negotiation phases) treats "all reviews in + all concerns resolved" as "ready for negotiation-complete," not "emit now." Orchestrator surfaces a summary to the human:
```
Ready to close repo-spec:
- server: approved ✓
- web: approved-with-conditions (see ~/.claude/reviews/web-1.md) ✓
- oracle: approved ✓
Concerns resolved:
- C-1 (web→server, api retry contract): resolution at ~/.claude/resolutions/C-1.md
- C-2 (oracle→server, schema migration order): resolution at ~/.claude/resolutions/C-2.md
Send `negotiation-complete` now? [approve | reopen <concern-id> <direction> | hold]
```
Human options: approve (send negotiation-complete), reopen (mark concern as reopened + relay direction to workers), hold (do nothing, keep listening; used when human wants to discuss further before deciding).

**B. `human_engaged` flag in orchestrator state.** New field in `_orchestrator.json`:
```
human_engaged: {
  active: true,
  concern_id: "C-1" | null,        // scoped to one concern, or null for session-wide
  set_at: "<ISO timestamp>",
  reason: "reviewing resolutions" | "negotiating directly" | "..."
}
```
When `active: true`:
- Auto round-5 hard-stop is SUPPRESSED (human is already here; auto-pausing workers would interfere).
- Straggler warnings for the scoped concern are SUPPRESSED.
- Auto `negotiation-complete` is SUPPRESSED — must go through human gate (A) even if completion condition met.
- All-idle prompt is SUPPRESSED (human is actively driving).
Auto-clears when: (i) the scoped concern closes (resolution written + human approves in gate A), (ii) phase transitions out of repo-spec, (iii) human explicitly clears via command.

**C. `concern-reopen` message type.** Orchestrator → workers. Fields: `concern_id`, `round_note` (human's reason/direction), optional `alignment_hint` (proposed new direction). Workers receive → mark concern as reopened in local state → re-read concern file for new round heading → investigate and respond per normal concern flow. Round counter continues (not reset) — if we're at round 5 and human reopens for round 6, escalation is skipped because `human_engaged` is true.

**Operator flow example:**
```
1. Repo-spec enters. Concerns C-1, C-2 raised.
2. Round 3 on C-1, round 2 on C-2.
3. Human starts reading the live round-3 exchange on C-1 in Slack → sends a directional message to both workers.
4. Orchestrator detects human engagement (Slack reply or explicit /xfleet engage C-1) → sets human_engaged.
5. Round 4 on C-1 lands. Normally round-5 risk; orchestrator DOES NOT pre-emptively pause — human is here.
6. Resolution C-1 reaches round 5 with alignment. Round-5 hard-stop SUPPRESSED by human_engaged.
7. C-2 resolves in round 3 normally.
8. Reviews all approved. Completion condition met.
9. Orchestrator surfaces human gate (A) with resolution summary. Human reviews. Says "approve."
10. Orchestrator emits negotiation-complete. human_engaged clears. Phase advances.
```

**Implementation notes (not yet done):**
- Extend orchestrator state schema (`shared/state-schema.md`) with `human_engaged` shape.
- Add `concern-reopen` to the message-type table in `shared/messaging.md` + validator in `send.sh`.
- Update repo-spec phase skill for orchestrator: completion check → human gate, not auto-send.
- Update worker phase skills: handle `concern-reopen` → reopen concern, investigate again.
- Add orchestrator commands: `/xfleet engage {concern_id?}`, `/xfleet disengage`, `/xfleet reopen {concern_id} --direction "..."`.
- Detection heuristic: auto-set `human_engaged` when orchestrator relays a human Slack reply into the session via send.sh (i.e., human pushed content into the negotiation). Manual `/xfleet engage` is the explicit path.

Related to F-9 (batching — the human gate is where batching pays off most; surface one coherent picture, not a stream). Related to F-13 (completion detection — this layers a human-approval step on top of the event-driven completion check). Related to F-1/F-2 (orchestrator grounding — a more grounded orchestrator can better detect "human is engaged" from context rather than needing explicit flags).

### F-15. Round counter increments per-send, not per-exchange (2026-04-22) — RESOLVED via cluster 4a (INCR only on `--type concern`, not `--type response`; 1 round = peer-A statement + peer-B response)
`send.sh` currently `INCR concern:{id}:rounds` on every worker-to-worker call that carries `--concern_id` (regardless of `--type`). But a "round" should mean a **logical exchange** — one party's statement plus the other's reply — not every message.

**Current behavior:**
```
A sends --type concern ...        → round=1
B sends --type response ...       → round=2
A sends --type concern [counter]  → round=3
B sends --type response ...       → round=4
A sends --type concern [counter]  → round=5  ← round-5 hard-stop fires
```
5 sends = ~2 logical exchanges. Round-5 escalation fires long before real rounds-of-disagreement have accumulated. Humans get pinged for escalation on what's really round 3 of negotiation.

**Expected behavior (logical rounds):**
```
A sends --type concern ...        → round=1  (A's opening statement)
B sends --type response ...       → round=1  (B's reply completes round 1)
A sends --type concern [counter]  → round=2  (A counter-proposes → new round)
B sends --type response ...       → round=2
A sends --type concern [counter]  → round=3
B sends --type response ...       → round=3
...
→ round-5 hard-stop fires at round 5 of real negotiation (10 sends)
```
A round starts when the raiser makes a statement; the responder's reply is part of that same round. Counter-statement = new round.

**Fix directions (not yet implemented):**

1. **INCR only on `--type concern` (statement/counter), not on `--type response`.** Simplest change. `send.sh` conditional:
   ```
   if [ "$type" = "concern" ] && [ "$concern_id" != "" ] && [ "$to" != "orchestrator" ]; then
     redis-cli INCR "concern:$concern_id:rounds"
   fi
   ```
   Round = one concern + one response. Counter-proposing starts round 2. Matches operator intuition and aligns escalation math with real disagreement.

2. **INCR when sender != last-sender for this concern.** Track last sender per concern; INCR when bounce occurs. Works regardless of type name, but adds state-tracking complexity for marginal benefit over #1.

3. **Separate counters per type.** `concern:{id}:statements` vs `concern:{id}:responses`. Round-5 hard-stop gates on statements. More granular; probably over-engineered for the actual need.

**Recommendation:** #1. Clean, matches the intuitive definition of a round, minimal code change, escalation math works immediately. Need to revisit the round-5 threshold after the fix lands — what was tuned for the old (send-counting) semantics may be too loose for real-rounds; could shift to round-3 or round-4.

**Knock-on effects to check:**
- Orchestrator's `_orchestrator.json` tracks `last_round5_pause` — may need to re-tune thresholds once counter is correct.
- Convergence counter (3+ gate re-opens on same phase) is separate, not affected.
- Any existing concern files with accumulated round headings from the current (wrong) counter should be re-interpreted or migrated; probably just note in the fix commit that "rounds pre-fix ≠ rounds post-fix semantically."

Related to F-13 (completion detection — round counter informs when a concern has dragged long enough that completion without resolution is suspect), F-14 (round-5 hard-stop is what `human_engaged` suppresses; correcting the counter also makes suppression criteria cleaner).

### F-16. `prepare-compact` timing policy gap in non-task phases (2026-04-22) — RESOLVED via cluster 4f (phase-aware thresholds + pre-flight compact + suggest-at-gates)
Current `prepare-compact` rhythm is calibrated for the implement phase — fired between tasks, between messages, and at context-check warn/critical thresholds (70%/80%). But non-task phases have their own predictable context cost patterns that aren't captured by the existing rules:

**Observed case (2026-04-22):** in repo-spec, about to write the final spec section + review peer sections. Human manually ran `prepare-compact` at ~50% context because they anticipated the write+review sequence would easily push past 80% in one burst with no natural check point in between. The existing rules wouldn't have fired — no phase-complete about to emit, no message boundary pending, context below warn threshold.

By the time the existing rules *would* have fired, the worker would be mid-write at 85%+, handoff would be rushed, and auto-compact could hit mid-operation.

**The gap:** compaction policy is event-triggered (message boundary, phase-complete, threshold crossing). Non-task phase work is often **predictably-expensive-in-one-burst** — spec writes, spec reviews, multi-section document assembly — which doesn't hit the events until the damage is done.

**Design considerations:**

1. **Phase-aware context budgets.** Each phase declares an expected context cost profile:
   - `implement`: moderate per-task; existing rules suffice.
   - `repo-spec`: high for spec-write + peer-review; compact proactively at ≥ 50% before starting a write-heavy subtask.
   - `qa-spec`: moderate for Q&A; existing rules mostly fine.
   - `cross-review` / `alignment`: variable; profile as observed.

   Phase skill frontmatter or on-entry block sets thresholds: `warn_at: 50, critical_at: 65` for repo-spec (vs default 70/80). Worker base loop respects phase-declared overrides.

2. **Pre-flight compact before known-expensive subtasks.** Phase skills mark specific subtasks as "context-heavy" (e.g., "Write your spec section", "Review peer N's section"). Before entering such a subtask, the worker runs `check-context` + if ≥ phase's compact threshold, runs `prepare-compact` preemptively and sets `status: "compacting"` so human can resume post-clear into the heavy work with fresh context.

3. **Human gates as natural compact checkpoints.** F-14's human gate at `negotiation-complete` is a perfect compaction point — the human is already pausing. Orchestrator can suggest (or the worker can auto-run) compact just before human gate entry. Tie the compaction rhythm to gate entries rather than inventing new checkpoints.

4. **"Entering write-heavy mode" explicit marker.** Worker skill: any block that will produce a multi-kilobyte Write (spec section, review file, resolution file) starts with: "I'm about to do a {subtask-name}. Running check-context first." If ≥ 50%, prepare-compact and stop. Makes the intent self-documenting — human reading the log sees the reasoning.

**Recommendation:** #1 + #3. Phase-aware thresholds give correct default behavior; human gates become the rhythm for proactive compaction in non-task phases (since they're already pauses). #2 complements by giving worker skills a way to preempt even before a gate. #4 is an always-on discipline that makes #2 observable.

**Pairs with:**
- F-6 (context-check injection gaps): F-6 is about *mechanism* — how check-context gets invoked. F-16 is about *policy* — when/at-what-threshold to prompt compaction. Both needed; neither is sufficient alone.
- F-10 (no handoff on orchestrator-driven phase transitions): a well-placed pre-phase-transition compact (from this finding) + a phase-boundary handoff (from F-10) together mean every phase transition is a clean resume point.
- F-14 (human gate before negotiation-complete): the gate is the natural compact trigger; this finding explicitly routes the compaction rhythm through gates.

**Implementation notes (not yet done):**
- Add `compact_warn_pct` / `compact_critical_pct` fields to phase-skill metadata.
- Worker base loop reads these on entry to a phase, overrides default 70/80.
- `check-context` skill accepts an override-threshold arg so phase-specific thresholds propagate in.
- Document phase-specific thresholds in xfleet README's check-context section.

### F-17. Orchestrator re-emits phase signals after human-driven reopens (2026-04-22) — RESOLVED via cluster 4a (one-shot `approved_by_human` authorization + UUID `emission_id` idempotency + audit log)
Observed: `negotiation-complete` was sent by orchestrator multiple times in one phase:

1. Initial completion condition met → orchestrator emits `negotiation-complete` to each worker.
2. Human interrupts: reopens a concern (via direct send.sh or Slack relay), steers toward a different resolution.
3. New resolution closes → completion condition becomes true again → orchestrator emits `negotiation-complete` again.
4. Workers correctly ignore the repeat — but only because the human had previously injected a directive in their sessions ("ignore fresh negotiation-complete"). Fragile: a worker that was session-restarted/resumed since the directive would have lost it and blindly obeyed the second emission, finalizing prematurely.

The root cause is that the orchestrator's completion-check (F-13) has no memory of **what phase-level signals it has already sent** and no gate on **whether the re-emission is authorized by the human**. After a reopen, the state transitions look identical to the orchestrator — concerns closed, reviews approved — and it emits again on autopilot.

**Proposed design: `human_approved` one-shot authorization per phase-level emission.**

Orchestrator state gains tracking for authorized-but-unconsumed emissions and already-sent emissions:

```json
{
  "phase_emissions": {
    "repo-spec": {
      "negotiation-complete": {
        "sent_at": "<ISO timestamp or null>",
        "sent_to": ["server", "web", "oracle"],
        "approved_by_human": false
      }
    }
  }
}
```

**Rules:**

1. **Must be explicitly human-approved before emission.** Any orchestrator-driven phase-level outbound (`negotiation-complete`, phase signals that transition out of a gated phase) requires `approved_by_human: true`. Completion-condition satisfied is necessary but not sufficient — the human gate (F-14) sets the flag to true.

2. **Flag is one-shot.** After emission, the flag AND the `sent_at` timestamp both record. `approved_by_human` stays `true` only until the emission fires; on next human gate entry for the same signal, it resets to `false`.

3. **Re-emission requires re-approval.** If a reopen happens after emission, orchestrator clears `sent_at` (to signal "we need to redo this") but does NOT auto-set `approved_by_human: true`. Human must go through the gate again after the reopened concern closes. Guards against autopilot re-firing.

4. **Workers honor idempotency via emission-id.** Each emission carries a unique `emission_id` (UUID or session+phase+sequence). Workers track last-handled emission_id per phase; duplicate emissions with same or older id are no-ops. This is belt-and-suspenders: even if orchestrator misfires, workers don't double-finalize. Doesn't require human directives in worker sessions, so session-restart-safe.

5. **Audit log.** Every emission (successful or refused) writes a line to `_orchestrator.json:emission_log[]` with timestamp, signal type, approved-by-human value, emission_id. Debuggable; the human can see exactly when each negotiation-complete fired and why.

**Operator flow after this lands:**

```
1. Completion condition met first time → orchestrator surfaces human gate (F-14).
2. Human approves → orchestrator sets approved_by_human=true, emits negotiation-complete #1,
   marks sent_at, clears approved flag.
3. Human immediately reopens a concern → orchestrator clears sent_at (so it knows to re-emit
   later), keeps approved_by_human=false. No autopilot emission.
4. Workers see concern-reopen (F-14 C), reopen their local state. Ignore any stale
   negotiation-complete that may arrive during the reopen window (idempotency via emission_id
   — they already consumed #1).
5. New resolution closes → completion condition true again.
6. Orchestrator surfaces human gate again (because approved_by_human=false). Human approves.
7. Orchestrator emits negotiation-complete #2 (new emission_id). Workers handle.
```

**Fix directions (not yet implemented):**

- Extend orchestrator state schema (`shared/state-schema.md`) with `phase_emissions`, `emission_log`.
- Update orchestrator's completion-check (from F-13 #1) to gate emission on `approved_by_human` in addition to the completion condition.
- Update `send.sh` to generate and stamp `emission_id` for applicable message types.
- Add emission_id idempotency handling to worker's `negotiation-complete` handler (and any other phase-closing signals).
- On `concern-reopen` (F-14 C), orchestrator clears `sent_at` for the current phase's emission — enforces re-approval.

**Recommendation:** land with F-14's human gate — they're the same feature surface. F-14 gives the human control over WHEN to approve; F-17 makes that approval a proper one-shot authorization so orchestrator can't bypass it.

Related to F-14 (human gate drives `approved_by_human`), F-13 (completion detection is the trigger that asks for approval), F-12 (worker resume after emission should recognize the emission via state, not require human re-injection of directives), F-15 (round counter needs to be correct for the human to trust the reopen count).

### F-18. Final spec should be written to a distinct new file (2026-04-22) — RESOLVED via cluster 4l (largely obsoleted by cluster 4c's snapshot mechanic; no separate finalized-suffix needed; spec.md current + spec-v{N}.md milestone snapshots; reviewers diff against latest snapshot)
After repo-spec negotiation completes and `finalize-spec` merges per-repo sections + resolutions, the consolidated final spec should land in a **new file**, not in the same path as the in-progress/draft spec. Reviewer agents and humans need a clear artifact to review that isn't contaminated by draft/section state.

**Why it matters:**
- **Reviewer agents get a clean input.** If the final spec lives next to section drafts and working copies, reviewers have to figure out which file is authoritative. A distinct filename/path removes the ambiguity.
- **Diff the transitions.** Keeping the draft (input) separate from the finalized version (output) makes the draft→final diff inspectable — what changed during negotiation and resolution is visible.
- **Audit trail.** Each phase's output is a durable artifact. Overwriting loses history; writing new preserves it.
- **Clearer handoff to downstream phases.** Plan / implement phases want to read "the spec" — they shouldn't have to know whether they're reading a draft or the finalized form.

**Current state (needs verification):** `finalize-spec` skill writes to `~/workspace/docs/superpowers/specs/{YYYY-MM-DD}-{slug}.md` per the existing convention, and refuses destinations under `~/.claude/specs/`. That's already a "new location" relative to the per-repo section files (`~/.claude/specs/{repo}-section.md`). But:
- If the draft-in-progress lived at the same `YYYY-MM-DD-{slug}.md` path (e.g., human was iterating in-place during qa-spec), finalize may overwrite it.
- Filename doesn't mark "this is finalized" vs "this is still being drafted."
- Reviewer agents invoked on the spec directory may still pick up both drafts and finalized versions.

**Fix directions (not yet implemented):**

1. **Explicit finalized-suffix or subdirectory.** Write the finalized spec to `~/workspace/docs/superpowers/specs/{YYYY-MM-DD}-{slug}-final.md`, or to a `specs/final/` subdirectory. Unambiguous from filename alone. Reviewers glob `*-final.md` or the `final/` dir.

2. **Finalized-header marker.** Frontmatter or explicit top-of-file block:
   ```
   ---
   status: finalized
   finalized_at: 2026-04-22T14:30:00Z
   source_draft: ~/workspace/docs/superpowers/specs/2026-04-22-reducto.md
   ---
   ```
   Reviewer agents check the header — no filename convention needed, but this alone doesn't solve the co-location problem.

3. **Draft-archive move on finalize.** When `finalize-spec` runs, it also moves the draft to `drafts/archive/{YYYY-MM-DD}-{slug}.md` (or renames to `.draft.md`) so only the finalized version sits at the primary path. Keeps the one-file-per-spec convention clean but loses the draft's inline status.

4. **Pointer file.** Write `specs/latest-{slug}.md` as a symlink or pointer to the current finalized file. Downstream consumers (plan, implement) read the pointer; it stays stable even as re-finalizations happen with new timestamps.

**Recommendation:** #1 + #2 together. `-final.md` suffix (or `/final/` subdir) gives a filename-level signal that's greppable/globbable; the finalized-header marker gives an in-file signal that survives path changes. #3 is worth considering if the draft files otherwise clutter the specs dir. #4 solves a downstream-consumer problem that may not exist yet.

**Implementation notes (not yet done):**
- Decide: suffix (`-final.md`) or subdirectory (`specs/final/`). Suffix is simpler; subdirectory groups the finalized-only view.
- Update `finalize-spec` skill: refuse overwrite if destination already finalized; emit with the chosen naming convention; include finalized-header in the output.
- Update reviewer agents (prd-reviewer dim agents, any spec-reviewing reviewers) to prefer finalized form when both exist.
- Document the draft → final workflow in xfleet README / finalize-spec SKILL.

Related to F-7 (script paths — if there's a wrapper `xfleet finalize-spec`, it can enforce naming conventions centrally), F-10 (phase-boundary handoff — finalized-spec emission is effectively the exit handoff from repo-spec to plan/implement).

### F-19. Per-repo spec sections (and plans, reviews, alignment) live in global `~/.claude/`, never land in the owning repo (2026-04-22) — RESOLVED (cluster 4c, 2026-05-04)
**Sub-findings (consolidated 2026-05-04):** F-26 (init-vs-clean section model — immutable qa-spec distribution snapshot) and F-27 (worker-side `finalize-section` skill + versioned outputs) — both elaborate on F-19's per-repo durability + content hygiene principles.

Current xfleet convention:
- Per-repo working files live in global `~/.claude/`:
  - `~/.claude/specs/{repo}-section.md` — repo's spec section during repo-spec phase
  - `~/.claude/plans/{repo}-plan.md` — repo's plan during plan phase
  - `~/.claude/reviews/{repo}*.md` — review output during cross-review
  - `~/.claude/alignment/{repo}.md` — alignment notes
- Only the **final merged spec** is written to `~/workspace/docs/superpowers/specs/{YYYY-MM-DD}-{slug}.md` (workspace, not the owning repos).
- `/cleanup` eventually wipes the global working files.
- **No phase today moves per-repo sections/plans/reviews to the owning repo's durable storage.**

**The gap:** oracle's section is written to `~/.claude/specs/oracle-section.md`, not `{oracle}/docs/superpowers/specs/sections/...`. After cleanup, oracle has no local artifact of what it contributed to the cross-repo spec. This costs:

- **Per-repo audit trail is missing.** The owning repo should have its own history of what it spec'd/planned/reviewed for every cross-repo session. Losing that to `/cleanup` erases institutional memory.
- **Reviewer agents in the owning repo can't easily inspect the work.** They'd have to reach into `~/.claude/` (global, not repo-scoped) to find the section. In-repo reviewers (`.claude/agents/...` in that repo) are designed for repo-local artifacts.
- **Normal repo tooling (git diff, code-review, in-repo search) doesn't see the section.** Every other artifact the repo produces lives in the repo; these don't.
- **Serena memories and repo-local CLAUDE.md context can't capture spec/plan lineage.** Future sessions in that repo have no local breadcrumb to find prior contributions.

**Fix directions (not yet implemented):**

1. **Workers write sections/plans/reviews to their own repo's `docs/superpowers/` tree.** Canonical paths per repo:
   - `{repo_path}/docs/superpowers/specs/sections/{YYYY-MM-DD}-{slug}.md`
   - `{repo_path}/docs/superpowers/plans/{YYYY-MM-DD}-{slug}-plan.md`
   - `{repo_path}/docs/superpowers/reviews/{YYYY-MM-DD}-{slug}-review.md`
   - `{repo_path}/docs/superpowers/alignment/{YYYY-MM-DD}-{slug}.md`

   Workers update their `~/.claude/state/{NAME}.json` with the path of the latest artifact of each type (so orchestrator and other workers can find them cross-repo). Global `~/.claude/specs/{repo}-section.md` goes away entirely.

2. **Global as working layer, per-repo as durable layer (two-stage).** Workers keep iterating in `~/.claude/` during the phase (coordination + collaborative read access), and on phase-complete they copy the artifact to their repo's `docs/superpowers/` durable location. `/cleanup` then only sweeps the global working copy, repo-local copies persist.

3. **Post-finalize distribution.** After `finalize-spec` runs, it also distributes per-repo sections back to each repo's `docs/superpowers/specs/sections/`. Keeps sections accessible globally during the phase (no protocol change for workers), adds a durable repo-local artifact at the end. But doesn't help for plans/reviews/alignment unless extended.

4. **Leave as-is but make cleanup preservationist.** `/cleanup` already preserves session-scoped xfleet handoffs in each repo's `docs/superpowers/handoffs/`. Extend: also preserve a bundle of per-repo artifacts (section, plan, review, alignment) to each repo on cleanup, then wipe the global copy. Lowest-protocol-change fix; highest garbage-potential if cleanup is forgotten.

**Recommendation:** #1 (workers write repo-local directly) is the clean long-term answer — it matches the pattern that every other meaningful artifact lives in the repo that owns it. Cross-repo reads are already normal in xfleet (workers read peers' code all the time), so cross-repo reads of peers' sections via state-file paths is a natural extension. Requires:
- Updating worker phase skills (repo-spec, plan, cross-review) to write to repo-local paths.
- Adding path fields to `~/.claude/state/{NAME}.json` (e.g., `current_section_path`, `current_plan_path`) so orchestrator and peers can resolve them.
- Updating `finalize-spec` to read from each worker's state file instead of the global `~/.claude/specs/` dir.
- Updating `/cleanup` to stop sweeping these paths in global (since they won't be written there anymore).

**Interim if #1 is too invasive:** #3 (post-finalize distribution) is the smallest change that gets a per-repo artifact for specs at least. Plans/reviews/alignment need separate handling.

Related to F-10 (phase-boundary handoffs — if workers already write handoffs to repo-local, extending to write full artifacts is a natural progression), F-18 (final spec output convention — same philosophy: durable artifacts go to durable places), F-7 (global-state-coordination vs per-repo-durability split is a recurring tension worth codifying in the xfleet design principles).

**Content hygiene — what the per-repo durable artifact should contain (2026-04-22):**

The per-repo section that lands in `{repo}/docs/superpowers/specs/sections/...` (or wherever fix #1 writes it) should be **clean** — just the final agreed-upon spec content for that repo. It should NOT include:

- Concern/response history from the negotiation rounds.
- Resolution text with back-and-forth reasoning.
- Review notes, cross-review findings, reviewer-agent output.
- Alignment-phase adjustment records.

**Why clean matters:**
- **Plan-phase input is simpler.** Plan skill reads the repo's spec section + repo's code. It doesn't need to re-digest the negotiation path — just what was agreed. Contaminating the section with concern history forces the plan to filter or risk mis-scoping the work.
- **The repo-local artifact is a reference, not an archive.** Future sessions reading the section want "what was the spec?" not "how did we get there?"
- **Reviewers (code reviewers, post-merge audits) shouldn't be re-litigating design decisions.** The spec section should read as a forward-looking contract, not a retrospective.

**What about the negotiation history, then?**

It has real audit value — future debugging of "why was this decided?" or "what concern did we dismiss?" benefits from having it. But it belongs in a separate, grouped artifact:

1. **Bundle per session.** `{repo}/docs/superpowers/xfleet/{slug}/` (path renamed by cluster 4c, 2026-05-04 — was `specs/sessions/{YYYY-MM-DD}-{slug}/` in original F-19 body) containing:
   - `section.md` — the clean final spec section (the artifact plan consumes).
   - `concerns.md` — all concerns this repo raised or was addressed in, with resolutions inline.
   - `reviews.md` — cross-review and repo-spec reviewer findings.
   - `alignment.md` — alignment-phase adjustments.
   - `README.md` — session metadata (date, participants, final spec path, link to the merged cross-repo spec).

2. **Or flat co-location** with naming convention:
   - `{YYYY-MM-DD}-{slug}-section.md` — clean section.
   - `{YYYY-MM-DD}-{slug}-history.md` — everything else bundled.

3. **Or keep only the clean section repo-local, archive history in the orchestrator's repo** (workspace `docs/superpowers/sessions/...`). Trade-off: per-repo gets the minimum needed; global archive holds the full audit.

**Recommendation:** option 1 (bundle per session) — keeps the clean artifact unambiguously identifiable (always `section.md` in the session dir) while preserving the audit trail in a well-named neighbor. Plan phase reads `section.md` directly, ignoring siblings.

**Impact on fix direction #1 (workers write repo-local):**
- Workers write the clean section, not the running draft with embedded concerns.
- Separate writes happen for `concerns.md`, `reviews.md`, `alignment.md` at phase-close boundaries.
- Phase skill guidance needs to explicitly say "do NOT inline concern/resolution text into your section — reference by link if needed."

**Impact on finalize-spec:**
- Source: reads `section.md` from each worker's state-file-provided path.
- Output: writes the merged cross-repo spec to workspace's durable tree as today, but also writes a session-level archive that links to each repo's session dir. Single pointer the orchestrator and humans can navigate.
- Stops deleting per-repo content (the `rm -f ~/.claude/specs/*-section.md` step goes away, since sections now live repo-local and aren't transient).

### F-20. Unified intensity flags across all reviewer agents (2026-04-22) — RESOLVED via cluster 4m (architect-review canonical for xfleet phase reviews; prd-review keeps dim agents; /code-review left as-is third-party; worker-config.md defaults to architect-review; intensity policy already locked by cluster 4a)
`architect-review` and `prd-review` skills support intensity levels (`standard` / `high` / `critical`). The per-repo reviewer agents configured via `worker-config.md:reviewers:` (used in repo-spec and cross-review phases) do NOT currently share this contract — they're invoked without a uniform intensity parameter, so their rigor is whatever the agent author hard-coded.

**Proposed:** standardize intensity flags across every reviewer agent in the xfleet ecosystem. Same schema, same semantics:

- **`standard`** (default): core review dimensions only. Fast, catches the obvious. Used during rapid iteration.
- **`high`**: adds adversarial / edge-case / evolution-of-pattern dimensions. Used before distributing a spec, before merging a plan.
- **`critical`** (also called `extreme` colloquially): highest rigor. Adds auto-ADR capture for Significant Concerns, longer search radius in Serena / Context7, explicit MISREAD/EVOLUTION passes. Used for irreversible calls (payments, auth, migrations).

**What each reviewer agent needs:**
- Accept an `intensity` input (argument or frontmatter field).
- Resolve intensity: explicit CLI/caller override → frontmatter declaration on target artifact → default `standard`.
- Gate which dimensions run based on intensity (same pattern as architect-review's Step 1 table).
- Declare supported intensities in the agent file so callers know what's available.

**Integration points:**

1. **worker-config.md `reviewers:`.** Each reviewer entry declares default intensity (or a phase-specific mapping: `{repo-spec: standard, cross-review: high}`). Workers passing to reviewer agents read these defaults, let orchestrator override per-phase.

2. **Orchestrator-level intensity policy.** Orchestrator sets session-wide intensity (e.g., "this is a payment feature — all reviewers at high minimum"). Broadcast via a `policy` message or set as a field in `_session.json:intensity_floor`.

3. **Phase-specific defaults.** Some phases warrant higher intensity by default — final repo-spec review, cross-review on risky features, pre-finalize spec review. Phase skills declare their default intensity; reviewer calls inherit unless overridden.

4. **prd-review dim agents already have it implicitly.** `prd-review` passes `intensity` to each dim. Extend to the per-repo reviewer dispatch path.

**Recommendation:**
- Define the unified intensity contract in `~/.claude/xfleet/shared/reviewer-contract.md` (new file) — documents the schema, resolution order, what each level changes.
- Update every reviewer agent file to declare intensity support + resolution logic (probably by referencing the shared contract rather than duplicating).
- Update phase skills (repo-spec, cross-review) to pass intensity when invoking reviewers.
- Update `worker-config.md` schema docs to show how to declare per-reviewer or phase-specific defaults.

**Terminology nit:** user used "extreme" for the top level. Existing skills use "critical." Decide: rename to `extreme` (more evocative, less overloaded — "critical" is also used for severity elsewhere) or keep `critical` for backwards compatibility. Minor but worth settling.

Related to F-14 (human_engaged / gate — higher intensity may warrant human gate at additional checkpoints), F-21 (reviewer findings blocking phase-complete — intensity determines how thoroughly findings are generated, which affects the block/proceed gate).

---

### F-21. Repo-spec phase should not complete while reviewer findings are unresolved (2026-04-22) — RESOLVED via cluster 4a (worker-side triage loop with convergence counter; alert-only JUDGMENT escalation via `xfleet escalation`; graduated intensity per phase)
Current repo-spec flow (from `~/.claude/xfleet/phases/repo-spec.md:14,51`):
```
On negotiation-complete:
  1. Write finalized section to ~/.claude/specs/{NAME}-section.md
  2. Run reviewer agents from worker-config.md
  3. Write findings to ~/.claude/reviews/{NAME}-final.md
  4. Send phase-complete --phase repo-spec --path ~/.claude/specs/{NAME}-section.md
```

**The gap:** reviewer findings in Step 3 are produced but **not triaged or addressed** before Step 4 fires. Phase-complete goes out even if the reviewers surfaced Critical Issues on the section. The findings file sits as a passive artifact; nothing enforces action on it. Workers move past repo-spec carrying known reviewer-flagged issues into plan phase, where they propagate.

Expected: no worker emits phase-complete until its reviewer findings are either resolved (section revised) or accepted (human explicitly waives). The repo-spec completion gate (F-13/F-14) should block until every worker's reviews are clean or waived.

**Fix directions (not yet implemented):**

1. **Findings-triage loop inside repo-spec (before phase-complete).**
   ```
   On negotiation-complete:
     1. Write finalized section.
     2. Run reviewer agents. Triage findings (LOOKUP/PATTERN/JUDGMENT from F-20's shared contract).
     3. For LOOKUP/PATTERN findings: worker revises the section to address them, re-runs the relevant reviewer(s), updates the findings file. Loop until no LOOKUP/PATTERN remain OR a convergence-counter trips (e.g., 3 revision passes).
     4. For JUDGMENT findings: send them to orchestrator as a `review-judgment` message with the finding + proposed disposition. Orchestrator surfaces to human (batched with peer workers' JUDGMENT findings per F-9) for approve/reopen/waive.
     5. Only after LOOKUP/PATTERN are resolved AND JUDGMENT are dispositioned → send phase-complete with final clean section path + decisions log.
   ```

2. **Orchestrator-gated completion-check (extending F-13).** Orchestrator's completion condition for repo-spec becomes:
   - All workers sent phase-complete.
   - All reviewer findings across workers are marked resolved, accepted, or waived.
   - All concerns (already existing condition) resolved.
   Orchestrator reads each worker's `reviews/{NAME}-final.md` to verify the findings count/status before emitting its own wrap-up signal. A phase-complete from a worker with unresolved RED/CRITICAL findings is not accepted — orchestrator sends back a `review-reopen` message prompting further revision.

3. **Convergence counter to prevent infinite loops.** If worker hits N revision passes (e.g., 3) and still has LOOKUP/PATTERN findings, escalate to JUDGMENT — human must accept or explicitly kill the issue. Prevents a single finding from deadlocking repo-spec.

4. **Intensity-gated strictness.** At `standard`, only Critical Issues block; Significant Concerns are advisory. At `high`, Significant Concerns also block. At `critical`, every finding must be resolved or explicitly waived. Ties directly to F-20.

**What "clean final spec" means (per the user's framing):**
- Section content addresses all blocking findings (determined by intensity per F-20).
- Non-blocking findings are documented in a `notes` or `deferred` section of the spec (if material) or listed in a companion file (if tangential) — never silently dropped.
- No open questions in the section itself — they've all become JUDGMENT decisions (human answered) or LOOKUP/PATTERN answers (worker investigated).
- The section reads forward-looking: "here's what we're building," not "here's what we debated."

**Recommendation:** #1 + #2 together. Worker runs its own triage loop locally (fast, no round-trips for LOOKUP/PATTERN). Orchestrator verifies at its completion check that findings are truly resolved before the phase can close. #3 is the safety valve against deadlocks. #4 pairs with F-20's unified intensity contract.

**Implementation notes (not yet done):**
- Update `repo-spec.md` on-entry block for workers to include the triage loop (Step 3+).
- Reviewer agents need to emit findings in a triage-compatible format (LOOKUP/PATTERN/JUDGMENT + severity) — pairs with F-20 standardization.
- Orchestrator's repo-spec phase skill needs a reviewer-findings completion check before advancing (like the concern-resolution check it already does).
- Convergence counter state lives in `~/.claude/state/{NAME}.json` (e.g., `review_revision_count: 2`).
- If the triage loop repeatedly fails to converge, worker emits an `escalation` message (existing type) with the stuck finding — human adjudicates.

Related to F-14 (JUDGMENT findings go to human gate), F-13 (completion condition gets the findings dimension), F-17 (orchestrator's gating / human-approved flag applies to phase-complete acknowledgments with unresolved findings), F-20 (intensity determines what's a blocker), F-19 (the clean section is what lands in repo-local durable storage).

### F-22. Dedicated message type for human → worker directives via orchestrator (2026-04-22) — RESOLVED via cluster 4e (F-51 Phase A taxonomy + Phase B `xfleet directive`)
Currently, when the human wants to give a worker direction (e.g., "reopen concern X with alignment toward Y", "pause this investigation and look at Z first", "add this consideration to your spec section"), they either:

1. **Write directly to the worker via `send.sh`** using `concern` type. This abuses the concern contract — `concern` implies cross-worker negotiation with round-counter semantics (F-15). Every human message INCRs the round counter wrongly. Orchestrator doesn't see it, so `human_engaged` (F-14) doesn't fire, auto-escalation keeps running.

2. **Or relay through orchestrator verbally** (in-session chat), which then writes a `concern` to the worker. Same `concern` misuse, plus orchestrator may not set up proper state tracking.

Both paths abuse `concern`. A directive is semantically distinct: it's **human → worker(s)**, carries intent not negotiation, doesn't start or extend a round, and should trigger orchestrator-side bookkeeping (human_engaged, directive log).

**Proposed message type: `directive`** (orchestrator → worker, human-originated).

```
send.sh orchestrator {worker} \
  --type directive \
  --origin human \
  --scope {task|concern|phase|session} \
  --concern_id {id?} \
  --path {file_with_directive_text} \
  --expected_action {investigate|revise|pause-topic|acknowledge|...} \
  --summary "one-line intent"
```

**Fields:**
- `origin: human` — distinguishes from orchestrator-generated directives if those ever exist.
- `scope`: what this affects. `task` = current in-flight work item, `concern` = a specific concern_id, `phase` = current phase work, `session` = whole session. Scope informs how the worker incorporates the directive.
- `concern_id` (optional): if directive relates to an open concern.
- `path`: file with the directive body (like existing `concern` pattern — content in a file, metadata in the message). Let the human write freely; orchestrator writes the file.
- `expected_action`: hints to the worker what kind of response to produce.

**Operator flow:**

```
1. Human: "oracle, pause your current investigation, prioritize reading docs/architecture/scheduler-and-digests.md before continuing"
2. Human tells orchestrator (in-session chat or /xfleet directive command).
3. Orchestrator clarifies if needed, reformulates if intent is ambiguous, writes the directive text
   to ~/.claude/directives/oracle-{id}.md.
4. Orchestrator: send.sh orchestrator oracle --type directive --origin human --scope task
   --path ~/.claude/directives/oracle-{id}.md --expected_action investigate
   --summary "read scheduler-and-digests.md before continuing current task"
5. Orchestrator sets human_engaged (F-14) with scope=task or concern as appropriate.
6. Orchestrator logs the directive in _orchestrator.json:directive_log[].
7. Worker receives directive via always-on handler:
   - Reads the file at path.
   - Acknowledges with `directive-ack` (carries worker's interpretation + planned action).
   - Executes the directive (read doc, revise section, pause investigation, etc.).
8. Worker responds when the directive is completed with `directive-response` — carries the outcome
   (what was done, findings, or confirmation of pause).
9. Orchestrator marks the directive as closed in the log; may clear human_engaged depending on scope.
```

**Fan-out case:** if directive targets multiple workers (e.g., "all workers: treat F-5 of the PRD review as JUDGMENT resolved — human decided window is 7 days"), orchestrator writes one directive file and sends `directive` to each target worker individually. `directive_log` tracks fan-out as a group.

**Worker handler rules (always-on):**
- `directive`: investigate/revise/etc. per `expected_action`. Write findings/response to file, send `directive-response` back with `--path`.
- `directive-ack`: not a normal message for workers to receive; orchestrator-side only.

**What this fixes:**
- **F-15 round counter isn't contaminated.** `directive` doesn't increment `concern:{id}:rounds`, even when `--concern_id` is set. Directives are interleaved guidance, not negotiation rounds.
- **F-14 human_engaged auto-fires.** Orchestrator knows a human directive went out; sets the flag correctly. Auto-escalation pauses.
- **Audit trail is clean.** `_orchestrator.json:directive_log[]` captures the sequence — what human said, when, to whom, outcome. Debuggable.
- **Concerns stay pure.** `concern` goes back to meaning "worker raises an issue with peer, they negotiate via rounds" — no human injection muddying the round semantics.
- **Multi-worker broadcast is structured.** Fan-out is a protocol thing, not "human writes to each worker by hand."

**Fix directions (not yet implemented):**
- Add `directive` / `directive-ack` / `directive-response` to `~/.claude/xfleet/shared/messaging.md` message-type table + validator in `send.sh`.
- Extend `~/.claude/xfleet/shared/state-schema.md` for `_orchestrator.json:directive_log[]`.
- Add an always-on `directive` handler to worker base skill + phase-skill guidance on how to incorporate directives per scope.
- Add an orchestrator `/xfleet directive` command (or equivalent) for the human to request a directive be sent — orchestrator handles formulation, file write, dispatch, state.
- Auto-set `human_engaged` when a `directive` is sent (with scope-appropriate extent).
- Document the human-input flow in xfleet README — "talk to orchestrator, not workers directly; orchestrator will route your directives properly."

**Recommendation:** build it. Current `concern`-abuse pattern is a concrete contributor to F-14 (human_engaged never fires), F-15 (round counter polluted), and general orchestrator confusion about session state. Clean separation of `concern` (worker↔worker) and `directive` (human→worker via orchestrator) is a real improvement in both protocol clarity and operator ergonomics.

Related to F-14 (directives trigger human_engaged), F-15 (directives don't pollute round counter), F-17 (directive_log is part of the orchestrator audit trail; emission approval model may apply to directives that carry phase-level weight), F-9 (directive responses batch with normal worker results for the human to review).

### F-23. Orchestrator ad-hoc procedural checks shouldn't live in `concerns/` (2026-04-22) — RESOLVED via cluster 4e (F-51 Phase A taxonomy + Phase B `xfleet task`; internal-procedures rule)
Observed example: `~/.claude/concerns/orchestrator-pre-clean-pull-check.md`. This isn't a cross-worker negotiation (what `concern` is for) — it's an orchestrator-initiated procedural check (something like "verify state before `/cleanup`"). Filing it as a concern misuses the type and the directory:
- Bleeds into F-15's round-counter flow if `--concern_id` ever references it.
- Pollutes `concerns/` listings used to enumerate real open negotiations.
- Lacks a clear lifecycle (no raiser/responder semantics apply).

**The broader question — message/artifact type taxonomy:**

xfleet currently conflates several different workload shapes under `concern`:
- Worker↔worker negotiation (the original intent).
- Human→worker direction (F-22 proposes `directive`).
- Orchestrator→worker procedural assignment (this finding).
- Orchestrator-internal checklist/procedure (probably not a message at all).

**Proposed types after F-22 + F-23:**

| Type | Sender → Recipient | Semantics | Rounds apply? |
|---|---|---|---|
| `concern` | worker → worker | Cross-repo negotiation | Yes |
| `directive` | orchestrator (human-sourced) → worker(s) | Human intent relayed | No |
| `task` | orchestrator → worker | Procedural assignment, not negotiation | No |
| (internal) | orchestrator → self | Procedure tracked in skill state, not via message | — |

**Where should `orchestrator-pre-clean-pull-check` live?**

- **If it's an orchestrator-internal procedure** (orchestrator runs the check itself): belongs **in a skill**, not as a file in `concerns/`. Options:
  - Inline in the `/cleanup` skill's pre-flight section.
  - A dedicated `/pre-cleanup` skill that `/cleanup` invokes.
  - Skill-level state file at `~/.claude/state/orchestrator-checklist.md` if a persistent running checklist is warranted across sessions.

- **If the check involves asking workers to verify state** (e.g., "workers, before we cleanup, confirm your git status is clean"): belongs as a new `task` message type sent to each worker. Not `concern` (no negotiation), not `directive` (not human-sourced).

- **If it's a hybrid** (orchestrator does some, asks workers for others): split it — orchestrator runs its part in a skill, dispatches the worker part as `task` messages.

**Proposed `task` message shape:**
```
send.sh orchestrator {worker} \
  --type task \
  --task_id {unique_id} \
  --task_kind {git-status-check|state-verify|artifact-audit|...} \
  --path {file_with_task_description} \
  --summary "one-line purpose" \
  --expected_response {yes-no|status|findings|...}
```

Worker handles via an always-on `task` handler (similar shape to `question`/`concern`), responds with `task-response` carrying the result.

**Key properties:**
- No round counter — this isn't negotiation.
- No `human_engaged` auto-fire — orchestrator originated, not human.
- Has a `task_id` for orchestrator-side tracking (completion, timeout, retry).
- `task_kind` enumerated so orchestrator/worker can match handlers to expected task categories (prevents arbitrary orchestrator-to-worker dispatch from drifting into ad-hoc prose).

**Fix directions (not yet implemented):**

1. **Move `orchestrator-pre-clean-pull-check` specifically:** inspect the file contents, decide if it's orchestrator-internal (→ roll into a skill) or worker-facing (→ becomes a `task`). Clean up the mis-filed artifact.

2. **Add `task` + `task-response` to the message-type table** in `shared/messaging.md` + validator in `send.sh`.

3. **Document the taxonomy** somewhere durable (xfleet README or a new `shared/message-type-taxonomy.md`):
   - `concern` = peer negotiation, rounds matter.
   - `directive` = human intent via orchestrator, suppresses auto-escalation.
   - `task` = orchestrator procedural assignment to worker(s).
   - Internal orchestrator procedures = skill content + state files, never messages.

4. **Audit existing `concerns/*.md` files** for misuse: anything filed there that isn't actually a worker-raised cross-repo concern should be reclassified. Candidates likely include other orchestrator-originated checks hiding under the concern type.

**Recommendation:** #1 immediately (it's a single-file cleanup). #2+#3 together (taxonomy gets real as soon as `task` and `directive` types land). #4 is worth doing as part of the next cleanup round.

Related to F-22 (directive type — same class of "we need another message type for a distinct workload shape"), F-15 (round-counter pollution — if concerns end up carrying non-negotiation workload, INCR fires incorrectly), F-13 (completion detection — orchestrator shouldn't look at `concerns/` listings for procedural-check artifacts when gating phase completion), F-19 (global-state-coordination-vs-per-repo-durability split — orchestrator-internal procedures may generate artifacts that belong in workspace's durable tree rather than transient `~/.claude/` state).

### F-24. `finalize-spec` should be formally integrated across phases, extended for PRD building and post-implementation (2026-04-22) — RESOLVED via cluster 4l (multi-mode: qa-spec / repo-spec; phase-skill integration via `xfleet phase --complete`; post-impl mode deferred — section template only, populating manual; spec.md write authority orch-only)
Current `finalize-spec` skill is designed narrowly: "end of the spec phase of an xfleet session" per the skill frontmatter, prereqs are per-repo sections + resolutions, output is one canonical cross-repo spec. Today it runs as a separately-triggered `/finalize-spec` slash command, NOT codified as a step inside any phase skill.

Three gaps surfaced this session:

**1. Not integrated into repo-spec phase close.**
At the tail of repo-spec — after negotiation-complete, after all sections written, after reviewer findings addressed (F-21) — the authoritative cross-repo spec should be produced. Currently it's manual: human remembers to run `/finalize-spec` before advancing. Should be part of the phase skill's on-exit sequence, not an afterthought.

**Fix:** repo-spec phase skill (orchestrator side) gains an explicit Step N at close: "Invoke `/finalize-spec` (or the skill body inline). Block phase transition until it completes and writes the final spec." Worker phase-complete messages are already the signal that all sections are in — this step just codifies that the orchestrator runs finalize-spec before emitting the next phase signal.

**2. Observed usage in qa-spec to build the PRD.**
In the current session, `finalize-spec` was used during qa-spec — before any per-repo sections existed — to synthesize the cross-repo Technical PRD from whatever was available (worker answers, drafted sections, notes). This contradicts the skill's stated prereqs but worked in practice. The skill's core capability (synthesize N inputs + M decisions into one canonical document, with worker review + human approval) is genuinely useful at every synthesis point in the xfleet flow, not just at repo-spec close.

**Fix:** generalize `finalize-spec` to support multiple source configurations:
- **qa-spec mode**: inputs are whatever drafting artifacts exist (worker answers to questions, initial outlines, decision captures). Output is the cross-repo Technical PRD that then drives repo-spec. No strict prereq on `{repo}-section.md` files.
- **repo-spec mode** (today's default): inputs are per-repo sections + resolutions. Output is the authoritative cross-repo spec.
- **post-implementation mode** (see #3 below): inputs are the authoritative spec + implementation divergences + code review findings. Output is the updated spec.

Skill frontmatter and Parse Arguments should accept a `--mode` or infer from available artifacts. The Destination Path Validator stays (always reject `~/.claude/specs/` for final outputs, always require a durable repo location).

**3. Post-implementation section for capturing divergences.**
After implementation and code review, the implemented behavior sometimes diverges from the spec — bugs found during implementation, scope adjustments, deferred items, discovered edge cases. Today these live in PR descriptions, commit messages, or Linear — nowhere in the spec tree. The spec becomes stale; readers think "spec says X" when actually "implementation does Y because X was infeasible."

**Fix (two sub-options):**

A) **Add a `## Post-Implementation Resolution` section template to finalize-spec output.** When finalize-spec runs in repo-spec mode, it emits the canonical spec with an empty/placeholder `## Post-Implementation Resolution` section at the end. This gets populated during/after implementation — either manually or via a future `/update-spec-from-implementation` pass. The section structure:
```
## Post-Implementation Resolution

### Divergences
- {divergence-id}: what the spec said → what was implemented → why
  - Referenced PR: #...
  - Referenced review: {path}

### Deferred items
- {item}: reason, tracking link

### Discovered edge cases
- {case}: how implementation handles it
```

B) **Add a `post-implementation` mode to finalize-spec.** Separate invocation after implementation completes: reads the authoritative spec + implementation artifacts (PRs, reviews, commit history) + human-declared divergences, produces an updated spec with the Post-Implementation Resolution section filled in. More capable; requires the skill to understand implementation inputs.

**Recommendation:** A as MVP (placeholder section in every finalized spec), B as follow-on when post-implementation reconciliation becomes a regular workflow. A costs near-zero to add (one section in the template); B requires real skill design work.

**Phase-integration summary (after F-24 fixes land):**

| Phase | When finalize-spec runs | Inputs | Output |
|-------|------------------------|--------|--------|
| qa-spec close | As last step before transition to repo-spec | Drafting artifacts (worker answers, outlines, notes) | Cross-repo Technical PRD |
| repo-spec close | As last step before transition to plan | Per-repo sections + resolutions | Authoritative cross-repo spec (with empty Post-Implementation Resolution section) |
| post-implementation | Triggered manually or by workflow at merge-time | Spec + PRs + reviews + divergences | Updated spec with Post-Implementation Resolution filled in |

**Implementation notes (not yet done):**
- Update `finalize-spec` skill frontmatter + description to reflect the multi-mode capability.
- Add mode resolution logic (explicit flag, or infer from available artifacts, or defer to human).
- Extend Prerequisites section: different prereqs per mode.
- Update Step 2 (Draft Combined Spec) to include the Post-Implementation Resolution placeholder section (empty for first-time finalize, populated during post-implementation runs).
- Update repo-spec phase skill (orchestrator side) to invoke finalize-spec at close.
- Update qa-spec phase skill to invoke finalize-spec at close (for PRD synthesis) — separate from prd-review which reviews the finalized PRD.
- Document the three modes in xfleet README.

Related to F-18 (final spec output convention — same philosophy extended across phases), F-19 (per-repo sections durability — post-implementation adjustments should flow back to per-repo durable spec copies too), F-21 (reviewer findings must be resolved before phase close — finalize-spec at close is when this convergence lands), F-10 (phase-boundary handoffs — finalize-spec output is effectively the handoff artifact between phases).

### F-25. `_orchestrator.json` schema underspecified — drift between doc and usage (2026-04-22) — RESOLVED via cluster 4b (state schema discipline; tools route by purpose; tight schema + narrow opt-in scratch)
**Sub-findings (consolidated 2026-05-04):** F-52 (state ad-hoc growth across all worker state files — same pattern, broader surface; same fix vehicle).

`~/.claude/xfleet/shared/state-schema.md:54-70` defines `_orchestrator.json` with three fields: `cycles`, `last_all_idle_notify`, `last_round5_pause`. Writers/readers: orchestrator only.

**Observed drift (2026-04-22):** during repo-spec cross-review and human-review cycles, the orchestrator reads/writes additional state that isn't documented in the schema. Session-internal tracking — what signals have been emitted, which workers are pending reviewer-finding resolution, whether a human gate has been cleared, whether a directive is in flight — either gets written as ad-hoc undocumented fields or gets reconstructed on every check by re-reading other files (worker state, concern files, review files, resolution files). The result:
- Schema documentation doesn't match actual file contents. Future maintainers can't trust the schema to describe the file.
- Orchestrator recovery after `/compact` or session-restart is fragile — state that should survive persists only if it happens to hit `cycles`/`last_all_idle_notify`/`last_round5_pause`. Everything else gets recomputed, which is error-prone and doesn't handle race conditions (e.g., reviewer finding marked resolved between recovery passes).
- Workers have no way to know what's considered shared orchestrator state (even read-only) vs truly orchestrator-internal. The schema's "orchestrator only" contract is honored, but workers/humans debugging stalls can't tell what to inspect.

**What the schema should grow to include, based on current and proposed usage:** — **SUPERSEDED 2026-05-10 by Decisions Log entry "A1 — State-schema consolidation"**. The proposed shapes below are historical; the ratified field list (event log shapes, worker-side findings_status, derived `prepare_compact_at`, and `current_task` write rules) lives in the Decisions Log. Read the A1 entry for the current truth.

Fields already used ad-hoc (retroactive documentation):
- Whatever gets written during repo-spec cross-review cycles — needs audit of the actual orchestrator skill body.
- Any human-review-gate tracking that survives compaction.

Fields proposed by open findings (superseded — kept for historical record; see A1 Decisions Log entry):
- ~~**F-13**: `completion_conditions` — per-phase, tracks which signals have been received, which workers are pending, the current gate evaluation.~~ → A1 locks `completion_log[]` (event log) instead.
- **F-14**: `human_engaged` — `{active: bool, concern_id: string | null, set_at: ISO, reason: string}`. (matches A1)
- **F-17**: `phase_emissions` — per-phase-per-signal `{sent_at, sent_to, approved_by_human, emission_id}`; `emission_log[]` — audit of every emission with timestamps and approval state. (matches A1)
- ~~**F-21**: `review_findings` — per-worker `{findings_path, blocking_count, resolved_count, waived_count, last_revised_at}`.~~ → A1 locks worker-side `review_revision_count` + `findings_status: {finding_id: state}` instead (orch never sees content; reviewer perfectionism contained per 4a's alert-only invariant).
- **F-22**: `directive_log[]` — every directive emitted, with origin, scope, concern_id, expected_action, response status. (matches A1)
- **F-23**: `task_log[]` — every orchestrator-assigned task, with task_id, task_kind, target, response status. (matches A1)

**Fix directions (not yet implemented):**

1. **Audit current orchestrator skill body** for every ad-hoc field it writes to `_orchestrator.json`. List them. Retroactively document in state-schema.md with descriptions and lifecycle.

2. **Update state-schema.md in lockstep with F-13/F-14/F-17/F-21/F-22/F-23 implementations.** Any finding that adds orchestrator-side state MUST come with a schema doc update in the same change. Treat the schema file as a hard contract.

3. **Validator tool.** Optional `tools/xfleet/validate-state.sh` that reads `_orchestrator.json` and compares against the documented schema, flags extra/missing fields. Run in `/cleanup` pre-flight and as part of session start to catch drift early.

4. **Migration notes.** When fields change shape (e.g., `cycles` becomes `cycles_by_phase`, or `last_round5_pause` gets absorbed into a broader `escalations` map), add migration guidance to the schema doc — one-time transforms that existing session state files need to survive.

**Recommendation:** #1 immediately — audit + retroactively document what's currently written. #2 as ongoing discipline — bundle schema updates with each finding's implementation. #3 is worth doing before the schema grows significantly; catches drift as soon as it happens. #4 as-needed.

Related to essentially every orchestrator-side finding (F-13, F-14, F-17, F-21, F-22, F-23) — this is the cross-cutting documentation layer they all need to update. Related to F-4 (session-resume) and F-8 (zombie listeners) indirectly: well-documented state is easier to reason about during recovery flows.

### F-26. Init-vs-clean section model — keep the qa-spec initial distribution as an immutable historical artifact (2026-04-22) — RESOLVED via cluster 4c (sub of F-19; renamed to `section-v0.md` for naming consistency with `section-vN.md` snapshots)
**Sub-finding of F-19 (consolidated 2026-05-04).** Refines F-19's per-repo session-bundle layout with explicit immutable-init + evolving-clean artifact split.

> **Rename note (2026-05-04, cluster 4c):** the immutable seed file was renamed from `section-init.md` to `section-v0.md` for naming consistency with the `section-vN.md` snapshot scheme (cluster 4c Decisions Log). Body text below uses the new name; semantics unchanged — v0 is still the immutable spec-distribution seed, still written at qa-spec close, still never modified by the worker.

During qa-spec close, `finalize-spec` (in qa-spec mode per F-24) produces the cross-repo Technical PRD. Each worker then gets an **initial per-repo section** — their slice of the PRD as distributed. During repo-spec, workers negotiate + refine, and during the review loop (F-21) they revise further based on reviewer findings. At phase close, they produce the **clean final section** (F-19's clean artifact).

**The question that surfaced:** when revisions happen during review, update the init file, the clean file, or both?

**Recommendation: two immutable-boundary artifacts.**

- **`section-v0.md`** — snapshot of the repo's section **as distributed from qa-spec**. Immutable after qa-spec close. Never updated during repo-spec or review cycles. Preserves "what were we originally asked to do?"

- **`section.md`** — the clean current authoritative section. Evolves through repo-spec negotiation → reviewer-findings loop (F-21) → phase close. At every gate, this is the one that reflects current agreement. Plan phase reads this.

- **History bundle** (F-19): `concerns.md`, `reviews.md`, `alignment.md` — the negotiation + review trail that connects init to clean.

**Layout per session** (extending F-19's bundle model):
```
{repo}/docs/superpowers/xfleet/{slug}/      # renamed by cluster 4c (2026-05-04) — was specs/sessions/{YYYY-MM-DD}-{slug}/
  README.md             # session metadata, participants, links
  section-v0.md       # qa-spec output, frozen
  section.md            # current authoritative (the one plan reads)
  concerns.md           # negotiation history
  reviews.md            # reviewer findings + resolutions
  alignment.md          # alignment-phase adjustments (if any)
```

**Why keep init immutable:**

1. **Diff tells the story.** `diff section-v0.md section.md` shows exactly what negotiation + review changed. Auditable, inspectable. Readers can ask "what did the PRD propose for this repo vs what we landed on?"
2. **Debugging scope creep.** If `section.md` grows far beyond `section-v0.md`, that's a signal — may have drifted from original intent. The immutable init is the reference point.
3. **Prevents "which file is current?" confusion** (the user's worry). Init is explicitly frozen; clean is explicitly current. No ambiguity about which to read for the authoritative spec.
4. **Plan phase input is unambiguous.** Plan always reads `section.md`. If init stayed mutable and lagged, plan might accidentally read the stale one.

**Update policy during review cycle:**

- Reviewer surfaces a finding → worker revises `section.md` (not `section-v0.md`).
- Revision might move content around, add/remove items, clarify language — all in `section.md`.
- `section-v0.md` stays byte-identical to what was distributed at qa-spec close. Only re-written if qa-spec is re-run (which would be a new session or a re-finalize).
- `reviews.md` in the history bundle logs what finding prompted what revision (cross-reference F-21's triage).

**What about mid-session "re-distribute" scenarios?**

If during repo-spec the human decides the PRD itself was wrong and re-runs qa-spec → new PRD → new distribution:
- That's effectively a new repo-spec round. Options:
  - (a) Move the current session dir to `{YYYY-MM-DD}-{slug}-v1/`, start a fresh `{YYYY-MM-DD}-{slug}-v2/` with a new `section-v0.md`. Explicit versioning.
  - (b) Append `section-init-v2.md` alongside `section-v0.md`. Preserves both frozen snapshots in one session. Less disruptive.
  - (c) Don't support this in-session; force a new session with a new slug. Cleanest protocol; uglier UX.

Recommend (a) as the natural pattern — session dirs are already dated, adding a version suffix is cheap and preserves full history.

**Fix directions (not yet implemented):**

1. **Write `section-v0.md` at qa-spec close.** When `finalize-spec` runs in qa-spec mode (F-24), it writes the PRD to workspace durable tree AND distributes per-repo slices as `{repo}/docs/superpowers/xfleet/{slug}/section-v0.md` (path renamed by cluster 4c, 2026-05-04 — was `specs/sessions/{YYYY-MM-DD}-{slug}/`) in each worker's repo. Immutable thereafter.

2. **Repo-spec writes `section.md` separately from `section-v0.md`.** Initial `section.md` on repo-spec entry is a copy of `section-v0.md`. All revisions during negotiation and review go to `section.md`. `section-v0.md` is never touched again during the session.

3. **Enforce immutability via skill guidance.** Worker phase skills state explicitly: "Never modify `section-v0.md` after qa-spec. All work happens in `section.md`."

4. **Optional: add a frontmatter marker.** `section-v0.md` gets `status: frozen, source: qa-spec, frozen_at: <ISO>` to make its immutability self-documenting. `section.md` gets `status: current, derived_from: ../section-v0.md`.

5. **Plan phase reads `section.md` only.** Explicit in plan-phase skill; the init file is not a plan input.

**Recommendation:** land together with F-19 (per-repo durability) and F-24 (finalize-spec multi-mode). The init-vs-clean distinction costs one additional file write (at qa-spec close) and pays off in every subsequent diff / debug / audit.

Related to F-19 (repo-local durability — init belongs durably alongside clean and history), F-21 (review cycles write to `section.md`, logged in `reviews.md`), F-24 (qa-spec mode of finalize-spec is what produces and distributes init), F-18 (final-spec naming convention — applies here: `section-v0.md` vs `section.md` is the repo-level analog of `spec-draft.md` vs `spec-final.md`).

### F-27. Worker-side `finalize-section` skill + versioned outputs from `finalize-spec` (2026-04-22) — RESOLVED via cluster 4c (sub of F-19; `/finalize-section` produces `section-vN.md` snapshots via Model A snapshot-after-revise)
**Sub-finding of F-19 (consolidated 2026-05-04).** Worker-side discipline that produces F-19's per-repo durable artifacts cleanly (with content hygiene); the versioning piece extends F-19's session-bundle layout across re-finalizations.

> **Rename note (2026-05-04, cluster 4c):** wave-1 paths used in this body (`~/.claude/specs/{NAME}-section.md`, `~/.claude/reviews/{NAME}-*.md`) are SUPERSEDED. New paths per cluster 4c: section work lives at `{repo}/docs/superpowers/xfleet/{slug}/section.md` (current) + `section-vN.md` (snapshots); reviews at `{repo}/docs/superpowers/xfleet/{slug}/reviews/` (transient, wiped at `/cleanup --final` per cleanup-model revision 2026-05-10). Body text below is preserved as historical record; semantics of the fix are unchanged, only the storage paths.

Two tightly-related gaps:

**Part A — Worker-side counterpart to `finalize-spec`.**

`finalize-spec` is orchestrator-side — merges N per-repo sections + M resolutions into one cross-repo canonical spec. Workers currently produce their clean section inline via the repo-spec phase-skill step ("write finalized section to `~/.claude/specs/{NAME}-section.md`") with no structured skill guiding the synthesis. This means:
- No enforcement of content hygiene (F-19: clean section shouldn't inline concern/resolution history).
- No explicit synthesis step — worker just writes "the final version" without a discipline for incorporating reviewer findings, resolving contradictions with peer agreements, or aligning terminology.
- No place to capture the "what changed since init" diff explicitly (F-26).
- No uniform output format — each worker might structure their section differently.

**Proposed: `/finalize-section` skill for workers.**

Worker-side counterpart to `/finalize-spec`. Invoked at repo-spec phase close, **before** sending `phase-complete`.

**Inputs:**
- `section-v0.md` (frozen qa-spec distribution per F-26).
- Current working `section.md` (evolved through negotiation + review).
- This worker's review findings from `~/.claude/reviews/{NAME}-*.md` (or repo-local equivalent per F-19).
- This worker's concerns/responses related to this section (from concern files and resolutions).
- Relevant cross-repo resolutions affecting this worker's section.

**Output:** updated `section.md` (content-hygiene-compliant per F-19 + F-26) — clean forward-looking spec, no inlined negotiation history.

**Skill steps:**
1. **Inventory** — list init, current working, reviews, concerns, resolutions.
2. **Synthesize** — produce the clean final section. Resolve terminology, align with cross-repo resolutions, address each reviewer finding (resolve in content or explicitly defer/waive with justification).
3. **Content hygiene check** — no concern text, no resolution prose, no reviewer-findings discussion inlined. Forward-looking voice only (see F-19).
4. **Diff against init** — compute and log `diff section-v0.md section.md` summary. Surface to human at gate so they can sanity-check scope.
5. **Human/reviewer re-check loop** (F-21) — if blocking findings remain unaddressed, don't exit the skill; iterate.
6. **Write** — update `section.md` in the session dir (per F-26 layout). Write a brief `changelog.md` or append to `reviews.md` noting what this finalization pass changed.
7. **Report** — summary to orchestrator: path, diff summary, findings-status.

**Symmetry with `finalize-spec`:** same general shape (inventory → synthesize → review → approve → write), different scope (per-repo vs cross-repo). Share conventions (Destination Path Validator, Rationalizations-to-Reject table).

**Part B — `finalize-spec` (and `finalize-section`) should write a new file each time, not overwrite.**

Currently `finalize-spec` defaults to `~/workspace/docs/superpowers/specs/{YYYY-MM-DD}-{slug}.md`. If the flow re-runs (because repo-spec reopened, or post-implementation reconciliation fires per F-24), the prior finalized version is overwritten. Lose history, lose the ability to diff "what did finalize-spec produce at timepoint T1 vs T2."

**Fix:** every finalize-spec run produces a distinct file; prior versions preserved.

**Naming options:**

1. **Sequential version suffix.** `{slug}-v1.md`, `{slug}-v2.md`, `{slug}-v3.md`. Simple, readable. Optional `{slug}-latest.md` symlink for downstream convenience.
2. **Timestamp suffix.** `{slug}-2026-04-22T14-30Z.md`. Total-ordering built in. Uglier filenames.
3. **Versioned subdirectory.** `specs/{slug}/v1.md`, `specs/{slug}/v2.md`, `specs/{slug}/latest.md`. Groups versions together. One level deeper in the tree.

**Recommendation:** #1 (sequential `-vN.md`) for finalize-spec cross-repo output. #1 or #3 for finalize-section per-worker output (#3 aligns with F-26's session-dir model — versioned `section-v1.md`, `section-v2.md` inside the session dir is natural; or even just git commits to `section.md` within the session dir if the session dir is under repo git).

**What triggers a new version:**
- Explicit re-run of `finalize-spec` or `finalize-section` (user or orchestrator-initiated).
- Any substantive change after initial finalization — post-implementation reconciliation (F-24 mode), human reopen (F-14 + F-17), iteration after discovered spec gap.
- Minor fixes (typos, formatting) can either produce a new version or edit-in-place — skill should prompt: "is this change substantive enough to version? [yes / in-place]".

**Latest pointer:**
- `{slug}-latest.md` — symlink to the most recent version. Downstream consumers (plan phase, reviewer agents, humans looking up "what's current?") read `-latest.md` to always get the authoritative version without knowing the version number.
- On each new finalize run: write `{slug}-vN.md`, update `{slug}-latest.md` symlink.

**Changelog:**
- `{slug}-changelog.md` sibling file logs every version with a one-line summary of what changed and why. Built cumulatively, not overwritten.

**Fix directions (not yet implemented):**

1. **Build `/finalize-section` skill.** Worker-side counterpart to `/finalize-spec`. Same shape, repo-local scope. Invoked inline in repo-spec phase skill at close (after reviewer findings resolved per F-21).

2. **Change `finalize-spec` output naming.** Sequential `-vN` suffix, `-latest` symlink, `-changelog` sibling. Skill's Step 5 (Write Final Spec) gains "determine next version number" pre-step.

3. **Apply same versioning to `/finalize-section` output.** Per-session directory already gives date-level grouping (F-26); within it, version the `section.md` as `section-v1.md`, `section-v2.md`, with `section.md` as the latest-pointer name (or symlink).

4. **Update downstream consumers.**
   - Plan phase reads `{slug}-latest.md` for cross-repo spec, `section.md` (latest) per repo.
   - `/cleanup` preserves all `-vN.md` files (don't glob-match them for deletion; only clean if explicit `--all-versions` flag).
   - Reviewer agents read latest version by default; older versions available for diff-based review.

5. **Migration**: existing single-file finalized specs stay — treat as implicit v1. On next finalize, they become the v1 and new output is v2.

**Recommendation:** #1 + #2 together. #3 extends the model to worker output. #4 is the ecosystem update. #5 is low-cost (no action needed, just grandfathered).

Related to F-18 (final spec output naming — this is the time-versioned extension of that), F-19 (repo-local session dirs host `section-vN.md` files naturally), F-21 (review cycles produce new section versions), F-24 (multi-mode finalize-spec — each mode invocation produces its own versioned output), F-26 (init-vs-clean — init is v0 in a sense, immutable; clean evolves as v1, v2, ...).

### F-28. `prd-review` re-raises issues already decided during repo-spec (2026-04-22) — RESOLVED via cluster 4l (`## Decisions Log` section in spec with forward-looking voice; prd-review skill reads Decisions Log + prior findings, injects as dim-agent context; dim agents skip resolved items unless strong new evidence)
Observed: after `finalize-spec` produces the finalized cross-repo spec post-repo-spec, running `prd-review` on that final spec surfaces the same findings that were already raised as concerns, negotiated, and resolved during repo-spec. Reviewers have no memory of prior decisions.

**Root cause — tension between two good principles:**

1. **F-19 content hygiene**: finalized specs don't inline concern/resolution history. The clean spec reads forward-looking.
2. **Reviewer context**: prd-review dim agents need to know "this was already debated and settled" to avoid re-raising.

Result: clean spec hides the decision trail; reviewers can't see what's already resolved; they re-flag every concern that resolution records quietly settled. Human has to re-triage the same issues every review pass. Signal-to-noise collapses.

**Fix directions (not yet implemented):**

1. **Decisions section in finalized specs.** Clean spec retains an explicit `## Decisions Log` (or `## Resolved Concerns`) section near the end. Forward-looking voice still (no back-and-forth negotiation prose), but each entry records an outcome:
   ```
   ### D-1: Retry semantics for cross-service calls
   **Decision:** Use exponential backoff with jitter, max 3 retries.
   **Rationale:** Peer services return 503 during rolling deploys; aggressive retry amplifies load.
   **Resolved in:** repo-spec round 3 (see resolutions/C-7.md for full discussion)
   ```
   Not history — decisions. Sister to ADRs in the project tree, lighter-weight. Preserves the "what's settled" signal in the spec itself. Reviewers (and plan phase, and future readers) see decision outcomes without having to read negotiation archives.

2. **Pass prior decisions context to dim agents.** `prd-review` skill reads `resolutions/*.md` + latest `prd-review-{slug}-*.md` findings file + the finalized spec's `## Decisions Log` section, and passes a "prior decisions" context block to each dim agent. Dim agents are instructed: "If a finding was already raised and resolved (appears in prior decisions), do not re-raise — either skip or reference the prior decision explicitly."

3. **Review waive-list.** Structured list maintained in `_orchestrator.json` (per F-25 schema extension) or in a dedicated `reviews/{slug}-waived.md` file: concerns that were raised in review and explicitly waived (human said "noted, not changing"). Dim agents consult this on each pass. Complements #2 — resolutions cover "settled by agreement," waived-list covers "acknowledged but not acted on."

4. **Dim agents read prior prd-review files.** Each dim agent's prompt includes: "Read the most recent prior findings file for this spec at `~/workspace/docs/superpowers/reviews/prd-review-{slug}-*.md`. For any finding there with human decision (JUDGMENT resolved/rejected/waived), do not re-raise without strong new evidence."

5. **Finding-ID continuity across reviews.** When a finding recurs legitimately (e.g., the spec changed and the prior issue resurfaced in a new form), re-use the prior F-N ID with a version suffix: `F-3-v2`. Makes the "this came back" signal explicit. Keep `F-3-v1` cross-linked.

**Recommendation:**
- **#1 (Decisions Log) is the core fix.** Both principles hold — clean spec stays forward-looking, but decisions are explicit and visible. Reviewers, plan phase, future readers, auditors all benefit. Lightweight content addition, high ROI.
- **#2 complements it** — explicitly pass prior decisions as dim agent input. Skill-level change, not agent-level, so retrofit is easy.
- **#4** as a defense-in-depth pass for when #1+#2 miss something.
- **#3** is worth having for the explicit-waive case.
- **#5** is nice-to-have; adds traceability but only matters if recurring findings become a pattern.

**What the Decisions Log is NOT:**
- Not the history bundle (F-19) — that stays separate and has the full negotiation prose, reviews, alignment, etc. The Decisions Log is a summary, not the archive.
- Not ADRs in `docs/superpowers/adr/` — those are for cross-project irreversible decisions. The Decisions Log is per-spec, session-scoped, lightweight.
- Not a concern list — concerns are pending negotiation artifacts. Decisions are resolved outcomes.

**Content-voice rule (extends F-19):**
- History bundle: backward-looking narrative ("we debated... eventually agreed...").
- Decisions Log: forward-looking statement with lightweight rationale ("use X with Y. Because Z.").
- Spec body proper: forward-looking design only, no rationale clutter.

**Implementation notes (not yet done):**
- Update `finalize-spec` skill to include a `## Decisions Log` section template in Step 2 (Draft Combined Spec). Populate from `~/.claude/resolutions/*.md` — summarize each resolution as one entry, forward-looking voice.
- Update `/finalize-section` (F-27) to include a `### Local Decisions` subsection in each worker's section listing decisions specific to that repo.
- Update `prd-review` skill Parse Arguments / Step 2 to read prior decisions + prior findings files and stamp them into the dim agents' prompts.
- Update dim agent prompts to explicitly check against the prior-decisions block before emitting findings.
- Document the content-voice rule in the xfleet README's spec-authoring section.

Related to F-19 (content hygiene — decisions are part of spec content; history stays in bundle), F-21 (reviewer findings — Decisions Log is the artifact that settles findings across review cycles), F-24 (finalize-spec generates the Decisions Log), F-26 (init vs clean — Decisions Log is populated in clean, absent from init), F-27 (per-repo finalize-section also gets a Local Decisions subsection), F-14 (human_engaged — human-approved decisions go in the log explicitly).

### F-29. Plan phase needs the same cross-repo negotiation + review-loop discipline as repo-spec (2026-04-22) — RESOLVED (cluster 3, 2026-05-04)
**Sub-findings (consolidated 2026-05-04):** F-31 (revisions integrated cleanly + re-reviewed before re-emission) and F-39 (plan folds must enumerate full pending scope upfront) — specific sub-rules of F-29's plan-phase discipline umbrella.

Current plan-phase flow (from `~/.claude/xfleet/phases/plan.md`):
```
1. Read approved spec section from ~/.claude/specs/{NAME}-section.md
2. Write implementation plan to ~/.claude/plans/{NAME}-plan.md (use superpowers writing-plans skill)
3. Send --type phase-complete --phase plan --path ~/.claude/plans/{NAME}-plan.md --summary "..."
```

Three gaps vs repo-spec's richer protocol:

1. **No structured cross-repo negotiation.** Plans often contain open questions that depend on peer repos' decisions — cross-repo contract details that weren't nailed down in the spec (ordering of deploys, shared library versions, API schema nuances). Today a worker writes the plan with these marked as "open" (often tagged as bucket C / [xrepo] items) and phase-completes — but there's no protocol for raising these as concerns to peers, negotiating rounds, and recording resolutions the way repo-spec does.

2. **No plan-reviewer agents.** repo-spec runs reviewer agents from `worker-config.md` to surface issues before phase-complete (F-21). Plan phase skips this entirely — workers phase-complete their plans without adversarial review. Plans go to implement with no quality gate beyond the author's own judgment.

3. **No re-send-phase-complete-after-resolution loop.** If a worker's plan needs cross-repo clarification, there's no mechanism today to negotiate, revise, and re-emit phase-complete with the updated plan. Phase-complete is currently single-shot.

**Proposed plan-phase flow (extending current):**

```
On phase=plan signal:
  1. Read approved spec section.
  2. Draft implementation plan (superpowers writing-plans skill).
  3. Identify open cross-repo items (bucket C / [xrepo] tagged) — anything requiring peer alignment.
  4. Send initial phase-complete --phase plan --path --summary with open-items count surfaced.

On orchestrator xrepo-negotiation signal (issued when ≥1 worker's plan has open xrepo items):
  5. For each [xrepo] item in plan, raise as concern to the relevant peer(s) using the concern
     protocol (same as repo-spec): concern → response → counter → resolution.
  6. Orchestrator nudges at round 2/3, applies round-5 hard-stop per F-15's corrected counter.
  7. Once all [xrepo] items resolved, update plan file to reflect decisions (clean voice —
     forward-looking, reference resolutions in a per-plan Decisions Log per F-28).

After cross-repo resolution:
  8. Run plan-reviewer agents from worker-config.md.
  9. Write findings to ~/.claude/reviews/{NAME}-plan-final.md (or repo-local path per F-19).
 10. Apply F-21 discipline: blocking findings must be resolved before re-emitting phase-complete.
 11. Send fresh phase-complete --phase plan --path (updated plan) --summary (updated)
     indicating readiness.

Orchestrator collects all workers' fresh phase-completes:
 12. Completion check: all workers phase-complete + all xrepo concerns resolved + all plan-review
     findings addressed (blocking) or waived (with approval).
 13. Emit `ready-for-human` gate signal — orchestrator surfaces per-worker plan summaries +
     resolutions + review findings (batched per F-9) to human.
 14. Human approves → orchestrator sends phase=implement to each worker (per F-17 human_approved).
 15. Human rejects / reopens → targeted concerns / directives (F-22) back to affected workers,
     loop back to step 5.
```

**User's articulation (verbatim from 2026-04-22):**
> 1. Signal all 3 workers: "Cross-repo open questions in your plans (bucket C [xrepo] items) — raise concerns to peers per the concern protocol, negotiate to resolution, ack when settled. Then run plan reviewer agents per your worker-config.md, write findings to `~/.claude/reviews/{NAME}-plan-final.md`, send fresh phase-complete --phase plan with updated path/summary."
> 2. Workers do peer-to-peer concern rounds for F-26/27/29/30/49/75 (same protocol as repo-spec; orchestrator nudges at round 2/3, hard-stops at 5).
> 3. Workers run their plan-reviewer agents.
> 4. Each worker re-sends phase-complete when both done.
> 5. Then human approval gate → dispatch phase implement.

**Cross-repo item format convention:**

Workers mark xrepo items in their plans with an explicit tag so the orchestrator can scan and surface them:

```markdown
## Bucket C: Cross-Repo Dependencies [xrepo]

### [xrepo:F-29] API contract for POST /v2/webhooks — schema ownership
Target peer: server
Question: does the server already have a schema for webhook events, or does this plan
need to propose one?
Impact: blocking — cannot finalize retry-handler design without schema shape.
```

Orchestrator regex-greps plan files for `[xrepo:<id>]` markers to enumerate open items.

**Reviewer agents for plan phase:**

Per-repo `worker-config.md` should declare `plan_reviewers:` alongside existing `reviewers:` (the spec-phase reviewers). Examples:
- Code-quality plan reviewer: checks plan for concrete steps, testability, rollback mention.
- Risk plan reviewer: flags irreversible steps missing rollback, missing observability hooks.
- Architectural plan reviewer: confirms plan aligns with cross-repo agreements from Decisions Log.

Reviewer findings carry LOOKUP/PATTERN/JUDGMENT triage tags (F-20 unified intensity + triage contract).

**Fix directions (not yet implemented):**

1. **Extend `plan.md` phase skill** to include xrepo-negotiation + reviewer-loop + re-send phase-complete protocol. Add handler table entries for concern/response/resolution (same as repo-spec's pattern) + a "ready-for-review" internal state.

2. **Add `plan_reviewers:` to `worker-config.md` schema.** Document in xfleet README. Default list if unspecified: some minimal plan-quality reviewer.

3. **Update orchestrator's plan-phase handling** to:
   - Detect open [xrepo:N] items across worker plans at initial phase-complete.
   - Emit xrepo-negotiation signal when open items exist.
   - Track completion across all workers' re-sent phase-completes + reviewer-findings status.
   - Gate plan → implement on human approval (F-14 / F-17 discipline).

4. **Standardize [xrepo:ID] tagging** in `writing-plans` skill guidance — anything requiring peer alignment MUST be tagged for orchestrator discovery.

5. **Apply F-19 content hygiene + F-28 Decisions Log** to plans too. Clean plan in final state has a per-plan Decisions Log section listing xrepo decisions that shaped it.

6. **Worker-side `/finalize-plan` skill** (analog to F-27's `/finalize-section`). Synthesizes plan, reviewer findings, xrepo resolutions into clean final plan. Versioned output (F-27).

**Recommendation:** land together with F-14 (human gate), F-17 (emission approval), F-21 (reviewer findings blocking), F-27 (finalize-section/plan + versioned outputs), F-28 (Decisions Log). The plan phase becomes structurally symmetric with repo-spec, which means operators learn one discipline and apply it in both phases — less cognitive overhead.

Related to every "phase discipline" finding (F-13 completion, F-14 human gate, F-17 emission approval, F-21 reviewer findings block, F-19 repo-local durability, F-26 init-vs-clean, F-27 finalize-section + versioning, F-28 Decisions Log) — this finding asserts that plan phase needs the same treatment repo-spec is getting. Also related to F-15 (round-counter correctness is needed for plan-phase concern rounds to escalate correctly), F-22 (directive type lets human steer ongoing plan negotiation cleanly), F-9 (batching — human gate's per-worker plan summaries benefit from the batched presentation).

### F-30. Authority hierarchy — orchestrator speaks for human; workers must not second-guess (2026-04-22) — RESOLVED via cluster 4g (`xfleet question` target validator + `xfleet escalation` subcommand + skill-text discipline; no slack-channel hooks; F-58 sets the principle)
Observed: workers sometimes stop mid-phase to ask the human directly for confirmation on something the orchestrator has already directed — even when the orchestrator's message was itself a relay of a human directive. This breaks the delegation model:
- Human → orchestrator → worker is the intended command path.
- Workers treating "human" and "orchestrator" as two separate authorities, or hedging by asking "are you sure?" on every orchestrator instruction, creates round-trip friction and undermines the orchestrator's role.
- The human's time is wasted re-confirming what they already said once to the orchestrator.

**The principle to encode:**

**The orchestrator speaks for the human.** Directives (F-22), tasks (F-23), phase signals, and resolutions relayed by the orchestrator ARE authoritative instructions. Workers execute them; they do not route around the orchestrator to re-confirm with the human.

**Fix directions (not yet implemented):**

1. **Strengthen worker skill conduct rules.** Add an explicit section to `~/.claude/skills/worker/SKILL.md`:
   ```
   ## Authority Hierarchy
   
   The orchestrator relays the human's intent. When you receive a directive,
   task, phase signal, resolution, or concern relay from the orchestrator,
   treat it as authoritative — execute it per the phase instructions. Do NOT
   stop mid-execution to ask the human for re-confirmation.
   
   If the instruction is ambiguous or appears to conflict with phase
   instructions, send a `question` back to the orchestrator (not directly to
   the human). Orchestrator decides whether to surface to human or clarify
   from session context. This preserves the delegation path and avoids
   bypassing orchestrator-side bookkeeping (human_engaged, directive_log,
   emission_log).
   
   The ONLY exception: peer-to-peer mode, where no orchestrator is present
   (~/.claude/state/_session.json missing or `_orchestrator.json` absent).
   In that mode, workers may interact with the human directly.
   ```

2. **Phase instructions codify the authority hierarchy.** Every phase skill (repo-spec, plan, implement, cross-review, alignment) has an "On receiving orchestrator message" section that reinforces: execute, don't reconfirm.

3. **Orchestrator stamps directives with authority markers.** When relaying a human-sourced directive (F-22's `--origin human`), orchestrator can optionally include a `--confidence` or `--authority-level` indicator:
   - `definitive` — human was explicit; do not question.
   - `inferred` — orchestrator interpreted human intent; worker may route a question if unclear.
   
   Default `definitive`. Workers seeing `inferred` may send clarifying `question` messages. Workers seeing `definitive` execute without reconfirmation.

4. **Formal question-routing discipline.** Workers explicitly forbidden from invoking `mcp__plugin_slack-channel_*` or any other direct-to-human channel during active xfleet sessions. All human-facing questions flow `worker → orchestrator → (orchestrator decides) → human or clarification response`. Enforce via the Rationalizations-to-Reject table in `worker/SKILL.md`.

5. **Orchestrator-side question-handling.** When worker sends `question` with no `--directed_at` field or with `--directed_at orchestrator`, orchestrator's handler:
   - First: can I answer from session context (spec, decisions, prior resolutions, F-28's Decisions Log)? If yes, answer directly.
   - Second: is this a clarification on an existing directive? Check `directive_log`. Re-relay the directive with clarification.
   - Third: if genuinely requires human input, surface to human via Slack/terminal, batch with any other pending items per F-9.
   
   Worker is blocked on the question until orchestrator responds. Orchestrator's throughput on questions determines worker forward progress.

6. **Audit indicator.** Add to `_orchestrator.json:directive_log[]`: `reconfirmation_requests[]` — how many times has a worker asked to re-confirm this directive. Signal of either ambiguous directives (orchestrator should phrase more clearly) or worker conduct drift. Human can review periodically.

**Phrasing to make sticky in worker skills (candidate language):**

> "When the orchestrator tells you to do something, it has already consulted the human (explicitly or as part of session context). You do not need to verify. Execute."
> "If you catch yourself thinking 'should I double-check with the human?' — the answer is no, ask the orchestrator."
> "Asking the human directly is a protocol violation in orchestrated mode. It bypasses tracking, duplicates effort, and trains future sessions to distrust the delegation."

**Why this matters beyond ergonomics:**
- Orchestrator-side tracking (F-14 human_engaged, F-17 emission_log, F-22 directive_log) assumes messages flow through it. Direct worker-to-human bypass breaks those audit trails.
- Batch surfacing (F-9) assumes orchestrator is the funnel. Direct questions fragment the human's attention.
- Trust: if workers second-guess, the human stops relying on the orchestrator as a faithful proxy. The whole system becomes flatter and noisier.

**Recommendation:** #1 (strengthen worker skill rules) + #2 (phase skill reinforcement) as the immediate fix — costs nothing, cultural. #4 (forbid direct-to-human channels) is the hard stop that makes the rule enforceable. #3 (authority-level marker) adds nuance for genuinely ambiguous cases. #5 (orchestrator question-handling) is the tool that makes route-through-orchestrator viable — workers have somewhere to go with their real questions. #6 (audit indicator) catches drift.

Related to F-22 (directive is the authoritative relay type — this finding is about how workers receive/obey it), F-14 (human_engaged assumes orchestrator is the signal source), F-17 (emission_log assumes orchestrator gates all phase-level signals), F-9 (batching presumes orchestrator is the funnel to human), F-23 (task messages are part of the authority hierarchy — orchestrator → worker procedural assignments).

### F-31. Plan-phase revisions must be integrated cleanly AND re-reviewed (2026-04-22) — RESOLVED via cluster 3 (sub of F-29; plan-phase symmetric with repo-spec discipline)
**Sub-finding of F-29 (consolidated 2026-05-04).** Also a plan-phase application of F-21's review-blocks-completion rule.

Refinement of F-29 + F-21 when applied to plan phase. Two discipline points that need to be explicit:

**1. Revisions are fully integrated into the plan, not bolted on.**

When a reviewer raises a finding and the worker addresses it, the plan must be **revised properly** — the changed step, new step, or corrected assumption lives in the plan body as if it had always been there. It does NOT appear as:
- A "Reviewer Notes" appendix (violates F-19 content hygiene).
- Inline prose explaining "I'm changing X because reviewer said Y" (belongs in the log, not the plan).
- A bolted-on "Corrections" section (signals the plan is unfinalized — if it's finalized, the correction is the plan now).

Forward-looking voice rule extends to plan revisions: the plan reads as the authoritative execution reference, not as a diffed-up patchwork.

**What changed + why goes in the plan's Decisions Log section (F-28)** as a new entry:
```
### D-N: Adjusted rollback step sequence
**Decision:** Roll back database migration before blob-store cleanup (swapped order from initial draft).
**Rationale:** Reviewer flagged that blob-store cleanup is not atomic — partial-state recovery requires DB to be in pre-migration state first.
**Logged against:** F-R-3 (plan-reviewer finding), resolved 2026-04-22.
```

**2. Revised plans must be re-reviewed before phase-complete re-send.**

F-21 establishes the review loop for repo-spec:
- LOOKUP/PATTERN findings → worker revises → re-runs reviewer → iterates until no blocking findings remain.
- Convergence counter caps the loop (e.g., 3 passes) to prevent infinite iteration.

F-29 extends this to plan phase. This finding sharpens: **re-review is not optional.** A worker that addresses findings and emits phase-complete WITHOUT re-running its plan-reviewer agents has not completed the loop. The worker's own judgment is not sufficient — the point of reviewers is adversarial review. Self-review by the author always under-detects.

**Required loop for plan-phase revision:**

```
For each batch of reviewer findings:
  1. Triage findings (LOOKUP/PATTERN/JUDGMENT per F-20 unified contract).
  2. Address blocking findings (revise plan content per #1 above; update Decisions Log).
  3. Re-run the relevant plan-reviewer agents on the revised plan.
  4. If new findings surface OR old findings persist:
     - Increment convergence counter.
     - If counter < threshold: loop back to step 2.
     - If counter >= threshold: escalate as JUDGMENT — human decides accept/waive/kill.
  5. Once reviewers come back clean (or all surviving findings are JUDGMENT-waived):
     - Log final review-pass timestamp in the plan.
     - Emit fresh phase-complete per F-29's re-send protocol.
```

**Worker self-check rule (add to worker phase-skill for plan):**

> "You have not completed plan phase until your plan-reviewer agents have produced a clean finding set (or all open findings are explicitly waived). Addressing findings without re-running review is not finishing — it's claiming to finish."

**Why this matters specifically for plan phase (vs. the same point in F-21 for repo-spec):**

Plans execute — specs describe. A plan revision that "looks right" but introduces a subtle sequencing bug or missing step will break at implement phase. Repo-spec revisions have more forgiveness (humans re-read; plans get mechanically executed). So plan phase needs MORE review rigor per revision, not less.

**Fix directions (not yet implemented):**

1. **Explicit re-review rule in plan phase-skill** — worker skill body adds the self-check rule above. No shortcut from "I addressed the findings" to phase-complete.

2. **Orchestrator-side validation of the re-review.** When orchestrator accepts the worker's re-sent phase-complete (F-29 step 11), it reads the findings file and checks:
   - Does it reflect a timestamp after the most recent plan revision? (Ensures review was actually re-run on the revised plan, not stale.)
   - Is the findings set clean or all-waived? (Ensures loop closure.)
   If either fails, orchestrator rejects the phase-complete back to the worker with a `review-reopen` directive.

3. **Decisions Log entry required per revision.** Worker's `/finalize-plan` skill (F-27 Part A applied to plans) enforces: if plan content changed vs prior version, there MUST be a new Decisions Log entry explaining what and why. Guards against silent edits.

4. **Timestamp diff audit.** Plan file's frontmatter tracks `last_revised_at` and `last_reviewed_at`. If `last_reviewed_at < last_revised_at`, worker is not done. Orchestrator can detect this automatically.

**Recommendation:** land with F-29 implementation — all three layers (content hygiene integration + re-review discipline + Decisions Log per revision) fit naturally in the plan phase skill + `/finalize-plan` skill. Short explicit rules go further than long prose; keep the worker self-check one sentence.

Related to F-21 (this is the plan-phase sharpening of F-21's repo-spec review loop), F-29 (plan-phase discipline — this is a specific sub-requirement), F-19 (content hygiene — revisions live in the plan body, not bolted on), F-27 (finalize-plan enforces Decisions Log entries), F-28 (Decisions Log is where the "what changed and why" lives).

### F-32. Worker misrepresents listen state — claims running when it isn't (2026-04-23) — RESOLVED via F-51 Phase B
**Sub-findings (consolidated 2026-05-04):** F-42 (two-call pattern post-send — outbound complement to F-32's inbound atomicity discipline). F-32 is verify-before-claim on inbound delivery; F-42 is verify-before-walk-away on outbound send.

Observed sequence:
```
Worker: "Listen loop is still running (bash_id=bfgwqi9uw) to receive the go-ahead.
         Let me know if you want me to adjust the concern content before the orchestrator signal arrives."
Human: "no listen is running"
Worker: "Right — the listen loop fired when the pre-alignment concern arrived (task bfgwqi9uw completed),
        and I never restarted it after ACK. Starting a fresh listen."
```

The worker confidently reported a running listen that had actually completed and been ACKed. The worker thought its listen was live; reality was that the bash_id referred to a completed task. A message could have arrived and sat in the pending list forever without the worker noticing.

**Root cause:** worker tracks listen state mentally (via remembered `bash_id`) rather than verifying against the actual harness state. When the bash task completes (because a message arrived and listen.sh exited to deliver it), the worker's assumption "listen is running" becomes stale — but nothing tests the assumption.

This is the **inverse** of F-8 (too many listeners): here there are zero listeners, but the worker believes there's one. Both stem from the same fuzzy relationship between worker state-of-mind and actual harness state.

**Fix directions (not yet implemented):**

1. **Verify before claiming.** Before ever asserting "listen is running" — in status messages, reports to human, orchestrator status-check replies — worker queries the actual state of the recorded `bash_id`. If the task has completed, acknowledge and restart. Skill rule:
   > "Never claim 'listen is running' without verifying. If your last-recorded bash_id has completed, the listen is NOT running — restart it before making any claim."

2. **Atomic handle-and-restart sequence.** Phase skills codify handle-message → ACK → restart-listen as a single indivisible sequence. No intermediate steps (report to human, save state, invoke skill) between ACK and restart. Worker skill's Listen Loop section makes this explicit:
   ```
   The sequence is:
   1. Receive message from listen (background task completes, output file written).
   2. Parse message, dispatch to handler.
   3. Handler completes.
   4. ack.sh {NAME} {_stream_id}.
   5. IMMEDIATELY start new listen.sh {NAME} 0 with run_in_background: true.
   
   Steps 4-5 are atomic. Do NOT interleave report generation, state writes, or
   any other work between them. Any reporting happens AFTER the new listen is
   running.
   ```

3. **Listen watchdog.** Every N minutes (or between phase-specific tasks during implement), worker runs a self-check: "Is my recorded bash_id still running?" If not, restart. Doesn't rely on discipline — proactive recovery. Could be invoked from the same pause points as `check-context` (F-6).

4. **Status-check reports verified listen state.** Orchestrator's `status-check` handler, when workers reply, includes an explicit "listen_alive: true/false" field in the status message. Orchestrator aggregates; if any worker reports `listen_alive: false`, orchestrator knows worker is stalled and can nudge or escalate. Augments F-25's state schema with a verified listen-liveness indicator.

5. **Resume-mode listen verification.** After `/worker --resume` (F-4), before declaring "listen started," verify the new bash task is actually alive. Sanity check — shouldn't fail normally, but catches harness-init bugs. Cross-reference F-8 (active cleanup) — if cleanup happened and restart is the next step, the new listen should be verified before claiming resume is complete.

6. **Explicit reporting vocabulary.** Worker language should distinguish:
   - **"Listen started (bash_id=X)"** — just started, verified alive.
   - **"Listen running (verified bash_id=X)"** — checked at status report time, confirmed alive.
   - **"Listen unknown — bash_id=X, last verified at T"** — haven't checked recently.
   Never "listen is still running" without qualifier — the lazy form is what produced this bug.

**Recommendation:**
- **#2 (atomic handle-and-restart) is the prevention** — make the sequence indivisible so the worker never ends a handler without restarting listen.
- **#1 (verify before claiming) is the detection** — if prevention fails, catch the drift before misreporting.
- **#3 (watchdog) is the recovery** — periodic self-check restarts silently-dead listens.
- **#4 (status-check reports) is the observability layer** — orchestrator sees listen-liveness across workers; stalls become visible.
- **#5** is resume-specific defense.
- **#6** is cosmetic/linguistic discipline.

**Relationship to F-8 (duplicate listeners):** both findings are about keeping the worker's mental model synchronized with actual listen-process state. F-8 handles "too many," F-32 handles "zero but believed to be one." Together they define the invariant: **exactly one live listen per worker, at all times, verifiable at any point.** A worker that can't verify this invariant can't be trusted in its state reports.

**Implementation notes (not yet done):**
- Update `~/.claude/skills/worker/SKILL.md` Listen Loop section with the atomic sequence (#2) and verify-before-claim rule (#1).
- Add watchdog (#3) to the between-tasks pause points where check-context already fires.
- Extend `state-schema.md` per F-25 to include `listen_alive` (bool, last-verified timestamp) in worker state.
- Update orchestrator's `status-check` handler to request and record listen-liveness field.
- Candidate implementation: `tools/xfleet/is-listen-alive.sh {name}` — reads recorded bash_id from state file, queries harness, outputs true/false + last-verified timestamp. Worker invokes this pre-claim and periodically.

Related to F-4 (resume mode), F-8 (active cleanup of duplicate listeners), F-12 (resume leaves work dormant — same class of state/reality drift), F-6 (context-check injection at pause points — watchdog could fire at the same points), F-25 (state schema needs a listen-liveness field).

### F-33. Resolution-receiver handler missing peer close-ack — workers silently "close" without notifying peer (2026-04-23) — RESOLVED via cluster 4e (`resolution-ack` terminal handshake)
Observed: when web sends a resolution to oracle, oracle writes the resolution file and notifies the orchestrator, but does NOT notify web. Web has no explicit signal that oracle received/accepted; it relies on orchestrator-mediated `negotiation-complete` as implicit closure. When asked to fix this, the worker (repeatedly) saves the pattern to memory and sends the ack — but the next similar situation, they forget again. The user (2026-04-23) asked: "is there any specific instruction that's making you forget?"

**Root cause — instruction is missing from the phase skill, not misinterpreted:**

`~/.claude/xfleet/phases/repo-spec.md:49-50` has asymmetric handlers:

- **Line 49** (initiator sending resolution): "write resolution file, send `--type resolution` to the other worker + `--type resolution-summary` to orchestrator." Sender notifies **both** peer and orchestrator. ✓
- **Line 50** (receiver accepting an incoming resolution): "Write resolution file to `~/.claude/resolutions/{id}.md`. Send `--type resolution-summary --concern_id {id} --summary "..." --path ...` to orchestrator." Receiver notifies **only orchestrator**. ✗

The receiver's handler has no step for notifying the peer. The worker's forgetting is consistent with the skill not requiring it.

**Design intent vs observed expectation:**

Original design may have relied on orchestrator mediation: receiver tells orchestrator → orchestrator tracks all resolutions → orchestrator emits `negotiation-complete` when the last one lands → implicit closure for everyone. Silence between peers is expected.

But operator expectation (observed across multiple incidents) is that workers explicitly acknowledge closure to each other. When web writes "Closing unless oracle pushes back," web is waiting for a signal from oracle, not from the orchestrator's eventual `negotiation-complete`. Asymmetric silence breaks that expectation and forces workers to guess at peer state.

**Fix directions (not yet implemented):**

1. **Add explicit peer close-ack to receiver handler.** Update `repo-spec.md:50` (and equivalent handlers in other phases that deal with resolution acceptance):
   ```
   | `resolution` (accepted) | Write resolution file to ~/.claude/resolutions/{id}.md.
     Send --type resolution-ack --concern_id {id} --path ... to the peer who sent
     the resolution. Send --type resolution-summary --concern_id {id} --summary "..."
     --path ... to orchestrator. |
   ```
   New message type `resolution-ack` (or `close-ack` per user's vocabulary): worker → worker, confirms resolution received and accepted. No rounds, no negotiation reopen — terminal handshake.

2. **Document the two-party close handshake** in `shared/messaging.md`:
   ```
   Resolution closure is a two-message handshake:
   - Initiator: writes resolution file, sends `resolution` to peer + `resolution-summary` to orchestrator.
   - Peer: writes local resolution ref (or verifies sender's file), sends `resolution-ack` back to initiator + `resolution-summary` to orchestrator.
   - Both sides know the concern is closed once the ack round-trip completes.
   ```

3. **Handler for `resolution-ack`** on sender side: mark local concern state as closed-acked, no further action. Optional: include in the worker's state file as `confirmed_closed_concerns[]`.

4. **Add `resolution-ack` to the message-type table** in messaging.md and validator in `send.sh`.

5. **Retrofit existing phases.** Any phase that uses `resolution` message type (repo-spec, plan's xrepo negotiation per F-29, possibly alignment) needs the receiver-side handler updated to include the ack.

**Alternative fix — accept orchestrator-mediated closure and update expectations:**

If the design intent was truly orchestrator-mediated (no peer ack needed), the fix is in the opposite direction: update worker conduct to explicitly NOT expect peer acknowledgment. Workers should say "resolution delivered to peer + orchestrator; awaiting orchestrator's negotiation-complete signal for session closure" rather than "closing unless peer pushes back." This requires:
- Clear phase-skill language: "silence from peer after resolution is the expected state; do not wait for or expect a peer ack; closure comes from orchestrator's negotiation-complete."
- Worker reporting vocabulary that reflects this (no "closing unless X" phrasing that implies ack expectation).

**Recommendation:** go with **direction #1 (explicit peer ack).** Reasons:
- Matches operator/worker intuition. The "silence = ambiguous" observation is right: workers shouldn't have to infer peer state from absence.
- Makes peer-to-peer mode (no orchestrator) work correctly by symmetry. Orchestrator-mediated closure only works in orchestrated sessions; explicit peer ack works in both modes.
- Fixes the recurring forgetting pattern permanently by putting the instruction in the skill, not in memory.
- Cheap: one new message type, one handler update, one skill-doc addition.

**Why "save to memory" didn't fix it:**
- Memory is per-session. Next session's worker doesn't have the memory loaded (or it's scoped to a different context).
- The skill is the durable instruction source. If the skill is silent, the worker reasons from scratch each time — and sometimes reasons to "resolution file written = done" because that's an intuitive reading.
- Fix: instruction lives in the skill, which every session loads, not in memories that may or may not surface.

**Implementation notes (not yet done):**
- Update `~/.claude/xfleet/phases/repo-spec.md` handler table line 50.
- Add `resolution-ack` to `~/.claude/xfleet/shared/messaging.md` message-type table + closure handshake documentation.
- Add `resolution-ack` validator in `tools/xfleet/send.sh`.
- Add handler for incoming `resolution-ack` on sender side (mark local state closed-acked).
- Apply same pattern to other phases that process resolutions (plan xrepo per F-29, alignment).
- Worker state file schema update (per F-25): `confirmed_closed_concerns[]` optional field.

Related to F-13 (completion detection — orchestrator still determines overall session closure; peer ack is for worker-level awareness, doesn't change orchestrator flow), F-14 (human_engaged — if human reopens after ack round-trip complete, it's a distinct new round, not continuation), F-15 (round counter — resolution-ack doesn't increment; terminal message), F-30 (authority hierarchy — workers communicate closure to each other directly in this case because it's worker-to-worker state, not human-to-worker), F-32 (state verification — "did I send the ack?" is another verify-before-claim case; skill-level atomicity in the handler prevents forgetting).

### F-34. Plan updates must always use `superpowers:writing-plans` — no exceptions (2026-04-23) — RESOLVED (cluster 3, 2026-05-04)
Observed: during xfleet flow, plans get updated through multiple mechanisms beyond initial authoring — folding peer changes, reviewer-findings revisions (F-21), xrepo-negotiation outcomes (F-29), post-implementation reconciliation (F-24). Multiple actors touch the same plan: worker, orchestrator (when relaying/folding), human (when directing updates).

**The discipline violation:** only the initial plan write consistently uses the `superpowers:writing-plans` skill. Subsequent updates — folds, reviewer-driven revisions, orchestrator-assisted edits — often bypass the skill and edit ad-hoc. Result: plan starts with writing-plans' structural discipline (task breakdown, step granularity, rollback/success criteria sections, consistent voice) and accumulates edits that don't honor those conventions. The plan becomes a hybrid: part writing-plans-compliant, part freeform. Downstream consumers (implement phase, reviewer agents, future humans reading the plan) hit inconsistencies that weren't there at initial authoring.

**User's phrasing (verbatim 2026-04-23):**
> "always use /writing-plans, even you updated without it ... have them verify again with that, you too, not an exception, the inital plan was written using superpowers:writing-plans, these things cause deviations and errors later"

**Principle to encode:**

**If a plan was authored under `superpowers:writing-plans` discipline, every subsequent edit must re-engage the skill.** No in-session shortcuts, no "this is a small edit" exemptions. The orchestrator is not an exception; workers are not an exception; the human, if directly editing a plan file, should route through the skill too.

**Why this matters:**

- **Structural consistency.** writing-plans enforces specific shapes — task IDs, step granularity, prerequisites/outputs per step, explicit rollback, success criteria. Ad-hoc edits drift from these shapes.
- **Reviewability.** Plan reviewer agents (F-29's `plan_reviewers:`) are calibrated to writing-plans-compliant structure. A hybrid plan produces reviewer findings that look like content issues but are actually structural drift.
- **Implement-phase reliability.** Plans are mechanically executed (F-31's "plans execute, specs describe"). Structural drift = subtle execution bugs. A task that reads fine to a human but has missing prerequisites or ambiguous success criteria will break at implement.
- **Audit trail.** If every plan touch goes through writing-plans, the plan's evolution (versioned per F-27) is auditable as "always produced by the same skill." If some edits bypass, the trail becomes "sometimes skill, sometimes not" — less trustworthy.

**Fix directions (not yet implemented):**

1. **Plan phase skill rule.** Worker's plan phase skill adds an explicit line:
   > "All plan creation AND all plan edits MUST invoke `superpowers:writing-plans`. This includes folding in peer-negotiation outcomes (F-29), revising after reviewer findings (F-31), incorporating human-directed changes (F-22). No exceptions. If you find yourself editing a plan without engaging writing-plans, stop and restart via the skill."

2. **Orchestrator rule when relaying plan updates.** When orchestrator folds peer outcomes into a plan (e.g., "worker A's xrepo negotiation resolved — update worker B's plan to reflect"), orchestrator invokes writing-plans in its own session before producing the updated content. Not a "quick edit" applied directly.

3. **`/finalize-plan` skill (F-27 extension) must invoke writing-plans.** Every finalize-plan run invokes writing-plans to produce the clean final version. Finalization is not editing; it's re-authoring under discipline.

4. **Rationalizations-to-reject table** in plan phase skill:
   | Excuse | Reality |
   |--------|---------|
   | "This is a small edit — one-line change, writing-plans is overkill." | writing-plans keeps structure consistent. A one-line edit in the wrong place breaks task-ID conventions, prerequisite chains, or success-criteria linkage. Invoke the skill. |
   | "I already know what writing-plans would produce, I'll just write it." | Engaging the skill re-loads the current conventions (skills evolve). Skipping means you're applying a remembered version, which may be stale. Invoke. |
   | "The worker is senior / the orchestrator is trusted — no need to double-check." | Trust is not the lever; structural consistency is. Invoke. |
   | "The original plan diverged from writing-plans already — catching up later." | Catching up later is how drift compounds. Invoke now, fix structure now. |

5. **Verification pass discipline.** After any plan edit, worker (and orchestrator-helper when applicable) runs a verify pass: re-invoke writing-plans on the revised plan, confirm structure matches conventions. This is separate from reviewer agents — it's a self-check that the edit respected the skill's format, before review even runs. Lightweight, catches drift before reviewers have to.

6. **Tooling nudge.** Optional: before any `Edit`/`Write` targeting a plan file (`docs/superpowers/plans/*.md` or session dir `section.md`/plan equivalents), Claude harness prompts: "Plan file detected. Have you engaged `superpowers:writing-plans`? [y/n]." Friction that catches drift at the edit boundary. Could be a hook or skill-level check.

**Why "just remember" doesn't work (same class as F-33):**

The user observed this repeatedly — workers and orchestrator drift back to ad-hoc edits unless the skill/phase-skill explicitly requires writing-plans. Memory-based discipline fades; skill-based discipline is durable because every session reloads the skill.

- F-33: skill silent on peer-ack → workers forget → fix is in skill, not memory.
- F-34: skill permissive on plan edit mechanism → workers/orchestrator drift to ad-hoc → fix is in skill, not memory.

Same pattern: durable behavior changes live in skill bodies, not in session memories or user reminders.

**Implementation notes (not yet done):**
- Update `~/.claude/xfleet/phases/plan.md` with the "always writing-plans" rule.
- Update `~/.claude/skills/worker/SKILL.md` with a general "plan-file edits always invoke writing-plans" rule.
- Update `~/.claude/skills/orchestrator/SKILL.md` with the same for orchestrator-side plan relays/folds.
- Add the Rationalizations-to-Reject table to plan phase skill.
- Land verification pass discipline as part of the worker's finalize-plan flow (F-27 Part A).
- Document in xfleet README that `writing-plans` is the ONE way plans are produced or edited.

**Broader principle emerging:**

Several findings now share the pattern "skill-level instructions are the durable discipline layer; memories and in-session reminders are not sufficient." F-33, F-34, F-32, F-30 all rely on this. Worth capturing somewhere durable (meta-skill, principles doc) that:
- Skills are the source of truth for agent behavior.
- Discipline that needs to survive session boundaries MUST be in skills.
- Memories complement skills (context, preferences) but cannot replace them for behavior rules.
- When a behavior keeps drifting despite correction, the fix is almost always in the skill, not in "remembering harder."

Consider adding this as a stand-alone finding (F-35?) or as a design principle document in `~/.claude/xfleet/shared/design-principles.md`.

Related to F-21 (reviewer revisions — every revision must use writing-plans), F-27 (finalize-plan — must invoke writing-plans), F-29 (plan-phase xrepo fold — writing-plans applies to the fold), F-31 (plan-phase revision discipline — integrates writing-plans), F-32/F-33/F-30 (skill-level discipline vs memory-based, same pattern), F-17 (emission-authorization — if a plan update emission is authorized but the update itself bypassed writing-plans, emission tracking is undermined).

### F-35. Design principle — skills are the durable discipline layer; memories are not (2026-04-23) — RESOLVED via cluster 4n (locked in `design-principles.md` xfleet-scoped; corollaries: skills-first correction, memory-as-signal, durability test, memory-appropriate scope, review guard; not project-wide because non-xfleet sessions rely on F-53 prepare-compact for durability)
A recurring pattern across multiple findings in this shakedown:

1. User observes a worker/orchestrator behavior they want changed.
2. User corrects in-session ("always do X before Y," "don't forget to Z").
3. Worker/orchestrator acknowledges and commits to memory.
4. Next session (or later in the same session after /clear or compact), the behavior drifts back. User corrects again.
5. User is frustrated — "why do you keep forgetting?"

**Root cause:** in-session corrections and memories are not sufficient to encode durable behavior. Skills are.

**Evidence across this shakedown:**

| Finding | Pattern instance |
|---|---|
| F-30 | Workers bypass orchestrator to ask human directly. Corrected, forgotten. Fix: authority-hierarchy rules in worker skill body. |
| F-32 | Workers claim "listen is running" without verifying. Corrected, forgotten. Fix: verify-before-claim rule + atomic handle-and-restart in worker skill body. |
| F-33 | Receiver of resolution forgets to send peer close-ack. Corrected repeatedly, forgotten. Fix: `resolution-ack` message type + handler in phase skill body. |
| F-34 | Plan edits bypass `superpowers:writing-plans`. Corrected, forgotten. Fix: "always writing-plans" rule in plan phase skill + orchestrator skill body. |

Each instance: the observed corrective path was "save to memory" or "remember this." Each instance: the durable fix is **modifying the skill/phase-skill content** so every session loads the corrected discipline fresh.

**The principle to encode:**

> **Skills are the source of truth for agent behavior. Discipline that must survive session boundaries belongs in skill bodies, not in memories or in-session reminders.**
>
> Memories complement skills (user context, preferences, project-state snapshots) but cannot replace them for behavior rules. When a behavior keeps drifting despite correction, the fix is almost always "update the skill," not "remember harder."

**Corollaries:**

1. **Skills-first correction.** When user corrects a drift, the response should be: (a) acknowledge, (b) identify which skill owns the behavior, (c) update that skill (not just the user's memory, not just a worker memory). Memory update is additional, not a substitute.

2. **Memory-as-signal.** If a correction is saved to memory without a skill update, that's a signal the fix will recur. Treat memory-only corrections as incomplete. Sessions where the user says "remember to X" should usually end with "…and let's also update the {skill} to encode it."

3. **Durability test.** For any corrective guidance, ask: "If the next session starts with a fresh context (no memories loaded), would this behavior still be correct?" If no, the fix is incomplete — skill must be updated.

4. **Memory appropriate scope.** Memories durably hold: user identity, project context, collaboration preferences, fact snapshots at a point in time. Memories should NOT hold: xfleet protocol rules, phase-handler sequences, message-type contracts, tool invocation conventions.

5. **Review guard.** When code-reviewing xfleet changes, check: if behavior rules appear in the change but the relevant skill file wasn't updated, that's a drift-waiting-to-happen. Flag.

**Proposed durable location:**

Capture this principle in `~/.claude/xfleet/shared/design-principles.md` (new file — sibling to `messaging.md`, `state-schema.md`, and the proposed `reviewer-contract.md` from F-20). Doc is referenced by every xfleet skill in their Protocol section the same way they already reference `messaging.md`. Every worker, orchestrator, finalize-spec, etc. session loads this as part of its context setup, so the principle is re-established every time.

Other principles worth capturing in the same doc as they crystallize:
- **Coordination-vs-durability split** (F-19): global `~/.claude/` is for transient coordination state; per-repo `docs/superpowers/` is for durable artifacts.
- **Content hygiene** (F-19): clean artifacts are forward-looking; history lives in sibling bundles.
- **Authority hierarchy** (F-30): orchestrator speaks for human; workers execute without second-guessing.
- **Atomic state transitions** (F-32, F-33): critical-sequence operations (ACK→listen, write-resolution→peer-ack) must be indivisible in the skill instructions.
- **Verify-before-claim** (F-32): worker state-of-mind about listen/task state must be verified against actual state before reporting.
- **Skill as behavior source of truth** (this finding).

**Fix directions (not yet implemented):**

1. **Create `~/.claude/xfleet/shared/design-principles.md`** with this principle as entry #1 and space for the others listed above.

2. **Reference from every xfleet skill.** Worker, orchestrator, finalize-spec, finalize-section, capture-decision — all get a "Design principles: see `shared/design-principles.md`" line in their Protocol sections. Loaded on every session startup.

3. **Update the correction-response workflow.** When user reports a drift, the canonical response is: acknowledge → locate owning skill → update skill → optionally save context to memory. Not: acknowledge → save to memory → move on.

4. **Apply retroactively** — every finding flagged as "skill-level fix, not memory" (F-30, F-32, F-33, F-34) should land its skill update; this finding is the meta-layer that makes sure the pattern isn't just ad-hoc.

5. **User-facing note in xfleet README** — brief paragraph explaining that xfleet discipline lives in skills, so requesting a behavior change means changing a skill, not just telling a worker in-session. Sets operator expectations.

**Why this is a first-class finding, not just commentary:**

It explains why several other findings have "recurring" as a symptom. Without this principle codified, each new drift-then-corrected-then-forgotten cycle re-teaches the same lesson. With it codified, the corrective workflow terminates in a skill update instead of a memory entry that fades. Compound improvement: every future finding benefits from the principle being explicit.

Related to: every finding that mentions "memory insufficient" (F-30, F-32, F-33, F-34). This is the meta-layer making the pattern explicit. Also related to F-25 (state schema drift — another "keep docs in lockstep with reality" problem, adjacent to skills being the source of truth).

### F-36. Agents pause for human confirmation between plan steps instead of executing autonomously (2026-04-24) — RESOLVED via cluster 4n (autonomous-execution principle in `design-principles.md`; prominent `## Autonomous Execution` section elevated to top of worker/orchestrator SKILL.md; 4-question rubric + Rationalizations-to-Reject table)
Observed: workers and the orchestrator pause at each step, checking in with the human for direction, instead of following the plan and skill structure autonomously. User had to explicitly correct (2026-04-24): "why are you pausing everytime for my instructions, follow the plan and the skill structure. only pause if there's something breaking or deviation from the plan."

**The rule already exists in the skill — the drift is why it's not followed.**

`~/.claude/skills/worker/SKILL.md:201` says (summarized):
> "Drive phases autonomously. Do not wait for human unless at an explicit gate. During implement, after each superpowers task completes with DONE, start the next task immediately — don't pause for 'what's next?' direction. Only stop for BLOCKED/NEEDS_CONTEXT cases."

Yet the worker (and orchestrator) keep pausing. Classic F-35 instance: **the discipline exists in the skill but gets ignored in practice.** The single-line rule in a long skill body lacks enough weight to override the default "check with human" instinct.

**Why agents drift to pausing:**

- **Default safety bias.** "When uncertain, ask" is a reasonable heuristic, but it overfires. Most steps aren't genuinely uncertain — they're the next action in a plan or handler sequence.
- **Confirmation-seeking feels responsible.** Pausing to confirm looks like diligence. It isn't in this context — the diligence is in executing the documented path.
- **No clear rubric for "is this worth pausing over?"** The rule says "explicit gate" or "breaking" but doesn't give concrete decision criteria. Agents apply their own (conservative) interpretation.

**Principle to encode (candidate for `design-principles.md` per F-35):**

**Autonomous execution.** Agents execute the plan and skill-defined handler flow without pausing for human confirmation between steps. Pause only for:
1. An **explicit gate** defined by the plan or skill (e.g., human approval at phase transition, approval_by_human per F-17).
2. A **breaking error** — tool failure, contradiction in state, missing required input that can't be obtained without human input.
3. A **deviation from the plan** — before executing a step that wasn't in the plan, or skipping a planned step, check in.

Don't pause for:
- Next expected step (just do it).
- Routine progress (just report at milestones).
- "Am I doing this right?" (re-read the plan; if it answers, act).
- Uncertainty that a Serena/Context7/grep lookup could resolve (look it up; act).

**Decision rubric when unsure:**

Ask yourself:
1. **Is this step in the plan?** → Yes: execute. No: check in.
2. **Is there a gate defined?** → Yes, I'm at it: pause. No: execute.
3. **Did I hit an error that breaks progress?** → Yes: pause with the specific error. No: execute.
4. **Am I about to deviate from the plan?** → Yes: check in first. No: execute.

If all four are "execute," execute. Do NOT pause just because the step is important or you want reassurance.

**Fix directions (not yet implemented):**

1. **Elevate the rule to a prominent section in worker/SKILL.md.** Not a single line at line 201, but a dedicated `## Autonomous Execution` section near the top (right after Overview), with the principle statement + rubric + Rationalizations-to-Reject table.

2. **Same treatment in orchestrator/SKILL.md.** Orchestrator drives through its handler table autonomously — it doesn't pause to confirm routing decisions, completion detections, or signal emissions (beyond the human gates that are explicitly part of its protocol).

3. **Rationalizations-to-Reject table in worker skill:**
   | Excuse | Reality |
   |--------|---------|
   | "This step seems important — I should confirm before doing it." | Importance isn't a gate. Gates are defined in the plan or skill. If it's not a gate, execute. |
   | "I'm not 100% sure this is right — safer to ask." | Uncertainty that a grep/Serena/plan re-read can resolve is not a pause-worthy uncertainty. Resolve, then act. |
   | "Last time I didn't check, user was annoyed." | That was a different situation — check the pattern, not the instance. If it wasn't a gate, executing was correct. |
   | "The human seems busy/happy — might as well confirm while they're around." | Proactive check-ins break flow. Report at milestones, not at every step. |
   | "This is a multi-step chain — let me confirm before the next one." | If the chain is in the plan, execute. Milestone-level reporting is enough. |
   | "I might cause something irreversible." | Then the plan should have marked it as a gate. If it didn't, it's not intended as one. If you think it SHOULD be, raise the design issue after executing the current step. |

4. **Milestone-level reporting instead of step-level confirmation.** Agents report after a meaningful chunk completes (e.g., "Section written and reviewed, no blocking findings, sending phase-complete now"), not after each sub-step ("Reading config... Checking state file... Preparing to write section..."). Reporting is for the human's visibility, not for permission.

5. **Add to F-35's `design-principles.md`.** "Autonomous execution" as an additional principle in the same durable location. Referenced by worker and orchestrator skills.

6. **Verify-before-pause rubric.** Before pausing, agents mentally walk through the four rubric questions. If any answer isn't "execute," only then pause. Adds a micro-friction to pausing that flips the default.

**Why F-35 applies:**

The skill already has autonomous-execution language at line 201. The drift persists because the rule is buried and abstract. Durable fix: elevate the rule, give it a section, add rationalizations, add rubric. Memory ("user said don't pause") isn't the answer — the structural change to the skill is.

**Implementation notes (not yet done):**
- Restructure `~/.claude/skills/worker/SKILL.md` to include a prominent `## Autonomous Execution` section.
- Mirror in `~/.claude/skills/orchestrator/SKILL.md`.
- Add principle to `~/.claude/xfleet/shared/design-principles.md` (when that doc is created per F-35).
- Consider a hook that, on long-gap inactivity (agent has been silent waiting for N seconds), surfaces the rubric — prompts self-check "am I pausing for a valid reason?"

Related to F-35 (skill-vs-memory discipline — this is another "skill has the rule but it's not prominent enough" case), F-30 (authority hierarchy — orchestrator drives autonomously; workers trust orchestrator's relays without re-confirming), F-14 (human gates are defined, explicit, and limited — autonomous execution happens between gates), F-22 (directives flow top-down; agents don't pause to re-confirm directives they've received), F-17 (only phase-level emissions require human approval; routine handler work does not).

---

### F-37. ~~PID-based listener cleanup is unsafe across parallel sessions~~ → MERGED into F-8 (2026-05-04)
Content consolidated into F-8's "Critical amendment to fix #1" block. F-37 was an amendment to F-8's proposed fix, not a separate observation; merged to keep the constraint co-located with the fix it amends.

### F-38. Workers must not Bash/Grep/Read into sibling repos directly (2026-05-03, retroactive from web memory) — RESOLVED via cluster 4o (worker analog of cluster 4h orch discipline; skill-text rule + Rationalizations-to-Reject; cross-repo source reads route through `xfleet question`/`xfleet concern`; `docs/superpowers/` reads remain permitted)
**Source:** `web` memory `feedback_cross_repo_via_messaging.md` (2026-04-09).

Worker-side discipline complementary to F-1 (orchestrator delegating to workers). When a worker (e.g., web) needs to know about a peer repo's state — "what does oracle emit in field X today?", "which Beanie model owns Y?", "is there a controller for Z in server?" — the correct path is to send a `question` to that worker via `send.sh`. NOT to `Bash`/`Grep`/`Read` the sibling repo's source tree directly.

**Why this matters:**

- **Each worker has Serena-indexed view of its repo.** Cross-repo Serena from the web worker's session is unavailable (Serena per-repo); falls back to grep, which is slow + error-prone (wrong branch, stale checkouts, missed conventions).
- **The peer worker can answer authoritatively** with Serena memories + branch state + repo-local conventions. Targeted question gets a targeted answer in one round-trip.
- **Symmetry with F-1.** F-1 says orchestrator delegates investigation to workers because workers have Serena-grounded views. Same logic applies between workers: web shouldn't peek into oracle, oracle shouldn't peek into server.
- **The collaboration primitive exists** — `question` / `concern` / `directive` / `task` (F-22 / F-23). Not using it bypasses orchestrator-side bookkeeping (concern_id, round counter, audit trail).

**Exception:** Read-only cross-repo reads are fine for `docs/superpowers/` content (plans, specs, handoffs, reviews) — that's coordination state, not code. Source code questions → message the peer worker.

**Fix direction (not yet implemented):**

1. **Worker skill rule.** Add to `~/.claude/skills/worker/SKILL.md`:
   > "Investigation of peer-repo source code goes through the peer worker via `question` / `concern` messages. Bash/Grep/Read of sibling repo source is forbidden in orchestrated mode. Cross-repo reads are limited to `docs/superpowers/` content (specs, plans, handoffs, reviews)."

2. **Rationalizations-to-Reject entry:**
   | Excuse | Reality |
   |--------|---------|
   | "It's faster to grep than to message — I know what I'm looking for." | Grep finds matches without semantic context; the peer worker answers with intent. Latency is similar; correctness gap is not. |
   | "The peer worker isn't actively listening / will be slow." | Peer's listener is always running (per F-44). Round-trip is seconds. |
   | "Just one quick lookup, won't bother sending." | One quick lookup turns into a wrong assumption that propagates through the section/plan. Send the message. |

3. **Phase-skill reinforcement** in `repo-spec.md`, `plan.md`, `cross-review.md`: when the worker needs cross-repo info, the explicit step is "send a question," not "investigate."

**Why memory wasn't sufficient:** classic F-35 instance — discipline lived in a worker memory but drifted because the skill was silent. Codify in skill body.

Related to F-1 (orchestrator's analog of this discipline), F-30 (authority hierarchy — workers route through orchestrator for human contact, route through peers for cross-repo info), F-22/F-23 (the protocol channels that make this viable), F-35 (skill-vs-memory discipline pattern).

### F-39. Plan folds must enumerate full pending scope upfront (2026-05-03, retroactive from oracle memory) — RESOLVED via cluster 3 (sub of F-29; new local `plan-fold` skill + coverage-table procedure)
**Sub-finding of F-29 (consolidated 2026-05-04).** Specific discipline within F-29's plan-phase umbrella: when `writing-plans` runs to fold artifacts into the plan, the fold must claim full pending scope upfront. Companion to F-31 (revisions discipline).

**Source:** `oracle` memory `feedback_plan_fold_complete_scope.md` (2026-04-23 reducto-migration session).

Sharpening of F-31 (plan revision discipline) and F-34 (always use writing-plans). When `writing-plans` runs to fold artifacts into an existing plan — specs, ADRs, research, cross-repo resolutions, prior handoff "Out of Scope / Deferred" items — the fold MUST enumerate the full set of pending inputs before starting, not silently fold a subset.

**Concrete miss (oracle, 2026-04-23):** an earlier writing-plans pass folded cross-repo-resolution scope (envelope wire fields, several specific tasks) but silently omitted async-rebuild ADR/spec scope (other tasks rewritten) even though the handoff's "Out of Scope / Deferred" section listed those as pending a separate writing-plans pass. On resume, the worker presented options assuming the plan was complete; the user had to ask "plan wasn't already updated? what did you do earlier?" to surface the gap. ~3 wasted turns + an architect-review pass against an under-folded plan.

**The discipline gap:** `writing-plans` allows partial folds without flagging them. The plan reads as authoritative even when only some of the pending inputs were absorbed. Downstream consumers (worker + reviewer + human) treat partial folds as complete folds.

**Fix direction (not yet implemented):**

1. **Coverage checklist as fold pre-step.** Before any fold begins, produce a one-shot table:
   ```
   | Pending input                          | Source                            | Target plan section | Status   |
   |----------------------------------------|-----------------------------------|---------------------|----------|
   | Cross-repo resolution C-7              | resolutions/C-7.md                | Task 4 + Task 11    | folding  |
   | Async-rebuild ADR                      | docs/superpowers/adr/0042-...     | Task 5 (rewrite)    | folding  |
   | Handoff deferred: Task 18 split        | handoffs/xfleet-...-implement.md  | Task 18 (split)     | deferred |
   ```
   Every pending item maps to a target section OR is explicitly retired with a justification. No silent omission.

2. **Out-of-Scope review pre-step.** Before fold: read the current handoff's "Out of Scope / Deferred" section + the plan's own Post-Resolution Amendments section. Every item there is a candidate until explicitly retired in this fold.

3. **Partial fold = explicit declaration.** If a fold knowingly skips inputs (e.g., out of context budget, pending design decision), the resulting plan's frontmatter or a "Pending Folds" section enumerates what's still outstanding. Downstream consumers see "plan partial-folded; X still pending" and don't treat as complete.

4. **`/finalize-plan` (F-27) enforces this.** When finalize-plan runs, it verifies all pending inputs from prior phases are accounted for in the plan body or in an explicit deferred list. Refuses to finalize if pending inputs are silent.

**Why this is distinct from F-31:** F-31 is about re-review after revisions and integration of revisions into plan body. F-39 is about coverage of inputs into the fold itself — what came in vs what got integrated. They stack: F-39 ensures inputs are accounted for; F-31 ensures the resulting plan is structurally clean and re-reviewed.

Related to F-31 (plan revision discipline), F-34 (writing-plans always), F-27 (finalize-plan enforces coverage), F-42 (scope-boundary surfacing — the coverage table should also lead with deferred items), F-35 (skill-vs-memory — codify in writing-plans skill body, not just oracle's memory).

### F-40. Verify resolution dates vs state-file "deferred" labels (2026-05-03, retroactive from oracle memory) — RESOLVED via cluster 4o (worker self-check rule before reciting state labels; resolution date < last task commit → in-scope-unshipped; state schema timestamps `since`/`verified_at` deferred per observe-first; NOT subsumed by 4b — different layer)
**Source:** `oracle` memory `feedback_verify_resolution_timing_during_tasks.md` (2026-04-25).

State-file labels like `deferred`, `pending`, `wave-1.x`, `out-of-scope` cannot be trusted at face value. They often reflect "we forgot to fold it in" rather than "we deliberately deferred it." Before reciting these labels — to the user, in handoffs, in plan-fold coverage — verify the corresponding resolution / research / spec file's date against the relevant task's commit history.

**Concrete miss (oracle, 2026-04-25):** state file said F-49 was "deferred to oracle-side implementation pending." User pointed out the resolution file is dated 2026-04-23, well before Task 11's final commits. The contract was locked while Task 11 was still in flight; the implementation just didn't get folded in. Same shape as a Reducto-questions miss earlier in the same session — surfacing already-resolved items as still pending.

**The discipline gap:** state files are written by humans + workers in the moment; their labels don't auto-refresh when underlying artifacts change. A resolution that lands mid-task gets labeled `deferred` if it wasn't immediately folded; the label persists even after the resolution is in fact ready.

**Decision rule:**
- If the resolution / research file lands BEFORE the relevant task's completion commits → treat as **in-scope-but-unshipped** (a defect to close out in the current scope), NOT new wave-1.x work.
- If the resolution lands AFTER → genuinely new scope; the deferred label is honest.
- Same vigilance for research docs marked "pending verification" — check empirical-findings sections for resolved entries before re-flagging probes as user-side TODOs.

**Fix direction (not yet implemented):**

1. **State-file consistency check.** Worker (and orchestrator before reciting state to human) runs a verification:
   ```
   for each {item} labeled "deferred" or "pending" in state file:
     resolution_date = stat ~/.claude/resolutions/{item}.md
     last_relevant_commit = git log --until {resolution_date} {affected_paths}
     if resolution_date < last_relevant_commit_date_of_task:
       surface as "MAY BE STALE: resolution X.md dated Y, but task Z committed at W; check"
   ```

2. **Label-with-timestamp rule.** State file fields that mark items as deferred include a `since` timestamp + a `verified_at` timestamp. If `verified_at < since` and lots of activity has happened, prompt re-verification.

3. **Worker self-check before reciting.** Adds to worker skill:
   > "Before reciting any state-file label like 'deferred,' 'pending,' or 'out-of-scope' to the user, verify the corresponding resolution / research file's date against the relevant work's commits. If the resolution lands first, the item is in-scope-unshipped, not new scope. State labels are point-in-time observations, not live state."

4. **Plan-fold uses verified state.** F-39's coverage checklist reads verified state, not raw labels. An item showing as "deferred" in raw state but verifying as "resolution before task complete" enters the fold as in-scope.

Related to F-32 (verify-before-claim — same class of "worker mental model can drift from reality"), F-39 (plan fold coverage uses verified state), F-25 (state-schema underspecified — adding `since` / `verified_at` formalizes the lifecycle), F-35 (codify in skill body, not memory).

### F-41. Implement-phase persistent background-listen vs `--no-block` default (2026-05-03, retroactive from server memory) — RESOLVED via F-51 Phase B
**Source:** `server` memory `feedback_implement_background_listen.md` (2026-04-27).

Phase-skill default conflicts with operational reality. The `~/.claude/xfleet/phases/implement.md` flow defaults to `listen.sh --no-block` polls between tasks, on the theory that subagents block the main thread and a persistent background listener competes for attention.

User explicit override (server, 2026-04-27): "keep listening in background." Wants real-time visibility into orchestrator/peer messages while subagents run, not just at task boundaries. The `--no-block` default introduces multi-minute coordination lag (orchestrator escalation, peer concerns, status-checks) — unacceptable for active sessions.

**The discipline gap:** the phase-skill default is wrong for orchestrated sessions. It optimizes for "agent isn't paying attention to inbox between subagent dispatches anyway" but ignores that a backgrounded listen.sh delivers messages asynchronously — the agent doesn't have to be paying attention; the harness delivers when listen.sh exits.

**Fix direction (not yet implemented):**

1. **Flip the default.** `implement.md` phase-skill default becomes "keep ONE persistent background `listen.sh {name} 0` running across the entire phase. ACK-and-restart on every delivery (per F-32 atomic sequence). `--no-block` polls are NOT an alternative; they're a fallback for emergencies only."

2. **Combine with F-32's atomic restart.** On every message delivery: parse → handle → ACK → IMMEDIATELY restart background listen. Between subagent dispatches, no need to also `--no-block` poll if the background listener is active and recent.

3. **Verify before subagent dispatch.** Worker skill adds: before dispatching a subagent, verify the listener is still alive (per F-32 verify-before-claim). If dead, restart before dispatch.

4. **Document the principle:** xfleet README's implement-phase section explicitly states "background listen runs continuously, even during subagent execution." Removes the lingering ambiguity from the prior `--no-block` framing.

**Connection to F-32:** F-32 says "atomic ACK→restart, never claim listen running without verifying." This finding adds: in implement specifically, the *baseline* is one always-running background listen, not periodic polls. Both findings together: the listener is always alive, always verifiable, always restarted atomically post-delivery.

Related to F-32 (atomic restart, verify-before-claim), F-44 (two-call pattern — every send needs a live listener after), F-8 (single listener invariant — implement-phase persistent listen still requires one-listener-per-worker), F-35 (codify in phase skill, not memory).

### F-42. Two-call pattern: every outbound send must verify a live listener (2026-05-03, retroactive from oracle memory) — RESOLVED via F-51 Phase B (sub of F-32; send-with-verify baked into `xfleet send` plumbing)
**Sub-finding of F-32 (consolidated 2026-05-04).** Outbound complement to F-32's verify-before-claim discipline: F-32 is inbound (after delivery, atomic ACK→restart); F-42 is outbound (after send, verify-or-spawn-listener).

**Source:** `oracle` memory `feedback_always_keep_listener_running.md` (2026-04-09 + 2026-04-23).

Operational discipline that tightens F-32 (verify-before-claim). After every `send.sh` invocation that could trigger a response (concern, question, fold signal, close-ack, resolution), the worker MUST verify a live listener is running before continuing. The "send and walk away" pattern silently drops peer responses.

**Concrete miss (oracle, 2026-04-23):** sent a close-ack via send.sh without restarting the listener; the peer's next-round response (if any) would have sat in inbox indefinitely. User caught it.

**The pattern to encode:**

The "two-call pattern" — every outbound message is followed by either:
- (a) Verification that the existing listener is still alive (check recorded bash_id is in harness's running-task list), OR
- (b) A fresh `listen.sh {name} 0` background spawn.

Never `send.sh` and proceed to next work without one of (a) or (b).

**Fix direction (not yet implemented):**

1. **Worker skill rule.** Add to `~/.claude/skills/worker/SKILL.md`:
   > "After every `send.sh` of a type that may receive a response (`concern`, `question`, `resolution`, `directive-response`, `task-response`, `escalation`, fold signals), the next action MUST be either verify-existing-listener or spawn-new-listener. No exceptions. Skipping this drops peer responses silently."

2. **Pair with F-32 atomicity.** F-32's atomic ACK→restart sequence handles the inbound side; F-42's two-call pattern handles the outbound side. Together: the worker has a live listener at all times, verifiable at every send/recv boundary.

3. **Send wrapper option.** A wrapper `xfleet send-and-listen` (extending the F-7 wrapper) that combines the send + listener-verify in one atomic operation — closes the discipline gap at the tooling level. Worker skills invoke `xfleet send-and-listen ...` instead of bare `send.sh ...` for response-expecting messages.

4. **Phase-skill reinforcement.** Each phase skill that uses send.sh prominently (repo-spec, plan, cross-review) reiterates the rule in its handler-table.

**Why memory-only didn't fix it:** F-35 instance — oracle's memory captured the rule, but the worker reasoned from scratch in subsequent sessions and missed it. Codify in skill body so every session loads it.

Related to F-32 (verify-before-claim — same class of state-vs-reality drift, opposite direction), F-8 (single listener — never spawn parallel; verify-before-spawn), F-37 (track listener by bash_id, not pgrep — verification reads recorded bash_id), F-41 (implement-phase persistent listen — the baseline state two-call discipline maintains), F-35 (codify in skill body).

### F-43. Read task `.output` files is permitted in worker flow (2026-05-03, retroactive from oracle + web memory) — RESOLVED via cluster 4o (skill-text update reverses prohibition; permits `Read(/private/tmp/claude-*/.../tasks/*.output)`; plugin default permissions allow-list per cluster 4i pattern; messaging.md documents as canonical method)
**Source:** `oracle` memory `feedback_read_task_output_files.md` + `web` memory `feedback_worker_output_files.md` (both 2026-04-07/09).

Protocol contradiction. The `/worker` command template says "NEVER read from `/private/tmp/` output files" — but `TaskOutput` is deprecated in this runtime and cannot resolve background task IDs. The task-notification only contains status + output-file path, NOT inline JSON. The output file is the only place the actual `listen.sh` message JSON lives. User has explicitly overridden the worker.md prohibition twice (oracle 2026-04-09, web 2026-04-07).

**The discipline gap:** worker.md still carries the prohibition. New sessions reason from skill text and may try TaskOutput first (fails), then escalate to user, then get told "just read the file." Repetitive friction.

**Fix direction (not yet implemented):**

1. **Update `/worker` skill.** Replace the "NEVER read output files" line with:
   > "Background `listen.sh` task notifications carry `output_file` paths but NOT inline JSON. Read the file at `output_file` directly with the Read tool. `TaskOutput` is deprecated and will not resolve listen.sh task IDs. Reading `/private/tmp/claude-*/.../tasks/{id}.output` is the supported pattern."

2. **Document the recovery use case.** After `/clear` or `/compact`, list files in `/private/tmp/claude-501/<project>/<session>/tasks/` and read them to recover orchestrator messages received before the reset. Secondary cross-check — durable handoffs at `docs/superpowers/handoffs/` are still primary, but output files cover the gap when handoffs miss something.

3. **Update messaging.md.** `~/.claude/xfleet/shared/messaging.md` documents the worker-side "how do I read a delivered message?" path — reference output-file reading as the canonical method, not as an override.

4. **Allow-list in settings.** Read access to `/private/tmp/claude-*/tasks/*.output` is explicitly allowed in user settings — small permission scope, eliminates repeated approval prompts.

**Why memory-only didn't fix it:** F-35 instance — both worker memories capture the override but the skill text still says "never read." Each new session has to re-encounter the contradiction. Update the skill once, the contradiction is gone.

Related to F-35 (skill-vs-memory — fix at skill layer), F-3 (permission scope — output-file read is the analog of send.sh tmp-file write; both need narrow allow-list patterns), F-32 (worker reads output files to verify listen state too).

### F-44. Workers near warn-threshold should clear before phase transition (2026-05-03, retroactive from orchestrator memory) — RESOLVED via cluster 4f (always-compact at phase transitions; pattern (b) baked in as universal default; cluster 4d's handoff IS the compact artifact)
**Source:** orchestrator memory `feedback_workers_clear_before_phase_transition.md` (2026-04-22 Reducto wave-1 transition).

Operational pattern not currently in the findings doc. If a worker is ≥50% context AND has already run `prepare-compact` (i.e., its handoff file at `<repo>/docs/superpowers/handoffs/xfleet-{worker}-{phase}.md` is fresh), the next phase signal SHOULD NOT be dispatched until that worker has `/clear`'d and re-resumed via `/worker --resume`.

**Why:** plan and implement phases are the most context-heavy. Pushing a worker that's already at the warn threshold into a new phase guarantees mid-phase compact, which adds operational friction — the worker has to compact mid-task, write a new handoff, lose in-flight context. Better to absorb the reset cost at the phase boundary, when handoff is already prepared and there's no in-flight work to lose.

**Confirmed pattern (from memory, 2026-04-22):**
- Oracle at ~23% on transition: ran fine without reset; the threshold isn't a hard rule below ~40%.
- Workers above 50% with prepare-compact done: explicitly held the phase signal, user `/clear`'d + `/worker` resumed, dispatched after confirmation.

**The decision rule:**
- Worker `<50%` context: dispatch normally; in-flight context grows but they have headroom.
- Worker `≥50%` AND fresh prepare-compact: hold phase signal until clear+resume.
- Worker `≥50%` WITHOUT fresh prepare-compact: orchestrator first asks worker to prepare-compact, then waits for clear+resume.

**Two valid coordination patterns:**
- (a) **Dispatch immediately, signals wait in inbox** until worker resumes. Faster; in-flight signals during reset.
- (b) **Hold signal, wait for user "done" confirmation, dispatch.** Cleaner; no in-flight messages.

User picks per situation; default to (b) when ambiguous.

**Fix direction (not yet implemented):**

1. **Orchestrator phase-transition pre-flight.** Before dispatching `phase` signals, orchestrator queries each worker's context_pct (via status-check + state file). If any worker hits the gate condition, surface to human:
   ```
   Ready to transition phase=plan, but:
   - server: 62% context, prepare-compact done at 14:30 → recommend /clear + /worker --resume before dispatch
   - oracle: 23% → ok to dispatch
   - web: 41% → ok to dispatch
   Hold dispatch until server clears? [hold | dispatch-anyway | dispatch-with-delay]
   ```

2. **Worker volunteers context_pct.** User reliably reports per-worker percent during transitions; formalize this as a status-check field workers self-report. Saves the orchestrator a round-trip.

3. **State-schema field** (per F-25): `context_pct`, `prepare_compact_at` (timestamp of last handoff write), in worker state file. Orchestrator reads these to gate transitions.

4. **Combined with F-10 (handoff at every phase boundary).** F-10 ensures handoffs are written before transition; F-44 uses handoff freshness as the gate on whether to clear-first. They compose cleanly.

**Why memory-only is insufficient:** classic F-35 — the rule lived in orchestrator memory but no skill checks for the gate condition. Codify in orchestrator's phase-transition pre-flight + state-schema.

Related to F-10 (handoff before transition), F-16 (phase-aware compaction policy — sets the warn threshold; this finding uses it as a gate), F-25 (state-schema needs context_pct + prepare_compact_at), F-6 (context-check injection — feeds the data this gate uses), F-35 (codify in orchestrator skill).

### F-45. Surface scope boundaries upfront in "what's next?" responses (2026-05-03, retroactive from oracle memory) — RESOLVED via cluster 4o (worker + orchestrator skill-text rule: boundary statement first, options after; concrete template + Rationalizations-to-Reject; pairs with F-39 plan-fold coverage table — same discipline, different surface)
**Source:** `oracle` memory `feedback_surface_scope_boundaries_upfront.md` (2026-04-23 reducto-migration).

Presentation discipline gap. When the user asks "where do things fit?", "what's next?", or "what about Y?", the response should LEAD with the handoff's explicit "Out of Scope / Deferred" boundary statement, then move to options. The current default-of-LLMs is to lead with options ("Option 1, Option 2, Option 3...") and bury deferred-scope context as a parenthetical.

**Concrete miss (oracle, 2026-04-23):** worker mapped uncommitted files to plan and presented Options 1/2/3 for starting Task 7 async without first stating clearly that the plan's Task 7 section had NOT been updated for the async rebuild. The handoff explicitly listed Task 7 / 5 / 18 as deferred pending a separate writing-plans pass. User had to ask "wasn't the plan already updated?" — the boundary IS the context they needed to choose; options without it are noise.

**The principle:**
> The boundary statement comes first. Options come after. If a deferred item bears on the question being asked, it's not "by the way" content — it's the structural context that makes options meaningful.

**Fix direction (not yet implemented):**

1. **Worker / orchestrator skill rule.** Add to both `~/.claude/skills/worker/SKILL.md` and `~/.claude/skills/orchestrator/SKILL.md`:
   > "When answering 'what's next?' / 'how does this fit?' / 'where does X belong?' — lead with a one-line boundary statement quoting the relevant handoff's 'Out of Scope / Deferred' section verbatim if applicable. THEN present options. Never bury deferred-scope items in parentheticals or 'by the way' framings."

2. **Concrete template for status-style responses:**
   ```
   Boundary: [handoff says X covered, Y/Z still deferred per ...].
   Options for current ask:
     1. ...
     2. ...
   Recommendation: ...
   ```

3. **Pair with F-39 plan-fold coverage table.** F-39's table is the structural form of this discipline at fold time; F-45 is the conversational form at status-check time. Same principle, different surface.

4. **Rationalizations-to-Reject:**
   | Excuse | Reality |
   |--------|---------|
   | "Options answer the user's question; deferred-scope is meta-context." | Options without the boundary are options on the wrong premise. The boundary IS the answer's frame. |
   | "User can ask if they want the deferred view." | They shouldn't have to. If you have it, surface it. |
   | "Listing deferred up front looks like dodging the question." | It IS answering the question — just with the structural context first. |

Related to F-39 (plan-fold coverage table — same discipline at a different surface), F-9 (batching — orchestrator should batch deferred items into the boundary statement when surfacing batches), F-35 (codify in skill body, not memory).

### F-46. Cross-surface asymmetries: unify by default, push back on convenience defers (2026-05-03, retroactive from orchestrator + web memories) — RESOLVED via cluster 4o (three-surface fix: worker proactive unification when cost is small; prd-review boundaries dim gains asymmetry-detection; resolution drafting template requires "Why narrowed" field; Rationalizations-to-Reject table)
**Source:** orchestrator memory `feedback_scope_narrowing_convenience.md` (2026-04-28) + `web` memory `feedback_consistency_across_doctypes.md` (2026-04-23).

Review-pattern discipline applicable to PRDs, resolutions, and locked decisions. When a resolution / spec / plan preserves an asymmetry across parallel surfaces (doctypes, repos, services, features), the default response is **unify, don't preserve** — unless there's an explicit, defended product reason. Phrases that should trigger pushback:
- "KEEP X untouched"
- "defer to wave-1.x"
- "no change to Y"
- "leave Z as-is"
- "X is revisited less frequently" (hand-wave; rejected unless quantified)

**Two confirmed instances:**

1. **Reducto wave-1 relay-elimination (orchestrator, 2026-04-28):** resolution said "KEEP receipt + PO untouched" for the feedback flow. Web later flagged this as preserving an unintended asymmetry between invoice (cross-session feedback memory) and receipt/PO (session-only). User confirmed the narrowing was unintended ("I assumed it will apply to all, but clearly not... casually moved to backlog as scope-narrowing convenience"). Expansion cost was zero on oracle/server, ~120 LOC on web — small enough that the convenience-deferral was net-negative.

2. **Web extraction flow (web, 2026-04-23):** invoice/receipt/PO are conceptually parallel — same extraction → feedback → submit pipeline. Asymmetric implementations create permanent cognitive tax ("why does invoice remember feedback but receipt doesn't?"), expand the bug surface, and signal that earlier scope-narrowing was convenience, not product judgment. Historical asymmetries (e.g., `parsingFeedbackState` only on invoice) are accidents to eliminate when touching the area, not invariants to preserve.

**The discipline:**

- **Real product call** — backed by a defended product/UX/architectural rationale (cited; user-confirmed; or aligned with explicit project direction). Lock and proceed.
- **Scope-narrowing convenience** — default-to-do-less choice with thin rationale, preserves a pre-existing asymmetry the user would not endorse if asked directly. Surface to user explicitly: "this defers X — is that a product call or a scope choice we want to revisit?"

When in doubt, err toward one extra clarifying question rather than locking convenience-defers as policy. Especially watch this in cross-repo resolutions where the cost is uneven (one repo absorbs all the work, others get a free pass).

**Fix direction (not yet implemented):**

1. **PRD-review reviewer-agent dimension.** Add an "asymmetry-detection" pass to `prd-review` (specifically the boundaries dim agent or a new dim): scan resolutions for narrowing language ("KEEP", "defer", "leave alone", "no change") and surface as JUDGMENT findings with the framing "is this a product call or convenience?".

2. **Resolution-drafting skill rule.** When orchestrator drafts a resolution that narrows scope, the resolution template requires a "Why narrowed" field. Empty / hand-wave entries get caught by the F-21 review loop.

3. **Worker-side discipline (web's pattern).** Workers touching cross-surface code (invoice/receipt/PO, server/oracle/web parallels) check for asymmetries proactively and unify if cost is small + propose otherwise. Not "should we unify?" — "I unified, here's the scope expansion."

4. **Rationalizations-to-Reject in resolution / PRD review:**
   | Excuse | Reality |
   |--------|---------|
   | "X is revisited less frequently than Y." | Unless quantified, this is a hand-wave. If the cost of unifying is small, unify. |
   | "Wave-1.x can pick this up." | Wave-N+1 deferrals stack; many never land. If it's small, do it now. |
   | "Defer reduces wave-1 risk." | Asymmetry is its own risk. Quantify both before deferring. |
   | "Asymmetry already exists, we're not making it worse." | You're entrenching it. Each touch that preserves an asymmetry makes it harder to remove. |

**When the narrowing IS justified:**
- Defended product rationale (UX research, support burden, conscious staging).
- Explicit cost asymmetry that exceeds the unification value (one repo would need a 3000-line rewrite vs. 200 elsewhere).
- User-confirmed staging strategy.

The exception is rare — surface and confirm rather than assume.

**Why this matters across xfleet:** cross-repo resolutions are the highest-frequency place asymmetries get locked in. Workers in different repos see different costs; whichever repo has the lowest cost may not advocate for unification. The orchestrator + reviewer agents are the mechanism that catches this.

Related to F-21 (reviewer findings block phase-complete — asymmetry-detection becomes one of the dimensions that can block), F-28 (Decisions Log — narrowing decisions get recorded with explicit rationale or get flagged as TBD), F-14 (human gate — narrowing decisions surface here for explicit ratification), F-19 (content hygiene — clean spec records the unified outcome, history bundle records the deliberation), F-35 (codify in skill / reviewer-agent body, not memory).

---

### F-47. Phase skill / subagent-driven-development not auto-engaged after `/worker --resume` (2026-05-04) — RESOLVED via cluster 2 / F-53 (collapsed into prepare-compact handoff Active-Skills section; resume flow re-engages)
**Sub-finding of F-12 (consolidated 2026-05-04).** Different facet of resume incompleteness: F-12 is in-flight task continuation; F-47 is phase-discipline skill loading.

**Source:** user observation across multiple sessions.

After `/worker --resume`, workers correctly rehydrate state, drain inbox, restart listen — but do NOT auto-engage the discipline skill that the current phase requires. Specifically:
- In `implement` phase: workers don't auto-invoke `superpowers:subagent-driven-development`. User has had to remind every time.
- Same pattern likely for other phase-specific disciplines (e.g., `writing-plans` for plan, brainstorming for qa-spec).

The phase skill body (e.g., `~/.claude/xfleet/phases/implement.md`) presumably references these disciplines, but the resume flow doesn't load the phase skill the same way the initial cold-start does — or loads it without the discipline-engagement step.

**Distinction from F-12:** F-12 ("resume leaves in-flight work dormant") is about not actively continuing the current task. F-47 is about not loading the phase-required *discipline skill* — even if the worker were to continue, it would do so without the structured workflow.

**Distinction from F-36:** F-36 is about agents pausing mid-execution (the inverse drift — over-confirming). F-47 is about not loading the discipline at all on resume.

Observation only. Fix discussion deferred.

Related to F-12 (resume incompleteness — different facet), F-4 (--resume mechanics), F-35 (skill-as-discipline — the discipline must auto-load every session, including post-resume), F-36 (autonomous execution discipline — once subagent-driven-development is engaged, F-36 becomes operative).

### F-48. Between-task check-context discipline skipped without explicit reminding; auto-compact risk (2026-05-04) — RESOLVED via cluster 4j (PostToolUse hook auto-fires; discipline doesn't depend on worker memory)
**Sub-finding of F-6 (consolidated 2026-05-04).** F-6 covers the *mechanism* gap (long mid-message operations push past checkpoints); F-48 covers the *discipline* gap (existing checkpoints get skipped). Distinct fix surfaces.

**Source:** user observation across multiple implement-phase sessions.

The protocol calls for `check-context` between tasks during implement phase. In practice, workers skip this check unless the user is actively watching and reminding. Result: context climbs unchecked, and sessions reach auto-compact (mid-task, mid-handoff, no warning) without any safety pause being triggered.

**Distinction from F-6:** F-6 ("context-check injection is gap-prone during long operations") is about the *mechanism* — the gap between scheduled checks during long mid-message operations. F-48 is about the *discipline* — the scheduled checks themselves being skipped. Even if F-6 were addressed (more frequent injection points), F-48 remains: workers don't reliably honor the existing rule between tasks.

**Distinction from F-44:** F-44 is orchestrator-side (orchestrator gates phase transitions on context_pct). F-48 is worker-side (worker honors check-context between own tasks).

This is a textbook F-35 instance: the rule exists in the implement phase skill but gets ignored without active human supervision.

Observation only. Fix discussion deferred.

Related to F-6 (mechanism vs discipline distinction), F-16 (compaction policy — F-48 is about honoring the policy at all), F-44 (orchestrator-side counterpart), F-35 (skill-vs-memory — the rule is in the skill but doesn't stick), F-32 (verify-before-claim — same class of "discipline-in-skill is not enough without structural reinforcement").

### F-49. Specs need epic-level decomposition for mid-implementation drift detection (BMAD pattern) (2026-05-04) — RESOLVED via cluster 5 (per-repo `## Epics` section template in plan.md anchored to cross-repo Integration Points; plan-fold coverage extended with IP rows; spec `docs/superpowers/specs/2026-05-11-cluster-5-epics-integration-points-design.md`)
**Source:** user, deferred for fuller info.

Big specs ship as single waves. Mid-implementation review cycles catch some drift, but progress checkpoints during a wave are coarse — drift accumulates silently between checkpoints and surfaces late.

User-proposed direction: **break large specs into epics (BMAD-style)**, with structured progress checkpoints between epics inside a single wave. Catches drift earlier, gives intermediate "is this still on-spec?" gates.

Placeholder finding — user to provide BMAD details and concrete decomposition criteria. Fix discussion deferred to that point.

Related to F-21 (review findings block — epic gates would carry the same blocking discipline), F-29 (plan-phase symmetry with repo-spec — epics are a unit of structure that plan phase would also consume), F-50 (API contract drift — epic gates are likely where contract reconciliation should fire), F-24 (finalize-spec multi-mode — finalize at epic close as well as wave close).

### F-50. API contract drift persists across cross-repo implementation despite mid-cycle reviews (2026-05-04) — RESOLVED via cluster 5 (Integration Points in spec.md + atomic contracts in new durable contracts.md + T1+T2+T3+T4 verification stack at IP close; T1 deterministic JSON Schema diff; T3 new `x-vergence-check` skill; light/heavy resolution paths; spec `docs/superpowers/specs/2026-05-11-cluster-5-epics-integration-points-design.md`)
**Source:** user, observed during Reducto wave-1 implementation.

In the Reducto wave-1 cross-repo implementation, API contracts between repos drifted during implementation — and crucially, **drift was not fully eliminated even after the mid-implementation reconciliation cycle**. By end-of-implementation, contract differences remained (request/response shapes, field names, error semantics, etc.). Required hand-correction.

The current xfleet protocol (concerns + resolutions + finalize-spec + cross-review) is designed for spec-time alignment but does not have a dedicated mechanism for **API-contract reconciliation during implementation**. The mid-implementation cycle catches some drift but proves insufficient — the user labels this "all over the place."

User-proposed direction: a dedicated API-contract-reconciliation skill that:
- Has a structured contract-snapshot format (per integration point: caller repo, callee repo, endpoint, request shape, response shape, error contract).
- Runs at deliberate cadence during implementation (per epic close per F-49? per cross-repo task completion?).
- Detects drift via diff against the locked contract from spec/plan phase.
- Has its own resolution loop separate from generic concerns (likely tighter rounds, must-resolve gate before continuing).

Placeholder finding — user to expand on triggering criteria, contract format, integration with existing xfleet phases. Brainstorming recommended (see response below).

Related to F-29 (plan phase needs cross-repo discipline — API contracts are the highest-value cross-repo artifact), F-21 (reviewer findings block phase-complete — API contract drift should be its own blocking class), F-49 (epic decomposition — contract checkpoints fit naturally at epic boundaries), F-13 (completion detection — contract-clean must be a completion condition for implement phase, not just plan), F-31 (revisions integrated cleanly — contract revisions during implementation must flow back to spec/plan with the same discipline), F-19 (per-repo durable artifacts — locked contracts belong in each owning repo's durable tree).

---

### F-51. Transform xfleet into a Claude Code plugin for structural enforcement (2026-05-04)
**Source:** cluster 1 fix discussion. F-35 (skills as durable discipline) named the problem; F-51 names the structural answer.

**The pattern across the listener cluster (F-7, F-8, F-11, F-32, F-37, F-42, F-41) and beyond (F-6/F-48 check-context, F-30 worker-bypass-orchestrator, F-43 output-file reading):** skill-rule enforcement is insufficient. Skills tell agents what to do; agents reason from scratch each session and re-derive shortcuts. Each new finding adds another rule that fades the same way.

**The plugin alternative makes the interface the discipline.** If `xfleet listen` always writes `listen_bash_id` as part of spawning, there's no "forget to update state" path. If `xfleet send` for response-bearing types pre-verifies a live listener and refuses without one, "send and walk away" is impossible at the call site. Hooks intercept Bash patterns and inject check-context. Commands are on PATH; no path hallucination. Skills + scripts ship together in git.

**What plugin solves vs doesn't solve:**

| Plugin solves directly | Plugin doesn't solve |
|---|---|
| F-7 (allow-list one-line: `xfleet *`) | Protocol design (F-13/F-14/F-17 completion gates) |
| F-11 (no path ambiguity) | Plan-discipline cluster (F-29/F-31/F-39) |
| F-8 + F-37 (own-listener cleanup baked in) | BMAD epic decomposition (F-49) |
| F-32 + F-42 (atomic ACK→restart, send-with-verify) | API contract reconciliation (F-50) |
| F-41 (persistent listen as command default) | Skill-level disciplines without clean tool boundaries (F-34 always-writing-plans) |
| F-43 (skill text matches reality — no contradicting prohibitions) | |
| F-6 + F-48 partially (PostToolUse hooks inject check-context) | |
| F-25 + F-52 (atomic state-write helpers validate schema) | |
| Distribution to other operators | |

**Phased approach:**

- **Phase A — packaging.** Wrap existing scripts as plugin commands (`xfleet send`, `xfleet listen`, `xfleet ack`, `xfleet peek`, `xfleet concern-append`, `xfleet status`). Skill bodies rewritten to invoke `xfleet ...`. No behavioral change; pure packaging. **Solves F-7, F-11, "workers try 3 paths" friction.** Low cost; ships in days.

- **Phase B — invariant enforcement via baked-in command behavior + hooks.** Commands carry the discipline:
  - `xfleet listen` writes `listen_bash_id` on spawn (eliminates "forgot to update state").
  - `xfleet ack {NAME} {stream_id}` returns the message AND atomically respawns listen (eliminates "forgot to restart").
  - `xfleet send --type {response-bearing}` verifies live listener via `listen_bash_id` before sending; refuses if dead (eliminates "send-and-walk-away").
  - PostToolUse hook on Agent / Read / Grep / mcp__serena__* injects `check-context` (eliminates F-6 mechanism gap + F-48 discipline gap).
  - State-write helpers (`xfleet state set/get`) validate against schema (addresses F-25 + F-52 ad-hoc growth).
  - **Solves the listener-lifecycle cluster as a unit + much of F-6/F-48 + F-25/F-52 schema discipline.**

- **Phase C — DEFERRED with strong preference against (2026-05-04).** Originally rejected, briefly revived after `slack-channel` plugin exploration, now demoted again on operator feedback: **active running processes have lifecycle costs.** Operator's experience with `slack-channel`'s MCP server (Slack WebSocket connection cycles, reconnect storms) makes session-long MCP processes an explicit anti-goal for xfleet — even though xfleet's MCP would be much lighter (no external connections, only local Redis).

  **MCP transport reality:** there's no standard per-call/stateless MCP transport. stdio MCP servers are session-scoped processes, not per-call. So "first-class tools without active process" is essentially unavailable today.

  **What we'd otherwise have wanted from MCP, addressed without it:**
  - **Discipline in tool descriptions / loaded every session:** `SessionStart` hook (matchers: `startup` / `resume` / `clear` / `compact`) outputs the xfleet protocol primer — same prose slack-channel puts in MCP `instructions`, delivered via hook output instead. Loaded every session, every resume.
  - **Tool-description schemas:** Replaced by `xfleet-* --help` style usage strings + bash `set -euo pipefail` arg validation. ~80% of typed-schema benefit at ~10% of complexity (per plugin survey).
  - **Inbound message push:** Lost for now (workers still poll via `xfleet-listen`). Acceptable given stateless ops.
  - **Primary/client lock pattern (would have eliminated F-8/F-37 zombies):** Replaced by Phase B's bash_id ownership tracking + `xfleet-listen-status` script + per-session diagnostic-only foreign-process detection. Less elegant; sufficient.

  **Phase A success criteria (operator-defined 2026-05-04):** if `bin/` scripts achieve (a) **first-try invocation correctness** (agents reach the right script on first attempt, no path-variant trial-and-error) AND (b) **fixed invocation style** (single canonical form, one allow-list entry covering all `xfleet-*` commands, no per-variant permission prompts), Phase C is not needed. These are testable on Phase A landing.

  **Conditions to revisit Phase C** (high bar — all three must hold):
  1. Phase A's invocation correctness criteria fail in practice
  2. AND Phase B's hook-based enforcement provably fails to keep listener discipline consistent
  3. AND `SessionStart`-injected protocol primer fails to substitute for MCP `instructions` field

  Until all three: Phase C stays out of scope. `slack-channel` (`src/mcp.ts`, `src/ipc.ts`, `src/lock.ts`) is documented as the upgrade template if ever needed.

**Other options considered and why plugin wins:**

| Option | Verdict |
|---|---|
| Status quo (improve scripts + skills) | Rejected — F-35 says won't stick. Each new rule fades. |
| Standalone wrapper script on PATH (no plugin manifest) | Functionally a subset of plugin. Loses bundled skills, hooks, standard distribution. Stepping stone at best, but plugin's incremental cost over wrapper is small. |
| Settings.json hooks alone (no command surface) | Hooks need something to intercept. Without `xfleet *` commands, hooks would intercept raw `bash send.sh ...` patterns — fragile and bypassable. Hooks compose with commands; alone they're insufficient. |
| MCP server | Overkill for local ops. Rejected per Phase C. |
| Custom subagent for xfleet | Agents are dispatchable units, not callable tools. Doesn't fit the use case. |

**Why now (not after all findings settle):**

- Phase A is low-cost, unblocks ~5 findings immediately, and is reversible.
- Phase B is the *only* clean fix for the listener-lifecycle cluster (without it, the cluster's fixes are skill-rules that won't stick per F-35).
- Remaining findings (completion protocol, plan discipline, BMAD, API contracts) are protocol design that benefits from being implemented INTO the plugin rather than retrofitted.

**Implementation notes (not yet decided):**
- Plugin manifest path: `~/.claude/plugins/xfleet/` or new git repo `purujit/claude-xfleet`.
- Phase B hook design: PreToolUse for refusal patterns, PostToolUse for state-injection patterns, SessionStart for resume-mode loading.
- State-schema enforcement: JSON Schema file shipped with plugin; `xfleet state` validates writes.
- Migration path from current scripts: skills body rewrites, deprecation period for direct-script invocation.

Related to F-7/F-11 (path/allow-list — Phase A solves), F-8/F-32/F-37/F-41/F-42 (listener cluster — Phase B solves), F-25/F-52 (schema discipline — Phase B's state helpers solve), F-35 (the meta-finding this implements at the tooling layer), F-43 (worker.md prohibition can be removed when plugin owns the I/O), F-3 (permission model — plugin's allow-list is one entry).

### F-52. State files accumulate ad-hoc keys without schema discipline (2026-05-04) — RESOLVED via cluster 4b (sub of F-25; tight schema + narrow opt-in scratch + Python-in-bin validation)
**Sub-finding of F-25 (consolidated 2026-05-04).** F-25 documents the orchestrator-side schema drift; F-52 extends the same pattern across all worker state files with concrete evidence. Same fix vehicle (plugin Phase B's state helpers + JSON Schema).

**Source:** state-file inspection during cluster 1 discussion (2026-05-04).

`~/.claude/xfleet/shared/state-schema.md` documents a small core for each state file. Reality has drifted far beyond. Per current files (2026-05-04 inspection):

| File | Schema-documented core | Actual key count | Sample undocumented additions |
|---|---|---|---|
| `_orchestrator.json` | 3 (`cycles`, `last_all_idle_notify`, `last_round5_pause`) | 13 | `wave_1_x_backlog`, `clean_spec_deferrals`, `finalize_overrides`, `finalize_overrides_canonical_source`, `oracle_internal_overrides_noted_only`, `completed_oracle_web_contract_sweep`, `completed_spec_amendments`, `wave_1_observability_adds`, `compacting_workers`, `phase_complete` |
| `oracle.json` | ~5 base worker fields | 22 | `amendment_cycles_consumed`, `deferred_implementation`, `wave_1_llm_extract_commits`, `resolved_concerns_recent`, `prior_phase_complete_msg_ids` |
| `server.json` | ~5 base worker fields | 20 | `branch_checked_out`, `branch_created`, `completed_phases`, `pending_phases`, `pushed_range`, `resolved_concerns_appended`, `status_detail`, `wave_1_x_backlog_path` |
| `web.json` | ~5 base worker fields | 14 | `listen_loop_bash_id` |

**Three concrete problems visible in the data:**

1. **Per-session ad-hoc accumulation.** Each new wave/feature adds its own keys (`wave_1_x_backlog`, `wave_1_llm_extract_commits`, `wave_1_observability_adds`) that should likely be transient session state, not durable schema. They never get cleaned up.

2. **Cross-worker inconsistency.** Same logical concept gets different names per worker:
   - `branch` (web, oracle) vs `branch_checked_out` + `branch_created` (server)
   - `resolved_concerns` (web) vs `resolved_concerns_appended` (server) vs `resolved_concerns_recent` (oracle)
   - Each worker invented its own dialect.

3. **Asymmetric adoption of cross-cutting fields.** The most important data point for cluster 1: **only `web.json` has `listen_loop_bash_id`.** Oracle and server don't track it. Workers started doing the right thing (tracking listener ownership by bash_id) — but only one of three actually adopted it. F-35 in action: skill-level discipline produces uneven adoption.

**Why this matters beyond cosmetics:**

- **Schema is meant to be a contract.** Fields like `human_engaged`, `phase_emissions`, `directive_log`, `task_log` are proposed by F-14/F-17/F-22/F-23 as authoritative state. If the existing schema is already drifting, those proposals land into a file that nobody trusts.
- **Recovery is fragile.** F-13's "orchestrator stalls" partly stems from completion-tracking state that lives in undocumented fields — restarts can't reliably reconstruct what was tracked.
- **Cross-tool consumption breaks.** A future `xfleet status` command (per F-7 wrapper / F-51 plugin Phase A) wants to read state files reliably. If every worker has a different dialect, the command needs N parsers or a normalizer.

**Fix directions (not yet implemented):**

1. **JSON Schema as enforced contract.** Ship `~/.claude/xfleet/shared/state-schema.json` (machine-readable) alongside the existing `state-schema.md` (human-readable). Required + optional fields per file type. Validate on every write.

2. **Atomic state-write helpers** (F-51 Phase B). `xfleet state set {name} {key} {value}` validates against schema before writing. `xfleet state set` refuses unknown keys unless `--allow-extra` is passed. Forces deliberation: if you want a new key, you justify it (and probably propose a schema update).

3. **Reserved namespace for transient session-scoped keys.** State files get a top-level `session_scratch: {}` object for ad-hoc per-session data that doesn't belong in the durable schema. `wave_1_x_backlog` and similar live there; gets wiped by `/cleanup`. Durable schema stays clean.

4. **Migrate cross-worker inconsistencies.** Pick canonical names (`branch`, `resolved_concerns`, etc.); rewrite worker skills to use the canonical names; add migration in `xfleet state migrate` for existing files.

5. **F-25 + F-52 land together.** F-25 is the documentation discipline; F-52 is the worker-side enforcement. Same fix surface (state-schema + plugin-owned state helpers).

6. **Audit cadence.** `xfleet state audit` (or similar) lists per-file keys vs schema; flags drift. Run in `/cleanup` pre-flight and at session start. Catches drift early.

**Specific to the cluster 1 listener fix:** `listen_bash_id` becomes a schema-required field on every worker state file. Plugin's `xfleet listen` writes it atomically; no other path. Web's existing field becomes the canonical name (or rename to `listen_bash_id` consistently); oracle and server adopt by virtue of using `xfleet listen` instead of raw `listen.sh`.

Related to F-25 (orchestrator-side schema drift — same pattern), F-51 (plugin Phase B is the enforcement vehicle), F-32 (verify-before-claim depends on a reliable `listen_bash_id` field — this finding ensures it exists), F-13 (completion tracking depends on schema-stable orchestrator state), F-14/F-17/F-22/F-23 (proposed orchestrator fields land cleanly only after schema discipline holds).

---

### F-53. `prepare-compact` handoffs should capture active skills + in-session user directives (2026-05-04, applies beyond xfleet) — RESOLVED via cluster 2 (local `prepare-compact` skill gains Active-Skills + In-Session-Directives + Resume-Instructions sections; resume flow reads + re-engages; absorbs F-47)
**Source:** cluster 2 discussion (2026-05-04). Surfaced as a cleaner alternative to F-47's xfleet-specific fix.

**Note:** `prepare-compact` is a local personal skill at `~/.claude/skills/prepare-compact/` (NOT a `superpowers:` skill). xfleet-specific addendum lives at `~/.claude/skills/prepare-compact/xfleet.md`. Fix lands in the local skill.

**Observation:** `prepare-compact` writes a handoff capturing in-flight task state, recent decisions, and resume instructions. It does NOT explicitly capture:
- Which discipline skills were active during the session (e.g., `superpowers:subagent-driven-development`, `superpowers:writing-plans`, `superpowers:executing-plans`, xfleet phase skills, project-specific skills, other local skills)
- User-supplied in-session instructions, preferences, or temporary directives that aren't yet in CLAUDE.md or memory ("don't run pre-commit hooks for this task," "use Sonnet for these subagents," "skip the plan-reviewer pass on this iteration")
- Current agent dispositions / standing operator decisions for the in-flight work

After `/clear` + resume, the next session has the artifacts but not the discipline that was actively running. Agent re-derives behavior from skills + memory; in-session directives evaporate.

**Generality — not xfleet-specific:**
Same pattern affects any `/clear`-then-resume flow: vanilla `/prepare-compact` runs, user `/clear`s, new session reads the handoff but doesn't know which skills the prior session had engaged. F-47 (phase skill not auto-engaged on `/worker --resume`) is the xfleet instance of this; the underlying gap is in `prepare-compact` itself.

**Fix direction (in local `prepare-compact` skill, not xfleet):**

1. **Add "Active Skills" section to handoff template.** Lists every discipline skill engaged during the session — auto-detect via skill-invocation history if available, or solicit from agent self-report at compact time. Format:
   ```
   ## Active Skills (re-engage on resume)
   - superpowers:subagent-driven-development (engaged at T+15min for implement loop)
   - xfleet phase: implement (engaged at T+0)
   - superpowers:writing-plans (engaged at T+45min for plan revision)
   ```

2. **Add "In-Session User Directives" section.** Captures verbal/typed directives the user gave that aren't durable (not in CLAUDE.md, not memorized, just "for this session"). Examples:
   - "Don't pause for confirmation between tasks"
   - "Use the Sonnet model for spec-reviewer"
   - "Skip the prepare-compact prompt at 70%; go to 80%"
   - "Treat F-N as resolved; don't re-raise"

3. **Add explicit "Resume Instructions" prefix** at the top of every handoff:
   ```
   ## Resume Instructions
   Before continuing this work:
   1. Invoke: superpowers:subagent-driven-development
   2. Re-engage: xfleet phase=implement (read ~/.claude/xfleet/phases/implement.md)
   3. Apply user directives below
   ```
   Resume flow (any agent reading the handoff) executes these before resuming work.

4. **Resume side: explicit re-engagement step.** `xfleet resume` (per F-51) reads handoff and outputs the resume instructions verbatim into context, prompting the agent to invoke listed skills. Same pattern works for non-xfleet `/clear`+resume — agent reading handoff sees the instructions and acts.

**What this fixes:**
- **F-47 collapses into this.** Phase skill auto-engagement on resume = "handoff says invoke X; agent invokes X." No xfleet-specific hook needed; works for any phase or discipline.
- **In-session directives survive `/clear`.** Currently invisible after restart; now explicit.
- **Cross-cluster benefit.** Cluster 2 (resume), cluster 3 (plan discipline, where in-session "use Sonnet for this reviewer" directives matter), cluster 4 (completion gates with operator standing decisions) — all benefit.

**Why this is a local `prepare-compact` change, not xfleet:**
- `prepare-compact` is a personal local skill at `~/.claude/skills/prepare-compact/SKILL.md`. The xfleet-specific addendum is at `~/.claude/skills/prepare-compact/xfleet.md` and gets loaded via the xfleet phase context.
- The Active-Skills + In-Session-Directives sections are generic — every session benefits regardless of xfleet involvement. They belong in `SKILL.md` (the base skill), not in `xfleet.md`.
- xfleet's specific addition lives in `xfleet.md` (phase, current_task, branch, listener state, etc.) — already partially there per `project_xfleet` memory; F-53 layers the generic skill+directive capture on top.
- Net layout after fix: base `SKILL.md` produces the generic handoff sections; xfleet (and any other domain) extends with their own addenda; resume flow reads both.

**Cross-references:**
- **F-47** (phase skill not auto-engaged) — solved by this; F-47's resolution becomes "F-53's handoff format covers it."
- **F-12** (resume leaves work dormant) — handoff is the bridge artifact; F-53 makes its format complete.
- **F-10** (handoffs at every phase transition) — extends F-10's per-phase handoffs with the active-skill capture.
- **F-35** (skills as durable discipline) — F-53 makes active-skill state survive `/clear`, closing one of F-35's enforcement gaps.
- **F-51** (xfleet plugin) — `xfleet resume` reads F-53-format handoffs; doesn't need to encode skill-loading itself.

---

### F-54. Git-versioning of plans/specs for diff-based reviewer reads (placeholder, 2026-05-04) — RESOLVED (cluster 4c, 2026-05-04): rejected; manual `-vN.md` snapshots are the diff mechanism instead
**Source:** user observation during cluster 3 discussion (2026-05-04). Captured for later; not part of current work.

**Observation:** today's plans and specs evolve in place during a phase (or via versioned files per F-27, with `-vN` suffixes). Reviewer agents read the full file each pass — re-evaluating content they've already approved. They have no efficient way to scope review to "what changed since last pass."

**User-proposed direction:** add git-versioning (or git-aware tracking) for plans/specs so reviewer agents can review the diff between versions, not the full file. Cuts reviewer token use, focuses attention on actual deltas, and makes "what specifically changed" auditable.

**Open questions (deferred):**
- Versioning mechanism: in-repo git (tracked changes), out-of-repo session git (session dirs become git repos), per-spec git tags, or simpler — frontmatter-tracked content hashes + diffs computed at review time?
- How does this interact with F-27's `-vN` versioning? Are `-vN` files the diff anchors, or replaced by git refs?
- Does this apply only to plans/specs, or also reviews, resolutions, alignment artifacts?
- Reviewer-agent prompt changes — pass diff + base version, not full file?

**Cross-references:** F-27 (versioned outputs from finalize-spec), F-31 (re-review on revision — diff-based review reduces re-review cost), F-21 (review findings block phase-complete — diffs let reviewers focus on what was added/changed), F-19 (per-repo durable artifacts — git-tracked locations are natural).

Placeholder; full design deferred.

### F-55. xfleet message-flag confusion: `--type` / `--phase` / `--name` overlap (2026-05-04) — RESOLVED via cluster 4e (single `xfleet` binary with subcommand-per-message-type; `--type` flag eliminated, `xfleet send` retired)
**Source:** user observation during cluster 3 discussion (2026-05-04).

**Observation:** workers struggle with the current `xfleet-send` flag set:
```
xfleet-send {to_name} --type phase-complete --phase plan --path ... --summary "..."
```
Three flags carry conceptually overlapping things:
- `--type` — message kind (`concern` / `phase-complete` / `resolution` / `directive` / `task` / etc.)
- `--phase` — which phase the message refers to (`plan` / `repo-spec` / `implement` / etc.)
- `{to_name}` (positional) or `--name` — worker identifier

Agents conflate them — write `--type plan` (wrong; that's a phase), `--phase phase-complete` (wrong; that's a type), or get confused about whether `--phase plan` modifies the type or the recipient. Real ergonomics issue producing real-time errors.

**Fix direction (Phase A territory):**

1. **Subcommand-per-message-type.** Eliminate `--type` entirely. Each message kind becomes its own subcommand:
   ```
   xfleet phase-complete server --phase plan --path ... --summary "..."
   xfleet send-concern server --concern_id C-7 --path ... --summary "..."
   xfleet resolution server --concern_id C-7 --path ...
   xfleet directive oracle --scope task --path ...
   ```
   Type is implicit in subcommand name; no flag confusion. Tab-completion works naturally.

2. **Argument naming clarity.** `--phase` becomes `--for-phase` or `--regarding-phase` where it remains needed. Recipient stays positional (clearer than `--name`).

3. **Allow-list pattern.** With subcommands, allow-list becomes one line: `Bash(xfleet-* *)` or per-subcommand entries if finer scope wanted.

4. **Skill body rewrites.** Phase skills + worker/orchestrator skill bodies updated to use subcommand syntax.

**Why this matters beyond ergonomics:** flag confusion produces invalid messages that orchestrator silently rejects or peers misinterpret. Loss of trust in the protocol. Ties to F-35 (skill-rule discipline of "remember the right flag" doesn't stick — structural fix in command surface needed).

Related to F-7 (allow-list patterns — subcommands simplify it), F-11 (path/invocation ambiguity — subcommand naming is part of the same fix surface), F-51 (Phase A — subcommand structure is part of plugin packaging).

---

### F-56. Cross-repo artifact naming inconsistency + no master index per wave (2026-05-04) — RESOLVED via cluster 4b (grep + wikilinks `[[name]]` free baseline; auto-generated `xfleet/{slug}/index.md` only when concrete trigger hits; graphify/embeddings explicitly out of scope)
**Source:** cluster 4b investigation (2026-05-04). Inventory of `docs/superpowers/` across workspace + server + web + oracle for Reducto wave-1.

**Observed pattern (Reducto wave-1):**

Five coexisting naming conventions for the same wave:
- `xfleet-reducto-migration-wave-1-*` (xfleet handoffs, all 3 worker repos)
- `reducto-migration-wave-1-*` (oracle's separate handoffs)
- `reducto-wave-1-*` (server's mixed)
- `reducto-wave1-*` (web — no hyphen)
- `wave-1-*` / `wave-1x-*` / `wave1-*` (variants)

Multiple competing backlog files:
- `server/.../plans/2026-04-25-reducto-wave-1-x-backlog.md`
- `web/.../plans/2026-04-25-reducto-wave-1-x-backlog.md`
- `oracle/.../scratch/cleanup-backlog.md` (different name + different directory)
- workspace: no consolidated backlog

Multi-source specs/PRDs:
- workspace (orchestrator): the cross-repo PRD + a consolidation summary
- oracle: 2 specs of its own + 2 ADRs covering wave-1 sub-decisions
- server, web: no specs (consumed orchestrator's)

**No master index exists** that says "for wave-1, here are all artifacts across all repos." Discovery requires grepping each repo with all five naming conventions.

**Impact:**
- Anyone joining mid-wave (or returning post-`/clear`) cannot quickly answer "what's the state of wave-1?" without manual reconnaissance across 4 repos.
- Worker self-classification fragmented — backlog items live in different file types (plans/, scratch/, handoffs/), making `/cleanup` and `/finalize-spec` blind to half of them.
- Duplication risk: same content (e.g., wave-1 review findings) stored in oracle's research/ AND web's research/ AND server's research/ with similar but not identical names.

**Fix direction (not yet implemented):**

1. **Naming convention enforced by xfleet tools.** Plugin tools that create wave artifacts use a single canonical pattern: `{branch-slug}-{phase|kind}` (e.g., `xfleet-reducto-migration-wave-1-implement`). Other names refused. Plugin's `xfleet-handoff write`, `xfleet-finalize-spec`, etc. apply the convention automatically. Operator can't write to a non-canonical path via these tools.

2. **Per-wave master index at orchestrator.** `workspace/docs/superpowers/xfleet/{slug}/index.md` (path renamed by cluster 4c, 2026-05-04 — was `branches/{branch-slug}/index.md`) — auto-generated by xfleet tools as artifacts land. Lists every artifact per repo, with link + one-line description. Built incrementally; full rebuild via `xfleet-index rebuild --slug {slug}` reads each repo's `docs/superpowers/xfleet/{slug}/` and writes the index.

3. **Wave-scoped subdirectory.** Per F-19 + F-26's session-bundle proposal, extend to wave-level: `{repo}/docs/superpowers/xfleet/{slug}/` (path renamed by cluster 4c, 2026-05-04 — was `branches/{branch-slug}/`) houses everything wave-specific (handoffs, plans, reviews, backlogs). Standard repo-level dirs (`plans/`, `specs/`, etc.) reserved for non-wave work.

4. **Migration of existing wave-1 artifacts.** Optional one-shot: `xfleet-migrate-wave reducto-migration-wave-1` reads all matching files across 4 repos, normalizes names, writes to canonical location. Probably skip — the user's call earlier was "no migration."

**Cross-references:**
- **F-19** (per-repo durability) — extends F-19's per-repo session-bundle proposal to wave-level.
- **F-26 / F-27** (init-vs-clean, versioned outputs) — same scope; wave-level is just the cross-cutting dimension above session-level.
- **Cluster 4b** (this finding surfaced during) — orchestrator-level backlog/deferred is one specific case of the master-index pattern.
- **F-49** (BMAD epics) — if specs decompose into epics, the index needs to cover epic-level artifacts too.

**Belongs in cluster 4c** (per-repo durability + path migration) — same fix surface; F-19's resolution should explicitly cover this finding.

**Discovery-layer scope (validated 2026-05-04 via research, see `docs/superpowers/research/2026-05-04-doc-discovery-research.md`):**

xfleet's scale (30-50 markdown files/wave, fixed paths, 6-10 types) is well below the threshold where graph/embedding infrastructure pays off. Karpathy's "LLM Wiki" gist (the principle the operator referenced) explicitly says embeddings/graphs are unnecessary at moderate scale (~100 sources, hundreds of pages); his own recommendation is grep + curated `index.md`. Graphify (the tool the operator asked about) is a third-party riff optimized for messy multi-modal corpora — wrong fit for our typed/pathed markdown tree.

**Resulting upgrade ladder (cheapest viable):**

1. **Today (no work):** grep + fixed paths. Sufficient until pain materializes.
2. **First upgrade — auto-generated `xfleet/{slug}/index.md`** (this finding's fix #2; path renamed by cluster 4c, was `branches/{slug}/`). ~50 lines of shell/python in plugin's `bin/`, runs at end of each phase. Flat list per artifact type with one-line summary (first H1 + frontmatter status). Zero LLM cost.
3. **Second upgrade (only if #2 insufficient):** `[[wikilinks]]` between cross-referenced artifacts (resolution → concern → spec). Still markdown-native; still grep-compatible.
4. **Probably never:** embeddings, Neo4j, knowledge graphs, Graphify-style tooling. Reserved for when a concrete discovery query exists that grep + index can't answer in <2s.

**Trigger criteria for moving to step 2:**
- An agent asks "what's pending for wave-N?" and grep returns >20 hits across types, OR
- A worker can't find a decision it knows exists, OR
- Operator observes >2 misfind incidents within a wave.

Until any trigger hits, the index work stays optional — F-56's resolution is "build the script when needed, not preemptively." This is consistent with F-49's BMAD principle (don't build infrastructure until the pain is real).

---

### F-57. Agents construct compound bash commands that trigger permission prompts unnecessarily (general, 2026-05-04) — CLOSED OUT-OF-SCOPE (2026-05-11) — general agent-infra problem, not xfleet-solvable; local mitigation added to `~/.claude/CLAUDE.md` Workflow Rules extending the "No `git -C`" pattern
**Source:** user observation 2026-05-04 during prepare-compact's check-context invocation. **Not xfleet-specific** — pattern observed across all agent sessions.

**Pattern observed:** agents defensively construct bash commands with compound forms that don't match simple allow-list patterns:
- Logical OR fallbacks: `cmd 2>/dev/null || echo "fallback"`
- Compound chains: `cd path && cmd && other_cmd`
- Stderr redirects: `cmd 2>&1`
- Subshells: `$(cmd)` or backticks
- Tilde expansion: `~/path/script` (when `Bash($PATH-cmd *)` would match the bare name)
- Loops: `for x in ...; do cmd; done`

A simple allow-list like `Bash(check-context.sh *)` doesn't match `~/.claude/skills/check-context/check-context.sh 2>/dev/null || echo "..."` — the entire compound is treated as a new command pattern, requiring permission. Result: even already-allowed commands trigger prompts when wrapped defensively.

**Why agents do this:**
- Defensive programming habit (graceful degradation if file missing)
- Robustness (handle missing tools without crashing)
- Compactness (one line vs multiple sequential calls)
- Same shell idioms humans use

**Cost:** every defensive bash invocation = a permission prompt, even when the underlying command would be allowed in simpler form. Friction accumulates across the session.

**Distinction from F-7 / F-11:** F-7 / F-11 were about xfleet-specific script invocation. F-57 is broader — applies to all agent bash usage including check-context, file existence checks, conditional cleanup, etc.

**Fix directions (not yet implemented):**

1. **Agent-level discipline (skill update):** Add to general agent guidance — "prefer simple bash forms over defensive compounds; use the Read tool for missing-file fallback (Read returns error visibly) rather than `cmd 2>/dev/null`. Use multiple sequential bash calls rather than `&&` chains when arguments differ — each simpler form might match allow-list."

2. **Plugin / settings allow-lists for known-safe compound patterns:** if a specific compound form is recurring and safe (e.g., `bash ~/.claude/skills/*/check-context.sh *` with stderr redirect), pre-allow it. Operator-driven, not auto-derived.

3. **Permission system enhancement (Claude Code roadmap?):** if the harness can decompose `cmd1 || cmd2` into "approve cmd1; if it fails, approve cmd2 separately" rather than treating the whole compound as one unallowed pattern, this disappears.

4. **`fewer-permission-prompts` skill** (already exists per available-skills list): designed to scan transcripts and add allow-list patterns for recurring read-only commands. Run periodically to catch compound forms that surface repeatedly.

**Operational mitigation today:** when the operator notices the same compound form prompting repeatedly, manually add to settings allow-list. Tedious but effective.

**Cross-references:**
- F-7 / F-11 (xfleet-specific allow-list patterns — share the compound-form root cause)
- F-43 (worker.md prohibitions vs reality — agents work around via `Bash` to read .output files; same defensive-pattern theme)
- F-51 Phase A (xfleet plugin's settings.json ships default permission allow-list — solves xfleet-specific cases but not general agent bash hygiene)
- F-35 (skills as durable discipline — agent-level fix #1 above is the pattern: encode in skill, not just memory)

This is broader infrastructure pain not solvable inside xfleet alone; flagged here for visibility while we work the xfleet-specific cases.

### F-58. Worker `standby` mode is a self-drive gate; orchestrator inbound is always honored (2026-05-07) — RESOLVED via own Decisions Log entry (2026-05-07; closes cluster 2's open scope; codifies single-track `current_task` model)
**Closes the open scope of cluster 2's `xfleet resume --standby` flag.** Cluster 2 ratified that the flag exists; this finding codifies what the worker does (and does NOT do) while in standby.

The orchestrator is the human's proxy (F-30). Every orchestrator dispatch is human-approved. Therefore `standby` suppresses ONLY worker self-initiative — specifically, F-12 fix #1's auto-continuation of dormant in-flight tasks (`status=working` resume). Standby does NOT queue or gate orchestrator-driven inbound. The worker executes inbound directives / tasks / phase signals / resolutions as they arrive; orch's send IS the human's go-ahead.

**Why this matters as a finding** (not just an implicit corollary): the inverse drift is a real failure mode. A worker that thinks "human told me to standby, so I should ignore everything until human explicitly says continue" inverts F-30 (workers second-guessing orch) and generates spurious permission round-trips on the normal human → orch → worker dispatch path.

**Operational scope of `--standby`:**
- On resume: skip F-12 fix #1's auto-continue of in-flight `status=working` task. Worker holds its own forward-drive.
- Still does: drain queued inbox, restart listener, process orch inbound as normal.
- Lifted by either: an orch dispatch (worker executes it directly — no separate "continue" step needed), OR an explicit human "continue" via `xfleet continue` (or orch-relayed `directive --expected_action continue`).

**Task resumption — single-track model:**
- `current_task` in worker state always reflects the latest authoritative task, regardless of source. Orch directives during standby may update `current_task` in place; that update IS authoritative because orch is the human's proxy.
- On continue: worker reads `current_task` from state and resumes whatever it currently points to. No "original pre-standby task" preserved separately.
- Two-track state (preserving a snapshotted pre-standby task as well) would invert F-30 — would treat orch's intervening updates as advisory rather than authoritative. Single-track is the design.
- **Edge case** — if `current_task` is empty when human says continue (e.g., orch sent a directive that cleared the task without setting a new one), worker reports "no current task; awaiting direction" rather than guessing. **The human drives next steps — via orch or directly — rather than the worker assuming.** State-driven, not heuristic.

**Edge case** (user's framing): "orch instructions come in while I'm actively involved directly with a worker — this should never happen." Single-channel discipline — human → orch only, not human-direct + orch-also. If it did happen, the worker still executes orch's send (F-30); the protocol violation is on the human's side, not the worker's.

**Fix vehicle:** No new mechanism required beyond Cluster 2's locked `--standby` scope. F-58 makes the scoping explicit and adds an `xfleet continue` Bash command (Phase B) for the explicit unpause path. `messaging.md` documents standby semantics in a small section.

**Implementation notes (not yet implemented):**
- `xfleet resume --standby` sets `state.standby = true`; resumes everything except F-12 fix #1's auto-continue.
- Always-on inbound handlers ignore `state.standby` for orch messages — execute as normal.
- `xfleet continue` (new Phase B command) sets `state.standby = false`, then invokes F-12 fix #1 logic on current `current_task`.
- Worker state schema (cluster 4b): `standby: bool` field.
- `messaging.md` standby semantics section: "standby suppresses self-drive only; orch inbound is always honored."

Related to cluster 2 (closes its open scope), F-12 (fix #1 is what standby suppresses), F-30 (authority hierarchy underpins F-58's "orch is authoritative" rule), F-22 (`directive --expected_action continue` is one valid unpause path), F-44 (workers near warn-threshold may need to clear-then-resume; standby is one gating tool).

---

## Add new findings below as they surface

### F-59. architect-review consolidation — per-repo agent files drift from canonical global skill (2026-05-11) — RESOLVED via own Decisions Log entry (2026-05-14; prd-* pattern adopted: full-content global agent + dispatcher skill; oracle/sidekick repo-local committed agent file removed; committed `planning-workflow.md` made tool-agnostic; per-dev `worker-config.md` updates)
**Source:** Surfaced during cluster 5 spec post-discussion (2026-05-11) when reviewing worker-config.md across repos for the architect-review lift work.

The `architect-review` skill exists globally at `~/.claude/skills/architect-review/SKILL.md` with 10 dimensions (Correctness, Edge Cases, Scalability, Security, Operability, Complexity, Dependencies, Risk, Reuse-First, Adversarial), intensity gating (`standard` / `high` / `critical`), auto-ADR at critical intensity, and `worker-config.md`-driven language lens + `convention_files:`. Cluster 4m locked architect-review as the canonical reviewer for xfleet phase reviews.

**Per-repo drift surfaced (verified 2026-05-14):**

- **oracle, sidekick (worktree of oracle):** `worker-config.md` (personal, not committed) describes `architect-reviewer` as a "thin Task-isolation wrapper that invokes the globally-installed `architect-review` skill." The actual file at `.claude/agents/architect-reviewer.md` (committed) is a full 7-dim independent implementation — missing dims 8 (Risk), 9 (Reuse-First), 10 (Adversarial); no `--intensity` gating; no auto-ADR at critical; hardcoded "primarily Python" lens; no `worker-config.md` awareness. Oracle's and sidekick's files are byte-for-byte identical (shared via git worktree, not separate drift). Drift between described intent and actual code — F-35 pattern (description and reality diverged).
- **server:** `worker-config.md` declares `tech-architect`, `integration-architect`, `mongodb-architect` (specialized stack-specific reviewers). Server has no `architect-reviewer` agent file. Decision (2026-05-11): server keeps its specialized agents AS WELL; `architect-review` becomes available as additional default per cluster 4m. Per-case decision which to use. No specialized-agents migration in scope.
- **web:** `worker-config.md` declares `architect-pm` (UX-focused, from product-manager repo) + 3 Vercel skills (`react-best-practices`, `web-design-guidelines`, `composition-patterns`). Web has no `architect-reviewer` agent file. Decision (2026-05-11): web keeps Vercel skills; `architect-pm` vs `architect-review` direct comparison deferred to separate evaluation. Both become available; per-case decision.

**Resolution (2026-05-14) — prd-* pattern: full-content agent + dispatcher skill, no committed wrapper.**

Following the existing convention for global review agents (`prd-reviewer`, `prd-risk-analyst`, `prd-boundaries-reviewer`, etc. — all standalone agent files in `~/.claude/agents/` invoked by a dispatcher skill), with no repo-committed wrapper artifacts:

1. **New global agent** at `~/.claude/agents/architect-reviewer.md` — holds the full 10-dim review system prompt (content lifted verbatim from the prior skill body). Single source of truth.
2. **Skill rewrite** at `~/.claude/skills/architect-review/SKILL.md` — slim dispatcher: parses `$ARGUMENTS` for plan path (required) + optional `--intensity <standard|high|critical>`, dispatches the `architect-reviewer` agent via the Task tool with the parsed args, returns the agent's output verbatim. Preserves the `/architect-review <plan-path> [--intensity <level>]` slash-command surface; routes through the agent transparently.
3. **References files** at `~/.claude/skills/architect-review/references/{risk,reuse-first,adversarial}.md` — unchanged. The agent reads them at runtime when the corresponding dim runs (absolute paths in agent body; no relocation).
4. **Repo-local committed agent file removed:** `oracle/.claude/agents/architect-reviewer.md` deleted (also clears sidekick's worktree copy). Other devs lose this file on pull — intentional; the underlying skill+agent are personal and cannot be assumed to be present in another dev's `~/.claude/`.
5. **Committed `planning-workflow.md` made tool-agnostic** (oracle/sidekick share one file via worktree). Step 4 changes from "Run **architect-reviewer** agent as a background task on the finished plan" to "Run an architectural review on the finished plan"; closing line changes from "**Always run architect-reviewer**..." to "**Always perform an architectural review**...". Other devs without a personal reviewer install fall back to inline Claude review against the convention files declared in their setup. Steps 5-6 and the solution-explorer lines untouched.
6. **Per-dev `worker-config.md` updates (personal, not committed):**
   - **oracle:** rewrite `architect-reviewer` entry to point at `~/.claude/agents/architect-reviewer.md` (drop the obsolete `.claude/agents/architect-reviewer` repo-local path reference).
   - **server:** append `architect-reviewer` entry as "additional default" alongside `tech-architect`/`integration-architect`/`mongodb-architect`. Per-case decision which to use.
   - **web:** append `architect-reviewer` entry alongside `architect-pm`. Both available; per-case decision; `architect-pm` vs `architect-review` direct comparison still deferred per locked F-59 decision.

**Sharing the new agent + skill** with other devs handled separately (out-of-repo) — e.g., team onboarding doc, personal-tooling-share channel. Not committed to any repo, per the "no committed wrapper" property.

**Out of F-59 scope — separate handling:**

- **`oracle/.claude/agents/solution-explorer.md`** (also committed, identical in sidekick worktree) — same "logic-in-repo-vs-personal-global" question may apply if its underlying logic is similarly personal. Deferred per user direction: oracle-only usage so far; generalization can come later if needed.
- **Server's specialized-agents → `convention_files:` pattern migration** — interesting future work but explicitly out of F-59 scope; would mirror oracle's pattern across stacks (Kotlin equivalents for `tech-architect`/`integration-architect`/`mongodb-architect`).
- **`architect-pm` vs `architect-review` direct comparison for web** — deferred per locked F-59 decision; both available; per-case use.

**Constraints (carried from original finding):**

- `architect-review` skill itself is already at canonical global location — no lift work outside the skill body content move.
- Multi-model variant of architect-review (cross-model — Codex reviews Claude-authored, etc.) explicitly dropped during cluster 5 deliberation: Codex CLI not available in environment.

Cross-refs: cluster 4m (architect-review canonical for xfleet phase reviews); cluster 4o-F-46 (asymmetry pushback — described-vs-actual drift was the asymmetry); F-35 (skills as durable discipline — described behavior must match actual implementation); F-51 Phase A (plugin packaging — consolidation lands as part of Phase A bundle if/when the plugin transformation proceeds); `prd-reviewer` / other `prd-*` agents (architectural pattern adopted).

### F-60. Architecture Guard — continuous post-implementation architectural governance (2026-05-11)
**Source:** Spec Kit community extension *Architecture Guard* (v1.8.1), surfaced via spec-kit-broader-skills research subagent during cluster 5 deliberation.

`architect-review` is one-shot pre-implementation critique — it stress-tests a written plan before code is written. There is no continuous post-implementation surface that catches architectural debt introduced across waves: boundaries violations that snuck in, contract drift after-the-fact, coupling that crept in, layering violations that compounded.

`x-vergence-check` (cluster 5) handles cross-source verification at Integration Point close (post-code, pre-PR; cross-repo contract focus). Distinct from continuous architecture governance — IP-scoped and contract-focused, not wave-spanning and architecture-focused.

**Proposed direction (fix discussion deferred to separate session):**

A standalone skill (likely `architecture-guard` or similar) that:

- Fires after `/cleanup --final` OR at end of implement phase (timing TBD)
- Detects boundaries violations, post-lock contract drift, coupling that crept in
- Cross-references current code state against locked architectural decisions (cluster 4l Decisions Log, ADRs, design-principles.md per cluster 4n)
- Produces refactor tasks added to backlog (NOT blockers — non-blocking governance per the Spec Kit extension's framing)
- Per-repo or cross-repo scope TBD

**Composition with locked clusters:**

- Cluster 4c (cleanup-model revision) — `--final` timing is a natural firing point
- Cluster 4l (Decisions Log + spec.md amendments) — Architecture Guard reads these as inputs
- Cluster 4n (design-principles.md) — Architecture Guard verifies adherence
- Per-repo ADRs (cluster 4c durable list) — read as locked architectural decisions

**Distinct from:**

- `architect-review`: one-shot pre-implementation (Architecture Guard is continuous post-implementation)
- `x-vergence-check`: IP-scoped cross-repo contract verification (Architecture Guard is wave-spanning architecture verification)
- `/code-review`: per-PR code review (Architecture Guard runs at wave boundaries, not per-PR)

Cross-refs: F-51 (plugin transformation — Architecture Guard ships as plugin skill); cluster 4c (`--final` timing); cluster 4l (Decisions Log + spec.md as input); cluster 4n (design-principles.md adherence); F-59 (consolidation; same reviewer-family infrastructure once F-59 lands).

### F-61. grill-with-docs — adversarial design-phase plan grilling + glossary maintenance (2026-05-11)
**Source:** mattpocock skills repository (https://github.com/mattpocock/skills/tree/main/skills/engineering/grill-with-docs), surfaced via user share during cluster 5 deliberation.

The `superpowers:brainstorming` skill is collaborative dialogue-driven design but doesn't actively challenge fuzzy terminology or maintain a project glossary. Domain model + locked terminology drift silently as designs accumulate; new designs invent new words for existing concepts; CONTEXT.md / domain-model docs (where they exist) don't get cross-checked during design.

**The grill-with-docs pattern (from mattpocock):**

- "Grilling session that challenges your plan against the existing domain model, sharpens terminology, and updates documentation (CONTEXT.md, ADRs) inline as decisions crystallise"
- Process: interview relentlessly; walk decision tree one-by-one; recommend an answer per question; cross-reference code with stated assumptions; challenge ambiguous terms ("your glossary defines 'cancellation' as X, but you seem to mean Y — which is it?"); discuss concrete scenarios to force precision
- Artifacts: CONTEXT.md (glossary — strictly devoid of implementation details; created lazily on first term resolution) + ADRs (only when 3 criteria met: hard-to-reverse + surprising-without-context + real-trade-off; uses ADR-FORMAT.md template)

**Constraint:**

`superpowers:brainstorming` is a third-party skill from the superpowers plugin — cannot be edited directly. Absorption requires either:

- A standalone skill that runs alongside or instead of brainstorming for designs that benefit from domain-grilling
- Local fork of brainstorming with grill-with-docs additions
- Upstream PR to superpowers
- Or: invoke grill-with-docs as a sibling skill that brainstorming hands off to when terminology pressure surfaces

**Proposed direction (fix discussion deferred to separate session):**

- Author a standalone skill (likely `grill-with-docs` or `design-grilling`) modeled on mattpocock's pattern
- Adapt to workspace conventions: ADR location (per cluster 4c — per-repo `{repo}/docs/adr/`), CONTEXT.md location (per-repo or per-xfleet-wave TBD), glossary scope (per-repo vs cross-repo)
- Cross-reference with `capture-decision` skill (ADR creation overlap — could compose; capture-decision handles ADR write, grill-with-docs handles the trigger)
- Composition with brainstorming TBD — sibling skill the user invokes after brainstorming reaches a fuzzy-terminology blocker, OR standalone for designs that need domain grilling from the start

**Distinct from:**

- `brainstorming` (third-party): collaborative dialogue-driven design; not adversarial; doesn't maintain glossary
- `capture-decision`: writes ADRs but doesn't grill for the 3-criteria check (hard-to-reverse + surprising-without-context + real-trade-off)
- `prd-review` adversarial dimension: hostile reinterpretation of a written PRD (post-design); grill-with-docs fires during design, not after

Cross-refs: third-party superpowers `brainstorming` skill (composition TBD); `capture-decision` skill (ADR write overlap); cluster 4c (per-repo ADR durable location); cluster 4n (design-principles.md — grill-with-docs could enforce adherence to principles during design); cluster 4o-F-46 (asymmetry pushback — fuzzy terminology is an asymmetry surface).
