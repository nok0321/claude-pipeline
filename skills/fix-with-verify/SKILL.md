---
name: fix-with-verify
description: Use this skill whenever the user wants to apply a single bug fix or refactor with a built-in safety net — compile/type-check after each edit, run the existing test suite as a regression baseline, and automatically revert if the change breaks anything green. Trigger phrases include "fix this bug safely", "fix and verify", "make sure this doesn't break anything", "fix with regression check", "patch this without breaking other tests", or any single-issue fix where the user worries about ripple effects. Trigger even when the user does not say "fix-with-verify" — implicit phrases like "fix this but check it works", "small fix with safety", or "patch this and run the tests" qualify. For broad feature work, prefer `impl-orchestrator` instead.
argument-hint: "[issue-description or file:line]"
allowed-tools: Read, Write, Edit, MultiEdit, Bash, Grep, Glob
---

# Fix → verify pipeline

Apply a localized fix, prove it does not introduce regressions, and revert automatically when verification fails.

## Step 1: Record baseline

1. Inspect the current state with `git diff` to establish what is already pending.
2. Run the existing test suite to record a baseline (auto-detect language):

| Language | Command |
|----------|---------|
| Rust | `cargo test -p <crate> 2>&1 \| tail -20` |
| Python | `pytest <test file> 2>&1 \| tail -20` |
| Go | `go test ./<package>/... 2>&1 \| tail -20` |
| Node | `npm test 2>&1 \| tail -20` |

3. If tests already fail, confirm whether those failures are exactly the target of this fix.

## Step 2: Impact analysis

1. Use Grep to find call sites of the function or type under repair.
2. Inspect module dependencies — a change in a core module can ripple downstream.
3. Treat changes to public-API signatures as broad-impact and plan accordingly.

## Step 3: Apply the fix

1. Edit **one file at a time**. Bundling multi-file edits before verification defeats the safety net.
2. After each edit, run a compile or type check:

| Language | Command |
|----------|---------|
| Rust | `cargo check -p <crate>` (use `cargo check --workspace` for core changes) |
| Python | `ruff check <file>` / `mypy <file>` |
| Go | `go build ./<package>/...` |
| Node | `npx tsc --noEmit` |

3. Resolve any compile or type error before proceeding.

## Step 4: Targeted hardening (when applicable)

Apply the relevant pattern only when the fix touches one of these areas:

### Panic / crash sources
- `unwrap()` / `expect()` → `?` or explicit error handling
- Array index access → `.get()` with error handling
- Division → guard against zero before the operation

### Injection vectors
- SQL / NoSQL string concatenation → parameter binding

### Input validation
- Type and range checks on external input
- NaN / Infinity / empty-input handling

## Step 5: Regression verification

1. Re-run the same test suite captured in Step 1.
2. For core-module changes, also run downstream tests:
   - Rust: `cargo test --workspace`
   - Go: `go test ./...`
   - Node: `npm test`
3. **Revert immediately if any previously green test now fails:**
   ```bash
   git checkout HEAD -- <file>
   ```
   Why: a localized fix that breaks an unrelated test is more dangerous than the original bug.
4. After a revert, attempt a smaller-scoped redo.
5. Three consecutive regressions on the same fix → present three alternative approaches and ask the user to choose. Why: continued blind retries indicate the approach itself is wrong.

## Step 6: Add edge-case tests

When the existing suite did not cover the original bug, add:

- A reproducer test for the bug just fixed (locks in the fix against future regression).
- Boundary-value tests (zero, empty, max, null/None/nil).
- Error-case tests (invalid input, timeout, etc.).

Re-run tests after adding the new cases to confirm green.

## Step 7: Wrap up

1. `git diff --stat` for a change summary.
2. Confirm lint is clean.
3. Print a fix summary:
   - What was broken
   - How it was fixed
   - What tests were added
