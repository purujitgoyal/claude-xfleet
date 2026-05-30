#!/usr/bin/env python3
"""Generate the Field Reference table in shared/state-schema.md from the JSON Schema.

Walks each top-level $def (orchestrator, worker), flattens nested objects with
dotted paths (map-value keys shown as {key}), and emits one Markdown table per
object between the <!-- BEGIN GENERATED --> / <!-- END GENERATED --> markers.
Operator/CI-run, not session-run.
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent.parent
SCHEMA = ROOT / "tools" / "xfleet" / "state-schema.json"
DOC = ROOT / "shared" / "state-schema.md"

BEGIN = "<!-- BEGIN GENERATED -->"
END = "<!-- END GENERATED -->"

# Top-level $defs to document, in order, with their state-file label.
OBJECTS = [("orchestrator", "_orchestrator.json"), ("worker", "{worker}.json")]


def type_str(node):
    if "const" in node:
        return f'const "{node["const"]}"'
    if "enum" in node:
        return "enum: " + ", ".join(node["enum"])
    t = node.get("type", "any")
    if isinstance(t, list):
        return " \\| ".join(t)
    if t == "array":
        item_t = node.get("items", {}).get("type", "any")
        return f"array<{item_t}>"
    if t == "object":
        return "object"
    return t


def walk(name, node, required, prefix, rows):
    """Emit a row for `node`, then recurse into nested object/map/array shapes."""
    field = f"{prefix}{name}"
    desc = node.get("description", "").replace("\n", " ").strip()
    req = "yes" if name in required else "no"
    rows.append((field, type_str(node), req, desc))

    t = node.get("type")
    types = t if isinstance(t, list) else [t]

    if "object" in types:
        props = node.get("properties")
        if props:
            sub_req = node.get("required", [])
            for k, v in props.items():
                walk(k, v, sub_req, f"{field}.", rows)
        # map-shaped object: value subschema under additionalProperties
        ap = node.get("additionalProperties")
        if isinstance(ap, dict):
            walk("{key}", ap, [], f"{field}.", rows)
    if "array" in types:
        items = node.get("items", {})
        if items.get("type") == "object" and items.get("properties"):
            sub_req = items.get("required", [])
            for k, v in items["properties"].items():
                walk(k, v, sub_req, f"{field}[].", rows)


def table_for(defs, def_name, label):
    obj = defs[def_name]
    required = obj.get("required", [])
    rows = []
    for k, v in obj["properties"].items():
        walk(k, v, required, "", rows)

    lines = [f"### `{label}`", "", "| Field | Type | Required | Description |",
             "|-------|------|----------|-------------|"]
    for field, typ, req, desc in rows:
        lines.append(f"| `{field}` | {typ} | {req} | {desc} |")
    return "\n".join(lines)


def main():
    schema = json.loads(SCHEMA.read_text())
    defs = schema["$defs"]
    blocks = [table_for(defs, name, label) for name, label in OBJECTS]
    generated = "\n\n".join(blocks)

    lines = DOC.read_text().splitlines()
    # Anchor on the markers as standalone lines so prose mentioning the marker
    # tokens cannot collide with the real block delimiters.
    begin_idx = next(i for i, ln in enumerate(lines) if ln.strip() == BEGIN)
    end_idx = next(i for i, ln in enumerate(lines) if ln.strip() == END)
    if end_idx <= begin_idx:
        raise SystemExit("END marker must follow BEGIN marker")

    new_lines = lines[: begin_idx + 1] + generated.splitlines() + lines[end_idx:]
    DOC.write_text("\n".join(new_lines) + "\n")
    print(f"Field Reference regenerated in {DOC}")


if __name__ == "__main__":
    main()
