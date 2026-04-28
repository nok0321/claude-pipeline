---
name: boundary-test
description: Use this skill whenever the user wants to detect contracts at the boundaries between components — REST API ↔ frontend, WASM ↔ TypeScript, DB ↔ application, or unit / coordinate / encoding conversion functions — and auto-generate or run boundary contract tests for them. Surfaces type mismatches and conversion errors mechanically rather than relying on review judgment. Trigger phrases include "test the API/frontend contract", "WASM type-mismatch test", "round-trip test for the converter", "DB schema vs ORM mismatch", "boundary contract test", "test the conversion functions for round-trip", "post-impl-orchestrator final gate", or any conversion / contract test request after API / DB / WASM schema changes. Trigger even when the user does not say "boundary-test" — phrases like "make sure the JSON shape matches what the front end expects" qualify.
argument-hint: "[detect | generate | run | all] [component-name]"
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
model: claude-opus-4-7
---

# Boundary contract test

Detect contracts at component boundaries (API, WASM, DB, conversion functions) and auto-generate plus run contract tests. Catch type mismatches and conversion errors mechanically — independent of review judgment.

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

#### Type A: REST API ↔ Frontend

**Provider side (API):**

| Language / FW | Pattern |
|---------------|---------|
| Rust (Axum) | `async fn` + handler types (`Json<T>`, `Path<T>`, `State<T>`) |
| Rust (Actix) | `#[get]`, `#[post]` + handler functions |
| Node (Express) | `router.get`, `router.post` + response type |
| Python (FastAPI) | `@app.get`, `@app.post` + Pydantic models |
| Java (Spring) | `@GetMapping`, `@PostMapping` + DTO classes |
| Go (gin / echo) | `r.GET`, `r.POST` + response struct |

**Consumer side (frontend):**

| Pattern | Targets |
|---------|---------|
| fetch / axios | `fetch("`, `axios.get(`, `axios.post(` + URL pattern |
| Type definitions | response interface / type definitions |
| API client | generated clients (e.g. openapi-generator) |

**Match by:** URL path + HTTP method.

#### Type B: WASM ↔ TypeScript

**Provider side (WASM):**

| Language | Pattern |
|----------|---------|
| Rust | `#[wasm_bindgen]` + `pub fn` / `pub struct` |
| Go | `//export` directive |
| C / C++ | `EMSCRIPTEN_KEEPALIVE` |

**Consumer side (TypeScript):**
- WASM import: `import { ... } from '*.wasm'` / `init()` pattern
- Types: matching `.d.ts`

**Match by:** export name.

#### Type C: DB ↔ Application

**Schema side:**

| Method | Pattern |
|--------|---------|
| Migration | `CREATE TABLE`, `ALTER TABLE` (SQL) |
| ORM definition | `#[derive(Entity)]`, `@Entity`, `models.Model`, `Schema({` |
| SurrealQL | `DEFINE TABLE`, `DEFINE FIELD` |

**Application side:**
- Model struct / entity class
- Column references in queries

**Match by:** table name + column name.

#### Type D: Conversion boundaries (coordinates, units, encoding, etc.)

Pull conversion rules from CLAUDE.md `## Critical Constraints`.

Detection:
1. Grep for conversion functions (`to_`, `from_`, `convert_`, `transform_`).
2. Pinpoint conversion functions between the type pairs the constraint mentions.
3. Identify round-trippable conversion pairs.

Example (data-format conversion):
```
Constraint: <FormatA>=[<field1>,<field2>], <FormatB>=[<field2>,<field1>]
Detected: to_<format_b>(), from_<format_b>()
Test:    value → to_<format_b> → from_<format_b> → assert_eq(value)
```

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

[A-1] GET /<api_path>
  API: <path/to/handler>:<N> → Json<Vec<<Item>>>
  FE:  <path/to/client>:<N> → expects <Item>[]
  Status: types match ✓ / no test ✗

[A-2] POST /<api_path>
  API: <path/to/handler>:<N> → Json<<CreateResponse>>
  FE:  <path/to/client>:<N> → expects { id: string }
  Status: type mismatch ✗ — response shape diverges

═══ Type D: Conversion ═══

[D-1] <DataType> format conversion
  Constraint: <FormatA>=[<field1>,<field2>] ↔ <FormatB>=[<field2>,<field1>]
  Conversion: <path/to/convert>:<N> — to_<format_b> / from_<format_b>
  Status: no test ✗
```

---

## Step 2: Generate tests

### 2-1: Per-language placement

| Language | Test file | Framework |
|----------|-----------|-----------|
| Rust | `tests/boundary_*.rs` | `#[tokio::test]` + reqwest (API) / direct call (conversion) |
| TypeScript | `__tests__/boundary_*.test.ts` or `*.boundary.test.ts` | vitest / jest |
| Python | `tests/test_boundary_*.py` | pytest |
| Java | `src/test/**/Boundary*IT.java` | JUnit5 + TestContainers + MockMvc |
| Go | `*_boundary_test.go` | `testing` package |

When CLAUDE.md `## Test Conventions` exists, follow that placement instead.

### 2-2: Per-boundary test strategy

#### Type A: REST API ↔ Frontend

```
Strategy: validate response JSON shape

1. Send a request to the API endpoint
2. Verify the JSON shape (field names + types)
3. Compare against the FE type definition

Checks:
- Response field names match FE definition
- Field types (string / number / boolean / array / object) match
- Required vs optional fields match
- Nested object shapes match
- Array element types match
```

#### Type B: WASM ↔ TypeScript

```
Strategy: typed input / output shape

1. Call the WASM function directly
2. Verify input type conversion
3. Verify output type matches the TS expectation

Checks:
- JS → WASM argument conversion is correct
- WASM → JS return-value conversion is correct
- Errors propagate correctly
```

#### Type C: DB ↔ Application

```
Strategy: round-trip (insert → select → assert)

1. Insert a model from the application layer
2. Read back from the DB
3. Assert equality with the original model

Checks:
- Every field maps correctly
- Type conversions (DateTime, JSON, Enum) are correct
- NULL / default-value handling
- Related-table integrity
```

#### Type D: Conversion boundaries

```
Strategy: round-trip (value → forward → reverse → equal)

1. Prepare test values (typical + edge cases)
2. Apply forward conversion
3. Apply reverse conversion
4. Assert equality with the original

Test values:
- Typical values
- Boundary values (0, max, min, negative)
- Edge cases (NaN, Infinity, empty, polar singularities)

Checks:
- Round-trip equality (epsilon tolerance allowed)
- Intermediate range check (output within expected bounds)
```

### 2-3: Avoid duplicate tests

Before generating, grep existing tests; skip when an equivalent check already exists.

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

| Language | Command |
|----------|---------|
| Rust | `cargo test --test 'boundary_*'` |
| TypeScript | `npx vitest run --reporter verbose **/*.boundary.test.ts` or `npx jest --testPathPattern boundary` |
| Python | `pytest tests/test_boundary_*.py -v` |
| Java | `./gradlew test --tests '*BoundaryIT*'` |
| Go | `go test -run Boundary ./...` |

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

═══ Failures ═══

[FAIL] boundary_api::test_get_<resource>_response_shape
  Expected: { items: <Item>[] } (<path/to/client>:<N>)
  Actual:   Vec<<Item>> (bare array, no wrap)
  Boundary: [A-2] GET /<api_path>
  Fix: wrap the API response as { items: [...] } or change the FE type to a bare array

[FAIL] boundary_convert::test_<value>_roundtrip_<edge_case>
  Input:    <Value> { <field1>: NaN, <field2>: 0.0 }
  Expected: round-trip equality or explicit error
  Actual:   panic at <path/to/convert>:<N>
  Boundary: [D-1] <DataType> format conversion
```

---

## Pipeline integration

### impl-orchestrator Stage 3

When boundary tests already exist, they run as part of the regular test suite (Step 3-3 covers them).

When they don't exist:
- `/boundary-test detect` is run to record the boundary list.
- Generation happens as part of Stage 5 (treated as a finding).

### Escalation

Boundary-test failures classify as:
- Type mismatch → Tier 2 (auto-fix + post-report): patch the type definition.
- Design-level disagreement (fundamental API contract drift) → Tier 1 (escalate): user must pick the canonical side.
- Conversion bug → Tier 2: fix the conversion function.

---

## Project-specific boundary definitions

CLAUDE.md may declare additional boundaries via `## Boundary Definitions`:

```markdown
## Boundary Definitions
| Name | Source | Consumer | Conversion rule |
|------|--------|----------|-----------------|
| <name_a> | <component_a> [<field1>,<field2>] | <component_b> [<field2>,<field1>] | swap(0,1) |
| <name_b> | <component_a> [<field1>,<field2>] | <component_c> [<field1>,<field2>] | identity |
| <name_c> | <source> (<sourceFormat>) | <consumer> (<consumerFormat>) | <converter> |
```

When the table exists, `detect` also uses it as a detection source.

---

## Constraints

- `generate` never overwrites an existing boundary test file (creates new files only). Why: existing tests may contain manual edge cases that should not be lost.
- Adding cases to an existing test file is permitted via append.
- DB tests (Type C) require a test database; skip and report when unavailable.
- WASM tests (Type B) need a built WASM artifact; build before testing when missing.
