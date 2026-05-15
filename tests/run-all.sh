#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="${REPO_ROOT}/tests"
PYTHON="${XFLEET_PYTHON:-python3}"

failed=0

# Run all BATS suites
bats_files=()
while IFS= read -r -d '' f; do
    bats_files+=("$f")
done < <(find "${TESTS_DIR}" -name "*.bats" -print0 | sort -z)

if [[ ${#bats_files[@]} -gt 0 ]]; then
    echo "=== BATS ==="
    for f in "${bats_files[@]}"; do
        echo "--- $f"
        if ! bats "$f"; then
            failed=1
        fi
    done
else
    echo "=== BATS: no .bats files found ==="
fi

# Run all Python state-schema tests
py_files=()
while IFS= read -r -d '' f; do
    py_files+=("$f")
done < <(find "${TESTS_DIR}/state-validator" -name "test_*.py" -print0 2>/dev/null | sort -z)

if [[ ${#py_files[@]} -gt 0 ]]; then
    echo "=== Python (state-validator) ==="
    for f in "${py_files[@]}"; do
        echo "--- $f"
        if ! "${PYTHON}" "$f"; then
            failed=1
        fi
    done
else
    echo "=== Python (state-validator): no test_*.py files found ==="
fi

# Summary
echo ""
if [[ $failed -eq 0 ]]; then
    echo "All tests passed."
else
    echo "One or more tests FAILED." >&2
    exit 1
fi
