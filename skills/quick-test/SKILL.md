---
name: quick-test
description: Use this skill whenever the user wants to run only the tests relevant to their pending git diff rather than the full test suite — for instance "just run the tests for what I changed", "quick smoke test before commit", "fast test pass on this fix", or any pre-commit / pre-PR sanity check after editing code. The skill detects changed files via `git diff --name-only HEAD`, maps them to the corresponding tests for the project's language (Rust / TypeScript / Python / Go / Node), and runs the narrowest scope that still covers the change. Trigger even if the user does not say "quick test" — phrases like "did I break anything?", "rerun the tests on this file", or "run the relevant tests" all qualify. Skip if there are no uncommitted changes (nothing for `git diff` to pick up).
allowed-tools: Bash, Grep, Glob
---

# Diff-scoped fast test runner

Run only the tests related to the pending change set. Drastically faster than the full suite, suited for the inner edit loop and pre-commit gate.

## Step 1: Detect changed files

```bash
git diff --name-only HEAD
```

If the result is empty, report "no uncommitted changes — nothing to scope" and stop.

## Step 2: Identify project layout and pick a runner

### Rust (Cargo.toml)

Resolve the crate name from the changed path:

```bash
# crates/<name>/...   -> cargo test -p <name>
# src/...             -> cargo test (root crate)
```

When a core crate changes, also run downstream crates that depend on it.

### Node.js / TypeScript (package.json)

Auto-detect the runner from project config:

```bash
npm test              # package.json test script
npx vitest run        # Vitest
npx jest              # Jest
npx svelte-check      # Svelte type check
npx vue-tsc --noEmit  # Vue type check
npx tsc --noEmit      # TypeScript type check
```

### Python (pyproject.toml / setup.py)

```bash
pytest <test file matching the changed module>
# tests/test_<module>.py or <module>/tests/test_*.py
```

### Go (go.mod)

```bash
go test ./<changed package>/...
```

## Step 3: Narrow further when possible

Prefer a single test function when the change is localized:

- Rust: `cargo test -p <crate> <test_name>`
- Python: `pytest tests/test_module.py::test_function`
- Go: `go test -run TestName ./pkg/...`
- Node: `npx vitest run src/module.test.ts`

## Step 4: Report

- All green: report success.
- Failures: print the test name, failure reason, and a minimal repair suggestion.
- When a core module was changed, recommend a follow-up run on dependent modules to confirm no upstream regression.
