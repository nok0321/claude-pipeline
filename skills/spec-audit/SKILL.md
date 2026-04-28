---
name: spec-audit
description: Use this skill whenever the user wants to detect inconsistencies between design documents under `DESIGN/` — type-name drift, field-name mismatches, divergent API contracts, dependency cycles, DB-schema disagreements, terminology drift, and constant-value mismatches across multiple specs. Trigger phrases include "audit our design docs", "check the DESIGN/ markdowns for inconsistencies", "do the spec markdowns line up", "type names align between specs?", "API contract drift across designs", "scan DESIGN/*.md for mismatches before the freeze", or any cross-document consistency check on spec markdowns. Trigger even when the user does not say "spec-audit" — implicit phrases like "did the design docs drift?", "anything off between these markdowns?", or "find conflicts in DESIGN/" qualify.
argument-hint: "[component-name or 'all']"
allowed-tools: Read, Grep, Glob, Bash
model: claude-opus-4-7
context: fork
---

# Cross-document design-spec audit

Detect contradictions between design documents under `DESIGN/`. While `spec-check` compares spec to implementation, this skill compares spec to spec.

---

## Setup

### Collect the spec set

1. Read CLAUDE.md `## Component Mapping` to obtain the spec paths.
2. If absent, glob `DESIGN/*.md` directly.
3. If neither exists, report "no design docs found" and stop.

### Determine scope

| Argument | Behavior |
|----------|----------|
| Component name | That component's spec plus its dependency specs |
| `all` | Every spec |
| (none) | Every spec (same as `all`) |

### Load every spec

Read each in scope and extract:

- Type definitions (struct / interface / enum / type alias)
- Function signatures (`pub fn`, `export function`, etc.)
- API endpoint definitions
- DB table / collection definitions
- Domain terms and definitions
- Dependency declarations
- Constants and configuration values

---

## Checks

### Check 1: Type / field name drift

Different names for the same concept across specs.

Detection:
1. Extract type definitions from every spec.
2. Pair similarly-named types (e.g. `User` vs `UserInfo`, `Item` vs `ItemRecord`).
3. Decide whether they describe the same concept by comparing field composition.

Example output:
```
[AUDIT-1] Type-name drift
  DESIGN/<component_a>.md:<N> — struct <TypeA> { <field_x>: T, <field_y>: T }
  DESIGN/<component_b>.md:<N> — struct <TypeB> { <field_from>: T, <field_to>: T }
  Recommendation: unify the type and field names (suggest <TypeA> / <field_x>, <field_y>)
```

### Check 2: Shared-type field mismatch

A type that appears in multiple specs but with diverging fields.

Detection:
1. Find shared type names across specs.
2. Compare field names, types, and counts.

### Check 3: API contract mismatch

A provider component's API and a consumer component's expected call shape disagree.

Detection:
1. From each spec, extract "public API" and "dependencies / external calls".
2. Match provider signatures / endpoints with consumer expectations.

Example:
```
[AUDIT-2] API contract mismatch
  Provider: DESIGN/<provider>.md:<N> — GET /<api_path> → Vec<<Item>>
  Consumer: DESIGN/<consumer>.md:<N> — fetch("/<api_path>") → expects { items: <Item>[] }
  Diff: bare array vs object-wrapped response
  Recommendation: unify on one response shape
```

### Check 4: Dependency cycles

Cycles in component dependency declarations.

Detection:
1. Build a directed graph from each spec's dependency section.
2. Run DFS + back-edge detection.

### Check 5: DB-schema mismatch

When DB definitions appear in multiple specs.

Detection:
1. Extract table / column definitions from every spec.
2. Compare columns, types, constraints when the same table appears more than once.

### Check 6: Terminology drift

Domain terms not unified across specs.

Detection:
1. Pull primary terms from each spec's headings and definition sections.
2. Detect synonyms (e.g. "user" / "account holder", or English / Japanese / abbreviation drift).

### Check 7: Constant / configuration value drift

Same named constant (port, limit, timeout, etc.) with different values across specs.

---

## Severity scale

| Level | Definition | Example |
|-------|-----------|---------|
| **Critical** | Will cause a build or runtime failure | Type-field mismatch, broken API contract |
| **High** | Causes confusion or data drift but won't break the build | Constant-value mismatch, dependency cycle |
| **Medium** | Style / consistency issues that hurt readability | Type-name drift, terminology drift |
| **Low** | Improvement-only, no functional impact | Comment style, documentation gaps |

---

## Output format

```
╔══════════════════════════════════════╗
║  Cross-spec audit                    ║
║  Targets: <n> design docs            ║
╚══════════════════════════════════════╝

■ Summary
  Critical: <n> — must resolve
  High:     <n> — recommended
  Medium:   <n> — fix when reasonable
  Low:      <n> — optional

═══ Critical ═══

[AUDIT-1] API contract mismatch
  DESIGN/<provider>.md:<N> — GET /<api_path> → Vec<<Item>>
  DESIGN/<consumer>.md:<N> — expects { items: <Item>[] }
  Recommendation: unify the response shape

═══ High ═══

[AUDIT-3] Constant drift
  DESIGN/<a>.md — CONNECT_TIMEOUT_MS = 3000
  DESIGN/<b>.md — CONNECT_TIMEOUT_MS = 5000
  Recommendation: pick one canonical value

═══ Medium ═══

[AUDIT-5] Type-name drift
  DESIGN/<component_a>.md:<N> — <TypeA>
  DESIGN/<component_b>.md:<N> — <TypeB>
  Recommendation: unify on <TypeA>
```

---

## Pipeline integration

Not called from `impl-orchestrator` (it is a design-time tool, not an implementation gate).

When called from `design-phase` (Sprint 3):
- Run as a self-check after generation.
- Critical contradictions trigger autonomous repair.
- Domain-knowledge contradictions escalate to the user.

Standalone:
- Run during design review.
- Run as a pre-flight check on PRs that touch `DESIGN/*.md`.
