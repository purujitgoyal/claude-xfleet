#!/usr/bin/env bats
# Marketplace registration tests for Task 16.
#
# tests/marketplace/ is two levels below the repo root, so:
#   BATS_TEST_DIRNAME = <repo>/tests/marketplace
#   ../../.claude-plugin/marketplace.json = <repo>/.claude-plugin/marketplace.json
#   ../../.claude-plugin/plugin.json      = <repo>/.claude-plugin/plugin.json
#   ../../INSTALL.md                      = <repo>/INSTALL.md
#
# Assertions cover:
#   (1) marketplace.json exists and is valid JSON at the canonical location.
#   (2) Required top-level fields: name, description, owner, plugins.
#   (3) plugins[0] has correct name, source, and the name matches plugin.json.
#   (4) INSTALL.md exists and contains the install instruction.

bats_require_minimum_version 1.5.0

MARKETPLACE="${BATS_TEST_DIRNAME}/../../.claude-plugin/marketplace.json"
PLUGIN_JSON="${BATS_TEST_DIRNAME}/../../.claude-plugin/plugin.json"
INSTALL_MD="${BATS_TEST_DIRNAME}/../../INSTALL.md"

# --- file existence ----------------------------------------------------------

@test "marketplace.json exists at .claude-plugin/marketplace.json" {
    [ -f "${MARKETPLACE}" ]
}

@test "INSTALL.md exists at repo root" {
    [ -f "${INSTALL_MD}" ]
}

# --- JSON validity -----------------------------------------------------------

@test "marketplace.json is valid JSON" {
    run jq . "${MARKETPLACE}"
    [ "$status" -eq 0 ]
}

# --- required top-level fields -----------------------------------------------

@test "marketplace name is claude-xfleet" {
    run jq -r '.name' "${MARKETPLACE}"
    [ "$status" -eq 0 ]
    [ "$output" = "claude-xfleet" ]
}

@test "marketplace description is present and non-empty" {
    run jq -r '.description' "${MARKETPLACE}"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    [ "$output" != "null" ]
}

@test "marketplace owner.name is present and non-empty" {
    run jq -r '.owner.name' "${MARKETPLACE}"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    [ "$output" != "null" ]
}

# --- plugins array -----------------------------------------------------------

@test "marketplace plugins is a non-empty array" {
    run jq -r '.plugins | length' "${MARKETPLACE}"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "plugins[0].name is xfleet" {
    run jq -r '.plugins[0].name' "${MARKETPLACE}"
    [ "$status" -eq 0 ]
    [ "$output" = "xfleet" ]
}

@test "plugins[0].source is ./" {
    run jq -r '.plugins[0].source' "${MARKETPLACE}"
    [ "$status" -eq 0 ]
    [ "$output" = "./" ]
}

@test "plugins[0].description is present and non-empty" {
    run jq -r '.plugins[0].description' "${MARKETPLACE}"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    [ "$output" != "null" ]
}

@test "plugins[0].category is present and non-empty" {
    run jq -r '.plugins[0].category' "${MARKETPLACE}"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    [ "$output" != "null" ]
}

@test "plugins[0].homepage is present and non-empty" {
    run jq -r '.plugins[0].homepage' "${MARKETPLACE}"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    [ "$output" != "null" ]
}

# --- cross-file consistency: marketplace plugin name matches plugin.json name -

@test "marketplace plugins[0].name matches plugin.json name" {
    marketplace_plugin_name="$(jq -r '.plugins[0].name' "${MARKETPLACE}")"
    plugin_json_name="$(jq -r '.name' "${PLUGIN_JSON}")"
    [ "$marketplace_plugin_name" = "$plugin_json_name" ]
}

# --- no top-level version field (marketplace schema does not carry version) --

@test "marketplace.json has no top-level version field" {
    run jq -r 'has("version")' "${MARKETPLACE}"
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
}

# --- INSTALL.md content ------------------------------------------------------

@test "INSTALL.md contains the plugin install instruction" {
    run grep -F "/plugin install xfleet" "${INSTALL_MD}"
    [ "$status" -eq 0 ]
}

@test "INSTALL.md contains the marketplace add instruction" {
    run grep -F "purujitgoyal/claude-xfleet" "${INSTALL_MD}"
    [ "$status" -eq 0 ]
}

@test "INSTALL.md references XFLEET_REDIS_URL" {
    run grep -F "XFLEET_REDIS_URL" "${INSTALL_MD}"
    [ "$status" -eq 0 ]
}

@test "INSTALL.md references XFLEET_COORDINATION_ROOT" {
    run grep -F "XFLEET_COORDINATION_ROOT" "${INSTALL_MD}"
    [ "$status" -eq 0 ]
}
