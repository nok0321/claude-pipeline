# evals/scripts/

Self-contained eval framework for measuring trigger rates of the 8
surviving custom skills (post Phase 2 drop). Phase 0 / Phase 1 measured
the original 15-skill lineup; the 7 retired skills (dev-pipeline,
escalation, fix-with-verify, pipeline-state, quick-test, robust-fix,
spec-check, spec-fix) are no longer in `skills/` and are excluded from
re-runs. No dependency on the upstream skill-creator framework — see
[Design rationale](#design-rationale) below for why.

## Files

| File | Purpose |
|------|---------|
| `run_eval_compat.py` | Per-skill trigger eval. Spawns `claude -p` subprocesses, parses streaming JSON for `Skill` tool_use events, writes per-query results in the same schema as skill-creator's `run_eval.py` |
| `run_baseline.sh` | Iterates 10 skills × ~20 queries × N runs through `run_eval_compat.py`, saves per-skill JSON to `evals/results/<phase>/` |
| `aggregate.py` | Reads per-skill JSONs and produces a single summary (`BASELINE.json`, `PHASE1.json`, `POST.json`) with metrics broken down by tag |

## Prerequisites

1. `claude` CLI on `PATH`
2. `python` 3.10+

That's it — `run_eval_compat.py` is fully self-contained.

## Quick start (Phase 0 baseline)

```bash
# From the repo root (claude-pipeline/)
bash evals/scripts/run_baseline.sh
# -> writes evals/results/baseline/<skill>.json (one per skill)

python evals/scripts/aggregate.py evals/results/baseline > evals/BASELINE.json
```

## Phase 1 / Phase 5 reuse

```bash
# After Phase 1 description rewrites
bash evals/scripts/run_baseline.sh evals/results/phase1
python evals/scripts/aggregate.py evals/results/phase1 --phase phase1 > evals/PHASE1.json

# After Phase 5
bash evals/scripts/run_baseline.sh evals/results/post
python evals/scripts/aggregate.py evals/results/post --phase post > evals/POST.json
```

> **Important:** Do not edit any `skills/*/SKILL.md` while a baseline run
> is in flight. `run_eval_compat.py` evaluates the **real, installed
> skill** (see Design rationale §2) so concurrent edits contaminate the
> measurement.

## Subset runs

Run a specific subset of skills (useful when iterating on description
changes, or when re-measuring after a rate-limited run):

```bash
ONLY_SKILLS="spec-audit code-review" bash evals/scripts/run_baseline.sh

# Re-measure with reduced parallelism to avoid rate limits
ONLY_SKILLS="robust-fix robust-review spec-audit spec-check spec-fix" \
  WORKERS=3 \
  bash evals/scripts/run_baseline.sh evals/results/baseline-resub
```

Other env overrides:

| Var | Default | Purpose |
|-----|---------|---------|
| `MODEL` | `claude-opus-4-8` | Model for `claude -p` subprocess |
| `WORKERS` | `10` | Parallel workers per skill (within `run_eval_compat.py`). Drop to `3` if you hit rate limits |
| `TIMEOUT` | `30` | Per-query timeout (seconds) |
| `RUNS` | `3` | Runs per query for variance smoothing |

## Cost / time estimate

- 10 skills × ~20 queries × 3 runs ≈ **600 `claude -p` invocations**
- With `WORKERS=10`, expect 20–40 minutes wall clock
- With `WORKERS=3`, expect 60–90 minutes but no rate-limit hits
  (PHASE1 saw 5/15 skills hit 0.0 with WORKERS=10 — silent rate-limit
  artifact, see Troubleshooting)
- Cost: depends on prompt-cache hit rate; first run is most expensive

## Output schema (BASELINE.json)

```json
{
  "phase": "baseline",
  "model": "claude-opus-4-7",
  "timestamp": "2026-04-28T...",
  "skills": {
    "spec-audit": {
      "trigger_rate_overall": 0.85,
      "should_trigger_rate": 0.92,
      "should_not_trigger_rate": 0.78,
      "passed": 17,
      "total": 20,
      "by_tag": {
        "explicit": 1.000,
        "implicit": 0.833,
        "casual": 0.750,
        "near-miss-spec-check": 0.500,
        "near-miss-design-phase": 1.000,
        "generic": 1.000
      }
    }
  },
  "summary": {
    "total_skills": 15,
    "avg_trigger_rate": 0.62,
    "avg_pass_rate": 0.71,
    "skills_above_pass_threshold_0.7": 9
  }
}
```

## Design rationale

`run_eval_compat.py` is a port of skill-creator's `scripts/run_eval.py`,
diverging in three ways. Both divergences came from real failures during
Phase 0:

### 1. Threading-based stdout reader (Windows compatibility)

The upstream `run_eval.py` reads from the `claude -p` subprocess pipe with
`select.select()`. On Windows this raises `WinError 10038` because the
Win32 `select` API only accepts socket handles, not file handles. We
replace it with a reader thread that feeds a `queue.Queue`, which works
identically on Windows / Linux / macOS.

### 2. No "probe skill" injection

The upstream `run_eval.py` creates a unique probe skill at
`.claude/skills/<unique-id>/SKILL.md` so each eval has its own isolated
description and trigger event. In practice **claude-opus-4-7 (claude-code
2.1.119) flags uniquely-named skills as prompt-injection bait and refuses
to invoke them**, falling back to whichever real skill matches the query.
The eval becomes meaningless — the probe is never selected.

`run_eval_compat.py` instead evaluates the **real, installed skill**
directly by detecting whether `claude -p` emits a `tool_use` event with
`name="Skill"` and `input.skill` matching the target skill name.

Trade-off: we cannot evaluate hypothetical description rewrites without
temporarily editing the real `SKILL.md`. The Phase 1 → Phase 5 workflow
is therefore: edit `SKILL.md` → run baseline → analyze → iterate.

### 3. Output JSON schema preserved

The result JSON shape (`skill_name`, `description`, `results[]`,
`summary{}`) matches `run_eval.py` exactly so `aggregate.py` consumes
results uniformly regardless of which runner produced them.

## Troubleshooting

- **`run_eval_compat.py` not found**: Ensure you are running from the repo
  root and that `evals/scripts/run_eval_compat.py` is committed.
- **All evals timing out**: Increase `TIMEOUT=60` (some skills may be
  slower to surface as a `Skill` tool_use). Check the per-skill
  `*.stderr.log` files in the results directory.
- **Some skills show `trigger_rate_overall: 0.0` across the board**:
  Likely a rate limit. Re-run that subset with `WORKERS=3`. The `claude
  -p` subprocesses degrade silently to "no response" when rate-limited,
  which `run_eval_compat.py` correctly records as no `Skill` invocation.
- **Trigger rate suspiciously high for `should_not_trigger`**: The
  description is over-pushy and the skill triggers on near-miss queries.
  Note the tag in `by_tag` — Phase 1 description rewrites should reduce
  it.
- **Permission prompt appears mid-run**: `run_eval_compat.py` uses
  `claude -p --permission-mode bypassPermissions` to suppress prompts.
  If you see one, your CLI version may differ — check `claude --help`.
