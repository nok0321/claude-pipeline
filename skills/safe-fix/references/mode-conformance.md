# Mode A: Conformance (`spec-audit` Mode B findings)

Detail for SKILL.md Mode A. Replaces the retired `spec-fix` skill.

Findings stream in from `/spec-audit --mode=conformance` and carry one
of four classes: Missing / Diverged / Extra / Constraint.

---

## Fix direction by class

| Class          | Default direction        | Why                                                  |
|----------------|--------------------------|------------------------------------------------------|
| **Missing**    | Add to implementation    | Spec mandates it                                     |
| **Diverged**   | Per-case (table below)   | Both sides may be right                              |
| **Extra**      | Add to spec              | Implementation may have made a useful additive choice|
| **Constraint** | Patch implementation     | Constraints are absolute, anchored to the spec       |

### Diverged direction heuristic

| Condition                                                          | Direction              | Why                                          |
|--------------------------------------------------------------------|------------------------|----------------------------------------------|
| Implementation is strictly more robust (Result wrap, Option, etc.) | Update spec            | Adopt the better contract                    |
| Tests already validate the implementation behavior                 | Update spec            | Don't break green tests for spec hygiene     |
| Spec is more detailed and concrete                                 | Patch implementation   | Honor design intent                          |
| `git blame` shows the implementation was recently changed          | Patch implementation   | Recent change may be unintentional           |
| Cannot decide                                                      | **Escalate**           | User confirms direction (Tier 1)             |

Force flags:
- `--spec-wins` — every patch goes to the implementation side.
- `--impl-wins` — every patch goes to the spec side.

---

## Per-finding actions

| Finding              | Implementation patch                                | Spec patch                                |
|----------------------|-----------------------------------------------------|-------------------------------------------|
| Missing (function)   | Generate skeleton with spec signature + `todo!()`   | —                                         |
| Missing (type)       | Translate spec definition to code                   | —                                         |
| Missing (endpoint)   | Generate router entry + handler skeleton           | —                                         |
| Diverged (signature) | Update signature + call sites                       | Or update spec when impl is more robust   |
| Diverged (field)     | Rename / retype field                               | —                                         |
| Constraint           | Rewrite the violating site                          | —                                         |
| Extra                | —                                                   | Append impl surface to spec               |

---

## Loop mode (`--loop [N]`)

Iterate `spec-audit --mode=conformance` → `safe-fix --mode=conformance`
until the diff is empty or the cap (default 3) is hit.

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

When called from `impl-orchestrator`, the orchestrator's own outer loop
already plays this role — `--loop` is unnecessary inside the pipeline.
