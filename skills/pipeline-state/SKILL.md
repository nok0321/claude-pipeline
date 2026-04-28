---
name: pipeline-state
description: Use this skill whenever the user wants to read, initialize, update, or transition phases in `PIPELINE-STATE.md` — the structured cross-session state file used by `dev-pipeline`. Trigger phrases include "init pipeline", "what phase are we in", "advance to implementation", "move pipeline to testing", "log this finding to the escalation queue", "update the impl status table", or any reference to PIPELINE-STATE.md by name. Trigger even when the user does not say "pipeline-state" — anything about phase transitions, escalation queue updates, or the structured table of components belongs here. Skip free-form session hand-off (use `checkpoint` for that).
argument-hint: "[init <task-name>|update <section> <content>|read|transition <next-phase>]"
allowed-tools: Read, Write, Bash, Glob
---

# Pipeline state manager

Manage `PIPELINE-STATE.md` so phase transitions, escalation queues, and component status survive across sessions inside a single pipeline run.

---

## Commands

### /pipeline-state init \<task-name\>

Create a new `PIPELINE-STATE.md` at the project root:

```markdown
# Pipeline: <task-name>
Phase: planning
Updated: <ISO 8601>

## Plan summary
(empty — fill in during planning)

## Design artifacts
(empty — fill in during design)

## Implementation status
| Component | Impl | Verification gate | Review |
|-----------|------|-------------------|--------|
(empty — fill in during implementation)

## Escalation queue
| # | Phase | Class | Content | Status |
|---|-------|-------|---------|--------|
(none)

## Hand-off to next phase
(empty)
```

If `PIPELINE-STATE.md` already exists, do not overwrite — confirm with the user first.

---

### /pipeline-state update \<section\> \<content\>

Update the named section and refresh the `Updated:` timestamp.

Updatable sections:

- `plan` — fill in or revise the plan summary
- `design` — append or check off design artifacts
- `impl` — add or update a row of the implementation status table
- `escalation` — push an item onto the queue or update its status
- `handoff` — write the hand-off note for the next phase

Implementation row example:

```
/pipeline-state update impl "<component> | done | build:pass type:pass test:pass | security:clean robustness:clean spec:clean"
```

Escalation push example:

```
/pipeline-state update escalation "add | design | must-escalate | <design judgement needed>"
```

Escalation resolve example:

```
/pipeline-state update escalation "resolve #1 | user approved, proceed with <decision>"
```

---

### /pipeline-state read

Read `PIPELINE-STATE.md` and print:

```
Pipeline: <task-name>
Phase: <current-phase>
Updated: <timestamp>

Design artifacts: <done>/<total>
Implementation: <done components>/<total>
Escalation: <pending> pending, <resolved> resolved, <dismissed> dismissed

Next-phase hand-off:
<short summary of the hand-off note>
```

If the file does not exist, report "pipeline not initialized — run `/pipeline-state init <task-name>`".

---

### /pipeline-state transition \<next-phase\>

Run this sequence:

1. **Completion check.** Warn (do not block) on pending escalation items or unfinished components.
2. **Update the Phase field.** Allowed forward transitions: `planning → design → implementation → testing → reporting`. Reject backward transitions to prevent silent regressions.
3. **Auto-generate the hand-off note** — include this phase's artifacts, unresolved items, and warnings.
4. **Run a checkpoint save** equivalent so `CHECKPOINT.md` mirrors the new phase.
5. **Refresh the `Updated:` timestamp.**

If context usage is high after transition, recommend `/compact` or `/clear`.

---

## Relationship with checkpoint

| | PIPELINE-STATE.md | CHECKPOINT.md |
|---|---|---|
| Scope | Whole pipeline (multi-session) | Single session |
| Content | Phase, artifacts, escalations | Task progress, git state, hand-off |
| Use | Structured cross-phase hand-off | General session hand-off |
| Owner | pipeline-state skill | checkpoint skill |

Both files coexist. `transition` updates both.

---

## Constraints

- Exactly one `PIPELINE-STATE.md` lives at the project root. Concurrent pipelines are not supported.
- The file is committed to git (do not add it to `.gitignore`).
- Manual edits are fine, but preserve the section headings and table format.
