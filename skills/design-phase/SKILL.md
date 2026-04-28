---
name: design-phase
description: Use this skill whenever the user wants to autonomously generate or update design documents under `DESIGN/` — new specs from a plan summary, multi-component design generation, format learning from existing specs, and self-validation via `spec-audit`. Trigger phrases include "generate the design docs", "write DESIGN/03_payment.md from scratch", "create specs for the components in this plan", "draft DESIGN markdowns from PLAN.md", "design the backend / frontend / core layer", "design phase for the new feature", "update the design docs to match the plan", or any spec-creation request driven by a plan summary or requirement description. Trigger even when the user does not say "design-phase" — phrases like "let's start designing", "I need a spec for the payment retry workflow", or "draft the architecture docs" qualify.
argument-hint: "[component-name or 'all'] [--from-scratch | --update]"
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent
model: claude-opus-4-7
---

# Design phase automation

Generate `DESIGN/*.md` from a plan summary, then auto-detect and resolve
cross-spec contradictions.

For the default DESIGN template, the sub-agent generation prompt, and the
final output format, see [references/templates.md](references/templates.md).
For the audit prompt and contradiction-resolution rules, see
[references/spec-audit-handoff.md](references/spec-audit-handoff.md).

---

## Commands

```
/design-phase                # Generate specs for every component from PIPELINE-STATE.md
/design-phase backend        # Generate the spec for one component
/design-phase --from-scratch # Ignore existing DESIGN/*.md and regenerate (with confirmation)
/design-phase --update       # Diff-update existing DESIGN/*.md against the plan
```

---

## Flow

```
Step 1: Collect inputs
  ↓
Step 2: Learn the format
  ↓
Step 3: Generate specs (sonnet sub-agents)
  ↓
Step 4: Detect contradictions (opus sub-agent — spec-audit equivalent)
  ↓
Step 5: Auto-resolve or escalate
  ↓
Step 6: Update PIPELINE-STATE.md
```

---

## Step 1: Collect inputs

### 1-1: Plan summary

Priority order:
1. The "Plan summary" section of `PIPELINE-STATE.md` (when running inside a pipeline).
2. The conversation context (when running standalone — the user just described requirements).
3. Neither available → ask the user for requirements.

### 1-2: Project context

From CLAUDE.md (when present):
- `## Component Mapping` — existing component layout
- `## Critical Constraints` — hard rules to bake into the design
- `## Tech Stack` — language, framework, DB
- `## Escalation Overrides` — escalation customization

### 1-3: Existing-code scan

When code already exists:
1. Survey the directory structure (`ls -R` or Glob).
2. Extract the major type and API definitions.
3. Use those as references so the new spec aligns with reality.

---

## Step 2: Learn the format

### 2-1: Detect existing specs

```
Glob: DESIGN/*.md, docs/design/*.md, spec/*.md
```

### 2-2: Learn the structure

When `DESIGN/*.md` already exists:
1. Read all of them.
2. Extract the shared structure (section ordering, code-snippet language,
   type-definition notation, table conventions, frontmatter).
3. Use the learned structure as the template for generation.

### 2-3: Default template

When no existing spec is available, fall back to the default template in
[references/templates.md](references/templates.md).

---

## Step 3: Generate specs

### 3-1: Component partition

Identify components from the plan summary:
1. Explicit partition in the plan → follow it.
2. No partition → propose a responsibility-based split (frontend / backend / core / persistence).
3. Existing Component Mapping → align with it.

### 3-2: Dependency ordering

Analyze inter-component dependencies and design from the foundation up:

```
e.g. <foundation> → <domain> → <persistence> → <API> → <UI>
```

### 3-3: Generation (sonnet sub-agent)

Spawn one sonnet sub-agent per component. The full prompt template,
generation rules, and `--update` mode behavior are in
[references/templates.md](references/templates.md).

Inputs threaded into each sub-agent:
- Relevant slice of the plan summary
- CLAUDE.md Critical Constraints + Tech Stack
- Public-API sections of upstream specs already generated this run
- The Step 2 learned template (or the default template)

---

## Step 4: Detect contradictions

Run an opus sub-agent over the freshly generated set, equivalent to
`/spec-audit --mode=cross`. The exact prompt and the seven check
categories (type drift, shared-type field mismatch, API contract,
dependency cycles, DB schema, terminology, constant drift) live in
[references/spec-audit-handoff.md](references/spec-audit-handoff.md).

---

## Step 5: Resolve contradictions

Classify each finding against the escalation framework, then auto-resolve
Tier 2/3 and queue Tier 1 for the user. Re-run Step 4 after fixes (max 2
iterations).

The full classification table and the auto-resolve / re-check loop are in
[references/spec-audit-handoff.md](references/spec-audit-handoff.md).

---

## Step 6: Wrap up

### 6-1: PIPELINE-STATE.md

When `PIPELINE-STATE.md` exists:

1. Update the Design Artifacts section with `[x]` per generated spec and
   `[ ]` for any spec blocked on a Tier 1 escalation.
2. Push Tier 1 items into the escalation queue.
3. Write a hand-off note for the next phase (impl-orchestrator).

The exact PIPELINE-STATE.md layout is in
[references/spec-audit-handoff.md](references/spec-audit-handoff.md);
the canonical pipeline state format is ARCHITECTURE.md §B 補章.

### 6-2: Component Mapping proposal

When CLAUDE.md lacks a Component Mapping:
- Propose one based on the generated specs.
- After user approval, append to CLAUDE.md (used by `impl-orchestrator`).

---

## Output format

Final report renders the generated spec list, the audit summary, the
auto-resolved findings, the escalated findings, and (when applicable) the
Component Mapping proposal.

The full output template is in
[references/templates.md](references/templates.md).

---

## Pipeline integration

Inside `impl-orchestrator` (Phase 1, when DESIGN/*.md is missing):
- Pull the plan summary from `PIPELINE-STATE.md`.
- If escalation queue has pending items, present them and wait for the user.
- Only advance to implementation once every escalation is resolved.

Standalone:
- Take the requirements straight from the conversation.
- Run without `PIPELINE-STATE.md`.
