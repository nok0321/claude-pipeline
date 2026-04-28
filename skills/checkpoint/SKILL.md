---
name: checkpoint
description: Use this skill whenever the user is about to break a long-running task across sessions — before `/clear` or `/compact`, at the end of a working day, when picking up unfinished work the next morning, or any time the user mentions saving or restoring state with phrases like "save my place", "where was I", "pick up tomorrow", "checkpoint this". The skill writes or reads `CHECKPOINT.md` at the project root, capturing task progress, git state, decisions, and a hand-off note for the next session. Trigger even if the user does not say the word "checkpoint" — phrases like "let me come back to this later" or "I want to step away" are sufficient.
argument-hint: "[save|restore|status]"
allowed-tools: Read, Write, Bash, Glob
---

# Session continuation manager

Maintain `CHECKPOINT.md` at the project root so a long task survives across `/clear`, `/compact`, or a fresh session the next day. Free-form, single-task scope. For structured pipeline state across multiple components, defer to `pipeline-state`.

---

## /checkpoint save

1. Write or update `CHECKPOINT.md` at the project root with the following structure:

```markdown
# Checkpoint: <task name>
Updated: <ISO 8601 timestamp>
Session: ${CLAUDE_SESSION_ID}

## Goal
<final goal of the task>

## Done
- [x] <completed item> (commit: abc1234)

## In progress
- [ ] <current item>
  - Status: <concrete progress>
  - Blocker: <if any>

## Not started
- [ ] <remaining item>

## Key decisions
- <decision>: <reason>

## Environment
- Branch: <current branch>
- Uncommitted changes: <yes / no>
- Build status: <pass / failing — describe>

## Hand-off to next session
<concrete next instructions>
```

2. If there are uncommitted changes, propose a WIP commit so the checkpoint matches a recoverable git state.
3. Append the output of `git log --oneline -5` so the next session can locate the working point in history.

---

## /checkpoint restore

1. Verify `CHECKPOINT.md` exists. If not, report "no prior checkpoint found" and stop.
2. Read its contents and inject them into context.
3. Cross-check against `git log` — flag any drift (e.g., the commit referenced under "Done" no longer exists on this branch).
4. Run the project's compile / type-check command to confirm the build still matches what the checkpoint claims.
5. Resume from the "Hand-off to next session" instructions.

---

## /checkpoint status

1. Print the `Updated:` timestamp of `CHECKPOINT.md`.
2. Diff the recorded git state against the current `git status` and report drift.
3. Summarize counts of items under "Done", "In progress", and "Not started".
