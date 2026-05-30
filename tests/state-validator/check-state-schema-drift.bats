#!/usr/bin/env bats
# Drift-detector tests for tools/xfleet/check-state-schema-drift.sh (Task 17b).
#
# tests/state-validator/ is two levels below the repo root, so:
#   BATS_TEST_DIRNAME = <repo>/tests/state-validator
#   ../../tools/xfleet/check-state-schema-drift.sh = <repo>/tools/xfleet/check-state-schema-drift.sh
#
# All tests use FIXTURE schema/prose files written to BATS_TMPDIR so they are
# self-contained — no dependency on the real files drifting. The script accepts
# positional args: check-state-schema-drift.sh <schema.json> <prose.md>.
#
# Scenarios covered:
#   (a) All JSON Schema fields are mentioned in manual prose    → exit 0
#   (b) A field added to the schema is missing from prose       → exit 1, name in output
#   (c) A field mentioned in prose not in schema (stale ref)    → exit 1, name in output
#   (d) A schema field with no description: keyword             → exit 1, name in output

bats_require_minimum_version 1.5.0

SCRIPT="${BATS_TEST_DIRNAME}/../../tools/xfleet/check-state-schema-drift.sh"

# ---------------------------------------------------------------------------
# Fixtures helpers
# ---------------------------------------------------------------------------

# Minimal valid schema: orchestrator has `schema_version` + `status_note`,
# worker has `schema_version` + `worker_mode`. All have descriptions.
# All top-level field names appear in GOOD_PROSE below.
GOOD_SCHEMA='{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$defs": {
    "orchestrator": {
      "type": "object",
      "properties": {
        "schema_version": {
          "type": "string",
          "description": "Schema version string."
        },
        "status_note": {
          "type": "string",
          "description": "A note about orchestrator status."
        }
      }
    },
    "worker": {
      "type": "object",
      "properties": {
        "schema_version": {
          "type": "string",
          "description": "Schema version string."
        },
        "worker_mode": {
          "type": "string",
          "description": "The active mode for the worker."
        }
      }
    }
  }
}'

# Prose that mentions all fields from GOOD_SCHEMA in the manual sections
# (outside any BEGIN/END GENERATED block).
GOOD_PROSE='# xfleet State File Schema

## Lifecycle

The `schema_version` field is always "1". The `status_note` carries
orchestrator bookkeeping. Workers track their current mode in `worker_mode`.

<!-- BEGIN GENERATED -->
This section is auto-generated — the detector must ignore it.
A stale token here like `nonexistent_field` MUST NOT trigger a false positive.
<!-- END GENERATED -->

## Writer Ownership

Both `schema_version` and `worker_mode` are written by their respective owners.
The `status_note` is orchestrator-private.
'

# Schema where `missing_field` is defined but NOT mentioned in prose.
SCHEMA_WITH_MISSING_FIELD='{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$defs": {
    "orchestrator": {
      "type": "object",
      "properties": {
        "schema_version": {
          "type": "string",
          "description": "Schema version string."
        },
        "missing_field": {
          "type": "string",
          "description": "This field is not mentioned in prose."
        }
      }
    },
    "worker": {
      "type": "object",
      "properties": {
        "schema_version": {
          "type": "string",
          "description": "Schema version string."
        }
      }
    }
  }
}'

# Schema with `schema_version` only; prose references a stale `stale_ref_field`
# that is no longer in the schema.
SCHEMA_WITHOUT_STALE='{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$defs": {
    "orchestrator": {
      "type": "object",
      "properties": {
        "schema_version": {
          "type": "string",
          "description": "Schema version string."
        }
      }
    },
    "worker": {
      "type": "object",
      "properties": {
        "schema_version": {
          "type": "string",
          "description": "Schema version string."
        }
      }
    }
  }
}'

# Prose with `schema_version` mentioned AND a backtick-wrapped stale field
# that looks like a state field name but is NOT in the schema.
PROSE_WITH_STALE='# xfleet State File Schema

## Lifecycle

The `schema_version` field is always "1".
The `stale_ref_field` used to exist but was removed from the schema.

<!-- BEGIN GENERATED -->
Ignore this.
<!-- END GENERATED -->

## Writer Ownership

Writers set `schema_version`. The old `stale_ref_field` is no longer used.
'

# Schema where `no_desc_field` is missing its description: keyword entirely.
SCHEMA_MISSING_DESC='{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$defs": {
    "orchestrator": {
      "type": "object",
      "properties": {
        "schema_version": {
          "type": "string",
          "description": "Schema version string."
        },
        "no_desc_field": {
          "type": "string"
        }
      }
    },
    "worker": {
      "type": "object",
      "properties": {
        "schema_version": {
          "type": "string",
          "description": "Schema version string."
        }
      }
    }
  }
}'

# Prose that mentions every field in SCHEMA_MISSING_DESC (so only the missing
# description triggers failure, not a missing prose mention).
PROSE_FOR_MISSING_DESC='# xfleet State File Schema

## Lifecycle

The `schema_version` field is always "1". The `no_desc_field` is also present.

<!-- BEGIN GENERATED -->
Auto-generated section.
<!-- END GENERATED -->

## Writer Ownership

Writers set `schema_version` and `no_desc_field` as needed.
'

# Write a string to a temp file; print the path.
write_tmp() {
    local name="$1"
    local content="$2"
    local path="${BATS_TMPDIR}/${name}"
    printf '%s' "${content}" > "${path}"
    printf '%s' "${path}"
}

# ---------------------------------------------------------------------------
# Guard: script exists
# ---------------------------------------------------------------------------

@test "check-state-schema-drift.sh exists and is executable" {
    [ -f "${SCRIPT}" ]
    [ -x "${SCRIPT}" ]
}

# ---------------------------------------------------------------------------
# (a) All JSON Schema fields mentioned in manual prose → exit 0
# ---------------------------------------------------------------------------

@test "(a) no drift: exit 0 when all schema fields are in prose" {
    schema="$(write_tmp "good-schema.json" "${GOOD_SCHEMA}")"
    prose="$(write_tmp "good-prose.md" "${GOOD_PROSE}")"
    run bash "${SCRIPT}" "${schema}" "${prose}"
    [ "$status" -eq 0 ]
}

@test "(a) no drift: stdout does not report any missing field" {
    schema="$(write_tmp "good-schema.json" "${GOOD_SCHEMA}")"
    prose="$(write_tmp "good-prose.md" "${GOOD_PROSE}")"
    run bash "${SCRIPT}" "${schema}" "${prose}"
    [[ ! "${output}" =~ "missing from prose" ]]
}

# ---------------------------------------------------------------------------
# (b) Schema field missing from prose → exit 1, field named in output
# ---------------------------------------------------------------------------

@test "(b) schema→prose: exit 1 when a schema field is absent from prose" {
    schema="$(write_tmp "miss-schema.json" "${SCHEMA_WITH_MISSING_FIELD}")"
    prose="$(write_tmp "good-prose.md" "${GOOD_PROSE}")"
    run bash "${SCRIPT}" "${schema}" "${prose}"
    [ "$status" -ne 0 ]
}

@test "(b) schema→prose: output names the missing field" {
    schema="$(write_tmp "miss-schema.json" "${SCHEMA_WITH_MISSING_FIELD}")"
    prose="$(write_tmp "good-prose.md" "${GOOD_PROSE}")"
    run bash "${SCRIPT}" "${schema}" "${prose}"
    [[ "${output}" =~ "missing_field" ]]
}

# ---------------------------------------------------------------------------
# (c) Stale prose reference not in schema → exit 1, stale field named in output
# ---------------------------------------------------------------------------

@test "(c) prose→schema: exit 1 when prose references a field not in schema" {
    schema="$(write_tmp "no-stale-schema.json" "${SCHEMA_WITHOUT_STALE}")"
    prose="$(write_tmp "stale-prose.md" "${PROSE_WITH_STALE}")"
    run bash "${SCRIPT}" "${schema}" "${prose}"
    [ "$status" -ne 0 ]
}

@test "(c) prose→schema: output names the stale field" {
    schema="$(write_tmp "no-stale-schema.json" "${SCHEMA_WITHOUT_STALE}")"
    prose="$(write_tmp "stale-prose.md" "${PROSE_WITH_STALE}")"
    run bash "${SCRIPT}" "${schema}" "${prose}"
    [[ "${output}" =~ "stale_ref_field" ]]
}

# ---------------------------------------------------------------------------
# (d) Schema field with no description: keyword → exit 1, field named in output
# ---------------------------------------------------------------------------

@test "(d) no-description: exit 1 when a schema field lacks a description" {
    schema="$(write_tmp "nodesc-schema.json" "${SCHEMA_MISSING_DESC}")"
    prose="$(write_tmp "nodesc-prose.md" "${PROSE_FOR_MISSING_DESC}")"
    run bash "${SCRIPT}" "${schema}" "${prose}"
    [ "$status" -ne 0 ]
}

@test "(d) no-description: output names the field missing a description" {
    schema="$(write_tmp "nodesc-schema.json" "${SCHEMA_MISSING_DESC}")"
    prose="$(write_tmp "nodesc-prose.md" "${PROSE_FOR_MISSING_DESC}")"
    run bash "${SCRIPT}" "${schema}" "${prose}"
    [[ "${output}" =~ "no_desc_field" ]]
}

# ---------------------------------------------------------------------------
# Generated-block exclusion: tokens inside BEGIN/END GENERATED are not checked
# ---------------------------------------------------------------------------

@test "tokens inside the BEGIN/END GENERATED block do not cause false positives" {
    # GOOD_PROSE has 'nonexistent_field' inside the generated block; it must not
    # be flagged as a stale reference because the block is excluded from the
    # inverse check.
    schema="$(write_tmp "good-schema.json" "${GOOD_SCHEMA}")"
    prose="$(write_tmp "good-prose.md" "${GOOD_PROSE}")"
    run bash "${SCRIPT}" "${schema}" "${prose}"
    [ "$status" -eq 0 ]
}
