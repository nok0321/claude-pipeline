---
name: impl-orchestrator
description: Use this skill whenever the user wants to autonomously implement one or more components from their `DESIGN/*.md` specs — running the full loop of code generation (sonnet) → verification gate (build / type / test) → parallel review (security / robustness / spec compliance, opus ×3) → finding remediation, repeated up to three iterations. Trigger phrases include "implement the auth component from the spec", "build out DESIGN/03_payment.md", "autonomously implement the backend", "drive the implementation phase", "Phase 2 of the pipeline", "implement based on the design docs", or any spec-driven implementation request. Trigger even when the user does not say "impl-orchestrator" — phrases like "build this from the design doc", "make the code match DESIGN/", or "ship the component end to end" qualify when DESIGN/*.md exists.
argument-hint: "[component-name or 'all']"
allowed-tools: Read, Write, Edit, MultiEdit, Bash, Grep, Glob, Agent
model: claude-opus-4-7
---

# Implementation orchestrator

Drive the spec-to-shipped loop in 4 stages (Phase 2 P4 simplification — was 6 stages):

```
Stage 1: Setup
  → Stage 2: Implement & Verify (sonnet + gate)
  → Stage 3: Review & Remediate (opus ×3 + safe-fix)
  → Stage 4: Iterate or Finalize
```

The 4-stage shape merges the previous Stage 2+3 (implementation and the verification gate now run as a single pair with in-stage fix attempts) and Stage 4+5 (parallel review feeds directly into safe-fix dispatch and the escalation queue without an intermediate hand-off).

---

## Internal state

```
component:        <target component name>
iteration:        1 / 3
design_files:     []     # corresponding DESIGN/*.md
impl_files:       []     # implementation files
gate_results:     {}     # verification gate output
findings:         []     # accumulated review findings
escalation_queue: []     # Tier 1 items (mirror to PIPELINE-STATE.md, see ARCHITECTURE.md §B)
```

---

## Stage 1: Setup

### 1-1: Read project context

From CLAUDE.md:

1. **Component Mapping** — components ↔ specs ↔ implementation directories.
   Missing this section: **escalate** ("Component Mapping not defined in CLAUDE.md — please define"). Why: the orchestrator has no canonical place to write the implementation otherwise.

2. **Commands** — build / test / lint commands.
3. **Critical Constraints** — data-format ordering, architecture rules, etc.
4. **Project-Specific Checks** — extra checks.
5. **Escalation Overrides** — only when present (applied per ARCHITECTURE.md §A).

### 1-2: Read the specs

Load every `DESIGN/*.md` corresponding to the target component.

- Argument `all` → process every component in the mapping in dependency order.
- No explicit ordering → infer from each spec's dependency section.
- DESIGN/*.md absent → fall back to `design-phase` via Agent delegation (entry-point fallback per ARCHITECTURE.md §3.3).

### 1-3: Check PIPELINE-STATE.md

When present, read prior context (plan summary, escalation queue) per ARCHITECTURE.md §B.
When absent, run in standalone mode.

### 1-4: Build the implementation plan

Enumerate implementation units (file granularity) from the specs and order them by dependency. Track progress with TodoWrite.

---

## Stage 2: Implement & Verify (sonnet sub-agent + mechanical gate)

### 2-1: Spawn the implementer

Delegate code generation to a sonnet sub-agent. Why sonnet: implementation is high-volume; judgment is captured downstream by opus reviewers and the verification gate.

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

### 2-3: Verification gate

Mechanical, no judgment required. **All gates must pass.** Use CLAUDE.md `## Commands` first; otherwise fall back by marker file:

| Gate | Marker | Fallback command |
|------|--------|------------------|
| Build | Cargo.toml | `cargo check --workspace` |
|       | package.json | `npm run build` or `npx tsc --noEmit` |
|       | build.gradle / pom.xml | `./gradlew compileJava` or `mvn compile` |
|       | go.mod | `go build ./...` |
| Type / lint | Cargo.toml | `cargo clippy --workspace -- -D warnings` |
|             | tsconfig.json + svelte | `npx svelte-check` |
|             | tsconfig.json | `npx tsc --noEmit` |
|             | pyproject.toml / ruff.toml | `ruff check .` |
|             | go.mod | `go vet ./...` |
| Test | Cargo.toml | `cargo test --workspace` |
|      | package.json | `npm test` |
|      | build.gradle | `./gradlew test` |
|      | go.mod | `go test ./...` |
| Boundary | `**/boundary_*.{rs,ts,test.ts,java}` glob match | covered by the regular test suite |

### 2-4: Gate failure handling

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

### 2-5: Record results

```
gate_results: {
  build: "pass",
  type_check: "pass",
  test_suite: "pass (42 passed, 0 failed)",
  boundary: "skipped (no boundary tests found)"
}
```

---

## Stage 3: Review & Remediate (opus reviewers ×3 + safe-fix)

After every gate passes, spawn three opus reviewers **simultaneously in a single message**, then dispatch findings to safe-fix and the escalation queue.

### 3-1: Prepare review prompts

Read `REVIEW-AGENTS.md` and expand placeholders:

| Placeholder | Value |
|-------------|-------|
| `{target_files}` | Files implemented or modified in Stage 2 |
| `{design_docs}` | DESIGN/*.md from Stage 1 |
| `{project_checks}` | Critical Constraints + Project-Specific Checks |
| `{component_mapping}` | CLAUDE.md Component Mapping |

### 3-2: Spawn the three reviewers

**Send all three Agent calls in one message.** Why parallel: the review axes are independent, and parallelism keeps wall time manageable.

```
Agent(description: "Security review: <component>",   model: "opus", prompt: "<robust-review template, security axis>")
Agent(description: "Robustness review: <component>", model: "opus", prompt: "<robust-review template, robustness axis>")
Agent(description: "Spec compliance: <component>",   model: "opus", prompt: "<spec-audit --mode=conformance>")
```

### 3-3: Fallback on agent failure

- Timeout (>5 min) → skip that axis and record `{ agent: "<axis>", status: "timeout" }`.
- Error exit → same with status `error`.
- Continue with the remaining axes.

### 3-4: Merge findings

Pull findings from all three outputs into `findings`. Deduplicate by file + line, keeping the higher severity.

### 3-5: Dispatch via safe-fix and escalation

Classify each finding via the framework in ARCHITECTURE.md §A. Apply CLAUDE.md `## Escalation Overrides` first.

| Tier | Action |
|------|--------|
| **Tier 1** (must escalate) | Push to `escalation_queue`, mirror to `PIPELINE-STATE.md` (§B). **Do not block.** Continue handling other findings; report at end. |
| **Tier 2** (auto-fix + post-report) | Hand off to `safe-fix` via Agent (`--mode=robust` for SEC-*/ROB-*, `--mode=conformance` for SPEC-*/AUDIT-*). safe-fix re-runs the Stage 2 verification gate after each patch and reverts on failure. Log the auto-fix entry for the post-report. |
| **Tier 3** (auto-fix silent) | Same as Tier 2 but no log entry. |

### 3-6: Design-change loop

When a review surfaces "spec is missing requirements" or "fundamental design issue":

1. **First time**: update `DESIGN/*.md` and return to Stage 2 to re-implement.
2. **Second time and beyond**: escalate as Tier 1. Why the cap: an unbounded design-change loop indicates the original requirement was wrong, which is a Tier 1 issue per ARCHITECTURE.md §A.

---

## Stage 4: Iterate or Finalize

### 4-1: State

```
open_findings = findings.filter(status == "open")
tier1_pending = escalation_queue.filter(status == "pending")
```

### 4-2: Decision

| Condition | Action |
|-----------|--------|
| `open_findings == 0` | **Done** — emit the report |
| `open_findings > 0` ∧ `iteration < 3` | `iteration += 1` → return to Stage 3 |
| `iteration == 3` | **Stop** — report remaining findings |

### 4-3: PIPELINE-STATE.md update

When present, update the implementation table per ARCHITECTURE.md §B:
```
| <component> | done | build:<result> type:<result> test:<result> | security:<result> robustness:<result> spec:<result> |
```

### 4-4: Context management

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
  Auto-fixed:  <n> (Tier 2 + Tier 3 via safe-fix)
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
- DESIGN/*.md missing → fall back to `design-phase` via Agent (impl-orchestrator is the entry point per ARCHITECTURE.md §3.3).
- Build / test commands must come from CLAUDE.md `## Commands` first (auto-detect is fallback only).
- Reviewers run on opus (judgment quality), implementers on sonnet (cost efficiency).
- Design-change reverse flow caps at one iteration per Stage 3-6.
- Tier classification uses ARCHITECTURE.md §A; remediation uses safe-fix (Mode A or B).
- For `all`, recommend a checkpoint between components when context is bloated.
