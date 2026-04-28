#!/usr/bin/env python3
"""Compare two aggregated eval phases (e.g. BASELINE vs PHASE1).

Reports per-skill trigger_rate / pass_rate / should_not_trigger_rate
deltas plus the summary delta. Writes a markdown table to stdout.

Usage:
    python evals/scripts/compare.py evals/BASELINE.json evals/PHASE1.json
    python evals/scripts/compare.py evals/BASELINE.json evals/PHASE1.json --md > evals/PHASE1-DIFF.md
"""

import argparse
import json
import sys
from pathlib import Path


def fmt_delta(d: float) -> str:
    if d >= 0.20:
        flag = "↑↑"
    elif d > 0.05:
        flag = "↑"
    elif d > 0:
        flag = "+"
    elif d == 0:
        flag = "="
    elif d > -0.05:
        flag = "-"
    elif d > -0.20:
        flag = "↓"
    else:
        flag = "↓↓"
    sign = "+" if d > 0 else ("" if d == 0 else "")
    return f"{sign}{d:+.3f} {flag}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("baseline", help="Earlier phase JSON (e.g. evals/BASELINE.json)")
    ap.add_argument("phase", help="Later phase JSON (e.g. evals/PHASE1.json)")
    ap.add_argument("--md", action="store_true", help="Emit markdown")
    args = ap.parse_args()

    b = json.loads(Path(args.baseline).read_text(encoding="utf-8"))
    p = json.loads(Path(args.phase).read_text(encoding="utf-8"))

    skills = sorted(set(b["skills"]) | set(p["skills"]))

    rows = []
    regressed = []
    snt_drops = []
    for sk in skills:
        bs = b["skills"].get(sk, {})
        ps = p["skills"].get(sk, {})
        bt = bs.get("trigger_rate_overall", 0.0)
        pt = ps.get("trigger_rate_overall", 0.0)
        bst = bs.get("should_trigger_rate", 0.0)
        pst = ps.get("should_trigger_rate", 0.0)
        bsnt = bs.get("should_not_trigger_rate", 1.0)
        psnt = ps.get("should_not_trigger_rate", 1.0)
        bp = (bs.get("passed", 0) / bs.get("total", 1)) if bs.get("total") else 0.0
        pp = (ps.get("passed", 0) / ps.get("total", 1)) if ps.get("total") else 0.0
        rows.append({
            "skill": sk,
            "b_trigger": bt, "p_trigger": pt, "d_trigger": pt - bt,
            "b_st": bst, "p_st": pst, "d_st": pst - bst,
            "b_snt": bsnt, "p_snt": psnt, "d_snt": psnt - bsnt,
            "b_pass": bp, "p_pass": pp, "d_pass": pp - bp,
        })
        if pt < bt - 0.001:
            regressed.append((sk, bt, pt, pt - bt))
        if psnt < 0.95:
            snt_drops.append((sk, psnt))

    # text/markdown
    if args.md:
        print(f"# {b.get('phase','baseline')} vs {p.get('phase','phase1')} diff\n")
        print(f"| skill | base trig | new trig | Δ trig | base ST | new ST | Δ ST | new SNT | base pass | new pass | Δ pass |")
        print(f"|---|---:|---:|---|---:|---:|---|---:|---:|---:|---|")
        for r in rows:
            print(f"| {r['skill']} | {r['b_trigger']:.3f} | {r['p_trigger']:.3f} | {fmt_delta(r['d_trigger'])} | "
                  f"{r['b_st']:.3f} | {r['p_st']:.3f} | {fmt_delta(r['d_st'])} | "
                  f"{r['p_snt']:.3f} | {r['b_pass']:.3f} | {r['p_pass']:.3f} | {fmt_delta(r['d_pass'])} |")
    else:
        header = f"{'skill':25} {'b_trig':>8} {'p_trig':>8} {'Δtrig':>10} {'b_ST':>7} {'p_ST':>7} {'p_SNT':>7} {'Δpass':>10}"
        print(header)
        print("-" * len(header))
        for r in rows:
            print(f"{r['skill']:25} {r['b_trigger']:>8.3f} {r['p_trigger']:>8.3f} "
                  f"{r['d_trigger']:>+10.3f} {r['b_st']:>7.3f} {r['p_st']:>7.3f} "
                  f"{r['p_snt']:>7.3f} {r['d_pass']:>+10.3f}")

    bs = b["summary"]
    ps = p["summary"]
    bt = bs["avg_trigger_rate"]
    pt = ps["avg_trigger_rate"]
    bp = bs["avg_pass_rate"]
    pp = ps["avg_pass_rate"]

    if args.md:
        print()
        print(f"## Summary\n")
        print(f"- avg_trigger_rate: {bt:.3f} → {pt:.3f} ({fmt_delta(pt-bt)})")
        print(f"- avg_pass_rate: {bp:.3f} → {pp:.3f} ({fmt_delta(pp-bp)})")
        print(f"- skills above pass threshold (0.7): "
              f"{bs.get('skills_above_pass_threshold_0.7', '?')} → "
              f"{ps.get('skills_above_pass_threshold_0.7', '?')}")
        print()
        if regressed:
            print(f"## Regressions (PHASE < BASELINE on trigger_rate)\n")
            for sk, b_, p_, d in regressed:
                print(f"- **{sk}**: {b_:.3f} → {p_:.3f} ({d:+.3f})")
            print()
        else:
            print("## Regressions\n\nNone.\n")
        if snt_drops:
            print(f"## should_not_trigger_rate < 0.95 (over-trigger risk)\n")
            for sk, snt in snt_drops:
                print(f"- **{sk}**: {snt:.3f}")
        else:
            print("## should_not_trigger_rate < 0.95\n\nNone — near-miss precision intact.\n")
    else:
        print()
        print(f"AVERAGE trigger : {bt:.3f} -> {pt:.3f} ({pt-bt:+.3f})")
        print(f"AVERAGE pass    : {bp:.3f} -> {pp:.3f} ({pp-bp:+.3f})")
        print()
        if regressed:
            print(f"Regressions ({len(regressed)}):")
            for sk, b_, p_, d in regressed:
                print(f"  - {sk}: {b_:.3f} -> {p_:.3f} ({d:+.3f})")
        else:
            print("No regressions.")
        if snt_drops:
            print(f"\nshould_not_trigger_rate < 0.95 ({len(snt_drops)}):")
            for sk, snt in snt_drops:
                print(f"  - {sk}: {snt:.3f}")
        else:
            print("\nshould_not_trigger_rate intact (all >= 0.95).")


if __name__ == "__main__":
    main()
