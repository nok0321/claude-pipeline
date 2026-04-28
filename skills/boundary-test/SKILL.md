---
name: boundary-test
description: Use this skill whenever the user wants to detect contracts at the boundaries between components — REST API ↔ frontend, WASM ↔ TypeScript, DB ↔ application, or unit / coordinate / encoding conversion functions — and auto-generate or run boundary contract tests for them. Surfaces type mismatches and conversion errors mechanically rather than relying on review judgment. Trigger phrases include "test the API/frontend contract", "WASM type-mismatch test", "round-trip test for the converter", "DB schema vs ORM mismatch", "boundary contract test", "test the conversion functions for round-trip", "post-impl-orchestrator final gate", or any conversion / contract test request after API / DB / WASM schema changes. Trigger even when the user does not say "boundary-test" — phrases like "make sure the JSON shape matches what the front end expects" qualify.
argument-hint: "[detect | generate | run | all] [component-name]"
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
model: claude-opus-4-7
context: fork
---

# Boundary contract test

Detect contracts at component boundaries (API, WASM, DB, conversion
functions) and auto-generate plus run contract tests. Catch type
mismatches and conversion errors mechanically — independent of review
judgment.

Per-boundary detection patterns and test strategies live under
`references/`:

- Type A (REST API ↔ Frontend) — see [references/type-a-rest-api.md](references/type-a-rest-api.md)
- Type B (WASM ↔ TypeScript) — see [references/type-b-wasm.md](references/type-b-wasm.md)
- Type C (DB ↔ Application) — see [references/type-c-db.md](references/type-c-db.md)
- Type D (Conversion) — see [references/type-d-conversion.md](references/type-d-conversion.md)

---

## Commands

```
/boundary-test detect              # Detect boundaries and list them
/boundary-test detect backend      # Detect within one component only
/boundary-test generate            # Generate tests for the detected boundaries
/boundary-test generate backend    # Generate tests for one component
/boundary-test run                 # Run the existing boundary tests
/boundary-test all                 # detect → generate → run end-to-end
```

---

## Step 1: Detect boundaries

### 1-1: Read project context

From CLAUDE.md (when present):
- `## Component Mapping` — components and implementation directories
- `## Critical Constraints` — conversion rules (coordinate ordering, etc.)
- `## Boundary Definitions` — project-specific boundary table

When Component Mapping is missing, infer from the project layout.

### 1-2: Per boundary type

Four categories. For each, apply the detection patterns from the
matching reference file:

| Type | Boundary             | Match key                  | Reference                                              |
|------|----------------------|----------------------------|--------------------------------------------------------|
| A    | REST API ↔ Frontend  | URL path + HTTP method     | [type-a-rest-api.md](references/type-a-rest-api.md)    |
| B    | WASM ↔ TypeScript    | Export name                | [type-b-wasm.md](references/type-b-wasm.md)            |
| C    | DB ↔ Application     | Table name + column name   | [type-c-db.md](references/type-c-db.md)                |
| D    | Conversion           | Conversion-pair signatures | [type-d-conversion.md](references/type-d-conversion.md) |

### 1-3: Detection report

```
╔══════════════════════════════════════╗
║  Boundary detection                  ║
╚══════════════════════════════════════╝

■ Summary
  Type A (REST API ↔ Frontend):  <n>
  Type B (WASM ↔ TypeScript):    <n>
  Type C (DB ↔ Application):     <n>
  Type D (Conversion):           <n>

═══ Type A: REST API ↔ Frontend ═══
[A-N] <METHOD> /<api_path>
  API: <path/to/handler>:<N> → <provider type>
  FE:  <path/to/client>:<N>  → expects <consumer type>
  Status: types match ✓ / type mismatch ✗ / no test ✗
```

Per-type field examples (Type A response shape, Type D conversion pair,
etc.) are in the type-specific reference files.

---

## Step 2: Generate tests

### 2-1: Per-language placement

| Language   | Test file                                                | Framework                                            |
|------------|----------------------------------------------------------|------------------------------------------------------|
| Rust       | `tests/boundary_*.rs`                                    | `#[tokio::test]` + reqwest (API) / direct call       |
| TypeScript | `__tests__/boundary_*.test.ts` or `*.boundary.test.ts`   | vitest / jest                                        |
| Python     | `tests/test_boundary_*.py`                               | pytest                                               |
| Java       | `src/test/**/Boundary*IT.java`                           | JUnit5 + TestContainers + MockMvc                    |
| Go         | `*_boundary_test.go`                                     | `testing` package                                    |

When CLAUDE.md `## Test Conventions` exists, follow that placement
instead.

### 2-2: Per-boundary test strategy

Apply the strategy from the matching reference file (links in Step 1-2).
At a glance:

| Type | Strategy                                                  |
|------|-----------------------------------------------------------|
| A    | Validate response JSON shape against FE type definition   |
| B    | Verify JS↔WASM argument and return-value conversions      |
| C    | Round-trip via DB (insert → select → assert)              |
| D    | Round-trip via conversion (forward → reverse → assert)    |

### 2-3: Avoid duplicate tests

Before generating, grep existing tests; skip when an equivalent check
already exists.

---

## Step 3: Run tests

### 3-1: Discover boundary tests

```
Glob: **/boundary_*.{rs,ts,test.ts,test.js,py,java,go}
Glob: **/*.boundary.test.{ts,js}
Glob: **/Boundary*IT.java
Glob: **/*_boundary_test.go
```

### 3-2: Per-language run

CLAUDE.md `## Commands` takes priority; otherwise auto-detect:

| Language   | Command                                                                        |
|------------|--------------------------------------------------------------------------------|
| Rust       | `cargo test --test 'boundary_*'`                                               |
| TypeScript | `npx vitest run --reporter verbose **/*.boundary.test.ts` or `npx jest --testPathPattern boundary` |
| Python     | `pytest tests/test_boundary_*.py -v`                                           |
| Java       | `./gradlew test --tests '*BoundaryIT*'`                                        |
| Go         | `go test -run Boundary ./...`                                                  |

### 3-3: Output

```
╔══════════════════════════════════════╗
║  Boundary test results               ║
╚══════════════════════════════════════╝

■ Summary
  Run:     <n>
  Pass:    <n> ✓
  Fail:    <n> ✗
  Skipped: <n> —
```

Per-type failure examples (with field-level diagnostics) live in the
type-specific reference files.

---

## Pipeline integration

### impl-orchestrator Stage 3

When boundary tests already exist, they run as part of the regular test
suite (Step 3-3 covers them).

When they don't exist:
- `/boundary-test detect` is run to record the boundary list.
- Generation happens as part of the review phase (treated as a finding).

### Escalation

Boundary-test failures classify as (see ARCHITECTURE.md §A 補章):
- Type mismatch → Tier 2 (auto-fix + post-report): patch the type definition.
- Design-level disagreement (fundamental API contract drift) → Tier 1 (escalate): user must pick the canonical side.
- Conversion bug → Tier 2: fix the conversion function.

---

## Project-specific boundary definitions

CLAUDE.md may declare additional boundaries via a `## Boundary Definitions`
table. When the table exists, `detect` also uses it as a detection source.
For the table format, see [references/claude-md-boundary-table.md](references/claude-md-boundary-table.md).

---

## Constraints

- `generate` never overwrites an existing boundary test file (creates new files only). Existing tests may contain manual edge cases that should not be lost.
- Adding cases to an existing test file is permitted via append.
- DB tests (Type C) require a test database; skip and report when unavailable.
- WASM tests (Type B) need a built WASM artifact; build before testing when missing.
