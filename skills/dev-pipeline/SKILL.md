---
name: dev-pipeline
description: Use this skill whenever the user explicitly wants the full plan → design → implementation → test → report pipeline driven end-to-end as one autonomous run, with the only required user touchpoints being plan approval and escalation answers. Each phase is delegated via the Agent tool to its dedicated sub-skill (design-phase, impl-orchestrator, boundary-test, spec-fix, robust-review). Trigger phrases include "run the full pipeline", "kick off dev-pipeline", "do the whole flow plan to ship", "autonomous build of <feature>", "resume the pipeline", or any explicit ask for cross-phase orchestration. Trigger even when the user does not say "dev-pipeline" — phrases like "take this requirement all the way to implementation" qualify only when the user clearly wants every phase rolled up. For implementation alone (specs already exist) prefer `impl-orchestrator`.
argument-hint: "<task-description> | resume | abort"
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent
model: claude-opus-4-7
---

# Autonomous development pipeline

A pure orchestrator that runs design → implementation → test → report autonomously. Hold no per-phase logic; delegate everything via the `Agent` tool.

User touchpoints: **plan approval** and **escalation answers** only.

---

## Phase map

| Phase | Name | Delegate | Model |
|-------|------|----------|-------|
| 0 | Plan (interactive) | dev-pipeline itself | opus |
| 1 | Design (autonomous) | `design-phase` skill | opus |
| 2 | Implementation (autonomous) | `impl-orchestrator` per component | opus |
| 2.5 | Boundary verification | `boundary-test all` | opus |
| 3 | Test (autonomous) | `spec-fix --loop all` + `robust-review all` | opus |
| 4 | Report | dev-pipeline itself | opus |

Every phase boundary updates `PIPELINE-STATE.md` via the `pipeline-state` skill and runs `checkpoint save`.

---

## Entry points

```
/dev-pipeline <task-description>   # Start a new pipeline
/dev-pipeline resume               # Resume from PIPELINE-STATE.md
/dev-pipeline abort                # Cancel an in-flight pipeline
```

If invoked with no argument and `PIPELINE-STATE.md` exists, treat as `resume`.

---

## Phase 0: Plan (interactive)

Structure the plan from `<task-description>` and obtain user approval.

### 0-1: Present the plan

```
╔══════════════════════════════════════╗
║  Pipeline plan                       ║
╚══════════════════════════════════════╝

■ Task overview / scope / component partition / approach / risks / size estimate

→ Proceed with this plan? [y / revise / abort]
```

### 0-2: User approval (the only required gate)

Approve → Phase 1. Revise → re-present. Abort → exit.

### 0-3: Initialize state

Run a `pipeline-state init <task-name>` equivalent and record the plan summary.

---

## Phase 1: Design

Delegate to `design-phase`:

```
Agent(
  description: "Phase 1: Design generation",
  subagent_type: "general-purpose",
  prompt: "
    Run the /design-phase skill.
    Generate DESIGN/*.md from the plan summary in PIPELINE-STATE.md and finish the spec-audit self-check.

    Return:
    - Paths to the generated DESIGN/*.md
    - Audit results (auto-resolved / Tier 1 escalation items)
    - Component Mapping proposal (when CLAUDE.md has none)
  "
)
```

Post-agent:
1. Surface any Tier 1 escalations to the user and wait.
2. Apply user answers and patch the specs if needed.
3. `pipeline-state update design ...` — record artifacts.
4. `pipeline-state transition implementation`.
5. `checkpoint save`.

---

## Phase 2: Implementation

Process components in dependency order. Each component runs in its own `impl-orchestrator` agent.

### 2-1: Component loop

```
for component in dependency_order:
    Agent(
      description: "Phase 2: Implement <component>",
      subagent_type: "general-purpose",
      prompt: "
        Run /impl-orchestrator <component>.
        Drive every Stage 1–6: full verification gate, parallel review (security / robustness / spec), and finding resolution.

        Return:
        - Verification gate results (build / type / test / boundary)
        - Review finding summary (counts by severity)
        - Auto-fix log (Tier 2)
        - Tier 1 escalation items
      "
    )
    pipeline-state update impl
    Surface any Tier 1 items and wait
```

### 2-2: Boundary verification

After every component:

```
Agent(
  description: "Phase 2.5: Boundary test",
  subagent_type: "general-purpose",
  prompt: "Run /boundary-test all — detect → generate → run. Try up to three autonomous fixes for failures."
)
```

### 2-3: Phase boundary

`pipeline-state transition testing` + `checkpoint save`. Recommend `/compact` if context is bloated.

---

## Phase 3: Test

Run final spec convergence and final robustness review **in parallel** (single message, two Agent calls):

```
Agent(
  description: "Phase 3: Spec convergence",
  subagent_type: "general-purpose",
  prompt: "Run /spec-fix all --loop 3. Iterate until the spec/impl diff hits zero or the cap. Report remaining items as escalation candidates."
)

Agent(
  description: "Phase 3: Robustness final review",
  subagent_type: "general-purpose",
  prompt: "Run /robust-review all. Apply /robust-fix for any Critical / High items missed in Phase 2. Report verification-gate results after the fixes."
)
```

After both agents return, surface Tier 1 items if any. Then `pipeline-state transition reporting`.

---

## Phase 4: Report

```bash
git diff --stat
```

```
╔══════════════════════════════════════════════════╗
║  Pipeline report                                  ║
╚══════════════════════════════════════════════════╝

■ Change summary       (file count, +/- lines)
■ Verification gate    (aggregated across phases)
■ Review findings      (Phase 2 + Phase 3 aggregate)
■ Resolution           (auto-fix vs escalation)
■ Auto-fix log         (Tier 2)
■ Escalation history
■ Residual risk        (Medium / Low remainder)
■ Recommended actions  (manual confirmations)
```

Aggregation sources: `PIPELINE-STATE.md` and per-phase agent return values.

`pipeline-state` confirms the Phase as `reporting`.

---

## Escalation policy

| Timing | Behavior |
|--------|----------|
| Phase 0 | Resolve interactively |
| Phases 1–3 | Accumulate per phase (or per component within Phase 2); present batched at the phase boundary |

**Important:** A pending escalation does not block work that is independent of it.

---

## Context management

| Phase boundary | Action |
|----------------|--------|
| Phase 0 → 1 | — |
| Phase 1 → 2 | checkpoint save |
| Phase 2 between components | checkpoint save, `/compact` when bloated |
| Phase 2 → 3 | checkpoint save, `/compact` recommended |
| Phase 3 → 4 | — |

Why: delegating to sub-agents keeps phase detail out of the orchestrator's context — the orchestrator only sees summaries.

---

## Suspend and resume

### Suspend
On Ctrl+C or session end:
1. Record the latest agent return values via `pipeline-state update`.
2. Run `checkpoint save`.

### Resume
`/dev-pipeline resume` (or `/dev-pipeline` with no args when `PIPELINE-STATE.md` exists):

```
Pipeline "<task-name>" detected.
Current: Phase 2 (implementation) — backend done, frontend pending
→ Continue? [y / restart / abort]
```

`y` resumes from the matching phase logic.

---

## Constraints

- This skill is **orchestration only**. It carries no per-phase logic. Why: ARCHITECTURE.md §3.3 — embedded logic prevents sub-skill updates from propagating.
- Each phase delegates to its sub-skill (`design-phase`, `impl-orchestrator`, `boundary-test`, `spec-fix`, `robust-review`).
- Edit this file only when adding or reordering phases. Sub-skill behavior changes flow through automatically.
- Sub-skill model selection follows their own frontmatter; the orchestrator itself is opus.
- Phase 0 user approval is mandatory. Why: it is the only safety gate against runaway autonomous work.
