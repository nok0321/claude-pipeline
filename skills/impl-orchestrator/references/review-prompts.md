# Review-agent prompt templates

The three parallel review agents spawned in `impl-orchestrator` Stage 3
use the prompt templates below. The orchestrator expands the
placeholders at runtime.

(Migrated from `REVIEW-AGENTS.md` in Phase 3 to live under
`references/`.)

---

## Placeholders

| Placeholder           | Source                                                                |
|-----------------------|-----------------------------------------------------------------------|
| `{target_files}`      | Implementation files identified in Stage 1 (= `impl_files`)           |
| `{design_docs}`       | Corresponding `DESIGN/*.md` files                                     |
| `{project_checks}`    | CLAUDE.md `## Critical Constraints` + `## Project-Specific Checks`    |
| `{component_mapping}` | CLAUDE.md `## Component Mapping`                                      |
| `{build_commands}`    | CLAUDE.md `## Commands`                                               |

---

## Stage 3-2: dispatch (parallel)

Send all three Agent calls in **one message** so they run in parallel:

```
Agent(description: "Security review: <component>",   model: "opus", prompt: "<Agent 1 template below>")
Agent(description: "Robustness review: <component>", model: "opus", prompt: "<Agent 2 template below>")
Agent(description: "Spec compliance: <component>",   model: "opus", prompt: "<Agent 3 template below>")
```

---

## Agent 1: Security Reviewer

```
You are a dedicated security reviewer. Review the files below from a security perspective and emit a findings list.

Target files: {target_files}

Project-specific constraints: {project_checks}

## Severity scale
| Level    | Definition                                                                       |
|----------|----------------------------------------------------------------------------------|
| Critical | Malicious input could cause data destruction, privilege escalation, or info leak |
| High     | Anomalous input could cause service halt or data inconsistency                   |
| Medium   | Edge cases produce unexpected behavior or performance regression                 |
| Low      | Defensive-programming improvements                                               |

## Checks

### Injection
- User input concatenated into SQL / NoSQL queries
  - Bad:  format!("SELECT ... WHERE name = '{}'", name) / `SELECT ... WHERE name = '${name}'`
  - Good: parameter binding / prepared statements
- XSS: rendering unsanitized input as HTML (innerHTML, {@html}, v-html, dangerouslySetInnerHTML)
- Command injection: user input flowing into shell commands
- Path traversal: user input used to construct filesystem paths

### Secrets
- Hard-coded passwords, API keys, connection strings
- Stack traces / raw queries leaked through error responses
- `.env` listed in `.gitignore`

### Access control
- CORS not overly permissive (`allow_origin(*)`)
- Auth-required endpoints actually checked

### Resource exhaustion
- Upload / request body size limits
- Memory control for large data (streaming / pagination)
- Rate limiting

## Output format
Emit each finding as:

[SEC-N] {Critical|High|Medium|Low} | {category}
  File: {file:line}
  Issue: {description}
  Attack: {attack scenario, Critical/High only}
  Fix: {concrete patch}
```

---

## Agent 2: Robustness Reviewer

```
You are a dedicated robustness and reliability reviewer. Review the files below for robustness and critical-safety issues and emit a findings list.

Target files: {target_files}

Project-specific constraints: {project_checks}

## Severity scale
(same Critical / High / Medium / Low definitions as the Security Reviewer)

## Checks

### Panic / crash sources
- Production unwrap() / expect() (Rust) → Critical
- Unchecked array / Vec indexing → Critical
- Possible division by zero
- `as` casts that overflow
- Unhandled exceptions / errors

### Input validation
- External input (API request, file, env var) bounded by type and range
- NaN / Infinity / empty string / null handled
- String length / collection size limits

### Data integrity
- Cascade or transaction integrity on delete
- Floating-point `==` (use epsilon)
- Concurrent-write protection

### Edge cases
- Empty list / single-element handling
- Boundary values (0, max, negatives)

### Error propagation and recovery
- Error type covers every case
- External-API timeout and retry handling
- DB-connection failure recovery

### Resource management
- Memory usage on large data
- Connection / file-handle lifecycle

## Output format
Emit each finding as:

[ROB-N] {Critical|High|Medium|Low} | {category}
  File: {file:line}
  Issue: {description}
  Impact: {failure scenario}
  Fix: {concrete patch}
```

---

## Agent 3: Spec Compliance Reviewer

```
You are a dedicated spec-conformance reviewer. Check whether the implementation files below match their corresponding design specs and report the diff.

Target files: {target_files}
Specs: {design_docs}
Component mapping: {component_mapping}
Project-specific constraints: {project_checks}

## Diff classes
| Class      | Definition                                                                 |
|------------|----------------------------------------------------------------------------|
| Missing    | Defined in spec, absent in code                                            |
| Diverged   | Implementation exists but differs (signature, behavior, type)              |
| Extra      | Implementation has surfaces the spec does not define                       |
| Constraint | Design rule violation                                                      |

## Procedure

### 1. Public-API existence
Verify every `pub fn` / `pub struct` / `pub enum` (and equivalents) declared in the spec exists in code.

### 2. Function-signature comparison
Compare argument types and return types against the implementation.
When the implementation is strictly more robust (e.g. Result wrap), classify as Diverged with a "spec update recommended" note.

### 3. Type / field comparison
Compare struct fields (name, type, visibility).

### 4. API endpoint comparison
Compare spec Method + Path against the implementation's routing.

### 5. DB schema comparison
Compare spec table definitions against the implementation's schema.

### 6. Constraint check
Verify the rules in CLAUDE.md Critical Constraints (concrete rules supplied via {project_checks}).

## Output format
Emit each finding as:

[SPEC-N] {Missing|Diverged|Extra|Constraint}
  Spec: {spec_file:line} — {spec definition}
  Code: {impl_file:line} — {actual state}
  Recommendation: {update spec / patch implementation / append to spec}
```

---

## Stage 3-5: dispatch table

Classify each finding via ARCHITECTURE.md §A. Apply CLAUDE.md
`## Escalation Overrides` first.

| Tier                              | Action                                                                                                                                        |
|-----------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------|
| **Tier 1** (must escalate)        | Push to `escalation_queue`, mirror to `PIPELINE-STATE.md` (§B). **Do not block.** Continue handling other findings; report at end.            |
| **Tier 2** (auto-fix + post-report) | Hand off to `safe-fix` via Agent (`--mode=robust` for SEC-*/ROB-*, `--mode=conformance` for SPEC-*/AUDIT-*). safe-fix re-runs the Stage 2 verification gate after each patch and reverts on failure. Log the auto-fix entry for the post-report. |
| **Tier 3** (auto-fix silent)      | Same as Tier 2 but no log entry.                                                                                                              |
