---
name: design-phase
description: Use this skill whenever the user wants to autonomously generate or update design documents under `DESIGN/` — new specs from a plan summary, multi-component design generation, format learning from existing specs, and self-validation via `spec-audit`. Trigger phrases include "generate the design docs", "write DESIGN/03_payment.md from scratch", "create specs for the components in this plan", "draft DESIGN markdowns from PLAN.md", "design the backend / frontend / core layer", "design phase for the new feature", "update the design docs to match the plan", or any spec-creation request driven by a plan summary or requirement description. Trigger even when the user does not say "design-phase" — phrases like "let's start designing", "I need a spec for the payment retry workflow", or "draft the architecture docs" qualify.
argument-hint: "[component-name or 'all'] [--from-scratch | --update]"
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent
model: claude-opus-4-7
---

# Design phase automation

Generate `DESIGN/*.md` from a plan summary, then auto-detect and resolve cross-spec contradictions.

---

## Commands

```
/design-phase                # Generate specs for every component from PIPELINE-STATE.md
/design-phase backend        # Generate the spec for one component
/design-phase --from-scratch # Ignore existing DESIGN/*.md and regenerate (with confirmation)
/design-phase --update       # Diff-update existing DESIGN/*.md against the plan
```

---

## Flow

```
Step 1: Collect inputs
  ↓
Step 2: Learn the format
  ↓
Step 3: Generate specs (sonnet sub-agents)
  ↓
Step 4: Detect contradictions (opus sub-agent — spec-audit equivalent)
  ↓
Step 5: Auto-resolve or escalate
  ↓
Step 6: Update PIPELINE-STATE.md
```

---

## Step 1: Collect inputs

### 1-1: Plan summary

Priority order:
1. The "Plan summary" section of `PIPELINE-STATE.md` (when running inside a pipeline).
2. The conversation context (when running standalone — the user just described requirements).
3. Neither available → ask the user for requirements.

### 1-2: Project context

From CLAUDE.md (when present):
- `## Component Mapping` — existing component layout
- `## Critical Constraints` — hard rules to bake into the design
- `## Tech Stack` — language, framework, DB
- `## Escalation Overrides` — escalation customization

### 1-3: Existing-code scan

When code already exists:
1. Survey the directory structure (`ls -R` or Glob).
2. Extract the major type and API definitions.
3. Use those as references so the new spec aligns with reality.

---

## Step 2: Learn the format

### 2-1: Detect existing specs

```
Glob: DESIGN/*.md, docs/design/*.md, spec/*.md
```

### 2-2: Learn the structure

When `DESIGN/*.md` already exists:
1. Read all of them.
2. Extract the shared structure:
   - Section ordering and naming
   - Code-snippet language and style
   - Type-definition notation
   - Table and list conventions
   - Frontmatter (if any)
3. Use the learned structure as the template.

### 2-3: Default template

Fall back to this structure when no existing spec is available:

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

## Step 3: Generate specs

### 3-1: Component partition

Identify components from the plan summary:
1. Explicit partition in the plan → follow it.
2. No partition → propose a responsibility-based split (frontend / backend / core / persistence).
3. Existing Component Mapping → align with it.

### 3-2: Dependency ordering

Analyze inter-component dependencies and design from the foundation up:

```
e.g. <foundation> → <domain> → <persistence> → <API> → <UI>
```

### 3-3: Generation (sonnet sub-agent)

Generate one component spec per sub-agent (sonnet model, cost-efficient for code-style output):

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
    <Step 2 template, or default>

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

### 3-4: --update mode

When `DESIGN/*.md` already exists:
1. Identify what changed in the plan summary.
2. Update only the affected sections.
3. Preserve prior design decisions (e.g. resolved escalations).

---

## Step 4: Detect contradictions

Run an opus sub-agent (judgment-quality matters) over the generated set, equivalent to `/spec-audit`:

```
Agent(
  description: "Cross-spec audit",
  model: "opus",
  prompt: "
    You are a design reviewer. Read the spec set below and surface contradictions.

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

Apply the escalation framework:

| Contradiction | Class | Action |
|---------------|-------|--------|
| Type-name drift, terminology drift | Tier 2 | Auto-resolve to the more general / accurate name |
| Field mismatch (minor) | Tier 2 | Auto-resolve to the dependent's definition |
| API contract mismatch | Tier 2 | Auto-resolve to the provider's definition |
| Constant drift | Tier 2 | Pick the first defined value |
| Design-policy contradiction | Tier 1 | Ask the user |
| Domain-model fundamental mismatch | Tier 1 | Ask the user |
| Dependency cycle | Tier 1 | Architecture decision required |

### 5-2: Auto-resolve

For Tier 2 / Tier 3:
1. Edit the relevant `DESIGN/*.md`.
2. Log the change.

### 5-3: Re-check

Re-run Step 4 after fixes (max 2 iterations):
- Confirm no new contradictions emerged.
- Two iterations still showing contradictions → escalate.

---

## Step 6: Wrap up

### 6-1: PIPELINE-STATE.md

When `PIPELINE-STATE.md` exists:

1. Update the Design Artifacts section:
   ```markdown
   ## Design artifacts
   - [x] DESIGN/01_<component_a>.md
   - [x] DESIGN/02_<component_b>.md
   - [x] DESIGN/03_<component_c>.md
   - [ ] DESIGN/04_<component_d>.md  ← awaiting escalation
   ```
2. Push Tier 1 items into the escalation queue.
3. Write the hand-off note:
   ```markdown
   ## Hand-off to next phase
   Design complete. Once escalation #1 is resolved, ready for implementation.
   Note: <component_d>'s <unresolved aspect> is pending (#1).
   ```

### 6-2: Component Mapping proposal

When CLAUDE.md lacks a Component Mapping:
- Propose one based on the generated specs.
- After user approval, append to CLAUDE.md (used by `impl-orchestrator`).

---

## Output format

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

---

## Pipeline integration

Inside `dev-pipeline` (Sprint 4) Phase 1:
- Pull the plan summary from `PIPELINE-STATE.md`.
- If escalation queue has pending items, present them and wait for the user.
- Only advance to Phase 2 (implementation) once every escalation is resolved.

Standalone:
- Take the requirements straight from the conversation.
- Run without `PIPELINE-STATE.md`.
