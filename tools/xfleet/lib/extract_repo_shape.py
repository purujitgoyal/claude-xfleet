#!/usr/bin/env python3
"""Repo-side Pydantic shape extractor for xfleet drift-check.

Imports a named Pydantic model from a target repo and prints its JSON Schema to
stdout. Runs under the REPO's OWN interpreter (so the model's transitive deps
resolve); drift_check.py shells out to it and never imports repo code itself.

Usage:
    python extract_repo_shape.py --module app.models.documents --model DocumentExtractRequest

Handles Pydantic v2 (model_json_schema()) and v1 (.schema()).

Exit codes:
    0  schema printed to stdout
    1  import / attribute / schema-extraction failure (message on stderr)
    2  bad arguments
"""

import argparse
import importlib
import json
import sys


def extract(module_name, model_name):
    """Import module_name, get model_name, return its JSON Schema dict."""
    try:
        module = importlib.import_module(module_name)
    except Exception as exc:  # noqa: BLE001 — surface any import-time failure
        raise RuntimeError(f"Cannot import module '{module_name}': {exc}") from exc

    try:
        model = getattr(module, model_name)
    except AttributeError as exc:
        raise RuntimeError(
            f"Module '{module_name}' has no attribute '{model_name}'"
        ) from exc

    # Prefer Pydantic v2; fall back to v1.
    if hasattr(model, "model_json_schema"):
        return model.model_json_schema()
    if hasattr(model, "schema"):
        return model.schema()
    raise RuntimeError(
        f"'{model_name}' is not a Pydantic model (no model_json_schema/schema)"
    )


def main():
    parser = argparse.ArgumentParser(description="Print a repo model's JSON Schema.")
    parser.add_argument("--module", required=True, help="Importable module path.")
    parser.add_argument("--model", required=True, help="Model attribute name.")
    args = parser.parse_args()

    try:
        schema = extract(args.module, args.model)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)

    json.dump(schema, sys.stdout)
    sys.stdout.write("\n")
    sys.exit(0)


if __name__ == "__main__":
    main()
