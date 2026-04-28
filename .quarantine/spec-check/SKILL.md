---
name: spec-check
description: Use this skill whenever the user wants to compare design documents under `DESIGN/` against the actual implementation and report the diff in four buckets — Missing (specified but unimplemented), Diverged (mismatch between spec and code), Extra (implementation has things the spec does not), and Constraint (architecture or design-rule violation). Trigger phrases include "check spec vs implementation", "does the code match DESIGN/01_auth.md?", "verify implementation matches the spec", "list missing items from the design doc", "find diverged signatures between spec and code", or any spec-to-impl conformance check. Trigger even when the user does not say "spec-check" — phrases like "is the implementation behind the spec?", "is anything missing from the design doc?", or "compare what we built against what we designed" qualify.
argument-hint: "[component-name or 'all']"
allowed-tools: Read, Grep, Glob, Bash
model: claude-opus-4-7
context: fork
---

# Spec ↔ implementation conformance check

Compare DESIGN/*.md against the implementation and surface the diff.

---

## Setup

### Resolve component mapping

Read CLAUDE.md `## Component Mapping`:

```markdown
## Component Mapping
| Component | Spec | Implementation directory |
|-----------|------|--------------------------|
| <component_a> | DESIGN/01_<component_a>.md | <path/to/component_a>/ |
| <component_b> | DESIGN/02_<component_b>.md | <path/to/component_b>/ |
```

If the section is missing:
1. Check whether `DESIGN/` exists.
2. If yes, derive component names from the spec filenames and probe the project layout for the implementation directory.
3. If no, report "missing DESIGN/ and Component Mapping" and stop.

### Determine scope

| Argument | Behavior |
|----------|----------|
| Component name | That component only |
| `all` | Every component in the mapping |
| (none) | Components touched by `git diff --name-only HEAD` |

### Project-specific context

Optional CLAUDE.md sections:
- `## Critical Constraints` — fed into the Constraint check
- `## Project-Specific Checks` — additional checks

---

## Diff classes

| Class | Meaning | Typical example |
|-------|---------|-----------------|
| **Missing** | Defined in the spec, absent in code | Function not implemented, endpoint not wired |
| **Diverged** | Implementation differs from the spec | Argument-type mismatch, field-name drift |
| **Extra** | Implementation has things the spec does not | Undocumented public API (could be intentional) |
| **Constraint** | Violates a design rule | Architecture violation, data-format ordering breach |

---

## Procedure

### Step 1: Public-API existence

Look for the public surfaces declared in the spec:

| Language | Targets |
|----------|---------|
| Rust | `pub fn`, `pub struct`, `pub enum`, `pub trait`, `pub type` |
| TypeScript | `export function`, `export class`, `export interface`, `export type`, `export const` |
| Go | identifiers starting uppercase |
| Java | `public class`, `public interface`, `public enum` |
| Python | module-level `def`, `class` |

Spec has it, code doesn't → **Missing**
Code has it, spec doesn't → **Extra**

### Step 2: Function-signature comparison

Compare spec signature against implementation:
- Argument names, types, order
- Return type
- Generics / type parameters
- Visibility (`pub` / `export`)

Mismatch → **Diverged**

Exception: when the implementation is strictly more robust than the spec (e.g. wraps the return in `Result`), report as Diverged with a "spec update recommended" note.

### Step 3: Type / struct field comparison

Compare structs, interfaces, enums:
- Field names, types, visibility
- Enum variants
- Default values

### Step 4: API endpoint comparison

When the spec lists REST endpoints:
- Method (GET / POST / PUT / DELETE)
- Path
- Request / response types
- Status codes

Match against the routing definitions in code (`Router`, `@app.route`, `@RequestMapping`, etc.).

### Step 5: DB schema comparison

When the spec defines tables / collections:
- Table name, column names, types
- Indexes
- Foreign-key constraints

Match against migrations / schema definitions in code.

### Step 6: Constraint check

For each rule in CLAUDE.md `## Critical Constraints`, define a concrete detection method. Examples:
- Architecture rule (forbidden import in directory X) → grep `import` statements
- Data-format ordering → check argument order at conversion boundaries
- Framework convention → argument or decorator order

Violation → **Constraint**

---

## Severity mapping

Findings inherit severity from the diff class:

| Class | Default severity |
|-------|------------------|
| Missing (public API or core type) | **Critical** |
| Diverged (signature, field, endpoint) | **High** |
| Constraint | **High** |
| Extra (public surface) | **Medium** |
| Missing (minor or doc-only) | **Medium** |
| Other | **Low** |

---

## Output format

```
╔══════════════════════════════════════╗
║  Spec conformance                    ║
║  Target: <component>                 ║
╚══════════════════════════════════════╝

■ Summary
  Missing:    <n>
  Diverged:   <n>
  Extra:      <n>
  Constraint: <n>

═══ Missing ═══

[SPEC-1] Missing | Public API
  Spec: DESIGN/<component>.md:<N> — pub fn <function_name>(<args>) -> <ReturnType>
  Code: (none)
  Recommendation: implement the function

═══ Diverged ═══

[SPEC-2] Diverged | Signature
  Spec: DESIGN/<component>.md:<N> — fn <function_name>(<args>) -> <ReturnType>
  Code: <path/to/file>:<N> — fn <function_name>(<args>) -> Result<<ReturnType>, Error>
  Recommendation: update the spec — implementation is strictly more robust

═══ Extra ═══

[SPEC-3] Extra | Function
  Code: <path/to/file>:<N> — pub fn <helper_name>(<args>)
  Recommendation: document in spec, or downgrade to internal visibility

═══ Constraint ═══

[SPEC-4] Constraint | Architecture
  File: <path/to/file>:<N>
  Rule: <component> may not depend on <forbidden> (CLAUDE.md Critical Constraints)
  Violation: <import / call chain>
  Fix: <alternative>
```

When everything matches: report "spec and implementation are fully aligned".

---

## Pipeline integration

Inside `impl-orchestrator` Stage 4 (Agent 3: Spec Compliance Reviewer):
- Target files and mappings flow in from the orchestrator.
- Findings convert to the orchestrator's unified format.

Standalone:
- Read CLAUDE.md Component Mapping directly.
- After the report, recommend `spec-fix` to apply repairs.
