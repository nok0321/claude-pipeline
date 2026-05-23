#!/usr/bin/env bash
# Run trigger-rate eval for the 7 surviving custom skills and save results.
#
# Skill set is the post-Phase-6-Sub-V lineup (7 skills). Phase 0 / Phase 1
# ran 15 skills; Phase 2 dropped 7 (dev-pipeline, escalation,
# fix-with-verify, pipeline-state, quick-test, robust-fix, spec-check,
# spec-fix) and added safe-fix. Phase 6 Sub-V Option A retired safe-fix
# itself — its remediation logic is now inlined into impl-orchestrator
# Stage 3 (see skills/impl-orchestrator/references/conformance-fix.md
# and robust-fix.md). Baseline trigger rates for all dropped skills
# remain in evals/BASELINE.json for historical reference.
#
# Uses evals/scripts/run_eval_compat.py (self-contained, threading-based)
# instead of skill-creator's scripts/run_eval.py, which fails on Windows
# due to select.select() not supporting file handles (WinError 10038).
#
# Usage:
#   bash evals/scripts/run_baseline.sh [output-dir]
#
# Environment overrides:
#   MODEL              Model id (default: claude-opus-4-7)
#   WORKERS            Parallel workers per skill (default: 10, drop to
#                      3 if rate-limit artifacts (0.0 trigger) appear)
#   TIMEOUT            Per-query timeout in seconds (default: 30)
#   RUNS               Runs per query for variance smoothing (default: 3)
#   ONLY_SKILLS        Space-separated subset to run (default: all)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

RUN_EVAL_SCRIPT="$REPO_ROOT/evals/scripts/run_eval_compat.py"
QUERIES_DIR="$REPO_ROOT/evals/queries"
RESULTS_DIR="${1:-$REPO_ROOT/evals/results/baseline}"
MODEL="${MODEL:-claude-opus-4-7}"
WORKERS="${WORKERS:-10}"
TIMEOUT="${TIMEOUT:-30}"
RUNS="${RUNS:-3}"

if [ ! -f "$RUN_EVAL_SCRIPT" ]; then
  echo "ERROR: run_eval_compat.py not found at $RUN_EVAL_SCRIPT" >&2
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "ERROR: 'claude' CLI not found in PATH." >&2
  exit 1
fi

if ! command -v python >/dev/null 2>&1; then
  echo "ERROR: 'python' not found in PATH." >&2
  exit 1
fi

mkdir -p "$RESULTS_DIR"

ALL_SKILLS=(
  boundary-test
  checkpoint
  code-review
  design-phase
  impl-orchestrator
  robust-review
  spec-audit
)

if [ -n "${ONLY_SKILLS:-}" ]; then
  read -ra SKILLS <<< "$ONLY_SKILLS"
else
  SKILLS=("${ALL_SKILLS[@]}")
fi

total=${#SKILLS[@]}
i=0
failures=0
start_ts=$(date +%s)

cd "$REPO_ROOT"

for skill in "${SKILLS[@]}"; do
  i=$((i + 1))
  query_file="$QUERIES_DIR/$skill.json"
  result_file="$RESULTS_DIR/$skill.json"
  log_file="$RESULTS_DIR/$skill.stderr.log"

  if [ ! -f "$query_file" ]; then
    echo "[$i/$total] SKIP $skill (no query file at $query_file)" >&2
    continue
  fi

  echo "[$i/$total] Running $skill ($MODEL, runs=$RUNS, workers=$WORKERS, timeout=${TIMEOUT}s) ..." >&2

  if python "$RUN_EVAL_SCRIPT" \
       --eval-set "$query_file" \
       --skill-path "$REPO_ROOT/skills/$skill" \
       --num-workers "$WORKERS" \
       --timeout "$TIMEOUT" \
       --runs-per-query "$RUNS" \
       --model "$MODEL" \
       --verbose \
       > "$result_file" 2> "$log_file"; then
    summary_line=$(tail -n 1 "$log_file" 2>/dev/null | grep -E "Results: " || tail -n 30 "$log_file" 2>/dev/null | grep -E "Results: " | head -n 1 || echo "")
    if [ -z "$summary_line" ]; then
      summary_line=$(grep -E "Results: " "$log_file" | head -n 1 || echo "")
    fi
    echo "  -> $result_file ${summary_line:+($summary_line)}" >&2
  else
    echo "  WARN: $skill eval failed (see $log_file)" >&2
    failures=$((failures + 1))
  fi
done

end_ts=$(date +%s)
elapsed=$((end_ts - start_ts))
echo "" >&2
echo "Done in ${elapsed}s. Results in $RESULTS_DIR" >&2
echo "Failures: $failures / $total" >&2
echo "" >&2
echo "Next: python evals/scripts/aggregate.py $RESULTS_DIR > evals/BASELINE.json" >&2
