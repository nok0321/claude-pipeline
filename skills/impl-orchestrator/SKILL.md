---
name: impl-orchestrator
description: Use this skill whenever the user wants to autonomously implement one or more components from their `DESIGN/*.md` specs — running the full loop of code generation (sonnet) → verification gate (build / type / test) → parallel review (security / robustness / spec compliance, opus ×3) → finding remediation, repeated up to three iterations. Trigger phrases include "implement the auth component from the spec", "build out DESIGN/03_payment.md", "autonomously implement the backend", "drive the implementation phase", "Phase 2 of the pipeline", "implement based on the design docs", or any spec-driven implementation request. Trigger even when the user does not say "impl-orchestrator" — phrases like "build this from the design doc", "make the code match DESIGN/", or "ship the component end to end" qualify when DESIGN/*.md exists.
argument-hint: "[component-name or 'all']"
allowed-tools: Read, Write, Edit, MultiEdit, Bash, Grep, Glob, Agent
model: claude-opus-4-7
---

# Implementation orchestrator

Drive the spec-to-shipped loop:

```
Stage 1: Setup → Stage 2: Implementation (sonnet) → Stage 3: Verification gate
  → Stage 4: Parallel review (opus ×3) → Stage 5: Resolve findings → Stage 6: Done check
```

---

## Internal state

```
component:        <target component name>
iteration:        1 / 3
design_files:     []     # corresponding DESIGN/*.md
impl_files:       []     # implementation files
gate_results:     {}     # verification gate output
findings:         []     # accumulated review findings
escalation_queue: []     # Tier 1 items
```

---

## Stage 1: Setup

### 1-1: Read project context

From CLAUDE.md:

1. **Component Mapping** — components ↔ specs ↔ implementation directories
   ```
   ## Component Mapping
   | Component | Spec | Implementation directory |
   ```
   Missing this section: **escalate** ("Component Mapping not defined in CLAUDE.md — please define"). Why: the orchestrator has no canonical place to write the implementation otherwise.

2. **Commands** — build / test / lint commands
3. **Critical Constraints** — data-format ordering, architecture rules, etc.
4. **Project-Specific Checks** — extra checks
5. **Escalation Overrides** — only when present

### 1-2: Read the specs

Load every `DESIGN/*.md` corresponding to the target component.

- Argument `all` → process every component in the mapping in dependency order.
- No explicit ordering → infer from each spec's dependency section.

### 1-3: Check PIPELINE-STATE.md

When present, read prior context (plan summary, escalation queue).
When absent, run in standalone mode.

### 1-4: Build the implementation plan

Enumerate implementation units (file granularity) from the specs and order them by dependency. Track progress with TodoWrite.

---

## Stage 2: Implementation (sonnet sub-agent)

Delegate code generation to a sonnet sub-agent. Why sonnet: implementation is high-volume, judgment is captured downstream by opus reviewers and the verification gate.

### 2-1: Spawn the implementer

```
Agent(
  description: "<component> implementation",
  model: "sonnet",
  prompt: "
    You are the implementer. Build the code that satisfies the spec below.

    ## Spec
    <DESIGN/*.md content>

    ## Project constraints
    <CLAUDE.md Critical Constraints>

    ## Implementation directory
    <Component Mapping path>

    ## Rules
    - Anchor implementation on the spec's code snippets
    - Honor every NEVER rule from CLAUDE.md
    - Match existing-code patterns
    - Add tests per the spec's test requirements
    - Report back the list of files implemented
  "
)
```

### 2-2: Record output

Pull the file list from the agent's report into `impl_files`.

---

## Stage 3: Verification gate

Mechanical, no judgment required. **All gates must pass.**

### 3-1: Build

Use CLAUDE.md Commands first. Otherwise, fall back by marker file:

| Marker | Command |
|--------|---------|
| Cargo.toml | `cargo check --workspace` |
| package.json | `npm run build` or `npx tsc --noEmit` |
| build.gradle / pom.xml | `./gradlew compileJava` or `mvn compile` |
| go.mod | `go build ./...` |

### 3-2: Type check / lint

| Marker | Command |
|--------|---------|
| Cargo.toml | `cargo clippy --workspace -- -D warnings` |
| tsconfig.json + svelte | `npx svelte-check` |
| tsconfig.json | `npx tsc --noEmit` |
| pyproject.toml / ruff.toml | `ruff check .` |
| go.mod | `go vet ./...` |

### 3-3: Test suite

| Marker | Command |
|--------|---------|
| Cargo.toml | `cargo test --workspace` |
| package.json | `npm test` |
| build.gradle | `./gradlew test` |
| go.mod | `go test ./...` |

### 3-4: Boundary contract tests (optional)

```
Glob: **/boundary_*.{rs,ts,test.ts,java}
```

If found, they are part of the regular test suite and covered by 3-3.

### 3-5: Gate failure handling

1. Parse the error and identify the cause.
2. Try up to three autonomous fixes:
   - Compile error → fix per the message.
   - Test failure → reconcile expected vs implemented behavior.
   - Lint warning → patch per the warning.
3. Three failures → **escalate**:
   ```
   Tier 1: verification gate fails after max retries
   Issue: <gate name> still failing after three fix attempts. Error: <summary>
   ```

### 3-6: Record results

```
gate_results: {
  build: "pass",
  type_check: "pass",
  test_suite: "pass (42 passed, 0 failed)",
  boundary: "skipped (no boundary tests found)"
}
```

---

## Stage 4: Parallel review (opus sub-agents ×3)

After every gate passes, spawn three opus reviewers **simultaneously in a single message**. Why parallel: the review axes are independent, and parallelism keeps wall time manageable.

### 4-1: Prepare review prompts

Read `REVIEW-AGENTS.md` and expand placeholders:

| Placeholder | Value |
|-------------|-------|
| `{target_files}` | Files implemented or modified in Stage 2 |
| `{design_docs}` | DESIGN/*.md from Stage 1 |
| `{project_checks}` | Critical Constraints + Project-Specific Checks |
| `{component_mapping}` | CLAUDE.md Component Mapping |

### 4-2: Spawn

**Send all three Agent calls in one message.**

```
Agent(
  description: "Security review: <component>",
  model: "opus",
  prompt: "<expanded REVIEW-AGENTS.md Agent 1 template>"
)

Agent(
  description: "Robustness review: <component>",
  model: "opus",
  prompt: "<expanded REVIEW-AGENTS.md Agent 2 template>"
)

Agent(
  description: "Spec compliance review: <component>",
  model: "opus",
  prompt: "<expanded REVIEW-AGENTS.md Agent 3 template>"
)
```

### 4-3: Fallback on agent failure

- Timeout (>5 min) → skip that axis and record:
  ```
  { agent: "security", status: "timeout", note: "post-report: security review timed out" }
  ```
- Error exit → same with status `error`.
- Continue with the remaining axes.

### 4-4: Merge findings

Pull findings from all three outputs into `findings`. Deduplicate by file + line, keeping the higher severity.

---

## Stage 5: Resolve findings

### 5-1: Escalation classification

Classify each finding via the `escalation` framework. Apply CLAUDE.md `## Escalation Overrides` first.

### 5-2: Tier 1 (must escalate)

- Push to `escalation_queue`.
- Mirror onto `PIPELINE-STATE.md`'s queue if it exists.
- **Do not block.** Continue handling other findings and report at the end.

### 5-3: Tier 2 (auto-fix + post-report)

1. Apply the fix.
2. Re-run **Stage 3 verification gate** end-to-end (must pass again).
3. Log for the post-report:
   ```
   [auto-fix] SEC-1 | Critical | <handler>:<line>
     Change: format!() → .bind() (SQL injection mitigation)
     Verification: <test command> → pass
   ```

### 5-4: Tier 3 (auto-fix silent)

1. Apply the fix.
2. Verify the gate still passes.

### 5-5: Design-change loop

When a review surfaces "spec is missing requirements" or "fundamental design issue":

1. **First time**: update `DESIGN/*.md` and return to Stage 2 to re-implement.
2. **Second time and beyond**: escalate. Why the cap: an unbounded design-change loop indicates the original requirement was wrong, which is a Tier 1 issue.

---

## Stage 6: Done check

### 6-1: State

```
open_findings = findings.filter(status == "open")
tier1_pending = escalation_queue.filter(status == "pending")
```

### 6-2: Decision

| Condition | Action |
|-----------|--------|
| `open_findings == 0` | **Done** — emit the report |
| `open_findings > 0` ∧ `iteration < 3` | `iteration += 1` → Stage 4 |
| `iteration == 3` | **Stop** — report remaining findings |

### 6-3: PIPELINE-STATE.md update

When present, update the implementation table:
```
| <component> | done | build:<result> type:<result> test:<result> | security:<result> robustness:<result> spec:<result> |
```

### 6-4: Context management

Per component, when running `all`:
- Estimate context size before moving to the next component.
- If high, run a checkpoint save and recommend `/compact`. Why: context bloat across components silently degrades subsequent stages.

---

## Final report

```
╔══════════════════════════════════════════════════╗
║  Implementation orchestrator report               ║
║  Target: <component>                              ║
║  Iteration: <iteration> / 3                       ║
╚══════════════════════════════════════════════════╝

■ Verification gate
  Build:    <pass/fail>
  Type:     <pass/fail>
  Test:     <pass/fail> (<passed> passed, <failed> failed)
  Boundary: <pass/fail/skipped>

■ Review summary
  Security:    Critical: <n> / High: <n> / Medium: <n> / Low: <n>
  Robustness:  Critical: <n> / High: <n> / Medium: <n> / Low: <n>
  Spec:        Missing: <n> / Diverged: <n> / Extra: <n> / Constraint: <n>

■ Resolution
  Auto-fixed:  <n> (Tier 2 + Tier 3)
  Escalated:   <n> (Tier 1, see below)

═══ Auto-fix log (Tier 2: post-report) ═══

[1] SEC-1 | Critical | <handler>:<line>
  Change: format!() → .bind() (SQL injection)
  Verification: test suite pass

[2] ROB-3 | High | <file>:<line>
  Change: unwrap() → ?
  Verification: test suite pass

═══ Escalation (Tier 1: user decision needed) ═══

[E-1] SPEC-2 | Missing | undocumented API needed
  Issue: <details>
  Question: <concrete question>

═══ Open findings (unresolved) ═══

(only when iteration cap was hit)

═══ Next actions ═══
  - Answer escalation items
  - Manual confirmation: <browser test, etc.>
```

---

## Constraints

- Component Mapping missing → escalate at Stage 1 and stop. Why: hard-coding paths inside the skill defeats the dynamic-config principle in ARCHITECTURE.md §6.
- Build / test commands must come from CLAUDE.md `## Commands` first (auto-detect is fallback only).
- Reviewers run on opus (judgment quality), implementers on sonnet (cost efficiency).
- Design-change reverse flow caps at one iteration. Why: see Stage 5-5.
- For `all`, recommend a checkpoint between components when context is bloated.
