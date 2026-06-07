# Task-planner templates

Formats referenced from [../SKILL.md](../SKILL.md) Steps 3, 4, and 6.

---

## SHARED-CONTRACT.md (Step 4)

The single up-front design artifact. Lives at the project root, committed to
git (like PIPELINE-STATE.md). Every task is built against it; plan-review and
boundary-test check tasks against it.

```markdown
# Shared Contract: <goal-name>
Updated: <ISO 8601>

## Shared types
| Type | Definition (field-level) | Owner task | Consumer tasks |
|------|--------------------------|------------|----------------|

## Cross-task API signatures
| Endpoint / Function | Signature (arg types → return) | Provider task | Consumer tasks |
|---------------------|--------------------------------|---------------|----------------|

## Data schema
| Entity / Table | Fields (name: type) | Owner task |
|----------------|---------------------|------------|

## Invariants
- <cross-cutting rule every task must honor — e.g. data-format ordering, ID format, auth header shape>
```

Rules:
- Only put **cross-task** surfaces here. Task-internal types stay inside the task.
- Every shared type / API / table names its owner and consumers — that is
  what makes a drift detectable.
- When a task needs to change a contract entry during implementation, that is
  a public-interface change → Tier 1 (ARCHITECTURE.md §A); update the
  contract and re-notify consumers, do not let tasks fork the definition.

---

## Tasks section (Step 6 → PIPELINE-STATE.md)

Extends the ARCHITECTURE.md §B state file. Replaces the design-first "Design
artifacts" section as the driver of the goal-driven flow.

```markdown
## Tasks
| # | Task | Summary | Depends on | Tech decisions | Status |
|---|------|---------|------------|----------------|--------|
| 1 | <name> | <one-paragraph summary> | — | <chosen option / axis> | planned |
| 2 | <name> | <summary> | 1 | <option> | planned |

## Shared contract
- SHARED-CONTRACT.md — <n> types, <n> APIs, <n> tables, <n> invariants
```

Status values: `planned` → `in-progress` → `done` (impl-orchestrator updates
the latter two as it builds each task).

---

## Output report (SKILL Output format)

```
╔══════════════════════════════════════╗
║  Task plan report                    ║
║  Goal: <goal-name>                   ║
║  Tasks: <n>                          ║
╚══════════════════════════════════════╝

■ Tech decisions
  [datastore]   <choice>   (deciding axis: <axis>, runner-up: <name>)
  [protocol]    <choice>   (constraint-forced)

■ Ordered tasks
  [1] <task>            deps: —      → <summary>
  [2] <task>            deps: 1      → <summary>

■ Shared contract (SHARED-CONTRACT.md)
  types: <n>  apis: <n>  tables: <n>  invariants: <n>

■ Plan review
  Findings: <n> → auto-revised: <n> / escalated: <n>  (iterations: <n>/2)

═══ Auto-revised ═══
[PLAN-2] Medium | Over-engineering
  Scope: task 3 (caching layer)
  Revision: drop the bespoke cache; the datastore's built-in TTL covers it.

═══ Escalated (Tier 1) ═══
[PLAN-5] High | Missing-requirement
  Scope: approach
  Question: the goal implies multi-tenant isolation but no tenancy model was
  given — per-row, per-schema, or per-db?

→ Hand off to: /impl-orchestrator (goal mode), tasks in dependency order
```
