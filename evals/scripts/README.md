# evals/scripts/

Wrapper scripts that drive the skill-creator eval framework against the 15
custom skills in this repository.

## Files

| File | Purpose |
|------|---------|
| `run_baseline.sh` | Iterates 15 skills × 20 (or 10) queries × 3 runs through `run_eval.py`, saves per-skill JSON to `evals/results/<phase>/` |
| `aggregate.py` | Reads per-skill JSONs and produces a single summary (`BASELINE.json`, `PHASE1.json`, `POST.json`) with metrics broken down by tag |

## Prerequisites

1. `claude` CLI on `PATH`
2. `python` 3.10+
3. skill-creator framework at `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/skill-creator/skills/skill-creator/` (override with `SKILL_CREATOR_DIR=` env var)

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

## Subset runs

Run a specific subset of skills (useful when iterating on description changes):

```bash
ONLY_SKILLS="spec-audit code-review" bash evals/scripts/run_baseline.sh
```

Other env overrides:

| Var | Default | Purpose |
|-----|---------|---------|
| `MODEL` | `claude-opus-4-7` | Model for `claude -p` subprocess |
| `WORKERS` | `10` | Parallel workers per skill (within `run_eval.py`) |
| `TIMEOUT` | `30` | Per-query timeout (seconds) |
| `RUNS` | `3` | Runs per query for variance smoothing |

## Cost / time estimate

- 15 skills × ~17 queries (avg of 20+10) × 3 runs ≈ **765 `claude -p` invocations**
- With `WORKERS=10`, expect 30〜60 minutes wall clock
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

## Troubleshooting

- **"`run_eval.py` not found"**: Set `SKILL_CREATOR_DIR=...` to point at the directory containing `scripts/run_eval.py`. The default path assumes the official `claude-plugins-official` marketplace is installed
- **All evals timing out**: Increase `TIMEOUT=60` (some skills may be slower to surface as a `Skill` tool call). Check the per-skill `*.stderr.log` files
- **Some skills fail with import errors**: Confirm `PYTHONPATH` is being set correctly. The wrapper sets `PYTHONPATH=$SKILL_CREATOR_DIR` and uses `python -m scripts.run_eval` to allow the `from scripts.utils import parse_skill_md` import inside `run_eval.py` to resolve
- **Trigger rate suspiciously high for `should_not_trigger`**: This indicates the description is over-pushy and the skill triggers on near-miss queries. Note the tag in `by_tag` — Phase 1 description rewrites should reduce it
