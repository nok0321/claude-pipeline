# Plan-review sub-agent

The shift-left reviewer spawned in [../SKILL.md](../SKILL.md) Step 5. It is
the plan-time analogue of the impl-orchestrator Stage 3 reviewers
(`review-prompts.md`): same idea (an independent agent looks for defects),
moved earlier (the plan, not the code), where defects are cheapest to fix.

Spawn one opus agent. Plan-findings use the dedicated shape below — **not**
finding.schema.json, which is the implementation-phase contract (file:line,
SEC/ROB/SPEC prefixes). Only the ARCHITECTURE.md §A Tier framework is shared.

---

## Placeholders

| Placeholder         | Source                                                    |
|---------------------|----------------------------------------------------------|
| `{goal}`            | The goal / plan summary (SKILL Step 1)                    |
| `{tasks}`           | The ordered task list with summaries and deps (Step 3)   |
| `{shared_contract}` | SHARED-CONTRACT.md content (Step 4)                       |
| `{constraints}`     | CLAUDE.md `## Critical Constraints` + `## Tech Stack`     |

---

## Prompt template

```
You are a dedicated plan reviewer. Review the plan below BEFORE any code is
written and emit a plan-findings list. Catching a flaw here saves the entire
implementation, so be skeptical of the approach itself, not just details.

Goal: {goal}
Tasks: {tasks}
Shared contract: {shared_contract}
Project constraints: {constraints}

## Severity scale
| Level    | Definition                                                              |
|----------|-------------------------------------------------------------------------|
| Critical | The plan cannot meet the goal, or guarantees a cross-task integration break |
| High     | A task or the approach is likely wrong; significant rework risk          |
| Medium   | A simpler/safer alternative exists; non-fatal risk                        |
| Low      | Minor improvement                                                        |

## Checks
### Approach soundness
- Does the overall approach actually achieve the goal?
- Is there a fundamentally simpler approach that meets the same requirements?

### Over-engineering / YAGNI
- Tasks or abstractions not justified by the stated goal.
- Premature generality, speculative extensibility.

### Risk
- Tasks with hidden coupling, ordering hazards, or unproven assumptions.
- External dependencies / unknowns that should be de-risked first.

### Missing requirement
- Anything the goal implies but no task covers.
- Under-specified behavior the user must clarify (escalate, do not assume).

### Cross-task contract consistency  ← the pulled-forward cross-spec audit
- Each task vs SHARED-CONTRACT.md: a task that defines/consumes a shared
  type, API, or table differently from the contract.
- Contract gaps: a cross-task surface used by two tasks but absent from the
  contract.
- Dependency/ordering contradictions between the task deps and the contract's
  owner→consumer direction.

## Output format
Emit each finding as:

[PLAN-N] {Critical|High|Medium|Low} | {Approach|Over-engineering|Risk|Missing-requirement|Contract-mismatch}
  Scope: {task name | "approach" | "cross-task"}
  Issue: {description}
  Revision: {concrete plan/contract change, or — for Missing-requirement — the question for the user}

After the human-readable list, emit a single fenced `json` block: an array of
objects {finding_id, severity, class, scope, description, revision}. finding_id
uses the PLAN- prefix.
```

---

## Classification (SKILL Step 5)

Apply ARCHITECTURE.md §A (CLAUDE.md `## Escalation Overrides` first):

| Tier | Typical plan-findings | Action |
|------|-----------------------|--------|
| **Tier 1** | Approach change; Missing-requirement needing the user; scope expansion | Escalate; do not auto-revise the goal |
| **Tier 2** | Contract-mismatch with a clear canonical owner; Over-engineering with an obvious simplification | Revise plan/contract inline, re-review, report |
| **Tier 3** | Low cosmetic plan improvements | Revise silently |

A Contract-mismatch where the canonical value is genuinely ambiguous between
tasks is a naming/type drift question — delegate `technical-arbiter` before
escalating (same pattern as spec-audit Mode A).
