#!/usr/bin/env bats
# Consistency tests for shared/messaging.md (Task 7).
#
# tests/docs/ is two levels below the repo root, so:
#   BATS_TEST_DIRNAME = <repo>/tests/docs
#   ../../shared/messaging.md                    = <repo>/shared/messaging.md
#   ../../tools/xfleet/lib/subcommand-registry.sh = the canonical registry
#
# These tests guard the section (h) "5-column subcommand table" against drift
# from the canonical XFLEET_SUBCOMMANDS registry. They deliberately ONLY inspect
# the section (h) table rows (bounded between the section (h) heading and the
# next heading) so that reflexive auto-handler names documented in section (f)
# prose are NOT matched by the inverse check.

bats_require_minimum_version 1.5.0

DOC="${BATS_TEST_DIRNAME}/../../shared/messaging.md"
REGISTRY="${BATS_TEST_DIRNAME}/../../tools/xfleet/lib/subcommand-registry.sh"

# Heading marker that opens section (h). The doc MUST contain this literal
# marker so the test can bound the table region deterministically.
SECTION_H_MARKER='SECTION-H-SUBCOMMAND-TABLE'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Load the 19 registry names into the REGISTRY_NAMES array.
load_registry_names() {
    # shellcheck disable=SC1090
    source "${REGISTRY}"
    REGISTRY_NAMES=("${XFLEET_SUBCOMMANDS[@]}")
}

# Extract the first pipe-delimited column from every data row of the section (h)
# table, trimming backticks and whitespace. Emits one name per line.
#
# Region is bounded: from the line containing $SECTION_H_MARKER up to (but not
# including) the next markdown heading line (a line starting with '#').
# Within that region we keep only table data rows: lines that start with '|',
# contain at least one more '|', and are NOT the header separator (---) or the
# header label row (whose first cell is literally "subcommand").
extract_table_names() {
    awk -v marker="${SECTION_H_MARKER}" '
        # Enter the region once we see the marker line.
        $0 ~ marker { inregion = 1; next }
        # A heading after the region begins ends the region.
        inregion && /^#/ { inregion = 0 }
        inregion {
            line = $0
            # Must look like a table row: leading optional space then "|".
            sub(/^[ \t]+/, "", line)
            if (line !~ /^\|/) next
            # Split on "|"; field 2 is the first column (field 1 is empty).
            n = split(line, cells, "|")
            if (n < 3) next
            col = cells[2]
            # Trim whitespace and backticks.
            gsub(/[ \t`]/, "", col)
            if (col == "") next
            # Skip separator rows (e.g. ---, :---:).
            if (col ~ /^:?-+:?$/) next
            # Skip the header label row.
            if (col == "subcommand") next
            print col
        }
    ' "${DOC}"
}

# ---------------------------------------------------------------------------
# Existence / structure
# ---------------------------------------------------------------------------

@test "shared/messaging.md exists" {
    [ -f "${DOC}" ]
}

@test "subcommand registry exists" {
    [ -f "${REGISTRY}" ]
}

@test "registry exposes exactly 19 subcommands" {
    load_registry_names
    [ "${#REGISTRY_NAMES[@]}" -eq 19 ]
}

@test "section (h) marker is present in messaging.md" {
    run grep -F "${SECTION_H_MARKER}" "${DOC}"
    [ "$status" -eq 0 ]
}

@test "section (h) table has exactly 19 data rows" {
    run extract_table_names
    [ "$status" -eq 0 ]
    count="$(printf '%s\n' "$output" | grep -c .)"
    [ "$count" -eq 19 ]
}

# ---------------------------------------------------------------------------
# Forward check: every registry name appears as a section (h) table row.
# ---------------------------------------------------------------------------

@test "every registry subcommand has a row in section (h) table" {
    load_registry_names
    table_names="$(extract_table_names)"
    missing=()
    for name in "${REGISTRY_NAMES[@]}"; do
        if ! printf '%s\n' "${table_names}" | grep -qxF "${name}"; then
            missing+=("${name}")
        fi
    done
    if [ "${#missing[@]}" -ne 0 ]; then
        echo "Registry names missing from section (h) table: ${missing[*]}" >&2
    fi
    [ "${#missing[@]}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Inverse check: every section (h) table row name exists in the registry.
# (Reflexive handlers in section (f) prose are outside the table region and
#  therefore never reach this check.)
# ---------------------------------------------------------------------------

@test "every section (h) table row maps to a real registry subcommand" {
    load_registry_names
    registry_blob="$(printf '%s\n' "${REGISTRY_NAMES[@]}")"
    extra=()
    while IFS= read -r row_name; do
        [ -z "${row_name}" ] && continue
        if ! printf '%s\n' "${registry_blob}" | grep -qxF "${row_name}"; then
            extra+=("${row_name}")
        fi
    done < <(extract_table_names)
    if [ "${#extra[@]}" -ne 0 ]; then
        echo "Section (h) table rows not in registry: ${extra[*]}" >&2
    fi
    [ "${#extra[@]}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Reflexive handlers must NOT appear as section (h) table rows.
# ---------------------------------------------------------------------------

@test "reflexive auto-handler names are absent from section (h) table" {
    table_names="$(extract_table_names)"
    reflexive=(directive-ack directive-response task-response resolution-ack resolution-summary escalation-response)
    leaked=()
    for name in "${reflexive[@]}"; do
        if printf '%s\n' "${table_names}" | grep -qxF "${name}"; then
            leaked+=("${name}")
        fi
    done
    if [ "${#leaked[@]}" -ne 0 ]; then
        echo "Reflexive handlers leaked into section (h) table: ${leaked[*]}" >&2
    fi
    [ "${#leaked[@]}" -eq 0 ]
}
