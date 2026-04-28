# Design templates

Templates referenced from `SKILL.md` Steps 2 and 3.

---

## Default DESIGN/*.md template

Used when no existing `DESIGN/*.md` is available to learn the format from
(SKILL.md Step 2-3 fallback).

```markdown
# <Component Name>

## Overview
<purpose and responsibilities>

## Dependencies
| Depends on | Use |
|------------|-----|

## Public API

### <function/method_name>
```<lang>
<signature>
```
<description>

## Type definitions

### <TypeName>
```<lang>
<definition>
```

## Internals
<module breakdown, major internal types>

## Error handling
<error type, error cases>

## Test requirements
- [ ] <test case 1>
- [ ] <test case 2>

## Constraints
<applicable Critical Constraints>
```

---

## Sub-agent generation prompt (Step 3-3)

One sonnet sub-agent per component. Cost-efficient for code-style spec
output; reserve opus for the audit pass.

```
Agent(
  description: "<component> spec generation",
  model: "sonnet",
  prompt: "
    Generate a design document for the component below.

    ## Requirements
    <relevant slice of the plan summary>

    ## Project constraints
    <CLAUDE.md Critical Constraints>

    ## Tech stack
    <CLAUDE.md Tech Stack, or inferred from existing code>

    ## Dependency specs (already generated)
    <public-API sections of upstream specs>

    ## Format
    <Step 2 learned template, or default template above>

    ## Rules
    - Public APIs include concrete signatures (argument types, return types)
    - Type definitions go down to the field level
    - Enumerate every error case
    - Test requirements list concrete cases
    - State constraints in a dedicated section
    - Align with the public APIs of upstream specs
  "
)
```

### Generation rules (sub-agent must obey)

- Public APIs include concrete signatures (argument types, return types).
- Type definitions go down to the field level.
- Enumerate every error case.
- Test requirements list concrete cases.
- State constraints in a dedicated section.
- Align with the public APIs of upstream specs.

---

## --update mode (Step 3-4)

When `DESIGN/*.md` already exists and the user passes `--update`:

1. Identify what changed in the plan summary.
2. Update only the affected sections.
3. Preserve prior design decisions (e.g. resolved escalations).

---

## Output format template

Final report rendered after Step 6.

```
╔══════════════════════════════════════╗
║  Design phase report                 ║
║  Components: <n>                     ║
╚══════════════════════════════════════╝

■ Generated specs
  [1] DESIGN/01_<component_a>.md    — <responsibility>
  [2] DESIGN/02_<component_b>.md    — <responsibility>
  [3] DESIGN/03_<component_c>.md    — <responsibility>
  [4] DESIGN/04_<component_d>.md    — <responsibility>

■ Audit
  Detected: <n> → auto-resolved: <n> / escalated: <n>

═══ Auto-resolved ═══

[1] AUDIT-2 | Medium | Type-name drift
  Resolution: <TypeA> / <TypeB> → unified to <TypeA>
  Affected: DESIGN/01, DESIGN/03

═══ Escalated ═══

[E-1] AUDIT-5 | Critical | <design judgement needed>
  DESIGN/<component_x>.md — option A vs option B
  DESIGN/<component_y>.md — assumes option C
  Question: which option do we adopt?

═══ Component Mapping proposal ═══
(only when CLAUDE.md has none)

## Component Mapping
| Component | Spec | Implementation directory |
|-----------|------|--------------------------|
| <component_a> | DESIGN/01_<component_a>.md | <path/to/component_a>/ |
| <component_b> | DESIGN/02_<component_b>.md | <path/to/component_b>/ |
| <component_c> | DESIGN/03_<component_c>.md | <path/to/component_c>/ |
| <component_d> | DESIGN/04_<component_d>.md | <path/to/component_d>/ |

→ Append to CLAUDE.md? [y/n]
```
