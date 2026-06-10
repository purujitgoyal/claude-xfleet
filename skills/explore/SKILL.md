---
name: explore
description: >
  Use when invoked as `/xfleet:explore` to park this repo's session as a
  read-only exploration responder. This skill should be used when the session
  must answer ad-hoc cross-repo questions from peer sessions over Redis —
  orchestrator-less exploration mode, no coordination session required.
  Trigger phrases: "park this repo as a responder", "start exploration mode",
  "run /xfleet:explore", "answer cross-repo questions for this repo".
---

## Identity + Scope

The explore responder is a **parked, strictly read-only** session in this repo.
It answers inbound `question` messages about THIS repo using the repo's own
tools, and does nothing else. It is the answering half of xfleet exploration
mode (`shared/messaging.md` section (i)); the asking half is `xfleet ask`,
which any session can run with no skill at all.

It does **not**: edit files, run tests or builds, commit, originate concerns or
escalations, talk to an orchestrator (there is none in this mode), or read
sibling repos. There are no phases, no state files, and no coordination root.

## On Load

1. Export `XFLEET_ROLE=worker` (needed by `xfleet answer`).
2. Resolve the responder name: the repo directory basename, unless the user
   supplies one. Export it as `XFLEET_WORKER_NAME`.
3. Announce: `parked as <name> — peers can reach me with: xfleet ask <name>
   --message "..."`.
4. Do NOT park in a repo that is currently an active coordination-session
   worker under the same name — both would consume the same `inbox:{name}`
   stream. If a coordination session is live here, stop and tell the user.

## Park Loop

Run `xfleet await` via Bash with `run_in_background: true` and **no
`--timeout`** — the session idles at zero token cost until `await` exits with a
message (the command prints the message JSON and exits 0; it refreshes the
presence key `xfleet:explore:presence:{name}` on every internal cycle).

On wake, parse the printed JSON by `type`:

- **`question`** — investigate **read-only** (Serena memories and symbols
  first, then `git log` / grep / file reads), then reply:
  `xfleet answer <reply_to> --message "<answer text>"`.
  Use the message's `reply_to` field as the recipient — `from` carries only
  the role string. Reply inline with `--message`; `--message-file` requires a
  coordination root (SC-5), which exploration mode does not have.
  Then **re-arm**: launch `xfleet await` in the background again.
- **Mutation request** (anything implying edits, test runs, builds, commits) —
  reply with the standard refusal: "exploration mode is read-only; this
  responder only answers questions about <repo>". Re-arm.
- **Any other type** — note it to the user, do not act on it. Re-arm.

## Permission Posture

Read-only is **behavioral, not wire-enforced**. Recommend starting the
responder session in a read-only permission mode (e.g. plan mode) so the
guarantee is structural, not just instructed.

## Context

When `check-context` reports warn or higher, finish the in-flight answer, then
tell the user to restart the parked session fresh.

## Unpark

On user interrupt or "stop": kill the background `await` task (TaskStop), then
run `xfleet await --unpark` to delete the presence key, and confirm to the
user.
