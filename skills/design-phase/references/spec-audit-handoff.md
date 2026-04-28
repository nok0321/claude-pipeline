# Cross-spec audit and contradiction handling

Detail for SKILL.md Steps 4 and 5: how to detect and resolve
contradictions across freshly generated `DESIGN/*.md`.

This is the same logic as `/spec-audit --mode=cross` but inlined so the
design-phase loop can run audit → auto-resolve → re-audit without spawning
a separate skill.

---

## Step 4: Detect contradictions (opus sub-agent)

Use opus — judgment quality matters more than cost here, and the input
size is bounded by the number of just-generated specs.

```
Agent(
  description: "Cross-spec audit",
  model: "opus",
  prompt: "
    You are a design reviewer. Read the spec set below and surface
    contradictions.

    <full content of every generated DESIGN/*.md>

    Checks:
    1. Type / field name drift
    2. Shared-type field mismatch
    3. API contract mismatch (provider vs consumer)
    4. Dependency cycles
    5. DB schema mismatch
    6. Terminology drift
    7. Constant / configuration drift

    Each finding:
    [AUDIT-N] <Critical|High|Medium|Low> | <category>
      Refs: <file1:line> ↔ <file2:line>
      Issue: <description>
      Recommendation: <fix>
  "
)
```

---

## Step 5: Resolve contradictions

### 5-1: Classify

Apply the escalation framework (see ARCHITECTURE.md §A 補章 for the
canonical Tier 1/2/3 definitions):

| Contradiction                       | Class  | Action                                        |
|-------------------------------------|--------|-----------------------------------------------|
| Type-name drift, terminology drift  | Tier 2 | Auto-resolve to the more general / accurate name |
| Field mismatch (minor)              | Tier 2 | Auto-resolve to the dependent's definition    |
| API contract mismatch               | Tier 2 | Auto-resolve to the provider's definition     |
| Constant drift                      | Tier 2 | Pick the first defined value                  |
| Design-policy contradiction         | Tier 1 | Ask the user                                  |
| Domain-model fundamental mismatch   | Tier 1 | Ask the user                                  |
| Dependency cycle                    | Tier 1 | Architecture decision required                |

### 5-2: Auto-resolve

For Tier 2 / Tier 3:

1. Edit the relevant `DESIGN/*.md`.
2. Log the change (one line per edit, surfaced in the final report under
   `═══ Auto-resolved ═══`).

### 5-3: Re-check loop

Re-run Step 4 after fixes (max 2 iterations):

- Confirm no new contradictions emerged.
- Two iterations still showing contradictions → escalate the remainder.

---

## Hand-off to PIPELINE-STATE.md (Step 6-1)

Tier 1 items must be pushed to the escalation queue, not silently
dropped. Update `PIPELINE-STATE.md` like this:

```markdown
## Design artifacts
- [x] DESIGN/01_<component_a>.md
- [x] DESIGN/02_<component_b>.md
- [x] DESIGN/03_<component_c>.md
- [ ] DESIGN/04_<component_d>.md  ← awaiting escalation

## Hand-off to next phase
Design complete. Once escalation #1 is resolved, ready for implementation.
Note: <component_d>'s <unresolved aspect> is pending (#1).
```

See ARCHITECTURE.md §B 補章 for the canonical PIPELINE-STATE.md layout.
