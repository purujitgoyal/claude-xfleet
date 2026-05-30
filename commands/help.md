---
description: Show xfleet CLI quick reference and subcommand listing
---

# xfleet CLI Quick Reference

`xfleet` is the xfleet plugin's command-line dispatcher. The `bin/` directory is added to PATH by the plugin's SessionStart hook, so all subcommands are available as bare `xfleet <subcommand>` calls — no path prefix needed.

## Usage

```
xfleet <subcommand> [arguments]
```

Run `xfleet --help` or `xfleet <subcommand> --help` for argument details.

## Subcommands by group

> Note: these groupings are operational (by use-context), not the structural message-type taxonomy (content-carrying vs state-mutating vs read-only) used in `shared/messaging.md`. For sender-authority and message-type rules, defer to messaging.md.

### Read-only / operational
| Subcommand | Purpose |
|------------|---------|
| `status`   | Show current agent and session status (most common diagnostic) |
| `peek`     | Read the next pending message without consuming it |
| `listen`   | Block until a message arrives |
| `ack`      | Acknowledge and consume the current message |

### Clarification
| Subcommand | Purpose |
|------------|---------|
| `question` | Send a clarification question to the orchestrator |
| `answer`   | Reply to a question from the orchestrator or another agent |

### Negotiation
| Subcommand | Purpose |
|------------|---------|
| `concern`        | Raise a concern that blocks further progress |
| `concern-reopen` | Re-open a previously closed concern |
| `resolution`     | Mark a concern as resolved |

### Orchestrator → worker
| Subcommand | Purpose |
|------------|---------|
| `directive` | Issue a directive to a worker agent |
| `task`      | Assign a task to a worker agent |
| `escalation`| Escalate an issue to a higher-authority agent |

### Lifecycle
| Subcommand | Purpose |
|------------|---------|
| `phase`          | Transition the session to a named phase |
| `engage`         | Engage (activate) an agent for a session |
| `disengage`      | Disengage (deactivate) an agent |
| `resume`         | Resume a paused session |
| `continue`       | Continue processing after an interruption |
| `phase-complete` | Mark the current phase as complete |

### Review
| Subcommand | Purpose |
|------------|---------|
| `review` | Request or submit a review for the current work product |

## Taxonomy and sender authority

For the full message taxonomy, sender-authority rules, and field definitions, see `shared/messaging.md` in the plugin root. The table above is a quick-reference only — messaging.md is the authoritative source.

## Common diagnostic

```
xfleet status
```

Run `/xfleet:status` to execute this from within a Claude Code session and display the formatted output inline.
