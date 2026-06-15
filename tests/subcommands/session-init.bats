#!/usr/bin/env bats
# session-init.bats — xfleet session-init subcommand: orchestrator roster writer.

bats_require_minimum_version 1.5.0

REPO="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
XFLEET="${REPO}/bin/xfleet"

setup() {
    COORD="${BATS_TEST_TMPDIR}/coord"
    mkdir -p "${COORD}"
    export XFLEET_ROLE="orchestrator"
    export XFLEET_COORDINATION_ROOT="${COORD}"
    export XFLEET_CONFIG_DIR="${BATS_TEST_TMPDIR}/cfg"
    mkdir -p "${XFLEET_CONFIG_DIR}"
    printf '{"repos":{"oracle":"/tmp/oracle","server":"/tmp/server"}}\n' \
        > "${XFLEET_CONFIG_DIR}/config.json"
}

# (a) Happy path: exits 0, roster.json exists, correct shape.
@test "(a) clean coord root: exits 0" {
    run "${XFLEET}" session-init --slug oauth oracle,server
    [ "$status" -eq 0 ]
}

@test "(a) roster.json is created" {
    "${XFLEET}" session-init --slug oauth oracle,server
    [ -f "${COORD}/roster.json" ]
}

@test "(a) roster started_at is non-empty" {
    "${XFLEET}" session-init --slug oauth oracle,server
    val="$(jq -r '.started_at' "${COORD}/roster.json")"
    [ -n "${val}" ]
    [ "${val}" != "null" ]
}

@test "(a) roster has 2 repos" {
    "${XFLEET}" session-init --slug oauth oracle,server
    count="$(jq '.repos | length' "${COORD}/roster.json")"
    [ "${count}" -eq 2 ]
}

@test "(a) first repo entry has name=oracle" {
    "${XFLEET}" session-init --slug oauth oracle,server
    val="$(jq -r '.repos[] | select(.name=="oracle") | .name' "${COORD}/roster.json")"
    [ "${val}" = "oracle" ]
}

@test "(a) first repo entry has correct path from registry" {
    "${XFLEET}" session-init --slug oauth oracle,server
    val="$(jq -r '.repos[] | select(.name=="oracle") | .path' "${COORD}/roster.json")"
    [ "${val}" = "/tmp/oracle" ]
}

@test "(a) second repo entry has correct path from registry" {
    "${XFLEET}" session-init --slug oauth oracle,server
    val="$(jq -r '.repos[] | select(.name=="server") | .path' "${COORD}/roster.json")"
    [ "${val}" = "/tmp/server" ]
}

@test "(a) all repo entries have slug==oauth" {
    "${XFLEET}" session-init --slug oauth oracle,server
    count="$(jq '[.repos[] | select(.slug=="oauth")] | length' "${COORD}/roster.json")"
    [ "${count}" -eq 2 ]
}

# (b) Unregistered name -> exits non-zero; stderr names the unknown repo and lists registered.
@test "(b) unregistered name: exits non-zero" {
    run "${XFLEET}" session-init --slug x oracle,ghost
    [ "$status" -ne 0 ]
}

@test "(b) unregistered name: stderr names the unknown repo" {
    run --separate-stderr "${XFLEET}" session-init --slug x oracle,ghost
    [[ "${stderr}" == *"ghost"* ]]
}

@test "(b) unregistered name: stderr lists registered repos" {
    run --separate-stderr "${XFLEET}" session-init --slug x oracle,ghost
    [[ "${stderr}" == *"oracle"* ]] || [[ "${stderr}" == *"server"* ]]
}

# (c) Missing --slug -> exits non-zero with usage error.
@test "(c) missing --slug: exits non-zero" {
    run "${XFLEET}" session-init oracle,server
    [ "$status" -ne 0 ]
}

@test "(c) missing --slug: stderr mentions slug or usage" {
    run --separate-stderr "${XFLEET}" session-init oracle,server
    [[ "${stderr}" == *"slug"* ]] || [[ "${stderr}" == *"usage"* ]] || [[ "${stderr}" == *"Usage"* ]]
}

# (d) Role gate: worker role -> exits non-zero.
@test "(d) role gate: worker role exits non-zero" {
    XFLEET_ROLE=worker run "${XFLEET}" session-init --slug oauth oracle,server
    [ "$status" -ne 0 ]
}

@test "(d) role gate: worker role prints role-mismatch error mentioning orchestrator" {
    XFLEET_ROLE=worker run --separate-stderr "${XFLEET}" session-init --slug oauth oracle,server
    [[ "${stderr}" == *"orchestrator"* ]]
}

# (e) Overwrite: pre-write a stale roster.json, run session-init, assert new roster.
@test "(e) overwrite: stale roster.json is replaced" {
    printf '{"started_at":"1970-01-01T00:00:00Z","repos":[]}\n' > "${COORD}/roster.json"
    "${XFLEET}" session-init --slug oauth oracle,server
    count="$(jq '.repos | length' "${COORD}/roster.json")"
    [ "${count}" -eq 2 ]
}

@test "(e) overwrite: new slug is reflected in overwritten roster" {
    printf '{"started_at":"1970-01-01T00:00:00Z","repos":[]}\n' > "${COORD}/roster.json"
    "${XFLEET}" session-init --slug newslug oracle
    val="$(jq -r '.repos[0].slug' "${COORD}/roster.json")"
    [ "${val}" = "newslug" ]
}

# (f) Missing XFLEET_COORDINATION_ROOT -> exits non-zero.
@test "(f) missing XFLEET_COORDINATION_ROOT: exits non-zero" {
    unset XFLEET_COORDINATION_ROOT
    run "${XFLEET}" session-init --slug oauth oracle,server
    [ "$status" -ne 0 ]
}

@test "(f) missing XFLEET_COORDINATION_ROOT: stderr mentions XFLEET_COORDINATION_ROOT" {
    unset XFLEET_COORDINATION_ROOT
    run --separate-stderr "${XFLEET}" session-init --slug oauth oracle,server
    [[ "${stderr}" == *"XFLEET_COORDINATION_ROOT"* ]]
}
