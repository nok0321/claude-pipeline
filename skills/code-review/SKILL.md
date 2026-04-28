---
name: code-review
description: Use this skill whenever the user wants a lightweight integrated code review for a small-to-medium change — typically right after editing code, before opening a PR, or as a sanity pass before commit. Covers static analysis, security spot-check, robustness spot-check, structure smells, and test-coverage gaps in one report ranked Critical / High / Medium / Low. Trigger phrases include "review my changes", "look over this PR", "give me a code review", "check this diff", "spot-check this commit", or any pre-PR / pre-commit review request. Trigger even when the user does not say "code-review" — implicit phrases like "anything wrong with this?", "anything to fix here?", or "ready to ship?" qualify when the context is a code diff. For deeper pre-merge security audits use `robust-review` instead.
argument-hint: "[file-path or git-range]"
allowed-tools: Read, Grep, Glob, Bash
model: claude-opus-4-7
context: fork
---

# Integrated lightweight code review

## Severity scale

| Level | Definition | Action |
|-------|-----------|--------|
| **Critical** | Defects that can cause data loss, panic / crash, or a security breach | Must fix before merge |
| **High** | Quality, maintainability, or performance issues that affect correctness or operability | Strongly recommended |
| **Medium** | Edge cases or moderate refactor opportunities | Fix when reasonable |
| **Low** | Style and minor improvements | Optional |

---

## Phase 1: Static analysis (automated)

Identify the language of the target files and run the appropriate tool:

| Language | Command |
|----------|---------|
| Rust | `cargo clippy --workspace -- -D warnings` |
| TypeScript | `npx tsc --noEmit` / `npx svelte-check` / `npx vue-tsc --noEmit` |
| Python | `ruff check` / `mypy` / `pyright` |
| Go | `go vet ./...` / `staticcheck ./...` |

Compile errors and type errors are **Critical**.

---

## Phase 2: Security review

### Injection
- [ ] User input concatenated into a SQL / NoSQL query → **Critical**
  - Bad: `format!("SELECT ... WHERE name = '{}'", name)` / `` `SELECT ... WHERE name = '${name}'` ``
  - Good: parameter binding / prepared statements
- [ ] XSS: rendering unsanitized input as HTML (`innerHTML`, `{@html}`, `v-html`, etc.)
- [ ] Command injection: user input passed into shell commands

### Secrets
- [ ] Hard-coded passwords, API keys, connection strings → **Critical**
- [ ] Internal information (stack traces, raw queries) leaked into error responses
- [ ] `.env` listed in `.gitignore`

### Access control
- [ ] CORS not overly permissive in production (`Access-Control-Allow-Origin: *`)
- [ ] Auth-required endpoints actually checked for authentication

### Resource exhaustion
- [ ] Upload size limits
- [ ] Request body size limits
- [ ] Memory control for large data (streaming / pagination)

---

## Phase 3: Robustness review

### Panic / crash sources
- [ ] Production `unwrap()` / `expect()` (Rust) → **Critical**
- [ ] Unchecked array indexing → **Critical**
- [ ] Possible division by zero
- [ ] Unhandled exceptions / errors (missing `catch`, propagation downstream of `?`)

### Input validation
- [ ] External input (API request, file, env var) bounded by type and range
- [ ] NaN / Infinity / empty string / null handled
- [ ] String length / collection size limits

### Edge cases
- [ ] Empty list / single-element handling
- [ ] Boundary values (0, max, negative)
- [ ] Floating-point comparison uses epsilon, not `==`

### Concurrency
- [ ] Shared state guarded (Mutex / lock)
- [ ] Deadlock possibility
- [ ] Concurrent DB writes

---

## Phase 4: Structural review (mostly High / Medium / Low)

- [ ] Single-responsibility adherence
- [ ] Unnecessary clone / copy / allocation
- [ ] Function purity (side effects localized)
- [ ] Consistency between API response types and internal data shapes
- [ ] Unified error type (avoid scattered string errors)

---

## Phase 5: Test impact

1. Identify tests corresponding to changed files.
2. Verify Critical-axis test cases exist.
3. Recommend missing test cases concretely (with code samples).

---

## Output format

```
### Review summary
- Critical: <n> — must fix before merge
- High:     <n> — strongly recommended
- Medium:   <n> — fix when reasonable
- Low:      <n> — optional

### Critical
<file:line> [<category>] <description>
Fix: ...

### High
<file:line> [<category>] <description>
Fix: ...

### Medium
<file:line> [<category>] <description>

### Low
<file:line> <description>

### Test additions recommended
- <missing test case description with code sample>
```
