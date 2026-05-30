---
name: robust-review
description: Use this skill whenever the user wants a deep, dedicated security and robustness review on changed or specified code — looking for injection vectors, panic / crash sources, data-integrity issues, edge-case fragility, and concurrency hazards across two axes (Security and Robustness) with findings ranked Critical / High / Medium / Low. Trigger phrases include "deep security review", "robustness review", "audit this code for vulnerabilities", "find injection vectors", "check for unwrap or panic sources", "pre-merge security pass", "release-readiness review", or any explicit ask for a thorough hardening review beyond a lightweight PR check. Trigger even when the user does not say "robust-review" — phrases like "what could break this in production?", "how safe is this code?", or "audit before release" qualify.
argument-hint: "[file-path, glob-pattern, or 'all']"
allowed-tools: Read, Grep, Glob, Bash
model: claude-opus-4-8
context: fork
---

# Security and robustness deep review

Run a two-axis deep review (Security + Robustness) over the target files and emit a ranked findings list.

---

## Setup

### Determine scope

| Argument | Behavior |
|----------|----------|
| File path | That file only |
| Glob pattern | All matching files |
| `all` | Every implementation directory listed in CLAUDE.md `## Component Mapping` |
| (none) | `git diff --name-only HEAD` (changed files) |

### Read project-specific context

From CLAUDE.md (when present):

1. `## Critical Constraints` — project rules (data-format ordering, architecture limits, framework conventions)
2. `## Project-Specific Checks` — additional checks to apply
3. `## Component Mapping` — used when scope is `all`

If none of these exist, proceed with generic checks (do not error out).

---

## Severity scale

| Level | Definition | Pipeline handling |
|-------|-----------|-------------------|
| **Critical** | Malicious input could cause data destruction, privilege escalation, info leak, or a crash | Tier 2: auto-fix + post-report |
| **High** | Anomalous input could cause service halt or data inconsistency | Tier 2: auto-fix + post-report |
| **Medium** | Edge cases that produce unexpected behavior or performance regression | Tier 3: auto-fix (silent) |
| **Low** | Defensive-programming improvements | Tier 3: auto-fix (silent) |

---

## Axis 1: Security review

### 1-1. Injection

- **SQL / NoSQL injection** — user input concatenated into a query
  - Bad: `format!("SELECT ... WHERE name = '{}'", name)` / `` `SELECT ... WHERE name = '${name}'` ``
  - Good: parameter binding / prepared statements / ORM query builder
  - Severity: **Critical**
- **XSS** — unsanitized input rendered as HTML
  - `innerHTML`, `{@html}`, `v-html`, `dangerouslySetInnerHTML`, template literals into the DOM
  - Severity: **Critical**
- **Command injection** — user input flows into a shell command
  - `exec()`, `spawn()`, `system()`, `Command::new()` with user-controlled args
  - Severity: **Critical**
- **Path traversal** — user input used to construct a filesystem path
  - Inputs containing `../` that escape the intended directory
  - Severity: **High**

### 1-2. Secrets

- Hard-coded passwords, API keys, connection strings → **Critical**
- Stack trace / raw query / internal path leaked through error responses → **High**
- `.env` not in `.gitignore` → **Medium**
- Tokens or PII written into logs → **High**

### 1-3. Access control

- Permissive CORS (`allow_origin(*)`, `Access-Control-Allow-Origin: *`) → **High**
- Authenticated endpoints lacking auth middleware / guard → **Critical**
- Resource-owner authorization (resource belongs to caller) → **Critical**
- CSRF protection (state token) → **High**

### 1-4. Resource exhaustion

- Upload / request body size limits → **Medium**
- Memory control for large data (streaming, pagination) → **Medium**
- Rate limiting → **Medium**
- Regex ReDoS susceptibility → **High**

### 1-5. Cryptography and sessions

- Deprecated algorithms (MD5 / SHA1 for hashing, ECB mode) → **High**
- Cryptographically secure RNG used for session tokens → **High**
- HTTPS enforcement → **Medium**

---

## Axis 2: Robustness review

### 2-1. Panic / crash sources

- Production `unwrap()` / `expect()` (Rust) → **Critical**
- Unchecked array / Vec / Map indexing → **Critical**
- Possible division by zero → **Critical**
- `as` casts that overflow or truncate → **High**
- Unhandled exceptions / errors (missing `catch`, downstream of `?`) → **High**
- `todo!()` / `unimplemented!()` left in tree → **Critical**

### 2-2. Input validation

- External input (API request, file, env var) bounded by type and range → **High**
- NaN / Infinity / empty string / null handled → **Medium**
- String length / collection size limits → **Medium**
- Deserialization rejects malformed data → **High**

### 2-3. Data integrity

- Cascade / transaction integrity on delete → **High**
- Floating-point `==` comparison (use epsilon) → **Medium**
- Concurrent-write protection (optimistic lock / isolation level) → **High**
- Foreign key constraints set at the DB level → **Medium**

### 2-4. Edge cases

- Empty list / single-element handling → **Medium**
- Boundary values (0, max, negatives, `i32::MAX`, `u64::MAX`) → **Medium**
- Unicode / multibyte handling → **Low**

### 2-5. Error propagation and recovery

- Error type covers every case (no over-broad `_` catch-all) → **Medium**
- External-API timeout configured → **High**
- Backoff strategy on retry → **Medium**
- DB-connection failure recovery → **High**

### 2-6. Resource management

- Memory usage on large data (avoid unnecessary `.collect()`) → **Medium**
- Connection / file-handle lifecycle → **High**
- Temporary-file cleanup → **Low**

---

## Project-specific checks

Apply rules from CLAUDE.md `## Critical Constraints` and `## Project-Specific Checks` as additional findings.

Examples:

- Architecture rule (component X must not import Y) → grep for the import → **Critical**
- Data-format ordering rule → check argument order at conversion boundaries → **High**
- Framework convention (handler argument order, etc.) → **Medium**

For each rule, emit a finding at the matching severity when violated.

---

## Output format

The full report block (Summary, Axis 1 Security findings, Axis 2
Robustness findings, Project-specific constraints) is templated in
[references/output-format.md](references/output-format.md). When no
findings exist, report "all checks clean".

---

## Pipeline integration

When called from `impl-orchestrator` Stage 3 (Review & Remediate):
- Target files arrive as `{target_files}` from the orchestrator
- Project checks arrive as `{project_checks}`
- The findings list feeds the Stage 3-5 inline remediation
  ([robust-fix.md](../impl-orchestrator/references/robust-fix.md)) or
  escalation directly

When run standalone:
- Read CLAUDE.md context independently
- After output, recommend invoking `impl-orchestrator` to drive the
  Critical / High auto-fixable subset per [robust-fix.md](../impl-orchestrator/references/robust-fix.md), or apply
  the fixes manually using the JSON Findings block as a checklist
