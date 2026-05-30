#!/usr/bin/env python3
"""Aggregate per-skill eval results into a single summary JSON.

Reads <skill>.json files (output of skill-creator's run_eval.py) from a
results directory and produces aggregated metrics:
- per-skill: trigger_rate_overall, should_trigger_rate,
  should_not_trigger_rate, passed, total, by_tag (rate per tag from query JSON)
- summary: avg_trigger_rate, avg_pass_rate, skills_above_threshold

Usage:
    python evals/scripts/aggregate.py evals/results/baseline > evals/BASELINE.json
    python evals/scripts/aggregate.py evals/results/post --phase post --model claude-opus-4-8
"""

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


def load_query_tags(queries_dir: Path, skill: str) -> dict[str, str]:
    """Load tag mapping (query text -> tag) for a skill."""
    qfile = queries_dir / f"{skill}.json"
    if not qfile.exists():
        return {}
    queries = json.loads(qfile.read_text(encoding="utf-8"))
    return {q["query"]: q.get("tag", "untagged") for q in queries}


def aggregate_skill(result_file: Path, queries_dir: Path) -> dict:
    """Compute metrics for one skill's run_eval output."""
    data = json.loads(result_file.read_text(encoding="utf-8"))
    skill = result_file.stem
    results = data.get("results", [])
    tags = load_query_tags(queries_dir, skill)

    should_trigger = [r for r in results if r["should_trigger"]]
    should_not_trigger = [r for r in results if not r["should_trigger"]]

    avg_st = (
        sum(r["trigger_rate"] for r in should_trigger) / len(should_trigger)
        if should_trigger else 0.0
    )
    avg_snt = (
        sum(r["trigger_rate"] for r in should_not_trigger) / len(should_not_trigger)
        if should_not_trigger else 0.0
    )

    by_tag: dict[str, list[float]] = {}
    for r in results:
        tag = tags.get(r["query"], "untagged")
        by_tag.setdefault(tag, []).append(r["trigger_rate"])
    by_tag_avg = {t: round(sum(rs) / len(rs), 3) for t, rs in by_tag.items()}

    passed = sum(1 for r in results if r["pass"])
    total = len(results)

    return {
        "trigger_rate_overall": round(
            sum(r["trigger_rate"] for r in results) / total if total else 0.0, 3
        ),
        "should_trigger_rate": round(avg_st, 3),
        "should_not_trigger_rate": round(1.0 - avg_snt, 3),
        "passed": passed,
        "total": total,
        "by_tag": by_tag_avg,
    }


def main():
    parser = argparse.ArgumentParser(description="Aggregate per-skill eval results.")
    parser.add_argument("results_dir", help="Directory with <skill>.json result files")
    parser.add_argument("--queries-dir", default=None,
                        help="Directory with query JSONs (default: ../../queries relative to results_dir)")
    parser.add_argument("--phase", default="baseline",
                        help="Phase label (baseline | phase1 | post)")
    parser.add_argument("--model", default="claude-opus-4-8",
                        help="Model used for the run")
    parser.add_argument("--threshold", type=float, default=0.7,
                        help="Pass-rate threshold for summary count")
    args = parser.parse_args()

    results_dir = Path(args.results_dir)
    if args.queries_dir:
        queries_dir = Path(args.queries_dir)
    else:
        queries_dir = results_dir.parent.parent / "queries"

    if not results_dir.exists():
        print(f"ERROR: results dir not found: {results_dir}", file=sys.stderr)
        sys.exit(1)

    skills_data: dict[str, dict] = {}
    for result_file in sorted(results_dir.glob("*.json")):
        try:
            skills_data[result_file.stem] = aggregate_skill(result_file, queries_dir)
        except Exception as e:
            print(f"WARN: failed to aggregate {result_file.name}: {e}", file=sys.stderr)

    pass_rates = [
        (s["passed"] / s["total"]) if s["total"] else 0.0
        for s in skills_data.values()
    ]
    avg_trigger = [s["trigger_rate_overall"] for s in skills_data.values()]
    above = sum(1 for r in pass_rates if r >= args.threshold)

    output = {
        "phase": args.phase,
        "model": args.model,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "skills": skills_data,
        "summary": {
            "total_skills": len(skills_data),
            "avg_trigger_rate": round(
                sum(avg_trigger) / len(avg_trigger) if avg_trigger else 0.0, 3
            ),
            "avg_pass_rate": round(
                sum(pass_rates) / len(pass_rates) if pass_rates else 0.0, 3
            ),
            f"skills_above_pass_threshold_{args.threshold}": above,
        },
    }

    print(json.dumps(output, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
