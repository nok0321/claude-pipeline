---
name: escalation
description: Use this skill whenever the user wants to classify a finding into one of the three escalation tiers — Tier 1 (must escalate to user), Tier 2 (auto-fix and report), Tier 3 (auto-fix silently) — to decide whether autonomous action is allowed. Trigger phrases include "should I escalate this", "is this Tier 1", "classify this finding", "do I need to ask the user about this", "auto-fix or escalate?", or any review-loop step deciding what to do with a Critical/High/Medium/Low item. Trigger even when the user does not say "escalation" — phrases like "should we just fix it?" or "does this need approval?" qualify. The skill defines the tier criteria, applies CLAUDE.md `## Escalation Overrides`, and outputs a recommended action.
argument-hint: "[classify <finding-description>]"
allowed-tools: Read, Grep, Glob
---

# Escalation framework

Classify findings discovered during design, implementation, testing, or review into three tiers and prescribe the response. Referenced from every layer of the pipeline.

## Usage

```
/escalation classify <finding description>
```

Output: tier, matched criterion, recommended action.

---

## Tier criteria

### Tier 1: must escalate (no autonomous action)

When any of the following holds, **stop and confirm with the user**. Do not auto-fix.

| Criterion | Why |
|-----------|-----|
| Selecting or changing an external API or DB schema | Domain knowledge and business requirements drive the choice |
| Auth / authz flow design decisions | Direct security-policy impact |
| Breaking changes to a public interface | Downstream consumers are affected |
| New requirements not covered by the design docs | Out-of-scope decisions belong to the user |
| Three consecutive failed attempts at the same fix | The approach itself needs review |
| Verification gate still fails after max retries | Root cause is likely outside the skill's scope |
| License or legal-constraint changes | Legal review is required |
| Design changes that materially shift performance characteristics | Trade-off belongs to the user |

### Tier 2: auto-fix + post-report

When any of the following holds, **fix autonomously and report after**.

| Criterion | Example |
|-----------|---------|
| Critical / High items with a known fix pattern | `unwrap()` → `?`, SQL string interpolation → `.bind()` |
| Minor design-doc inconsistency | Type-name drift, argument-order mismatch, field-name unification |
| Test-discovered logic bug | Failing test indicates a real defect to fix |
| Edge-case test additions | Boundary, empty input, NaN coverage |
| Missing item flagged by `spec-check` | Specified in design but not implemented |
| Constraint violations | Architecture-rule breach, data-format ordering, etc. |

Report format:

```
[auto-fix] <classification> | <file:line>
  Change: <what was modified>
  Reason: <why autonomous action is appropriate>
  Verification: <gate result, e.g. tests pass>
```

### Tier 3: auto-fix (no report needed)

When any of the following holds, **fix silently**.

| Criterion |
|-----------|
| Medium / Low / Info-level items |
| Formatting fixes, import organization |
| Doc comments add / edit |
| Minor refactor of existing tests with no behavior change |
| Lint / clippy warning resolution |

---

## Classification procedure

1. Read the finding.
2. Match against Tier 1 criteria. Any match → **Tier 1**.
3. Match against Tier 3 criteria. Any match → **Tier 3**.
4. Otherwise → **Tier 2**.
5. When in doubt, default to **Tier 1** (fail safe).

---

## Project-specific overrides

When CLAUDE.md contains `## Escalation Overrides`, apply those rules first.

```markdown
## Escalation Overrides
- promote: any DB-related change must escalate, even at High
- demote: documentation-only changes are always Tier 3
```

Order: read overrides → apply matching ones → fall back to default criteria for the rest.

---

## Output format

```
╔══════════════════════════════════════╗
║  Escalation classification           ║
╚══════════════════════════════════════╝

Finding: <input summary>

Class: Tier <1|2|3> — <must escalate | auto-fix + report | auto-fix silent>

Matched criterion: <which rule fired>

Action:
  Tier 1 → ask user: <concrete question>
  Tier 2 → apply fix and report: <what to change>
  Tier 3 → apply fix: <what to change>

Override applied: <name | none>
```

---

## Escalation queue

During a pipeline run, Tier 1 findings accumulate in `PIPELINE-STATE.md` under the escalation queue.

- Push new items as each stage completes.
- Present the pending queue to the user at phase boundaries (batched, not piecemeal).

After the user responds:

- Apply the resulting fix and mark the queue item `resolved`.
- If the user says "no action needed", mark the item `dismissed`.
