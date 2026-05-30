---
description: Show current xfleet agent and session status
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/xfleet:*)
---

Run the following command and display its output to the user, formatted clearly:

!`${CLAUDE_PLUGIN_ROOT}/bin/xfleet status`

After displaying the output, briefly explain any non-obvious status fields:

- **session**: the active coordination session identifier
- **role**: this agent's current role (orchestrator / worker / unset)
- **phase**: the current lifecycle phase (e.g. `plan`, `implement`, `qa`, `cleanup`)
- **pending**: number of messages waiting in the inbox
- **last-ack**: timestamp of the last acknowledged message

If the command exits non-zero or produces no output, inform the user that the xfleet session may not be initialized and suggest running `xfleet engage` to start a session.
