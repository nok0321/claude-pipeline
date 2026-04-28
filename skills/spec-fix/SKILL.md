---
name: spec-fix
description: Use this skill whenever the user wants to repair findings from `spec-check` — patching either the implementation or the design doc bidirectionally — based on heuristics (robustness wins, tests-validate-impl, recent-edit signal, git blame). Supports a `--loop` mode that iterates spec-check → spec-fix until the diff hits zero or a retry cap (succeeds the retired `spec-cycle`). Trigger phrases include "fix the spec mismatches", "reconcile spec and implementation", "apply the spec-check findings", "update the design doc to match the code", "make implementation match the spec", "fix the constraint violations", or any conformance-repair request after spec-check. Trigger even when the user does not say "spec-fix" — phrases like "close the gap between design and code" or "make spec and impl agree" qualify.
argument-hint: "[component-name or 'all'] [--spec-wins | --impl-wins | --dry-run | --loop [N]]"
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
model: claude-opus-4-7
---

# Spec ↔ implementation bidirectional auto-fix

Repair the diffs (Missing / Diverged / Extra / Constraint) found by `/spec-check`. The fix direction (touch the spec vs touch the code) is decided by finding class plus heuristics.

---

## Usage

```
/spec-fix                # Fix findings from the most recent spec-check output
/spec-fix all            # Run spec-check all first, then fix
/spec-fix backend        # Run spec-check on the component, then fix
/spec-fix --spec-wins    # Always patch the implementation (spec is canonical)
/spec-fix --impl-wins    # Always patch the spec (code is canonical)
/spec-fix --dry-run      # Print the fix plan only
/spec-fix --loop         # Iterate spec-check → spec-fix until diff = 0 or cap (default 3)
/spec-fix --loop 5       # Iterate up to 5 times
```

---

## Direction selection

### Default (no flag): heuristic

| Class | Default direction | Why |
|-------|-------------------|-----|
| **Missing** | Add to implementation | The spec mandates it |
| **Diverged** | Per-case decision (below) | Both sides may be right depending on context |
| **Extra** | Add to spec | Implementation may have made a useful additive choice |
| **Constraint** | Patch implementation | Constraints are absolute and live on the spec side |

#### Diverged direction heuristic

| Condition | Direction | Why |
|-----------|-----------|-----|
| Implementation is strictly more robust (Result wrap, Option, etc.) | Update spec | Adopt the better contract |
| Tests already validate the implementation behavior | Update spec | Don't break a green test for spec hygiene |
| Spec is more detailed and concrete | Patch implementation | Honor design intent |
| `git blame` shows the implementation was recently changed | Patch implementation | Recent change may be unintentional |
| Cannot decide | **Escalate** | User confirms direction |

### --spec-wins

Patch the implementation for every finding. Spec is never modified.

### --impl-wins

Patch the spec for every finding. Implementation is never modified.

---

## Execution flow

### Step 1: Acquire findings

1. Findings from a recent `/spec-check` output present in the conversation.
2. If an argument is provided, run `/spec-check` against it first.
3. Otherwise, run `/spec-check` against components touched by `git diff --name-only HEAD`.

### Step 2: Plan the fix

For each finding:
1. Decide direction (heuristic or flag).
2. Decide content.
3. Decide difficulty:
   - **Auto** — signature change, field add, type rename, etc.
   - **Semi-auto** — generate a skeleton with TODO (large Missing functions)
   - **Manual** — design decision required → escalate

`--dry-run` stops here and prints the plan.

### Step 3: Apply

#### Implementation-side patch (Missing / Constraint / spec-wins)

| Finding | Change |
|---------|--------|
| Missing (function) | Generate a skeleton with the spec signature + `todo!()`, or transcribe the spec's code snippet |
| Missing (type) | Translate the spec definition into code |
| Missing (endpoint) | Generate a router entry + handler skeleton |
| Diverged (signature) | Update the signature to match spec, plus call sites |
| Diverged (field) | Rename / retype the field to match spec |
| Constraint | Rewrite the violating site to comply |

#### Spec-side patch (Extra / some Diverged / impl-wins)

| Finding | Change |
|---------|--------|
| Extra | Append the implementation surface to the spec |
| Diverged (impl is more robust) | Update the spec signature / type to match the implementation |

### Step 4: Verify

- **Implementation patched** → run build / type / test (full verification gate).
- **Spec patched** → re-run `/spec-check` to confirm the diff resolved.
- **Both patched** → run both checks.

On verification failure:
- Implementation patch failed → revert the patch and skip with a report entry.
- Spec patch failed (introduced new contradiction) → re-run `spec-audit` to surface the new issue.

### Step 5: Escalation rules

Surface as escalation candidates (do not auto-fix):
- Diverged with no decisive heuristic.
- Missing where the function is large and a skeleton is insufficient.
- A fix that ripples into another component's spec.

---

## Output format

```
╔══════════════════════════════════════╗
║  Spec fix report                     ║
║  Target: <component>                 ║
║  Mode: <default|spec-wins|impl-wins> ║
╚══════════════════════════════════════╝

■ Summary
  Implementation patched: <n>
  Spec updated:           <n>
  Skipped:                <n> (escalation candidates)
  Verification: build:<result> type:<result> test:<result>

═══ Implementation patched ═══

[1] SPEC-1 | Missing → impl added
  Spec: DESIGN/<component>.md:<N>
  Added: <path/to/new_file> — pub fn <function_name>()
  Verification: build:pass type:pass test:pass

═══ Spec updated ═══

[2] SPEC-2 | Diverged → spec updated (impl is more robust)
  Code: <path/to/file>:<N> — fn <function_name>() -> Result<<ReturnType>, Error>
  Updated: DESIGN/<component>.md:<N> — return type changed to Result

═══ Skipped (user decision needed) ═══

[S-1] SPEC-5 | Diverged | direction unclear
  Spec: DESIGN/<component>.md:<N> — POST /<api_path>
  Code: <path/to/handler>:<N> — PUT /<api_path>
  Question: which HTTP method is canonical, POST or PUT?
```

---

## Loop mode (--loop)

Iterate spec-check → spec-fix until the diff is empty or the cap is hit.

```
iteration = 1
while iteration <= max:
    findings = spec-check(component)
    if len(findings) == 0:
        return "converged"
    fix_results = spec-fix(findings)
    if all skipped:
        return "stuck — escalate remaining"
    if findings count not decreasing:
        return "no progress — escalate"
    iteration += 1
return "max iterations reached"
```

Termination guarantees:
- Hard cap (default 3, configurable via `--loop N`) prevents infinite loops.
- Progress check: bail when the finding count fails to decrease, since continuing would only churn.
- All-skipped detection: bail immediately when no finding is auto-fixable.
- Same-finding regression: promote to Skipped on second appearance.

When called from `impl-orchestrator`, Stage 6's loop already plays this role — `--loop` is unnecessary.

---

## Pipeline integration

Inside `impl-orchestrator` Stage 5:
- Spec findings flow through the orchestrator's escalation classifier.
- Constraint violations are auto-fixed (Tier 2).
- Missing or Diverged items that need scope decisions are Tier 1 escalation.
