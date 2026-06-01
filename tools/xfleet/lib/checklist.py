#!/usr/bin/env python3
"""Structural validator for xfleet repo-spec (spec.md + contracts.md).

Usage:
    checklist.py --mode repo-spec --spec-file PATH --contracts-file PATH

Exit codes:
    0  all checks pass (warnings may still be printed)
    1  one or more ERROR findings
    2  bad arguments or unreadable input files
"""

import argparse
import re
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# Finding model
# ---------------------------------------------------------------------------

class Finding:
    def __init__(self, severity, code, message):
        # severity: "ERROR" or "WARNING"
        self.severity = severity
        self.code = code
        self.message = message

    def __str__(self):
        return f"[{self.severity}] {self.code}: {self.message}"


def error(code, message):
    return Finding("ERROR", code, message)


def warning(code, message):
    return Finding("WARNING", code, message)


# ---------------------------------------------------------------------------
# spec.md parsing — Integration Points table
# ---------------------------------------------------------------------------

def parse_ip_table(text):
    """Return list of dicts for every data row in the ## Integration Points table.

    Each dict has keys: id, name, repos, contracts, t4_gate, status, raw_line.
    Returns (rows, findings) — findings for structural issues with the table itself.
    """
    lines = text.splitlines()
    findings = []

    # Find the ## Integration Points section.
    section_start = None
    for i, line in enumerate(lines):
        if re.match(r"^##\s+Integration Points\b", line):
            section_start = i
            break
    if section_start is None:
        findings.append(error("IP-TABLE-MISSING", "No '## Integration Points' section found in spec.md"))
        return [], findings

    # Collect table lines until blank line or next ## section.
    table_lines = []
    for line in lines[section_start + 1:]:
        if line.startswith("## "):
            break
        if line.strip() == "" and table_lines:
            # Blank line after at least one table line ends the table.
            if any(l.startswith("|") for l in table_lines):
                break
        table_lines.append(line)

    # Extract rows (lines beginning with |, skip separator rows).
    raw_rows = [l for l in table_lines if l.startswith("|") and not re.match(r"^\|[-| ]+\|", l)]
    if not raw_rows:
        findings.append(error("IP-TABLE-EMPTY", "## Integration Points table has no data rows"))
        return [], findings

    # First row is the header.
    header_row = raw_rows[0]
    headers = [h.strip().lower() for h in header_row.strip("|").split("|")]

    # Map expected column names to indices.
    col = {}
    for name in ("id", "name", "repos", "contracts in scope", "t4 gate", "status"):
        try:
            col[name] = headers.index(name)
        except ValueError:
            findings.append(error("IP-HEADER-MISSING", f"IP table missing column '{name}'"))

    if findings:
        return [], findings

    rows = []
    for raw in raw_rows[1:]:
        cells = [c.strip() for c in raw.strip("|").split("|")]
        # Pad short rows.
        while len(cells) <= max(col.values()):
            cells.append("")

        rows.append({
            "id": cells[col["id"]],
            "name": cells[col["name"]],
            "repos": cells[col["repos"]],
            "contracts": cells[col["contracts in scope"]],
            "t4_gate": cells[col["t4 gate"]],
            "status": cells[col["status"]],
            "raw_line": raw,
        })

    return rows, findings


# ---------------------------------------------------------------------------
# contracts.md parsing
# ---------------------------------------------------------------------------

def find_contract_section(text, contract_id):
    """Return markdown slice for '## {contract_id} — ...', or None.

    Mirrors the approach in drift_check.py (not imported to avoid coupling).
    """
    lines = text.splitlines()
    header_re = re.compile(r"^##\s+" + re.escape(contract_id) + r"\b")
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


def list_contract_ids(text):
    """Return all C-N ids found as ## section headers in contracts.md."""
    ids = []
    for line in text.splitlines():
        m = re.match(r"^##\s+(C-\d+)\b", line)
        if m:
            ids.append(m.group(1))
    return ids


def canonical_has_python_fence(section):
    """True if a ```python fence sits under '### Canonical shape'.

    Mirrors drift_check.py's extract_canonical_block scoping: only the text
    between the Canonical shape heading and the next '### ' counts, so a fence
    living under '### Intent' does not falsely satisfy the canonical check.
    """
    lines = section.splitlines()
    in_canonical = False
    for line in lines:
        if re.match(r"^###\s+Canonical shape\b", line):
            in_canonical = True
            continue
        if in_canonical:
            if line.startswith("### "):
                return False
            if re.match(r"^```python\b", line.strip()):
                return True
    return False


def check_contract_parts(contract_id, section):
    """Return list of ERROR findings for missing required subsections."""
    findings = []
    has_canonical = bool(re.search(r"^###\s+Canonical shape\b", section, re.MULTILINE))
    has_python_fence = canonical_has_python_fence(section)
    has_intent = bool(re.search(r"^###\s+Intent\b", section, re.MULTILINE))
    has_verif = bool(re.search(r"^###\s+Verification at IP close\b", section, re.MULTILINE))

    if not has_canonical:
        findings.append(error("CONTRACT-NO-CANONICAL", f"{contract_id}: missing '### Canonical shape' subsection"))
    elif not has_python_fence:
        findings.append(error("CONTRACT-NO-PYDANTIC", f"{contract_id}: '### Canonical shape' has no ```python block"))
    if not has_intent:
        findings.append(error("CONTRACT-NO-INTENT", f"{contract_id}: missing '### Intent' subsection"))
    if not has_verif:
        findings.append(error("CONTRACT-NO-VERIF", f"{contract_id}: missing '### Verification at IP close' subsection"))
    return findings


# ---------------------------------------------------------------------------
# Verification path heuristic
# ---------------------------------------------------------------------------

# Patterns that suggest a file path argument follows the command keyword.
_PYTEST_RE = re.compile(r"\bpytest\s+([\w/.\-]+\.py\b)")
_NPM_TEST_RE = re.compile(r"\bnpm test\s+--\s+([\w/.\-]+\.(?:spec|test)\.[tj]s\b)")


def extract_test_paths(verif_section_text):
    """Return list of (path_str, context_line) from pytest/npm test commands."""
    results = []
    for line in verif_section_text.splitlines():
        for m in _PYTEST_RE.finditer(line):
            results.append((m.group(1), line.strip()))
        for m in _NPM_TEST_RE.finditer(line):
            results.append((m.group(1), line.strip()))
    return results


def check_verif_paths(contract_id, section):
    """Return WARNING findings for referenced test paths that don't exist.

    Best-effort: missing repo checkout is a WARNING, not an ERROR.
    """
    findings = []
    # Isolate the Verification subsection.
    lines = section.splitlines()
    in_verif = False
    verif_lines = []
    for line in lines:
        if re.match(r"^###\s+Verification at IP close\b", line):
            in_verif = True
            continue
        if in_verif and line.startswith("### "):
            break
        if in_verif:
            verif_lines.append(line)

    if not verif_lines:
        return findings

    verif_text = "\n".join(verif_lines)
    for path_str, context in extract_test_paths(verif_text):
        p = Path(path_str)
        if not p.is_absolute() and not p.exists():
            findings.append(warning(
                "VERIF-PATH-MISSING",
                f"{contract_id}: test path '{path_str}' not found locally "
                f"(repo may not be checked out) — context: {context!r}"
            ))
    return findings


# ---------------------------------------------------------------------------
# IP row validation
# ---------------------------------------------------------------------------

def validate_ip_rows(rows):
    """Return ERROR findings for malformed IP rows."""
    findings = []
    for row in rows:
        ip_id = row["id"] or "(unknown)"
        if not row["repos"].strip():
            findings.append(error("IP-MISSING-REPOS", f"IP {ip_id}: 'Repos' cell is empty"))
        if not row["contracts"].strip():
            findings.append(error("IP-MISSING-CONTRACTS", f"IP {ip_id}: 'Contracts in scope' cell is empty"))
        # Must be canonical lowercase exactly — downstream orchestrator
        # string-compares this, so True/TRUE/False must NOT pass.
        t4 = row["t4_gate"].strip()
        if t4 not in ("true", "false"):
            findings.append(error(
                "IP-BAD-T4GATE",
                f"IP {ip_id}: T4 Gate must be 'true' or 'false', got '{row['t4_gate'].strip()}'"
            ))
    return findings


def extract_contract_ids_from_ip(row):
    """Return list of C-N ids from a row's 'Contracts in scope' cell."""
    raw = row["contracts"]
    return [t.strip() for t in raw.split(",") if t.strip()]


# ---------------------------------------------------------------------------
# Main validation
# ---------------------------------------------------------------------------

def validate_repo_spec(spec_file, contracts_file):
    """Run all checks; return list of Finding objects."""
    all_findings = []

    # Load files.
    try:
        spec_text = Path(spec_file).read_text(encoding="utf-8")
    except OSError as exc:
        print(f"Cannot read spec file: {exc}", file=sys.stderr)
        sys.exit(2)

    try:
        contracts_text = Path(contracts_file).read_text(encoding="utf-8")
    except OSError as exc:
        print(f"Cannot read contracts file: {exc}", file=sys.stderr)
        sys.exit(2)

    # Parse IP table.
    rows, table_findings = parse_ip_table(spec_text)
    all_findings.extend(table_findings)
    if table_findings:
        # Fatal structural problem — can't proceed with cross-ref checks.
        return all_findings

    # Validate required IP cells and T4 Gate format.
    all_findings.extend(validate_ip_rows(rows))

    # Collect all C-N ids referenced by IPs.
    referenced_ids = {}  # id -> [ip_id, ...]
    for row in rows:
        for cid in extract_contract_ids_from_ip(row):
            referenced_ids.setdefault(cid, []).append(row["id"])

    # Collect all C-N ids defined in contracts.md.
    defined_ids = set(list_contract_ids(contracts_text))

    # Check dangling references (IP refs an undefined contract).
    for cid, ip_ids in referenced_ids.items():
        if cid not in defined_ids:
            all_findings.append(error(
                "CONTRACT-DANGLING-REF",
                f"Contract '{cid}' referenced by IP(s) {ip_ids} not found in contracts.md"
            ))

    # Check orphan contracts (defined but not referenced by any IP).
    for cid in sorted(defined_ids):
        if cid not in referenced_ids:
            all_findings.append(error(
                "CONTRACT-ORPHAN",
                f"Contract '{cid}' defined in contracts.md but not referenced by any IP"
            ))

    # Per-contract structural checks.
    for cid in sorted(defined_ids):
        section = find_contract_section(contracts_text, cid)
        if section is None:
            # Shouldn't happen since we found it via list_contract_ids, but guard.
            continue
        all_findings.extend(check_contract_parts(cid, section))
        all_findings.extend(check_verif_paths(cid, section))

    return all_findings


# ---------------------------------------------------------------------------
# Output + entry point
# ---------------------------------------------------------------------------

def print_findings(findings):
    if not findings:
        print("OK: all checks passed.")
        return
    errors = [f for f in findings if f.severity == "ERROR"]
    warnings = [f for f in findings if f.severity == "WARNING"]
    for f in errors + warnings:
        print(str(f))
    print(f"\n{len(errors)} error(s), {len(warnings)} warning(s).")


def main():
    parser = argparse.ArgumentParser(
        description="Structural validator for xfleet repo-spec."
    )
    parser.add_argument("--mode", required=True, choices=["repo-spec"], help="Validation mode.")
    parser.add_argument("--spec-file", required=True, help="Path to spec.md.")
    parser.add_argument("--contracts-file", required=True, help="Path to contracts.md.")
    args = parser.parse_args()

    findings = validate_repo_spec(args.spec_file, args.contracts_file)
    print_findings(findings)

    has_errors = any(f.severity == "ERROR" for f in findings)
    sys.exit(1 if has_errors else 0)


if __name__ == "__main__":
    main()
