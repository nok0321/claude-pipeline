# Verification gate commands and failure handling

Detail for SKILL.md Stage 2-3 (verification gate) and Stage 2-4 (failure
handling). The gate is mechanical and must be deterministic — no
judgment is required, and **all gates must pass** before Stage 3 starts.

---

## Command resolution order

1. CLAUDE.md `## Commands` (project-defined; takes priority).
2. Marker-file fallback in the table below.
3. Skip the gate and report `unknown` only if neither resolves.

---

## Per-language fallback commands

| Gate        | Marker                          | Fallback command                                         |
|-------------|---------------------------------|----------------------------------------------------------|
| Build       | Cargo.toml                      | `cargo check --workspace`                                |
|             | package.json                    | `npm run build` or `npx tsc --noEmit`                    |
|             | build.gradle / pom.xml          | `./gradlew compileJava` or `mvn compile`                 |
|             | go.mod                          | `go build ./...`                                         |
| Type / lint | Cargo.toml                      | `cargo clippy --workspace -- -D warnings`                |
|             | tsconfig.json + svelte          | `npx svelte-check`                                       |
|             | tsconfig.json                   | `npx tsc --noEmit`                                       |
|             | pyproject.toml / ruff.toml      | `ruff check .`                                           |
|             | go.mod                          | `go vet ./...`                                           |
| Test        | Cargo.toml                      | `cargo test --workspace`                                 |
|             | package.json                    | `npm test`                                               |
|             | build.gradle                    | `./gradlew test`                                         |
|             | go.mod                          | `go test ./...`                                          |
| Boundary    | `**/boundary_*.{rs,ts,test.ts,java}` glob match | covered by the regular test suite          |

---

## Failure handling (Stage 2-4)

1. Parse the error and identify the cause.
2. Try up to **three autonomous fixes**:
   - Compile error → fix per the message.
   - Test failure → reconcile expected vs implemented behavior.
   - Lint warning → patch per the warning.
3. Three failures → **escalate** as Tier 1 (per ARCHITECTURE.md §A):

```
Tier 1: verification gate fails after max retries
Issue: <gate name> still failing after three fix attempts. Error: <summary>
```

The cap of three is intentional: an unbounded fix loop usually means the
spec is wrong, which is a Tier 1 (user-decision) issue rather than
something the implementer can patch its way out of.

---

## Result-record schema (Stage 2-5)

Output of the gate stage feeds into `gate_results`:

```
gate_results: {
  build:      "pass" | "fail (<short reason>)",
  type_check: "pass" | "fail (<short reason>)",
  test_suite: "pass (<n passed>, <n failed>)" | "fail (<n passed>, <n failed>)",
  boundary:   "pass" | "fail" | "skipped (no boundary tests found)"
}
```
