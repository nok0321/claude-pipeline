# Stage 3 subagent calls

Detail for SKILL.md Stage 3-6 (Subagent-backed judgement).
Two subagents may be invoked from Stage 3 to absorb technical
judgement before Tier 1 escalation.

---

## technical-arbiter (Diverged conformance findings)

Use for naming / type / constant / terminology / api_contract drift in
the Diverged class — when the heuristic table in
[conformance-fix.md](conformance-fix.md) cannot decide.

### Input

```json
{
  "drift_type": "constant" | "type_name" | "field_name" | "terminology" | "api_contract",
  "candidates": [
    {"value": "<candidate value>", "evidence_locations": ["path:line", "..."]}
  ],
  "context_files": ["<path>", "..."]
}
```

`context_files` is optional — additional spec/code paths the caller
already knows are relevant.

### Output

The arbiter returns a JSON block with one of two shapes. See
`agents/technical-arbiter.md` for the full output contract.

| Shape                                   | Action                                                |
|-----------------------------------------|-------------------------------------------------------|
| `decision` with confidence high/medium  | Apply that value via the per-finding action table     |
| `deferred_to_user: true` + question     | Surface the question as a Tier 1 escalation           |

### Decision log

Append one JSON object per line to `evals/arbiter-decisions.jsonl`:

```json
{"ts": "<ISO 8601>", "skill": "impl-orchestrator", "drift_type": "...", "candidates": [...], "result": {...}}
```

---

## regression-judge (Ambiguous test failure attribution)

Use during Stage 3 per-edit verification when a gate failure cannot be
clearly attributed to the current patch by file overlap alone — typically
when the failing test exercises code paths unrelated to the patched file
but the failure first surfaced after the patch landed.

### Input

```json
{
  "failing_tests": ["<test name or path::name>", "..."],
  "patch_diff": "<unified diff of the just-applied edit>",
  "patch_files": ["<path>", "..."]
}
```

### Output

```json
{
  "attribution": "fix_caused" | "pre_existing" | "uncertain",
  "confidence": "high" | "medium" | "low",
  "reasoning": "<one paragraph: which signals fired>"
}
```

| `attribution`  | Action                                                                  |
|----------------|-------------------------------------------------------------------------|
| `fix_caused`   | Revert via `git checkout HEAD -- <file>`, skip with report entry        |
| `pre_existing` | Keep the patch; report the pre-existing failure separately              |
| `uncertain`    | Escalate as Tier 1 with the judge's reasoning                           |

### When to skip the judge

Skip the call when attribution is already obvious:

- Patched file is directly imported / referenced by the failing test → `fix_caused`
- Failing test exists in `git log` failing state before the patch → `pre_existing`

The judge is for the residual ambiguous cases only.
