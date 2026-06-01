#!/usr/bin/env python3
"""Deterministic Pydantic drift check for xfleet contracts (Task 3).

Answers: does {repo}'s current Pydantic shape for contract C-N still match the
locked canonical shape in contracts.md?

Two-interpreter design (resolves the cross-environment import problem):
  - Canonical shape: the self-contained ```python block under "### Canonical
    shape" (imports only pydantic + typing) is exec'd HERE under $XFLEET_PYTHON.
  - Repo shape: extract_repo_shape.py is run under the REPO's interpreter
    (--repo-python); it imports the real model and prints its JSON Schema, which
    we parse. We never import repo code ourselves.

Usage:
    drift_check.py --contract C-1 --repo server --contracts-file PATH \\
        [--repo-python python3]

Output: structured JSON report on stdout. Exit 0 even on drift (drift is in the
payload). Non-zero only on hard errors (contract/locator not found, helper fail).

Exit codes:
    0  ran successfully (see "drift" in the JSON payload)
    1  hard error (contract not found, no locator, repo-helper failure, etc.)
    2  bad arguments
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

import deepdiff

# Keys stripped from both schemas before diffing — they carry no structural
# meaning (docstrings/field titles) and would create noise.
VOLATILE_KEYS = {"title", "description"}

HELPER = Path(__file__).resolve().parent / "extract_repo_shape.py"


# ---------------------------------------------------------------------------
# contracts.md parsing
# ---------------------------------------------------------------------------

def find_contract_section(text, contract):
    """Return the markdown slice for '## {contract} — ...', or None.

    The section runs from its '## ' header until the next '## ' at the same
    level (or end of file).
    """
    lines = text.splitlines()
    # Header looks like "## C-1 — ..." — match the contract token as a word.
    header_re = re.compile(r"^##\s+" + re.escape(contract) + r"\b")
    start = None
    for i, line in enumerate(lines):
        if header_re.match(line):
            start = i
            break
    if start is None:
        return None
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if lines[j].startswith("## "):
            end = j
            break
    return "\n".join(lines[start:end])


def extract_canonical_block(section):
    """Return the first ```python fenced block under '### Canonical shape'.

    Returns the code string, or None if absent.
    """
    lines = section.splitlines()
    in_canonical = False
    for i, line in enumerate(lines):
        if re.match(r"^###\s+Canonical shape\b", line):
            in_canonical = True
            continue
        if in_canonical:
            # Stop scanning at the next ### subsection.
            if line.startswith("### "):
                return None
            if re.match(r"^```python\b", line.strip()):
                body = []
                for k in range(i + 1, len(lines)):
                    # Only a bare closing fence at column 0 ends the block; an
                    # indented/nested ``` inside the code does not.
                    if re.match(r"^```\s*$", lines[k]):
                        return "\n".join(body)
                    body.append(lines[k])
                return None
    return None


def find_locator(section, repo):
    """Return the 'module:Model' coordinate for repo from the Verification block.

    Looks under '### Verification at IP close' for a line whose first non-markdown
    token is '{repo} (' and that contains a backtick-wrapped 'module:Model'.
    Returns the coordinate string, or None.
    """
    lines = section.splitlines()
    in_verif = False
    # Strip leading list markers / bold / whitespace, then require "{repo} (".
    repo_re = re.compile(
        r"^[\s\-\*]*(?:\*\*)?" + re.escape(repo) + r"(?:\*\*)?\s*\("
    )
    coord_re = re.compile(r"`([^`]+:[^`]+)`")
    for line in lines:
        if re.match(r"^###\s+Verification\b", line):
            in_verif = True
            continue
        if in_verif and line.startswith("### "):
            break
        if in_verif and repo_re.match(line):
            m = coord_re.search(line)
            if m:
                return m.group(1).strip()
    return None


# ---------------------------------------------------------------------------
# Canonical shape extraction (exec under this interpreter)
# ---------------------------------------------------------------------------

def canonical_schemas(code):
    """Exec the canonical block in an isolated namespace; return {name: schema}.

    Returns a dict of every Pydantic model defined in the block (by class name)
    to its JSON Schema.
    """
    ns = {}
    exec(compile(code, "<canonical>", "exec"), ns)  # noqa: S102 — trusted, in-repo source
    base = ns.get("BaseModel")
    schemas = {}
    for name, obj in ns.items():
        if not (isinstance(obj, type) and hasattr(obj, "model_json_schema")):
            continue
        # Skip the imported BaseModel itself; keep concrete models in the block.
        if base is not None and obj is base:
            continue
        schemas[name] = obj.model_json_schema()
    return schemas


# ---------------------------------------------------------------------------
# Repo shape extraction (shell out to the repo's interpreter)
# ---------------------------------------------------------------------------

def repo_schema(repo_python, module, model):
    """Run extract_repo_shape.py under repo_python; return the parsed schema.

    Raises RuntimeError with a clear message on helper failure / bad output.
    """
    cmd = [repo_python, str(HELPER), "--module", module, "--model", model]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True)
    except OSError as exc:
        raise RuntimeError(f"Cannot run repo interpreter '{repo_python}': {exc}") from exc
    if proc.returncode != 0:
        detail = proc.stderr.strip() or proc.stdout.strip() or "(no output)"
        raise RuntimeError(f"Repo shape extraction failed: {detail}")
    return parse_repo_stdout(proc.stdout)


def parse_repo_stdout(stdout):
    """Extract the JSON Schema payload from helper stdout, tolerating noise.

    The repo's imports may print warnings/log lines to stdout before the JSON.
    Try whole-stdout parse first, then the last non-empty line, then the first
    line beginning with '{'. Raise with the raw stdout on total failure.
    """
    candidates = [stdout]
    lines = [ln for ln in stdout.splitlines() if ln.strip()]
    if lines:
        candidates.append(lines[-1])
    for ln in lines:
        if ln.lstrip().startswith("{"):
            candidates.append(ln)
            break
    for cand in candidates:
        try:
            return json.loads(cand)
        except json.JSONDecodeError:
            continue
    raise RuntimeError(
        f"Repo helper produced no parseable JSON. Raw stdout:\n{stdout!r}"
    )


# ---------------------------------------------------------------------------
# Canonicalization + diff
# ---------------------------------------------------------------------------

def canonicalize(schema):
    """Strip volatile keys recursively and sort every 'required' list."""
    if isinstance(schema, dict):
        out = {}
        for key, val in schema.items():
            if key in VOLATILE_KEYS:
                continue
            if key == "required" and isinstance(val, list):
                out[key] = sorted(val)
            else:
                out[key] = canonicalize(val)
        return out
    if isinstance(schema, list):
        return [canonicalize(v) for v in schema]
    return schema


def classify(diff):
    """Turn a DeepDiff result into added/removed/type_changed/optionality_changed.

    Deliberately coarse — semantic additive/breaking classification is a later
    layer's job. We map deepdiff buckets to property-path lists.
    """
    added, removed, type_changed, optionality_changed = [], [], [], []

    # deepdiff 9.1.0 shapes: *_item_added/removed are SetOrdered (set-like) for
    # dict keys and dict (path->value) for iterable items; *_changed/type_changes
    # are dict (path->detail). Iterating any of them yields path strings, so we
    # normalize every bucket to "iterate the paths" uniformly.
    def paths(key):
        return list(diff.get(key, ()))

    # Added/removed members. A change inside a 'required' list (sorted list of
    # field names) is an optionality change, not an add/remove of a property.
    for path in paths("dictionary_item_added") + paths("iterable_item_added"):
        (optionality_changed if "['required']" in path else added).append(path)
    for path in paths("dictionary_item_removed") + paths("iterable_item_removed"):
        (optionality_changed if "['required']" in path else removed).append(path)

    # Value/type changes. A 'required' membership swap is optionality; otherwise
    # treat as a type change (coarse — semantic classification is a later layer).
    for path in paths("values_changed"):
        (optionality_changed if "['required']" in path else type_changed).append(path)
    for path in paths("type_changes"):
        type_changed.append(path)

    return added, removed, type_changed, optionality_changed


def diff_model(canonical, repo):
    """Canonicalize both schemas and return the classified drift report dict."""
    can = canonicalize(canonical)
    rep = canonicalize(repo)
    dd = deepdiff.DeepDiff(can, rep, ignore_order=True)
    added, removed, type_changed, optionality_changed = classify(dd)
    drift = bool(added or removed or type_changed or optionality_changed)
    return {
        "drift": drift,
        "added": added,
        "removed": removed,
        "type_changed": type_changed,
        "optionality_changed": optionality_changed,
    }


# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------

def run(contract, repo, contracts_file, repo_python):
    """Return (exit_code, report_dict_or_error_str)."""
    try:
        text = Path(contracts_file).read_text(encoding="utf-8")
    except OSError as exc:
        return 1, f"Cannot read contracts file: {exc}"

    section = find_contract_section(text, contract)
    if section is None:
        return 1, f"Contract '{contract}' not found in {contracts_file}"

    code = extract_canonical_block(section)
    if code is None:
        return 1, f"No '### Canonical shape' python block for {contract}"

    try:
        can_schemas = canonical_schemas(code)
    except Exception as exc:  # noqa: BLE001
        return 1, f"Failed to exec canonical block for {contract}: {exc}"
    if not can_schemas:
        return 1, f"No Pydantic model found in canonical block for {contract}"

    locator = find_locator(section, repo)
    if locator is None:
        return 1, f"No drift-check locator for repo '{repo}' in {contract}"
    if ":" not in locator:
        return 1, f"Malformed locator '{locator}' for repo '{repo}' (expected module:Model)"
    module, model = locator.split(":", 1)
    module, model = module.strip(), model.strip()

    # The locator maps one repo to one model. Pick the canonical schema for that
    # model name; fall back to the sole model if names differ but there's one.
    if model in can_schemas:
        canonical = can_schemas[model]
    elif len(can_schemas) == 1:
        canonical = next(iter(can_schemas.values()))
    else:
        return 1, (
            f"Locator model '{model}' not among canonical models "
            f"{sorted(can_schemas)} for {contract}"
        )

    try:
        rep = repo_schema(repo_python, module, model)
    except RuntimeError as exc:
        return 1, str(exc)

    report = diff_model(canonical, rep)
    report = {"contract": contract, "repo": repo, **report}
    return 0, report


def main():
    parser = argparse.ArgumentParser(
        description="Deterministic Pydantic drift check against a locked contract."
    )
    parser.add_argument("--contract", required=True, help="Contract id, e.g. C-1.")
    parser.add_argument("--repo", required=True, help="Repo whose locator to use.")
    parser.add_argument("--contracts-file", required=True, help="Path to contracts.md.")
    parser.add_argument(
        "--repo-python",
        default="python3",
        help="Interpreter for the repo's own deps (default: python3).",
    )
    args = parser.parse_args()

    exit_code, result = run(
        args.contract, args.repo, args.contracts_file, args.repo_python
    )
    if exit_code != 0:
        print(result, file=sys.stderr)
        sys.exit(exit_code)

    json.dump(result, sys.stdout)
    sys.stdout.write("\n")
    sys.exit(0)


if __name__ == "__main__":
    main()
