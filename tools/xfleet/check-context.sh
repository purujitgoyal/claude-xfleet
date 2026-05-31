#!/usr/bin/env bash
# check-context.sh — PostToolUse hook: context-window monitor.
#
# Reads the CC PostToolUse JSON payload from stdin, computes current context
# usage from the transcript jsonl, and injects a system-reminder when usage
# crosses phase-specific warn/critical thresholds.
#
# Never exits non-zero — a monitoring hook must never block tool flow.
set -euo pipefail

# ---------------------------------------------------------------------------
# 1. Read payload + resolve transcript
# ---------------------------------------------------------------------------
PAYLOAD="$(cat)"

TRANSCRIPT="$(printf '%s' "$PAYLOAD" | jq -r '.transcript_path // empty' 2>/dev/null || true)"

if [[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 2. Compute PCT
# ---------------------------------------------------------------------------
LIMIT="${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-200000}"

LAST_USAGE="$(jq -c 'select(.message.usage != null) | .message.usage' "$TRANSCRIPT" 2>/dev/null | tail -1 || true)"
if [[ -z "$LAST_USAGE" ]]; then
  # Fallback to top-level .usage
  LAST_USAGE="$(jq -c 'select(.usage != null) | .usage' "$TRANSCRIPT" 2>/dev/null | tail -1 || true)"
fi

if [[ -z "$LAST_USAGE" ]]; then
  exit 0
fi

INPUT="$(printf '%s' "$LAST_USAGE" | jq '.input_tokens // 0' 2>/dev/null || echo 0)"
CR="$(printf '%s' "$LAST_USAGE" | jq '.cache_read_input_tokens // 0' 2>/dev/null || echo 0)"
CC="$(printf '%s' "$LAST_USAGE" | jq '.cache_creation_input_tokens // 0' 2>/dev/null || echo 0)"
TOKENS=$(( INPUT + CR + CC ))

if (( LIMIT <= 0 )); then
  exit 0
fi

PCT=$(( TOKENS * 100 / LIMIT ))

# ---------------------------------------------------------------------------
# 3. Resolve current_phase + thresholds
# ---------------------------------------------------------------------------
COORD="${XFLEET_COORDINATION_ROOT:-}"
WORKER="${XFLEET_WORKER_NAME:-}"
WORKER_STATE=""

if [[ -n "$COORD" && -n "$WORKER" && -f "${COORD}/state/${WORKER}.json" ]]; then
  WORKER_STATE="${COORD}/state/${WORKER}.json"
fi

CURRENT_PHASE=""
if [[ -n "$WORKER_STATE" ]]; then
  CURRENT_PHASE="$(jq -r '.current_phase // empty' "$WORKER_STATE" 2>/dev/null || true)"
fi

# Resolve plugin root: this file is at tools/xfleet/check-context.sh → ../.. = repo root
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

# Default thresholds
WARN=70
CRIT=80

if [[ -n "$CURRENT_PHASE" ]]; then
  SKILL_MD="${PLUGIN_ROOT}/skills/phase-${CURRENT_PHASE}/SKILL.md"
  if [[ -f "$SKILL_MD" ]]; then
    WARN_PARSED="$(grep -E '^warn_at:' "$SKILL_MD" | head -1 | sed -E 's/[^0-9]//g' || true)"
    CRIT_PARSED="$(grep -E '^critical_at:' "$SKILL_MD" | head -1 | sed -E 's/[^0-9]//g' || true)"
    [[ -n "$WARN_PARSED" ]] && WARN="$WARN_PARSED"
    [[ -n "$CRIT_PARSED" ]] && CRIT="$CRIT_PARSED"
  fi
fi

# ---------------------------------------------------------------------------
# 4. Determine level
# ---------------------------------------------------------------------------
LEVEL="below"
if (( PCT >= CRIT )); then
  LEVEL="critical"
elif (( PCT >= WARN )); then
  LEVEL="warn"
fi

# ---------------------------------------------------------------------------
# 5. Threshold-gated emission + two-level debounce
# ---------------------------------------------------------------------------

# Source state-io.sh only when needed for state writes (WORKER_STATE set)
_STATE_IO_SOURCED=0
_source_state_io() {
  if [[ "$_STATE_IO_SOURCED" -eq 0 ]]; then
    # shellcheck source=lib/state-io.sh
    source "${PLUGIN_ROOT}/tools/xfleet/lib/state-io.sh" 2>/dev/null || true
    _STATE_IO_SOURCED=1
  fi
}

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

_update_state() {
  local patch="$1"
  if [[ -n "$WORKER_STATE" ]]; then
    _source_state_io
    state_update_field "$WORKER_STATE" "$patch" || true
  fi
}

if [[ "$LEVEL" = "below" ]]; then
  # Silent; reset debounce if WORKER_STATE available
  if [[ -n "$WORKER_STATE" ]]; then
    PATCH="$(jq -cn --arg now "$NOW" --argjson pct "$PCT" \
      '{last_check_at: $now, context_pct: $pct, last_warn_emitted_at: null}')"
    _update_state ". + $PATCH" || true
  fi
  exit 0
fi

EMIT=1  # default: emit

if [[ "$LEVEL" = "warn" ]]; then
  if [[ -n "$WORKER_STATE" ]]; then
    LAST_WARN="$(jq -r '.last_warn_emitted_at // empty' "$WORKER_STATE" 2>/dev/null || true)"
    if [[ -n "$LAST_WARN" ]]; then
      # Already emitted a warn and pct hasn't dropped below warn since — skip
      EMIT=0
      # Still update last_check_at + context_pct
      PATCH="$(jq -cn --arg now "$NOW" --argjson pct "$PCT" \
        '{last_check_at: $now, context_pct: $pct}')"
      _update_state ". + $PATCH" || true
    fi
  fi
  # Degraded path (no WORKER_STATE): emit every time (no debounce)
fi

# critical: always emit, no debounce

if [[ "$EMIT" -eq 1 ]]; then
  # ---------------------------------------------------------------------------
  # 6. Emission
  # ---------------------------------------------------------------------------
  if [[ "$LEVEL" = "warn" ]]; then
    REMINDER="<system-reminder>xfleet context check: usage at ${PCT}% (warn_at ${WARN}) in phase '${CURRENT_PHASE}'. Consider running prepare-compact / prepare-handoff soon to avoid an uncontrolled auto-compact.</system-reminder>"
  else
    REMINDER="<system-reminder>xfleet context check: usage at ${PCT}% (critical_at ${CRIT}) in phase '${CURRENT_PHASE}'. HALT non-essential work: run prepare-handoff now, then /clear + resume. Do not start new large subtasks.</system-reminder>"
  fi

  jq -cn --arg ctx "$REMINDER" \
    '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'

  # Update state (set last_warn_emitted_at = NOW for both warn and critical)
  if [[ -n "$WORKER_STATE" ]]; then
    PATCH="$(jq -cn --arg now "$NOW" --argjson pct "$PCT" --arg lw "$NOW" \
      '{last_check_at: $now, context_pct: $pct, last_warn_emitted_at: $lw}')"
    _update_state ". + $PATCH" || true
  fi
fi

exit 0
