#!/usr/bin/env bats
# Tests for tools/xfleet/hooks/load-grounding.sh
#
# MANUAL SMOKE TEST (Step 7 — pending operator verification)
# -----------------------------------------------------------
# The four SessionStart event types must be verified manually in a live
# Claude Code session.  The automated BATS tests below cover --event flag
# handling, but cannot simulate the actual hook dispatch by the CC runtime.
#
# Events to verify:
#   1. startup  — start a fresh CC session and confirm the hook fires,
#                 grounding context appears, and env vars are set.
#   2. resume   — resume a previous session (e.g. `claude --resume`) and
#                 confirm the same.
#   3. clear    — run /clear inside a session and confirm re-injection.
#   4. compact  — run /compact inside a session and confirm re-injection.
#
# For each event, check:
#   - Grounding blocks appear in the session context (=== {repo} === markers)
#   - $XFLEET_COORDINATION_ROOT is exported
#   - $XFLEET_PYTHON is exported and passes jsonschema check
#   - $PATH includes the plugin bin/ directory
#
# CC version range tested: 2.1.140 (starting data point; fill in upper bound
#                          after verification)
# Operator: _____________  Date: ___________
# -----------------------------------------------------------

HOOK_SCRIPT="${BATS_TEST_DIRNAME}/../../tools/xfleet/hooks/load-grounding.sh"

# ---------------------------------------------------------------------------
# Setup: provide a working python with jsonschema as the default for all tests
# that are not explicitly testing python resolution.  Tests in group (g) that
# test failure paths override XFLEET_PYTHON inline.
# ---------------------------------------------------------------------------

setup() {
    # Use the venv python (created by Task 31's setup script) if available.
    # Tests that specifically test python resolution override this per-test.
    if [[ -x "${HOME}/.config/xfleet/venv/bin/python" ]]; then
        export XFLEET_PYTHON="${HOME}/.config/xfleet/venv/bin/python"
    fi
    # Point at a nonexistent config so tests don't accidentally pick up the
    # real ~/.config/xfleet/config.json (which could have coordination_root set).
    export XFLEET_CONFIG_FILE="/dev/null/nonexistent-xfleet-config.json"
    # Clear coordination root so tests control it explicitly.
    unset XFLEET_COORDINATION_ROOT || true
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Build a minimal fake coordination root with roster.json + repos.
# Usage: make_coordination_root <tmpdir> <repo1_path> <slug1> [<repo2_path> <slug2> ...]
# Writes roster.json with one entry per pair.
make_roster() {
    local root="$1"
    shift
    local json='[]'
    while [[ $# -ge 2 ]]; do
        local repo_path="$1"
        local slug="$2"
        shift 2
        json=$(printf '%s' "$json" | jq --arg r "$repo_path" --arg s "$slug" \
            '. + [{"repo": $r, "slug": $s}]')
    done
    printf '%s\n' "$json" > "${root}/roster.json"
}

# Create a fake repo with CLAUDE.md and optionally grounding.md.
make_repo() {
    local repo_dir="$1"
    local slug="$2"
    local with_grounding="${3:-true}"
    mkdir -p "${repo_dir}"
    printf 'CLAUDE.md content for %s\n' "${repo_dir}" > "${repo_dir}/CLAUDE.md"
    if [[ "$with_grounding" == "true" ]]; then
        local gdir="${repo_dir}/docs/superpowers/xfleet/${slug}"
        mkdir -p "$gdir"
        printf 'Grounding content for %s/%s\n' "${repo_dir}" "${slug}" > "${gdir}/grounding.md"
    fi
}

# ---------------------------------------------------------------------------
# (a) missing roster.json -> warning + exit 0
# ---------------------------------------------------------------------------

@test "(a) missing roster.json: emits warning and exits 0" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    # No roster.json in tmpdir
    run bash "${HOOK_SCRIPT}" \
        --event startup \
        --coordination-root "${tmpdir}"
    [ "$status" -eq 0 ]
    # Should warn about missing roster
    [[ "$output" =~ [Ww]arning ]] || [[ "$stderr" =~ [Ww]arning ]]
    rm -rf "${tmpdir}"
}

# ---------------------------------------------------------------------------
# (b) roster with 3 repos, all have CLAUDE.md + grounding.md -> concatenated
#     stdout with === {repo} === markers
# ---------------------------------------------------------------------------

@test "(b) 3 repos with all files: outputs === markers + content" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local repo1="${tmpdir}/repo-alpha"
    local repo2="${tmpdir}/repo-beta"
    local repo3="${tmpdir}/repo-gamma"
    make_repo "$repo1" "alpha"
    make_repo "$repo2" "beta"
    make_repo "$repo3" "gamma"
    make_roster "${tmpdir}" "$repo1" "alpha" "$repo2" "beta" "$repo3" "gamma"

    run bash "${HOOK_SCRIPT}" --event startup --coordination-root "${tmpdir}"
    [ "$status" -eq 0 ]

    # Each repo should have a === marker
    [[ "$output" =~ "=== ${repo1} ===" ]]
    [[ "$output" =~ "=== ${repo2} ===" ]]
    [[ "$output" =~ "=== ${repo3} ===" ]]

    # CLAUDE.md content should appear
    [[ "$output" =~ "CLAUDE.md content for ${repo1}" ]]
    [[ "$output" =~ "CLAUDE.md content for ${repo2}" ]]
    [[ "$output" =~ "CLAUDE.md content for ${repo3}" ]]

    # Grounding content should appear
    [[ "$output" =~ "Grounding content for ${repo1}/alpha" ]]
    [[ "$output" =~ "Grounding content for ${repo2}/beta" ]]
    [[ "$output" =~ "Grounding content for ${repo3}/gamma" ]]

    rm -rf "${tmpdir}"
}

# ---------------------------------------------------------------------------
# (c) one repo missing grounding.md -> warning + skip grounding + continue
# ---------------------------------------------------------------------------

@test "(c) one repo missing grounding.md: warns, skips it, continues other repos" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local repo1="${tmpdir}/repo-has-grounding"
    local repo2="${tmpdir}/repo-no-grounding"
    local repo3="${tmpdir}/repo-also-has-grounding"
    make_repo "$repo1" "slug1"
    make_repo "$repo2" "slug2" "false"   # no grounding.md
    make_repo "$repo3" "slug3"
    make_roster "${tmpdir}" "$repo1" "slug1" "$repo2" "slug2" "$repo3" "slug3"

    run bash "${HOOK_SCRIPT}" --event startup --coordination-root "${tmpdir}"
    [ "$status" -eq 0 ]

    # Repos 1 and 3 should appear with markers + content
    [[ "$output" =~ "=== ${repo1} ===" ]]
    [[ "$output" =~ "=== ${repo3} ===" ]]
    [[ "$output" =~ "CLAUDE.md content for ${repo1}" ]]
    [[ "$output" =~ "CLAUDE.md content for ${repo3}" ]]

    # Repo 2: CLAUDE.md present (should appear), grounding skipped with warning
    [[ "$output" =~ "=== ${repo2} ===" ]]
    [[ "$output" =~ "CLAUDE.md content for ${repo2}" ]]

    # Warning about missing grounding for repo2
    [[ "$output" =~ [Ww]arning ]] || [[ "$stderr" =~ [Ww]arning ]]

    rm -rf "${tmpdir}"
}

# ---------------------------------------------------------------------------
# (d) different --event values all behave the same
# ---------------------------------------------------------------------------

@test "(d) --event startup: runs normally" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local repo1="${tmpdir}/repo-a"
    make_repo "$repo1" "sla"
    make_roster "${tmpdir}" "$repo1" "sla"

    run bash "${HOOK_SCRIPT}" --event startup --coordination-root "${tmpdir}"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "=== ${repo1} ===" ]]
    rm -rf "${tmpdir}"
}

@test "(d) --event resume: runs same as startup" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local repo1="${tmpdir}/repo-a"
    make_repo "$repo1" "sla"
    make_roster "${tmpdir}" "$repo1" "sla"

    run bash "${HOOK_SCRIPT}" --event resume --coordination-root "${tmpdir}"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "=== ${repo1} ===" ]]
    rm -rf "${tmpdir}"
}

@test "(d) --event clear: runs same as startup" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local repo1="${tmpdir}/repo-a"
    make_repo "$repo1" "sla"
    make_roster "${tmpdir}" "$repo1" "sla"

    run bash "${HOOK_SCRIPT}" --event clear --coordination-root "${tmpdir}"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "=== ${repo1} ===" ]]
    rm -rf "${tmpdir}"
}

@test "(d) --event compact: runs same as startup" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local repo1="${tmpdir}/repo-a"
    make_repo "$repo1" "sla"
    make_roster "${tmpdir}" "$repo1" "sla"

    run bash "${HOOK_SCRIPT}" --event compact --coordination-root "${tmpdir}"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "=== ${repo1} ===" ]]
    rm -rf "${tmpdir}"
}

# ---------------------------------------------------------------------------
# (e) hook writes PATH export to $CLAUDE_ENV_FILE when set;
#     skips gracefully when $CLAUDE_ENV_FILE is not set
# ---------------------------------------------------------------------------

@test "(e) CLAUDE_ENV_FILE set: writes PATH export with plugin bin/" {
    local tmpdir env_file
    tmpdir="$(mktemp -d)"
    env_file="${tmpdir}/env_file"
    touch "$env_file"
    local repo1="${tmpdir}/repo-a"
    make_repo "$repo1" "sla"
    make_roster "${tmpdir}" "$repo1" "sla"

    CLAUDE_ENV_FILE="$env_file" CLAUDE_PLUGIN_ROOT="${tmpdir}/fake-plugin" \
        run bash "${HOOK_SCRIPT}" --event startup --coordination-root "${tmpdir}"
    [ "$status" -eq 0 ]

    # env_file must contain an export PATH line with plugin bin/
    grep -q 'export PATH=.*fake-plugin/bin' "$env_file"

    rm -rf "${tmpdir}"
}

@test "(e) CLAUDE_ENV_FILE unset: no error, exits 0" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local repo1="${tmpdir}/repo-a"
    make_repo "$repo1" "sla"
    make_roster "${tmpdir}" "$repo1" "sla"

    unset CLAUDE_ENV_FILE
    run bash "${HOOK_SCRIPT}" --event startup --coordination-root "${tmpdir}"
    [ "$status" -eq 0 ]

    rm -rf "${tmpdir}"
}

# ---------------------------------------------------------------------------
# (f) XFLEET_COORDINATION_ROOT resolution:
#     env var > config file > .xfleet-marker walk; loud error if none
# ---------------------------------------------------------------------------

@test "(f) XFLEET_COORDINATION_ROOT env var takes highest precedence" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local repo1="${tmpdir}/repo-a"
    make_repo "$repo1" "sla"
    make_roster "${tmpdir}" "$repo1" "sla"

    # Pass via env var; also pass a config that points elsewhere (should be ignored)
    local cfg="${tmpdir}/config.json"
    printf '{"coordination_root": "/nonexistent-should-not-be-used"}\n' > "$cfg"

    XFLEET_COORDINATION_ROOT="${tmpdir}" XFLEET_CONFIG_FILE="$cfg" \
        run bash "${HOOK_SCRIPT}" --event startup
    [ "$status" -eq 0 ]
    [[ "$output" =~ "=== ${repo1} ===" ]]

    rm -rf "${tmpdir}"
}

@test "(f) config file coordination_root used when env var absent" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local repo1="${tmpdir}/repo-a"
    make_repo "$repo1" "sla"
    make_roster "${tmpdir}" "$repo1" "sla"

    local cfg="${tmpdir}/config.json"
    printf '{"coordination_root": "%s"}\n' "${tmpdir}" > "$cfg"

    unset XFLEET_COORDINATION_ROOT
    XFLEET_CONFIG_FILE="$cfg" \
        run bash "${HOOK_SCRIPT}" --event startup
    [ "$status" -eq 0 ]
    [[ "$output" =~ "=== ${repo1} ===" ]]

    rm -rf "${tmpdir}"
}

@test "(f) .xfleet-marker in CWD resolves coordination root" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local repo1="${tmpdir}/repo-a"
    make_repo "$repo1" "sla"
    make_roster "${tmpdir}" "$repo1" "sla"

    # Place marker in tmpdir
    touch "${tmpdir}/.xfleet-marker"

    # Point to a nonexistent config so fallthrough happens
    local cfg="${tmpdir}/no-config.json"

    unset XFLEET_COORDINATION_ROOT
    # Run with CWD set to tmpdir so marker walk finds it
    XFLEET_CONFIG_FILE="$cfg" \
        run bash -c "cd '${tmpdir}' && bash '${HOOK_SCRIPT}' --event startup"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "=== ${repo1} ===" ]]

    rm -rf "${tmpdir}"
}

@test "(f) .xfleet-marker in ancestor dir resolves coordination root" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local repo1="${tmpdir}/repo-a"
    make_repo "$repo1" "sla"
    make_roster "${tmpdir}" "$repo1" "sla"

    # Marker is in tmpdir; CWD is a subdir
    touch "${tmpdir}/.xfleet-marker"
    local subdir="${tmpdir}/some/deep/subdir"
    mkdir -p "$subdir"

    local cfg="${tmpdir}/no-config.json"

    unset XFLEET_COORDINATION_ROOT
    XFLEET_CONFIG_FILE="$cfg" \
        run bash -c "cd '${subdir}' && bash '${HOOK_SCRIPT}' --event startup"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "=== ${repo1} ===" ]]

    rm -rf "${tmpdir}"
}

@test "(f) no resolution source: exits non-zero with loud warning" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    # No marker, no config, no env var; CWD has no .xfleet-marker up the tree
    local cfg="${tmpdir}/no-config.json"

    unset XFLEET_COORDINATION_ROOT
    # Use /tmp as CWD — no marker expected there
    XFLEET_CONFIG_FILE="$cfg" \
        run bash -c "cd /tmp && bash '${HOOK_SCRIPT}' --event startup"
    [ "$status" -ne 0 ]
    # Warning should appear in combined output/stderr
    [[ "$output" =~ [Ww]arning ]] || [[ "$stderr" =~ [Ww]arning ]] || \
        [[ "$output" =~ [Ee]rror ]] || [[ "$stderr" =~ [Ee]rror ]]

    rm -rf "${tmpdir}"
}

@test "(f) XFLEET_COORDINATION_ROOT exported to CLAUDE_ENV_FILE" {
    local tmpdir env_file
    tmpdir="$(mktemp -d)"
    env_file="${tmpdir}/env_file"
    touch "$env_file"
    local repo1="${tmpdir}/repo-a"
    make_repo "$repo1" "sla"
    make_roster "${tmpdir}" "$repo1" "sla"

    XFLEET_COORDINATION_ROOT="${tmpdir}" CLAUDE_ENV_FILE="$env_file" \
        run bash "${HOOK_SCRIPT}" --event startup
    [ "$status" -eq 0 ]

    grep -q "export XFLEET_COORDINATION_ROOT=" "$env_file"

    rm -rf "${tmpdir}"
}

# ---------------------------------------------------------------------------
# (g) XFLEET_PYTHON resolution: env > config python_bin > python3 system default
#     + jsonschema import check; loud error if check fails
# ---------------------------------------------------------------------------

@test "(g) XFLEET_PYTHON env var takes highest precedence" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local repo1="${tmpdir}/repo-a"
    make_repo "$repo1" "sla"
    make_roster "${tmpdir}" "$repo1" "sla"

    local cfg="${tmpdir}/config.json"
    printf '{"coordination_root": "%s", "python_bin": "/usr/bin/false"}\n' "${tmpdir}" > "$cfg"

    # Env var points to venv python with jsonschema
    XFLEET_COORDINATION_ROOT="${tmpdir}" \
    XFLEET_PYTHON="$HOME/.config/xfleet/venv/bin/python" \
    XFLEET_CONFIG_FILE="$cfg" \
        run bash "${HOOK_SCRIPT}" --event startup
    [ "$status" -eq 0 ]

    rm -rf "${tmpdir}"
}

@test "(g) config file python_bin used when XFLEET_PYTHON env var absent" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local repo1="${tmpdir}/repo-a"
    make_repo "$repo1" "sla"
    make_roster "${tmpdir}" "$repo1" "sla"

    local cfg="${tmpdir}/config.json"
    printf '{"coordination_root": "%s", "python_bin": "%s"}\n' \
        "${tmpdir}" "$HOME/.config/xfleet/venv/bin/python" > "$cfg"

    unset XFLEET_PYTHON
    XFLEET_COORDINATION_ROOT="${tmpdir}" XFLEET_CONFIG_FILE="$cfg" \
        run bash "${HOOK_SCRIPT}" --event startup
    [ "$status" -eq 0 ]

    rm -rf "${tmpdir}"
}

@test "(g) falls back to python3 when env and config both absent" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local repo1="${tmpdir}/repo-a"
    make_repo "$repo1" "sla"
    make_roster "${tmpdir}" "$repo1" "sla"

    local cfg="${tmpdir}/config.json"
    printf '{"coordination_root": "%s"}\n' "${tmpdir}" > "$cfg"

    unset XFLEET_PYTHON
    XFLEET_COORDINATION_ROOT="${tmpdir}" XFLEET_CONFIG_FILE="$cfg" \
        run bash "${HOOK_SCRIPT}" --event startup
    # May succeed or fail depending on system python3 having jsonschema;
    # either way it should not crash with an unbound-variable error.
    # Exit code 0 or non-zero is acceptable here; what matters is no bash error.
    [[ "$output" != *"unbound variable"* ]]
    [[ "$output" != *"unbound variable"* ]]

    rm -rf "${tmpdir}"
}

@test "(g) jsonschema not importable: exits non-zero with loud warning" {
    local tmpdir
    tmpdir="$(mktemp -d)"
    local repo1="${tmpdir}/repo-a"
    make_repo "$repo1" "sla"
    make_roster "${tmpdir}" "$repo1" "sla"

    local cfg="${tmpdir}/config.json"
    printf '{"coordination_root": "%s"}\n' "${tmpdir}" > "$cfg"

    # Point to /usr/bin/false which will always exit 1 for any invocation
    XFLEET_COORDINATION_ROOT="${tmpdir}" \
    XFLEET_PYTHON="/usr/bin/false" \
    XFLEET_CONFIG_FILE="$cfg" \
        run bash "${HOOK_SCRIPT}" --event startup
    [ "$status" -ne 0 ]
    [[ "$output" =~ [Ww]arning ]] || [[ "$stderr" =~ [Ww]arning ]] || \
        [[ "$output" =~ [Ee]rror ]] || [[ "$stderr" =~ [Ee]rror ]]

    rm -rf "${tmpdir}"
}

@test "(g) XFLEET_PYTHON exported to CLAUDE_ENV_FILE" {
    local tmpdir env_file
    tmpdir="$(mktemp -d)"
    env_file="${tmpdir}/env_file"
    touch "$env_file"
    local repo1="${tmpdir}/repo-a"
    make_repo "$repo1" "sla"
    make_roster "${tmpdir}" "$repo1" "sla"

    XFLEET_COORDINATION_ROOT="${tmpdir}" \
    XFLEET_PYTHON="$HOME/.config/xfleet/venv/bin/python" \
    CLAUDE_ENV_FILE="$env_file" \
        run bash "${HOOK_SCRIPT}" --event startup
    [ "$status" -eq 0 ]

    grep -q "export XFLEET_PYTHON=" "$env_file"

    rm -rf "${tmpdir}"
}
