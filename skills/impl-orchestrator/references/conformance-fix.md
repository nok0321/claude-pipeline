# Stage 3 remediation: Conformance findings

Detail for SKILL.md Stage 3-5 dispatch when the finding `finding_id`
starts with `SPEC-` or `AUDIT-` (output of `spec-audit --mode=conformance`).
Inline replacement of the retired `safe-fix --mode=conformance` flow.

Findings carry one of four classes: Missing / Diverged / Extra / Constraint.

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
| Cannot decide                                                      | **Arbiter → escalate** | Try `technical-arbiter` first; user confirms when deferred (Tier 1) |

For naming / type / constant / terminology / api_contract drift in the
Diverged class, call the `technical-arbiter` subagent before falling
through to Tier 1 escalation. See [subagent-calls.md](subagent-calls.md) (Stage 3-6 dispatch) for the
input/output contract.

---

## Per-finding actions

| Finding              | Implementation patch                                | Spec patch                                |
|----------------------|-----------------------------------------------------|-------------------------------------------|
| Missing (function)   | Generate skeleton with spec signature + `todo!()`   | —                                         |
| Missing (type)       | Translate spec definition to code                   | —                                         |
| Missing (endpoint)   | Generate router entry + handler skeleton            | —                                         |
| Diverged (signature) | Update signature + call sites                       | Or update spec when impl is more robust   |
| Diverged (field)     | Rename / retype field                               | —                                         |
| Constraint           | Rewrite the violating site                          | —                                         |
| Extra                | —                                                   | Append impl surface to spec               |

---

## Loop integration

The orchestrator outer loop (Stage 4) already iterates this remediation
against re-run conformance audits. No standalone loop is needed — fix
findings within Stage 3, hand back to Stage 4, and either iterate or
finalize per the iteration cap.
