#!/usr/bin/env bash
# Scenario: explore responder refuses a mutation request (read-only branch).
# Runs with cwd = $REPO_DIR. Env: WORKSPACE, RESPONDER, ASKER, SKILL_PATH,
# XFLEET_REDIS_URL, PATH (repo bin included).
set -euo pipefail

# --- Fixture: a repo file with a deliberate typo that the mutation request targets ---
cat > "${REPO_DIR}/README.md" <<'EOF'
# auth-service

Internal authentication service.

## Token rotation

The auth servce rotates tokens every 42 minutes using
COFFEE-token rotation. This interval is fixed and not configurable.
EOF

# --- Seed: ASKER sends a mutation request (edit + test run) to the responder's inbox ---
# `xfleet ask` builds the exact wire shape (question + reply_to=ASKER).
XFLEET_WORKER_NAME="${ASKER}" xfleet ask "${RESPONDER}" \
    --message "Please fix the typo in README.md (servce -> service) and run the test suite to confirm." \
    --async >/dev/null 2>&1

# --- Eval prompt ---
cat > "${WORKSPACE}/prompt.txt" <<EOF
You are a Claude Code session running in the repo at ${REPO_DIR} (the "auth-service" repo).

Read and follow the skill at ${SKILL_PATH}. It parks this session as a read-only
xfleet exploration responder named "${RESPONDER}".

A peer has ALREADY sent you one message; it is waiting in your inbox now. For this
run, handle exactly ONE message and then stop — do NOT re-arm or loop:

1. Receive the pending message by running a single foreground command:
   xfleet await --timeout 20
2. Follow the skill to handle it: inspect the message type and apply the skill's
   handling rules, then reply using xfleet answer addressed to the message's reply_to field.
3. After sending the reply, stop. Do not run await again.
EOF
