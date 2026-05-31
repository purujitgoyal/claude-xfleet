#!/usr/bin/env python3
"""JSON Schema validator for xfleet state files.

Usage:
    python validate-state.py <state-file> <schema-file> <def-name>

Arguments:
    state-file   Path to the JSON state file to validate.
    schema-file  Path to tools/xfleet/state-schema.json.
    def-name     Which $def to validate against: "orchestrator" or "worker".

Exit codes:
    0  valid
    1  schema validation failure (unknown key, bad type, missing required, etc.)
    2  malformed JSON or unreadable file
    3  schema_version missing or not "1"

On unknown-key failure the output includes the unknown key name and a
Levenshtein-based "did you mean X?" suggestion drawn from the known keys at
that schema level.
"""

import json
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# Levenshtein distance (inline — no external dependency)
# ---------------------------------------------------------------------------

def levenshtein(a, b):
    """Return the Levenshtein edit distance between strings a and b."""
    m, n = len(a), len(b)
    # Two-row rolling array to keep memory O(min(m,n)).
    if m < n:
        a, b, m, n = b, a, n, m
    prev = list(range(n + 1))
    for i in range(1, m + 1):
        curr = [i] + [0] * n
        for j in range(1, n + 1):
            cost = 0 if a[i - 1] == b[j - 1] else 1
            curr[j] = min(
                prev[j] + 1,        # deletion
                curr[j - 1] + 1,    # insertion
                prev[j - 1] + cost, # substitution
            )
        prev = curr
    return prev[n]


def closest_key(unknown, candidates):
    """Return the candidate with the smallest Levenshtein distance, or None."""
    if not candidates:
        return None
    return min(candidates, key=lambda c: levenshtein(unknown, c))


# ---------------------------------------------------------------------------
# Schema-version pre-check (SC-6)
# ---------------------------------------------------------------------------

SUPPORTED_VERSION = "1"
VERSION_ERROR = (
    "Unknown or missing schema_version; current plugin supports v1."
)


def check_schema_version(state):
    """Return VERSION_ERROR string if version is bad, else None."""
    sv = state.get("schema_version")
    if sv is None or sv != SUPPORTED_VERSION:
        return VERSION_ERROR
    return None


# ---------------------------------------------------------------------------
# Validation logic
# ---------------------------------------------------------------------------

def build_subschema(full_schema, def_name):
    """Build a standalone subschema from the named $def.

    Wraps the $def in a synthetic schema that exposes its $defs so that
    internal $refs resolve correctly under Draft202012Validator.
    """
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$defs": full_schema["$defs"],
        "$ref": f"#/$defs/{def_name}",
    }


def known_top_level_keys(full_schema, def_name):
    """Return the set of declared top-level property names for def_name."""
    obj = full_schema["$defs"].get(def_name, {})
    return set(obj.get("properties", {}).keys())


def format_error(err, full_schema, def_name):
    """Turn a ValidationError into a human-readable string with suggestions."""
    # jsonschema encodes the path to the offending instance in err.absolute_path
    # (a deque of keys/indices).  The failed validator is in err.validator.
    validator_name = err.validator
    path_parts = list(err.absolute_path)
    path_str = ".".join(str(p) for p in path_parts) if path_parts else "(root)"

    if validator_name == "additionalProperties":
        # err.message is like: "Additional properties are not allowed ('x' was unexpected)"
        # Extract the unknown key name from the message.
        msg = err.message
        # Isolate the key name between the first pair of quotes.
        import re
        match = re.search(r"'([^']+)'", msg)
        unknown = match.group(1) if match else "?"

        # Determine which level's known keys to suggest from.
        # Walk the schema along path_parts to find the sub-object schema.
        schema_node = full_schema["$defs"][def_name]
        for step in path_parts:
            props = schema_node.get("properties", {})
            if str(step) in props:
                schema_node = props[str(step)]
                # If this node is an array, step into items for the next round.
                if schema_node.get("type") == "array":
                    schema_node = schema_node.get("items", {})
            else:
                # Could be an additionalProperties map node.
                ap = schema_node.get("additionalProperties", {})
                if isinstance(ap, dict):
                    schema_node = ap
        known = set(schema_node.get("properties", {}).keys())

        suggestion = closest_key(unknown, known - {unknown})
        did_you_mean = f"; did you mean '{suggestion}'?" if suggestion else "."

        if path_str == "(root)":
            return f"Unknown key '{unknown}' at top level{did_you_mean}"
        return f"Unknown key '{unknown}' at {path_str}{did_you_mean}"

    # Generic fallback: surface the path and jsonschema's own message.
    return f"Validation error at {path_str}: {err.message}"


def validate(state_path, schema_path, def_name):
    """Validate state_path against schema_path using def_name.

    Returns (exit_code, messages_list).
    """
    # 1. Load files.
    try:
        state_text = Path(state_path).read_text(encoding="utf-8")
    except OSError as exc:
        return 2, [f"Cannot read state file: {exc}"]

    try:
        state = json.loads(state_text)
    except json.JSONDecodeError as exc:
        return 2, [f"JSON parse error: {exc}"]

    try:
        schema_text = Path(schema_path).read_text(encoding="utf-8")
        full_schema = json.loads(schema_text)
    except (OSError, json.JSONDecodeError) as exc:
        return 2, [f"Cannot load schema: {exc}"]

    # 2. schema_version pre-check (SC-6) — must come before jsonschema.
    ver_err = check_schema_version(state)
    if ver_err:
        return 3, [ver_err]

    # 3. JSON Schema validation.
    try:
        from jsonschema import Draft202012Validator
        from jsonschema.exceptions import ValidationError
    except ImportError as exc:
        return 2, [f"jsonschema not importable: {exc}"]

    subschema = build_subschema(full_schema, def_name)
    validator = Draft202012Validator(subschema)
    errors = sorted(validator.iter_errors(state), key=lambda e: list(e.absolute_path))

    if not errors:
        return 0, []

    messages = [format_error(e, full_schema, def_name) for e in errors]
    return 1, messages


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    if len(sys.argv) < 4:
        print(
            "Usage: validate-state.py <state-file> <schema-file> <orchestrator|worker>",
            file=sys.stderr,
        )
        sys.exit(2)

    state_path = sys.argv[1]
    schema_path = sys.argv[2]
    def_name = sys.argv[3]

    if def_name not in ("orchestrator", "worker"):
        print(f"Unknown def-name '{def_name}'; expected orchestrator or worker", file=sys.stderr)
        sys.exit(2)

    exit_code, messages = validate(state_path, schema_path, def_name)
    for msg in messages:
        print(msg)
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
