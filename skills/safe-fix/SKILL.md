---
name: safe-fix
description: Use this skill whenever the user wants to apply a verified fix or refactor — driven either by findings from `spec-audit` (conformance mode) / `robust-review` / `code-review`, OR by a free-form bug description — with a built-in safety net (build / type / test gate after each edit, automatic revert when the change breaks anything green). Trigger phrases include "fix the spec mismatches", "reconcile spec and implementation", "fix the robust-review findings", "auto-fix critical findings", "apply the unwrap fixes", "fix this bug safely", "fix and verify", "patch this without breaking anything", "remediate the security findings", or any pattern-based remediation request. Trigger even when the user does not say "safe-fix" — phrases like "fix what robust-review found", "close the gap between design and code", "make implementation match the spec", or "patch this and run the tests" qualify. For broad multi-component feature work, prefer `impl-orchestrator` instead.
argument-hint: "[finding-source | file:line | issue-description] [--mode=conformance|robust|adhoc] [--spec-wins | --impl-wins | --dry-run | --loop [N]]"
allowed-tools: Read, Write, Edit, MultiEdit, Bash, Grep, Glob
model: claude-opus-4-7
---

# safe-fix: finding-driven remediation with verification gate

Replaces the retired `spec-fix`, `robust-fix`, and `fix-with-verify` skills. Drives a single fix → verify → revert-on-failure loop with three input modes, a unified verification gate, and a unified revert policy.

---

## Input modes

The mode is auto-detected from the source of findings, or forced by `--mode=`:

| Mode | When | Replaces |
|------|------|----------|
| `conformance` | Findings from `spec-audit` Mode B (Missing / Diverged / Extra / Constraint) | spec-fix |
| `robust` | Findings from `robust-review` (SEC-* / ROB-*, severity-tagged) | robust-fix |
| `adhoc` | Free-form bug description or `file:line`, no upstream finding | fix-with-verify |

Finding input contract (informal — formal JSON schema lands in `references/finding.schema.json` in Phase 3 / Phase 4):

```json
{
  "finding_id": "SPEC-1 | AUDIT-3 | SEC-1 | ROB-3",
  "severity": "Critical | High | Medium | Low",
  "category": "Missing | Diverged | Extra | Constraint | SQL injection | unwrap | ...",
  "file": "path:line",
  "spec_ref": "DESIGN/...:N (conformance only)",
  "description": "...",
  "fix_hint": "..."
}
```

---

## Mode A: Conformance (`spec-audit` Mode B findings)

### Fix direction by class

| Class | Default direction | Why |
|-------|-------------------|-----|
| **Missing** | Add to implementation | Spec mandates it |
| **Diverged** | Per-case (table below) | Both sides may be right |
| **Extra** | Add to spec | Implementation may have made a useful additive choice |
| **Constraint** | Patch implementation | Constraints are absolute, anchored to the spec |

#### Diverged direction heuristic

| Condition | Direction | Why |
|-----------|-----------|-----|
| Implementation is strictly more robust (Result wrap, Option, etc.) | Update spec | Adopt the better contract |
| Tests already validate the implementation behavior | Update spec | Don't break green tests for spec hygiene |
| Spec is more detailed and concrete | Patch implementation | Honor design intent |
| `git blame` shows the implementation was recently changed | Patch implementation | Recent change may be unintentional |
| Cannot decide | **Escalate** | User confirms direction (Tier 1) |

`--spec-wins` forces every patch to the implementation side. `--impl-wins` forces every patch to the spec side.

### Per-finding actions

| Finding | Implementation patch | Spec patch |
|---------|----------------------|------------|
| Missing (function) | Generate skeleton with spec signature + `todo!()` | — |
| Missing (type) | Translate spec definition to code | — |
| Missing (endpoint) | Generate router entry + handler skeleton | — |
| Diverged (signature) | Update signature + call sites | Or update spec when impl is more robust |
| Diverged (field) | Rename / retype field | — |
| Constraint | Rewrite the violating site | — |
| Extra | — | Append impl surface to spec |

---

## Mode B: Robust (`robust-review` findings)

### Severity gate

| Severity | Action |
|----------|--------|
| Critical | **Always fix** |
| High | **Always fix** |
| Medium | Skip (report only) |
| Low | Skip (report only) |

### Pattern table

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

For Critical / High items that don't match a known pattern: attempt the fix, but **skip and report when confidence is low** rather than emit unsafe edits. When a fix would require a design decision, surface it as a Tier 1 escalation candidate.

---

## Mode C: Adhoc (free-form bug fix)

### Step 1: Record baseline

1. `git diff` to capture pending state.
2. Run the test suite (auto-detect language) to record a baseline:

| Language | Command |
|----------|---------|
| Rust | `cargo test -p <crate> 2>&1 \| tail -20` |
| Python | `pytest <test file> 2>&1 \| tail -20` |
| Go | `go test ./<package>/... 2>&1 \| tail -20` |
| Node | `npm test 2>&1 \| tail -20` |

3. If tests already fail, confirm whether those failures are exactly the target.

### Step 2: Impact analysis

1. Grep for call sites of the function / type under repair.
2. Treat public-API signature changes as broad-impact.

### Step 3: Apply + verify (see common gate below)

### Step 4: Add regression test

When the existing suite did not cover the original bug, add a reproducer test and boundary cases (zero, empty, max, null/None/nil) before declaring done.

---

## Common verification gate (all modes)

After each individual edit, run in order. Stop on the first failure.

| Gate | Detection | Command |
|------|-----------|---------|
| Build | Cargo.toml / package.json / go.mod | `cargo check` / `npm run build` / `go build ./...` |
| Type | same | `cargo clippy` / `npx tsc --noEmit` / `go vet` |
| Test | same | `cargo test` / `npm test` / `go test ./...` |

When CLAUDE.md `## Commands` exists, those commands take precedence.

---

## Common revert policy (all modes)

1. **One finding / one file at a time.** No batched edits — the gate must attribute failures to a specific patch.
2. Run the gate after each edit.
3. Failure attribution:
   - **Failure caused by this patch** → revert via `git checkout HEAD -- <file>` and skip with a report entry.
   - **Pre-existing failure** (unrelated to the patch) → keep the patch, report the pre-existing error separately.
4. **Three consecutive failures on the same finding** → skip and surface as Tier 1 escalation. Continued blind retries indicate the approach itself is wrong.
5. A hardening fix that breaks an unrelated test is worse than the original Critical — better to mark "needs human review" than leave the tree red.

---

## Loop mode (Mode A only, `--loop [N]`)

Iterate `spec-audit --mode=conformance` → `safe-fix --mode=conformance` until the diff is empty or the cap (default 3) is hit.

```
iteration = 1
while iteration <= max:
    findings = spec-audit conformance(component)
    if len(findings) == 0:
        return "converged"
    fix_results = safe-fix(findings)
    if all skipped:
        return "stuck — escalate remaining"
    if findings count not decreasing:
        return "no progress — escalate"
    iteration += 1
return "max iterations reached"
```

When called from `impl-orchestrator`, the orchestrator's own outer loop already plays this role — `--loop` is unnecessary inside the pipeline.

---

## Output format

```
╔══════════════════════════════════════╗
║  safe-fix report                     ║
║  Mode: <conformance | robust | adhoc>║
║  Target: <component | file | issue>  ║
╚══════════════════════════════════════╝

■ Summary
  Fixed:           <n>
  Skipped:         <n> (escalation candidates)
  Report-only:     <n> (Medium / Low — robust mode)
  Verification: build:<result> type:<result> test:<result>

═══ Fixed ═══

[1] SPEC-1 | Missing → impl added (Mode A)
  Spec: DESIGN/<component>.md:<N>
  Added: <path/to/new_file> — pub fn <function_name>()
  Verification: build:pass type:pass test:pass

[2] SEC-1 | Critical | SQL injection (Mode B)
  File: <handler>:<line>
  Change: format!() → .bind()
  Verification: build:pass type:pass test:pass

═══ Skipped (manual follow-up) ═══

[S-1] SPEC-5 | Diverged | direction unclear (Mode A)
  Spec: DESIGN/<component>.md:<N> — POST /<api_path>
  Code: <handler>:<N> — PUT /<api_path>
  Question: which method is canonical, POST or PUT?

[S-2] ROB-5 | High | concurrent write protection (Mode B)
  File: <repository>:<line>
  Reason: requires a transaction-isolation-level decision
  Recommendation: Tier 1 escalation

═══ Report only (Mode B Medium / Low) ═══

[I-1] ROB-8 | Medium | empty list not handled
  File: <file>:<line>
```

---

## Pipeline integration

- **From `impl-orchestrator` Stage 5** — findings stream from spec-audit Mode B and robust-review with severity tags. safe-fix auto-dispatches Mode A for SPEC-* / AUDIT-* and Mode B for SEC-* / ROB-*. Verification results flow back into `gate_results`. Skipped findings hand to escalation classification.
- **Standalone after `spec-audit --mode=conformance`** — Mode A; recommend `--loop` when iteration is acceptable.
- **Standalone after `robust-review`** — Mode B; default Critical + High auto-fix.
- **Standalone bug fix** — Mode C; baseline → impact analysis → fix → verify → regression test.
