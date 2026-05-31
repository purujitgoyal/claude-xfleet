#!/usr/bin/env bash
# check-state-schema-drift.sh — F-35 anti-drift gate (Task 17b).
#
# Keeps tools/xfleet/state-schema.json and the MANUAL prose sections of
# shared/state-schema.md in lockstep. CI gate and recommended pre-commit hook.
#
# Usage:
#   bash tools/xfleet/check-state-schema-drift.sh [<schema.json> [<prose.md>]]
#
# Arguments (both optional; defaults to real plugin paths):
#   $1  Path to the JSON Schema file  (default: tools/xfleet/state-schema.json)
#   $2  Path to the prose Markdown    (default: shared/state-schema.md)
#
# Checks performed:
#   1. Forward (schema->prose): every top-level + one-level named-object field
#      from orchestrator and worker $defs must appear >= 1 time in the manual
#      prose (everything outside <!-- BEGIN GENERATED --> ... <!-- END GENERATED -->).
#      Depth: top-level properties + one level of named nested-object
#      properties (where the nested object has its own "properties" dict, e.g.
#      human_engaged.active, current_task.task_id).
#      Array-item sub-fields (e.g. emission_log[].phase) are NOT required in
#      prose individually — prose discusses the parent array, not each item field.
#   2. Inverse (prose->schema): backtick-wrapped tokens in the manual prose
#      that look like state field names but are NOT in the schema (any depth)
#      are flagged as possible stale references.
#      Heuristic (conservative):
#        - Token must match [a-z][a-z0-9_]+ AND contain >= 1 underscore.
#          (Underscore requirement filters enum values, common words, commands.)
#        - The prose variant used for the inverse check ALSO strips two named
#          subsections structurally: "### Derived — NOT stored" and
#          "### Excluded — separate plan" (each subsection ends at the next
#          heading of any level). Non-field identifiers documented under those
#          subsections are invisible to the inverse check. Contract: those
#          headings must keep their exact text; a renamed heading causes the
#          formerly-suppressed token to become a flagged false positive → CI red.
#        - The vocabulary for the inverse check includes ALL schema field names
#          at all depths (top-level, nested objects, array-item properties, and
#          deep-nested map-value properties) so legitimate references to deeper
#          fields are not incorrectly flagged as stale.
#      Limitation: tokens without backticks are not checked. Multi-word field
#      references are not caught. False negatives are acceptable; false positives
#      are not — the heuristic errs toward precision.
#   3. Description presence: every named top-level and one-level-nested
#      property must carry a "description" key. The generator and this
#      detector both depend on it.
#
# Exit codes: 0 = no drift; 1 = drift or missing descriptions detected.
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

SCHEMA="${1:-${PLUGIN_ROOT}/tools/xfleet/state-schema.json}"
PROSE="${2:-${PLUGIN_ROOT}/shared/state-schema.md}"

if [[ ! -f "${SCHEMA}" ]]; then
    printf 'ERROR: schema file not found: %s\n' "${SCHEMA}" >&2
    exit 1
fi
if [[ ! -f "${PROSE}" ]]; then
    printf 'ERROR: prose file not found: %s\n' "${PROSE}" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 1. Extract field names from the schema — two vocabularies.
#
# SCHEMA_FIELDS_FORWARD: fields the forward check requires prose to mention.
#   - Top-level named properties from both orchestrator and worker $defs.
#   - One level of named nested object properties (objects with "properties"
#     dict, e.g. human_engaged, current_task, including nullable-object variants).
#   Array-item sub-fields are NOT included: prose discusses the parent array
#   name, not each individual item field.
#
# SCHEMA_FIELDS_ALL: full vocabulary for the inverse (stale-ref) check.
#   Adds array-item properties and deep map-value properties so legitimate
#   references to nested fields (e.g. emission_id in Cross-Field Invariants)
#   are not incorrectly flagged as stale.
#
# Note: JSON Schema "$defs" key starts with "$" which jq treats as a variable
# sigil; use .["$defs"] to access it literally.
# ---------------------------------------------------------------------------
SCHEMA_FIELDS_FORWARD="$(jq -r '
  (
    (.["$defs"].orchestrator.properties // {} | keys[]),
    (.["$defs"].worker.properties // {} | keys[]),
    (
      .["$defs"].orchestrator.properties // {}
      | to_entries[]
      | select(.value.type == "object" and .value.properties != null)
      | .value.properties | keys[]
    ),
    (
      .["$defs"].worker.properties // {}
      | to_entries[]
      | select(.value.properties != null)
      | .value.properties | keys[]
    )
  )
' "${SCHEMA}" 2>/dev/null | sort -u)" || {
    printf 'ERROR: failed to parse schema with jq: %s\n' "${SCHEMA}" >&2
    exit 1
}

if [[ -z "${SCHEMA_FIELDS_FORWARD}" ]]; then
    printf 'ERROR: no fields extracted from schema — check ["$defs"].orchestrator and ["$defs"].worker exist\n' >&2
    exit 1
fi

# Full vocabulary: add array-item properties and deep map-value properties.
SCHEMA_FIELDS_DEEP="$(jq -r '
  (
    (
      .["$defs"].orchestrator.properties // {}
      | to_entries[]
      | select(
          .value.items != null and
          (.value.items | type) == "object" and
          .value.items.properties != null
        )
      | .value.items.properties | keys[]
    ),
    (
      .["$defs"].worker.properties // {}
      | to_entries[]
      | select(
          .value.items != null and
          (.value.items | type) == "object" and
          .value.items.properties != null
        )
      | .value.items.properties | keys[]
    ),
    (
      .["$defs"].orchestrator.properties // {}
      | to_entries[]
      | select(
          .value.additionalProperties != null and
          (.value.additionalProperties | type) == "object" and
          .value.additionalProperties.additionalProperties != null and
          (.value.additionalProperties.additionalProperties | type) == "object" and
          .value.additionalProperties.additionalProperties.properties != null
        )
      | .value.additionalProperties.additionalProperties.properties | keys[]
    )
  )
' "${SCHEMA}" 2>/dev/null | sort -u)" || {
    printf 'ERROR: failed to extract deep field vocabulary from schema: %s\n' "${SCHEMA}" >&2
    exit 1
}

SCHEMA_FIELDS_ALL="$(printf '%s\n%s' "${SCHEMA_FIELDS_FORWARD}" "${SCHEMA_FIELDS_DEEP}" | sort -u)"

# ---------------------------------------------------------------------------
# 2. Check that every named property has a "description" key.
#
# Top-level and one-level nested object properties only. Map-value
# additionalProperties (anonymous/dynamic-keyed) are excluded.
# ---------------------------------------------------------------------------
MISSING_DESCS="$(jq -r '
  (
    (
      .["$defs"].orchestrator.properties // {}
      | to_entries[]
      | select(.value.description == null)
      | .key
    ),
    (
      .["$defs"].worker.properties // {}
      | to_entries[]
      | select(.value.description == null)
      | .key
    ),
    (
      .["$defs"].orchestrator.properties // {}
      | to_entries[]
      | select(.value.type == "object" and .value.properties != null)
      | .value.properties
      | to_entries[]
      | select(.value.description == null)
      | .key
    ),
    (
      .["$defs"].worker.properties // {}
      | to_entries[]
      | select(.value.properties != null)
      | .value.properties
      | to_entries[]
      | select(.value.description == null)
      | .key
    )
  )
' "${SCHEMA}" 2>/dev/null | sort -u)" || {
    printf 'ERROR: failed to check descriptions in schema with jq\n' >&2
    exit 1
}

# ---------------------------------------------------------------------------
# 3. Extract the manual prose (everything outside BEGIN/END GENERATED block).
#
# MANUAL_PROSE: used for the forward check (all manual content).
# INVERSE_PROSE: used for the inverse check; additionally strips the two
#   named subsections "### Derived — NOT stored" and
#   "### Excluded — separate plan" so that non-field identifiers documented
#   there are not flagged as stale references. Each subsection is suppressed
#   from its ### heading until the next heading of any level.
# ---------------------------------------------------------------------------
MANUAL_PROSE="$(awk '
    /<!-- BEGIN GENERATED -->/ { skip=1; next }
    /<!-- END GENERATED -->/   { skip=0; next }
    !skip { print }
' "${PROSE}")"

INVERSE_PROSE="$(awk '
    /<!-- BEGIN GENERATED -->/ { gen_skip=1; next }
    /<!-- END GENERATED -->/   { gen_skip=0; next }
    gen_skip { next }
    /^#/ { sub_skip=0 }
    /^### Derived — NOT stored$/  { sub_skip=1; next }
    /^### Excluded — separate plan$/ { sub_skip=1; next }
    !sub_skip { print }
' "${PROSE}")"

# ---------------------------------------------------------------------------
# 4. Forward check: schema fields (forward vocab) not mentioned in manual prose.
# ---------------------------------------------------------------------------
MISSING_FROM_PROSE=()
while IFS= read -r field; do
    [[ -z "${field}" ]] && continue
    if ! printf '%s\n' "${MANUAL_PROSE}" | grep -qF "${field}"; then
        MISSING_FROM_PROSE+=("${field}")
    fi
done <<< "${SCHEMA_FIELDS_FORWARD}"

# ---------------------------------------------------------------------------
# 5. Inverse check (conservative): prose tokens that look like field names
#    but are not in the schema (full vocabulary including deep nested fields).
#
# Uses INVERSE_PROSE (the manual prose with the "### Derived — NOT stored"
# and "### Excluded — separate plan" subsections structurally removed) so
# that non-field identifiers documented in those subsections are not flagged.
# ---------------------------------------------------------------------------
PROSE_CANDIDATES="$(printf '%s\n' "${INVERSE_PROSE}" | grep -oE '\`[a-z][a-z0-9_]+\`' | tr -d '`' | sort -u || true)"

STALE_REFS=()
while IFS= read -r token; do
    [[ -z "${token}" ]] && continue
    # Require >= 1 underscore (conservative filter against false positives).
    if [[ "${token}" != *_* ]]; then
        continue
    fi
    # Flag if not in the full schema field vocabulary (all depths).
    if ! printf '%s\n' "${SCHEMA_FIELDS_ALL}" | grep -qxF "${token}"; then
        STALE_REFS+=("${token}")
    fi
done <<< "${PROSE_CANDIDATES}"

# ---------------------------------------------------------------------------
# 6. Report and exit.
# ---------------------------------------------------------------------------
drift=0

if [[ -n "${MISSING_DESCS}" ]]; then
    drift=1
    printf 'DRIFT: the following schema fields are missing a description: keyword:\n'
    while IFS= read -r f; do
        [[ -z "${f}" ]] && continue
        printf '  [no description]  %s\n' "${f}"
    done <<< "${MISSING_DESCS}"
fi

if [[ ${#MISSING_FROM_PROSE[@]} -gt 0 ]]; then
    drift=1
    printf 'DRIFT: the following schema fields are missing from prose sections:\n'
    for f in "${MISSING_FROM_PROSE[@]}"; do
        printf '  [missing from prose]  %s\n' "${f}"
    done
fi

if [[ ${#STALE_REFS[@]} -gt 0 ]]; then
    drift=1
    printf 'DRIFT: the following backtick-wrapped identifiers in prose look like\n'
    printf '  state field names but are not in the schema (possible stale references):\n'
    for f in "${STALE_REFS[@]}"; do
        printf '  [stale reference]  %s\n' "${f}"
    done
fi

if [[ "${drift}" -eq 0 ]]; then
    printf 'OK: no schema/prose drift detected.\n'
fi

exit "${drift}"
