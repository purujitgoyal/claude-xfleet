#!/usr/bin/env bash
# run-evals.sh — driver for xfleet skill behavioral evals.
#
# For each scenario: flush sandbox Redis, build a throwaway repo, run setup.sh
# (seeds inbox + writes prompt.txt), run the skill headless via `claude -p`
# bounded by a wall-clock timeout, then run assert.sh.
#
# Usage:
#   bash tests/evals/run-evals.sh [--skill <name>] [--scenario <name>]
#                                 [--model <id>] [--timeout <secs>]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/eval-lib.sh
source "${SCRIPT_DIR}/lib/eval-lib.sh"

SKILL="explore"
ONLY_SCENARIO=""
MODEL="claude-sonnet-4-6"
RUN_TIMEOUT=150

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skill)    SKILL="$2"; shift 2 ;;
        --scenario) ONLY_SCENARIO="$2"; shift 2 ;;
        --model)    MODEL="$2"; shift 2 ;;
        --timeout)  RUN_TIMEOUT="$2"; shift 2 ;;
        *) printf 'unknown option: %s\n' "$1" >&2; exit 1 ;;
    esac
done

SKILL_SRC="${EVAL_REPO_ROOT}/skills/${SKILL}"
[[ -f "${SKILL_SRC}/SKILL.md" ]] || { printf 'no skill at %s\n' "${SKILL_SRC}" >&2; exit 1; }
SCN_ROOT="${SCRIPT_DIR}/scenarios/${SKILL}"
[[ -d "${SCN_ROOT}" ]] || { printf 'no scenarios at %s\n' "${SCN_ROOT}" >&2; exit 1; }

# Pick a `timeout` binary (gtimeout on macOS via coreutils, else timeout).
TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"

total=0; failed=0
for scn_dir in "${SCN_ROOT}"/*/; do
    scn="$(basename "${scn_dir}")"
    [[ -n "${ONLY_SCENARIO}" && "${scn}" != "${ONLY_SCENARIO}" ]] && continue
    [[ -f "${scn_dir}/setup.sh" && -f "${scn_dir}/assert.sh" ]] || continue
    total=$((total + 1))

    printf '\n=== %s / %s ===\n' "${SKILL}" "${scn}"

    # Per-scenario sandbox.
    WORKSPACE="${SCRIPT_DIR}/.work/${SKILL}/${scn}"
    rm -rf "${WORKSPACE}"; mkdir -p "${WORKSPACE}"
    # Names are unique per scenario so a leaked background process from a prior
    # scenario can never consume this scenario's streams (defense in depth on top
    # of the per-scenario FLUSHDB). The responder name MUST equal the repo-dir
    # basename: the explore skill resolves its name from basename($PWD).
    RESPONDER="resp-${scn}"
    ASKER="ask-${scn}"
    REPO_PARENT="$(mktemp -d "${TMPDIR:-/tmp}/xfleet-eval-${scn}.XXXXXX")"
    REPO_DIR="${REPO_PARENT}/${RESPONDER}"
    mkdir -p "${REPO_DIR}"
    # Copy the skill into the (allowed) workspace so the headless agent can Read
    # it without granting access to the source repo.
    cp -R "${SKILL_SRC}" "${WORKSPACE}/skill"
    SKILL_PATH="${WORKSPACE}/skill/SKILL.md"
    export WORKSPACE REPO_DIR RESPONDER ASKER SKILL_PATH

    # Coordination root for state-writing skills. The explore skill is rootless
    # by design, so it gets none — keeping that scenario faithful.
    if [[ "${SKILL}" != "explore" ]]; then
        export XFLEET_COORDINATION_ROOT="${WORKSPACE}/coord"
        eval_build_coord_root "${XFLEET_COORDINATION_ROOT}"
    else
        unset XFLEET_COORDINATION_ROOT || true
    fi

    eval_flush || { printf 'flush failed\n'; failed=$((failed + 1)); continue; }

    # Seed + fixture + prompt.
    ( cd "${REPO_DIR}" && bash "${scn_dir}/setup.sh" ) || {
        printf 'setup failed\n'; failed=$((failed + 1)); continue; }

    [[ -f "${WORKSPACE}/prompt.txt" ]] || {
        printf 'setup did not write prompt.txt\n'; failed=$((failed + 1)); continue; }

    # Mirror a parked responder session: role + name live in the environment so
    # every Bash call inherits them (Claude Code shells don't persist exports).
    # This is plumbing the unit tests already cover; the eval tests behavior.
    export XFLEET_ROLE="worker" XFLEET_WORKER_NAME="${RESPONDER}"

    # Run the skill headless, bounded.
    # No --dangerously-skip-permissions: the headless agent runs in a constrained
    # auto-mode where only Bash + Read are auto-approved. --add-dir grants read of
    # the throwaway repo and the workspace (which holds the skill copy + prompt).
    # stream-json captures every tool call (run.jsonl) so a run is debuggable even
    # when `timeout` kills it mid-flight; run.out is the extracted final text.
    run_cmd=(claude -p "$(cat "${WORKSPACE}/prompt.txt")"
             --allowed-tools "Bash Read" --output-format stream-json --verbose
             --model "${MODEL}" --add-dir "${REPO_DIR}" --add-dir "${WORKSPACE}")
    if [[ -n "${TIMEOUT_BIN}" ]]; then
        ( cd "${REPO_DIR}" && "${TIMEOUT_BIN}" "${RUN_TIMEOUT}" "${run_cmd[@]}" ) \
            > "${WORKSPACE}/run.jsonl" 2> "${WORKSPACE}/run.err"
    else
        ( cd "${REPO_DIR}" && "${run_cmd[@]}" ) \
            > "${WORKSPACE}/run.jsonl" 2> "${WORKSPACE}/run.err"
    fi
    rc=$?
    jq -r 'select(.type=="result").result // empty' "${WORKSPACE}/run.jsonl" \
        > "${WORKSPACE}/run.out" 2>/dev/null || true
    printf 'run exit: %s (stream: %s)\n' "${rc}" "${WORKSPACE}/run.jsonl"

    # Assert.
    if ( cd "${REPO_DIR}" && bash "${scn_dir}/assert.sh" ) | tee "${WORKSPACE}/grading.txt"; then
        printf '%s: PASS\n' "${scn}"
    else
        printf '%s: FAIL\n' "${scn}"; failed=$((failed + 1))
    fi

    # Stop any background listener a scenario started. Kill the whole process
    # GROUP: the listener's bash loop respawns its redis-cli child, so killing the
    # child alone leaks. listen_bash_id is a "bash-<pid>" label (the group leader,
    # since the listener is setsid'd). The pkill on the unique stream name is the
    # backstop and is safe because names are scenario-unique.
    if [[ -n "${XFLEET_COORDINATION_ROOT:-}" && -f "${XFLEET_COORDINATION_ROOT}/state/${RESPONDER}.json" ]]; then
        lid="$(jq -r '.listen_bash_id // empty' "${XFLEET_COORDINATION_ROOT}/state/${RESPONDER}.json" 2>/dev/null || true)"
        if [[ -n "${lid}" ]]; then
            kill -- -"${lid#bash-}" 2>/dev/null || true
            kill "${lid#bash-}" 2>/dev/null || true
        fi
    fi
    pkill -f "inbox:${RESPONDER} " 2>/dev/null || true

    rm -rf "${REPO_PARENT}"
done

printf '\n=== summary: %s scenario(s), %s failed ===\n' "${total}" "${failed}"
[[ "${failed}" -eq 0 ]]
