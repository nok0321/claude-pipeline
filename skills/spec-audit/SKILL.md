---
name: spec-audit
description: Use this skill whenever the user wants a unified design-spec audit — either detecting inconsistencies BETWEEN design documents under `DESIGN/` (type / field drift, divergent API contracts, dependency cycles, DB-schema disagreements, terminology and constant drift) OR comparing design documents AGAINST the implementation (Missing / Diverged / Extra / Constraint). Trigger phrases include "audit our design docs", "do the spec markdowns line up", "API contract drift across designs", "scan DESIGN/*.md for mismatches" (cross-spec mode), as well as "check spec vs implementation", "does the code match DESIGN/01_auth.md?", "verify implementation matches the spec", "list missing items from the design doc", "find diverged signatures between spec and code" (conformance mode). Trigger even when the user does not say "spec-audit" — implicit phrases like "did the design docs drift?", "is the implementation behind the spec?", "anything off between these markdowns?", or "compare what we built against what we designed" qualify.
argument-hint: "[component-name or 'all'] [--mode=cross|conformance|both]"
allowed-tools: Read, Grep, Glob, Bash
model: claude-opus-4-8
context: fork
---

# Spec audit (cross-spec + implementation conformance)

Two-mode skill that audits design specs in `DESIGN/`:

- **Cross-spec mode** — contradictions between specs (the original `spec-audit` job).
- **Conformance mode** — diff between spec and implementation (replaces the retired `spec-check`).

Mode is chosen by the user request or the explicit `--mode=` argument; default is `both`.

---

## Setup

### Resolve component mapping

Read CLAUDE.md `## Component Mapping`:

```markdown
## Component Mapping
| Component | Spec | Implementation directory |
|-----------|------|--------------------------|
| <component_a> | DESIGN/01_<component_a>.md | <path/to/component_a>/ |
```

If absent: glob `DESIGN/*.md`, infer component names from filenames, probe the project layout for the implementation directory. If neither `DESIGN/` nor a mapping exists, report "no design docs found" and stop.

### Determine scope

| Argument | Behavior |
|----------|----------|
| Component name | That component (plus its dependency specs in cross mode) |
| `all` | Every spec / every component |
| (none) | Components touched by `git diff --name-only HEAD` (conformance) or every spec (cross) |

### Mode dispatch

| `--mode=` | Effect |
|-----------|--------|
| `cross` | Cross-spec checks only |
| `conformance` | Spec-vs-impl checks only |
| `both` (default) | Cross-spec first, then conformance; merge findings |

If the user request mentions only design docs (no implementation noun), default to `cross`. If it mentions code, implementation, signatures, or endpoints, default to `conformance`.

### Project-specific context

Optional CLAUDE.md sections:
- `## Critical Constraints` — fed into the conformance Constraint check.
- `## Project-Specific Checks` — additional checks for either mode.

---

## Mode A: Cross-spec checks

### Inputs

For each spec in scope, extract: type definitions (struct / interface / enum / alias), function signatures (`pub fn`, `export function`, etc.), API endpoint definitions, DB table / collection definitions, domain terms, dependency declarations, constants and configuration values.

### Checks

1. **Type / field name drift** — same concept named differently. Pair similarly-named types, compare field composition.
2. **Shared-type field mismatch** — same type name, diverging fields across specs.
3. **API contract mismatch** — provider signature vs consumer expectation (response shape, status codes).
4. **Dependency cycles** — DFS + back-edge detection on declared deps.
5. **DB-schema mismatch** — same table with diverging columns / types / constraints.
6. **Terminology drift** — synonyms, language drift, abbreviation drift across specs.
7. **Constant / configuration drift** — same named constant with different values.

### Arbitration

For findings in categories 1, 6, and 7 (naming/terminology/constant drift), invoke the `technical-arbiter` subagent before emitting the report. The arbiter takes the candidate values plus evidence and returns either a canonical recommendation (with confidence and reasoning) or a deferral with a specific user question. Categories 2, 3, 4, 5 skip arbitration — those resolve mechanically (merges, DFS) or require user-only judgement an arbiter cannot supply.

Invocation (one call per affected finding; independent calls may be batched in parallel):

```
Task tool → subagent_type: technical-arbiter
prompt: <JSON: drift_type, candidates[{value, evidence_locations[]}], context_files[]>
```

Incorporate the arbiter response into the finding's `Recommendation` field:

| Arbiter response | Recommendation field |
|---|---|
| `confidence: high` or `medium` | `use <value> — <one-sentence reasoning from arbiter>` |
| `deferred_to_user: true` | prepend the arbiter's `user_question`, then `pick one canonical value` |

Append every arbiter call to `evals/arbiter-decisions.jsonl` (append-only, one JSON object per line):

```json
{"timestamp":"<ISO8601>","skill":"spec-audit","finding_id":"<AUDIT-n>","drift_type":"<type>","candidates":[{"value":"...","evidence_locations":["..."]}],"decision":{"value":"...","confidence":"...","reasoning":"..."},"deferred_to_user":false,"user_question":null}
```

When `deferred_to_user: true`, set `decision: null` and populate `user_question`. The log is the source of truth for arbiter behavior review during dogfooding.

---

## Mode B: Implementation conformance

### Diff classes

| Class | Meaning | Default severity |
|-------|---------|------------------|
| **Missing** | Spec has it, code doesn't | Critical (public API / core type) or Medium (doc-only) |
| **Diverged** | Implementation differs from spec | High (signature, field, endpoint) |
| **Extra** | Code has it, spec doesn't | Medium (public surface) or Low (otherwise) |
| **Constraint** | Violates a CLAUDE.md `## Critical Constraints` rule | High |

### Procedure

1. **Public-API existence** — by language:

   | Language | Targets |
   |----------|---------|
   | Rust | `pub fn`, `pub struct`, `pub enum`, `pub trait`, `pub type` |
   | TypeScript | `export function`, `export class`, `export interface`, `export type`, `export const` |
   | Go | identifiers starting uppercase |
   | Java | `public class`, `public interface`, `public enum` |
   | Python | module-level `def`, `class` |

   Spec has it, code doesn't → **Missing**. Code has it, spec doesn't → **Extra**.

2. **Function-signature comparison** — argument names / types / order, return type, generics, visibility. Mismatch → **Diverged**. If the implementation is strictly more robust than the spec (e.g. wraps return in `Result`), report Diverged with a "spec update recommended" note.

3. **Type / struct field comparison** — field names, types, visibility, enum variants, default values.

4. **API endpoint comparison** — method, path, request / response types, status codes. Match against routing definitions (`Router`, `@app.route`, `@RequestMapping`, etc.).

5. **DB schema comparison** — table name, columns, types, indexes, foreign-key constraints. Match against migrations / schema definitions.

6. **Constraint check** — for each rule in CLAUDE.md `## Critical Constraints`, define a detection. Architecture rules → grep `import` statements. Data-format ordering → check arg order at conversion boundaries. Framework convention → arg / decorator order.

---

## Severity scale (both modes)

| Level | Definition |
|-------|-----------|
| **Critical** | Will cause a build or runtime failure |
| **High** | Causes confusion or data drift but won't break the build |
| **Medium** | Style / consistency issues that hurt readability |
| **Low** | Improvement-only, no functional impact |

---

## Output format

Cross-mode finding tag = `AUDIT-<n>`. Conformance-mode tag = `SPEC-<n>`. When `both`, emit one combined report per severity bucket.

```
╔══════════════════════════════════════╗
║  Spec audit                          ║
║  Mode: <cross | conformance | both>  ║
║  Targets: <n> specs / <n> components ║
╚══════════════════════════════════════╝

■ Summary
  Critical: <n> — must resolve
  High:     <n> — recommended
  Medium:   <n> — fix when reasonable
  Low:      <n> — optional

═══ Critical ═══

[SPEC-1] Missing | Public API
  Spec: DESIGN/<component>.md:<N> — pub fn <function_name>(<args>) -> <ReturnType>
  Code: (none)
  Recommendation: implement the function

[AUDIT-1] API contract mismatch
  Provider: DESIGN/<provider>.md:<N> — GET /<api_path> -> Vec<<Item>>
  Consumer: DESIGN/<consumer>.md:<N> — expects { items: <Item>[] }
  Recommendation: unify the response shape

═══ High ═══

[SPEC-2] Diverged | Signature
  Spec: DESIGN/<component>.md:<N> — fn <function_name>(<args>) -> <ReturnType>
  Code: <path/to/file>:<N> — fn <function_name>(<args>) -> Result<<ReturnType>, Error>
  Recommendation: update spec — implementation is strictly more robust

[AUDIT-3] Constant drift
  DESIGN/<a>.md — CONNECT_TIMEOUT_MS = 3000
  DESIGN/<b>.md — CONNECT_TIMEOUT_MS = 5000
  Recommendation: pick one canonical value

═══ Medium ═══

[SPEC-3] Extra | Function
  Code: <path/to/file>:<N> — pub fn <helper_name>(<args>)
  Recommendation: document in spec, or downgrade to internal visibility

[AUDIT-5] Type-name drift
  DESIGN/<component_a>.md:<N> — <TypeA>
  DESIGN/<component_b>.md:<N> — <TypeB>
  Recommendation: unify on <TypeA>
```

When everything matches: report "specs are mutually consistent and aligned with the implementation".

### Schema-compliant JSON emission

After the human-readable report, emit a single fenced code block tagged
`json` containing every finding as an array conforming to
[skills/impl-orchestrator/references/finding.schema.json](../impl-orchestrator/references/finding.schema.json).
Conformance findings use `finding_id` prefix `SPEC-`, cross-spec findings use `AUDIT-`. Both modes must populate `spec_ref`. This block is the input contract for the orchestrator's inline conformance remediation (see [conformance-fix.md](../impl-orchestrator/references/conformance-fix.md)).

---

## Pipeline integration

- **Standalone (cross mode)** — design review, or pre-flight on PRs that touch `DESIGN/*.md`.
- **From `design-phase`** — run in cross mode as a self-check after generation. Critical contradictions trigger autonomous repair; domain-knowledge contradictions escalate to the user.
- **From `impl-orchestrator` Stage 4 (Spec Compliance Reviewer)** — run in conformance mode. Findings convert to the orchestrator's unified format.
- **Standalone (conformance mode)** — after the report, recommend invoking `impl-orchestrator` to drive remediation per [conformance-fix.md](../impl-orchestrator/references/conformance-fix.md), or apply patches manually using the JSON Findings block as a checklist.
