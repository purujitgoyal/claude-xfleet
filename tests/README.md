# Tests

## Dependencies

### BATS (shell tests)

macOS:
```
brew install bats-core
```

Linux (Debian/Ubuntu):
```
apt install bats
```

### Python / jsonschema (state-schema tests)

```
pip install jsonschema
```

Or use the plugin's setup-script-managed venv (see the top-level README for `xfleet setup`). Set `XFLEET_PYTHON` to point at that venv's python binary to use it when running tests.

## Running tests

```
bash tests/run-all.sh
```

`XFLEET_PYTHON` overrides the python binary used to run `test_*.py` files (default: `python3`). Example:

```
XFLEET_PYTHON=~/.config/xfleet/venv/bin/python bash tests/run-all.sh
```

## Test layout

```
tests/
  smoke.bats          # dispatcher smoke test (fails until Task 6 lands bin/xfleet)
  state-validator/    # Python jsonschema tests (test_schema.py lands in Task 17)
  run-all.sh          # top-level test runner
```

## Why does smoke.bats fail?

`tests/smoke.bats` asserts that `bin/xfleet` is executable and responds to `--help`. This is an intentional TDD red — `bin/xfleet` does not exist yet. It will pass once Task 6 lands the dispatcher.
