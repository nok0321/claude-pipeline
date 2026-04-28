---
name: impl-orchestrator
description: Use this skill whenever the user wants to autonomously implement one or more components from their `DESIGN/*.md` specs — running the full loop of code generation (sonnet) → verification gate (build / type / test) → parallel review (security / robustness / spec compliance, opus ×3) → finding remediation, repeated up to three iterations. Trigger phrases include "implement the auth component from the spec", "build out DESIGN/03_payment.md", "autonomously implement the backend", "drive the implementation phase", "Phase 2 of the pipeline", "implement based on the design docs", or any spec-driven implementation request. Trigger even when the user does not say "impl-orchestrator" — phrases like "build this from the design doc", "make the code match DESIGN/", or "ship the component end to end" qualify when DESIGN/*.md exists.
argument-hint: "[component-name or 'all']"
allowed-tools: Read, Write, Edit, MultiEdit, Bash, Grep, Glob, Agent
model: claude-opus-4-7
---

# Implementation orchestrator

Drive the spec-to-shipped loop in 4 stages (Phase 2 P4 simplification —
was 6 stages):

```
Stage 1: Setup
  → Stage 2: Implement & Verify (sonnet + gate)
  → Stage 3: Review & Remediate (opus ×3 + safe-fix)
  → Stage 4: Iterate or Finalize
```

The 4-stage shape merges the previous Stage 2+3 (implementation + gate
as one pair with in-stage fix attempts) and Stage 4+5 (review feeds
directly into safe-fix dispatch and escalation, no hand-off).

Detail references:
- [implementer-prompt.md](references/implementer-prompt.md) — Stage 2 sonnet sub-agent prompt
- [gate-commands.md](references/gate-commands.md) — Stage 2 gate command tables and failure handling
- [review-prompts.md](references/review-prompts.md) — Stage 3 reviewer templates and dispatch table
- [final-report.md](references/final-report.md) — Stage 4 final report template

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

1. **Component Mapping** — components ↔ specs ↔ impl directories.
   Missing → **escalate** ("Component Mapping not defined"); the orchestrator has no canonical place to write the implementation otherwise.
2. **Commands** — build / test / lint commands.
3. **Critical Constraints** — data-format ordering, architecture rules.
4. **Project-Specific Checks** — extra checks.
5. **Escalation Overrides** — applied per ARCHITECTURE.md §A when present.

### 1-2: Read the specs

Load every `DESIGN/*.md` corresponding to the target component.

- Argument `all` → process every component in the mapping in dependency order.
- No explicit ordering → infer from each spec's dependency section.
- DESIGN/*.md absent → fall back to `design-phase` via Agent delegation
  (entry-point fallback per ARCHITECTURE.md §3.3).

### 1-3: Check PIPELINE-STATE.md

When present, read prior context (plan summary, escalation queue) per
ARCHITECTURE.md §B. When absent, run in standalone mode.

### 1-4: Build the implementation plan

Enumerate implementation units (file granularity) from the specs and
order them by dependency. Track progress with TodoWrite.

---

## Stage 2: Implement & Verify (sonnet sub-agent + mechanical gate)

### 2-1: Spawn the implementer

Delegate code generation to a sonnet sub-agent. The full prompt template
is in [references/implementer-prompt.md](references/implementer-prompt.md).

Inputs threaded into the prompt:
- `<DESIGN/*.md content>` for the target component
- CLAUDE.md `## Critical Constraints`
- The Component Mapping path for the component

### 2-2: Record output

Pull the file list from the agent's report into `impl_files`.

### 2-3: Verification gate

Mechanical, no judgment required. **All gates must pass.** The full
command resolution table (CLAUDE.md `## Commands` first, otherwise
marker-file fallbacks for Rust / Node / Python / Java / Go) is in
[references/gate-commands.md](references/gate-commands.md).

### 2-4: Gate failure handling

Up to **three autonomous fix attempts**; on the fourth failure, escalate
as Tier 1. Full procedure and the escalation message format are in
[references/gate-commands.md](references/gate-commands.md).

### 2-5: Record results

Populate `gate_results` per the schema in
[references/gate-commands.md](references/gate-commands.md).

---

## Stage 3: Review & Remediate (opus reviewers ×3 + safe-fix)

After every gate passes, spawn three opus reviewers **simultaneously in
a single message**, then dispatch findings to safe-fix and the
escalation queue.

### 3-1: Prepare review prompts

Read [references/review-prompts.md](references/review-prompts.md) and
expand its placeholders against the current state.

### 3-2: Spawn the three reviewers

Send all three Agent calls (security / robustness / spec-compliance) in
**one message**. Review axes are independent; parallelism bounds wall
time. Templates: [references/review-prompts.md](references/review-prompts.md).

### 3-3: Fallback on agent failure

Timeout (>5 min) or error exit → skip that axis, record `{agent, status}`,
continue with the remaining axes.

### 3-4: Merge findings

Pull findings from all three outputs into `findings`. Deduplicate by
file + line, keeping the higher severity.

### 3-5: Dispatch via safe-fix and escalation

Classify each finding via ARCHITECTURE.md §A (apply CLAUDE.md
`## Escalation Overrides` first). The Tier 1/2/3 dispatch table is in
[references/review-prompts.md](references/review-prompts.md).

### 3-6: Design-change loop

If a review surfaces "spec is missing requirements" or "fundamental
design issue": **first time**, update `DESIGN/*.md` and return to Stage
2; **second time**, escalate as Tier 1 — an unbounded design-change loop
means the original requirement was wrong, which is a §A Tier 1 issue.

---

## Stage 4: Iterate or Finalize

### 4-1: Decision

Compute `open_findings = findings.filter(status == "open")`.

| Condition                                  | Action                                  |
|--------------------------------------------|-----------------------------------------|
| `open_findings == 0`                       | **Done** — emit the report              |
| `open_findings > 0` ∧ `iteration < 3`      | `iteration += 1` → return to Stage 3    |
| `iteration == 3`                           | **Stop** — report remaining findings    |

### 4-2: PIPELINE-STATE.md update

When present, update the implementation table per ARCHITECTURE.md §B:

```
| <component> | done | build:<result> type:<result> test:<result> | security:<result> robustness:<result> spec:<result> |
```

### 4-3: Context management

When running `all`, estimate context size before moving to the next
component. If high, run a checkpoint save and recommend `/compact` —
context bloat across components silently degrades subsequent stages.

### 4-4: Final report

Emit the report. The full block (verification gate, review summary,
resolution log, escalation list, open findings, next actions) is
templated in [references/final-report.md](references/final-report.md).

---

## Constraints

- Component Mapping missing → escalate at Stage 1 and stop.
- DESIGN/*.md missing → fall back to `design-phase` via Agent (impl-orchestrator is the entry point per ARCHITECTURE.md §3.3).
- Build / test commands come from CLAUDE.md `## Commands` first (auto-detect is fallback only).
- Reviewers run on opus (judgment), implementers on sonnet (cost).
- Design-change reverse flow caps at one iteration (Stage 3-6).
- Tier classification uses ARCHITECTURE.md §A; remediation uses safe-fix.
