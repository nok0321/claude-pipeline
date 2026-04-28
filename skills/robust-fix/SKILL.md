---
name: robust-fix
description: Use this skill whenever the user wants to auto-apply pattern-based fixes for the Critical and High findings produced by `robust-review` — for instance unwrap removal, SQL-injection mitigation, unchecked-index hardening, divide-by-zero guards, and similar mechanical patches — and verify each patch against the build / type / test gate, reverting when verification fails. Trigger phrases include "fix the robust-review findings", "auto-fix critical findings", "apply the unwrap fixes", "remediate the security findings", "robust hot-fix before release", or any follow-up to a robust-review run. Trigger even when the user does not say "robust-fix" — phrases like "fix what robust-review found" or "apply the auto-fixes from that audit" qualify. For broad bug fixes outside the robust-review pattern set, use `fix-with-verify` instead.
argument-hint: "[file-path or 'all'] [--dry-run]"
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
model: claude-opus-4-7
---

# Robustness finding auto-fix

Apply the canonical fixes for Critical and High findings from `robust-review` and verify each fix with the build / type / test gate before moving on.

---

## Usage

```
/robust-fix              # Fix findings from the most recent robust-review output
/robust-fix all          # Run robust-review all first, then fix
/robust-fix src/api.rs   # Run robust-review on the file, then fix
/robust-fix --dry-run    # Print the fix plan only (no edits)
```

---

## Execution flow

### Step 1: Acquire findings

In priority order:

1. Findings from a recent `/robust-review` output present in the conversation.
2. Findings produced by running `/robust-review` against the explicit argument (`all` or a file path).
3. Findings produced by running `/robust-review` against `git diff --name-only HEAD`.

### Step 2: Select fix targets

| Severity | Action |
|----------|--------|
| Critical | **Always fix** |
| High | **Always fix** |
| Medium | Skip (report only) |
| Low | Skip (report only) |

Pattern table:

| Finding category | Pattern | Fix |
|------------------|---------|-----|
| SQL injection | `format!()` / template literal in query | `.bind()` / parameterized query |
| XSS | unsanitized output | apply sanitizer |
| `unwrap()` / `expect()` | panic source | `?` / `match` / `.unwrap_or()` |
| Unchecked index | `arr[i]` | `.get(i)` / explicit bound check |
| Division by zero | `a / b` | guard the denominator + error path |
| `todo!()` / `unimplemented!()` | unimplemented marker | implement per design or return an error |
| Hard-coded secret | literal value | env var / config reference |
| `as` cast | implicit truncation | `try_into()` / `checked_*` |

For Critical / High items that don't match a known pattern:
- Attempt the fix, but **skip and report when confidence is low** rather than emit unsafe edits.
- When the fix would require a design decision, surface it as a Tier 1 escalation candidate.

### Step 3: Apply the fix

`--dry-run` stops here and prints the plan.

1. Edit one finding at a time. Do not bundle.
2. Why one-at-a-time: the verification gate must attribute any failure to a specific patch so the revert in Step 5 can be precise.
3. Run the verification gate (Step 4) after each edit.

### Step 4: Verification gate

Per fix, run in order. Stop on the first failure.

| Gate | Detection | Command |
|------|-----------|---------|
| Build | Cargo.toml / package.json / go.mod | `cargo check` / `npm run build` / `go build ./...` |
| Type | same | `cargo clippy` / `npx tsc --noEmit` / `go vet` |
| Test | same | `cargo test` / `npm test` / `go test ./...` |

When CLAUDE.md `## Commands` exists, those commands take precedence.

### Step 5: Revert decision on failure

When the gate fails:

1. Parse the error.
2. **Failure caused by this patch** → revert (`git checkout -- <file>`) and move on.
3. **Pre-existing failure** (unrelated to the patch) → keep the patch and report the pre-existing error separately.
4. Three consecutive failures on the same finding → skip and surface in the report.

Why this strict revert policy: a hardening fix that breaks an unrelated test is worse than the original Critical, because it masks the real signal. Better to mark the finding "needs human review" than to leave the tree red.

---

## Output format

```
╔══════════════════════════════════════╗
║  Robustness fix report               ║
╚══════════════════════════════════════╝

■ Summary
  Fixed:        <n>
  Skipped:      <n> (no pattern match or fix failed)
  Report-only:  <n> (Medium / Low)

═══ Fixed ═══

[1] SEC-1 | Critical | SQL injection
  File: <handler>:<line>
  Change: format!() → .bind()
  Verification: build:pass type:pass test:pass

[2] ROB-3 | Critical | unwrap() panic source
  File: <file>:<line>
  Change: unwrap() → ? operator
  Verification: build:pass type:pass test:pass

═══ Skipped (manual follow-up needed) ═══

[S-1] ROB-5 | High | Concurrent write protection
  File: <repository>:<line>
  Reason: requires a transaction-isolation-level decision
  Recommendation: Tier 1 escalation

═══ Report only (Medium / Low) ═══

[I-1] ROB-8 | Medium | Empty list not handled
  File: <file>:<line>
[I-2] SEC-4 | Low | confirm `.env` is in `.gitignore`
```

---

## Pipeline integration

When called from `impl-orchestrator` Stage 5:
- Findings arrive directly from the orchestrator (skip Step 1).
- Verification-gate results flow back into the orchestrator's `gate_results`.
- Skipped findings are handed to escalation classification.

Standalone:
- Trigger `/robust-review` first, then fix.
