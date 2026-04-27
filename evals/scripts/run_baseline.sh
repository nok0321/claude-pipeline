#!/usr/bin/env bash
# Run trigger-rate eval for all 15 custom skills and save results.
#
# Usage:
#   bash evals/scripts/run_baseline.sh [output-dir]
#
# Environment overrides:
#   SKILL_CREATOR_DIR  Path to skill-creator (default: ~/.claude/plugins/.../skill-creator)
#   MODEL              Model id (default: claude-opus-4-7)
#   WORKERS            Parallel workers per skill (default: 10)
#   TIMEOUT            Per-query timeout in seconds (default: 30)
#   RUNS               Runs per query for variance smoothing (default: 3)
#   ONLY_SKILLS        Space-separated subset to run (default: all)
#
# Default output: evals/results/baseline/<skill>.json (one per skill)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SKILL_CREATOR="${SKILL_CREATOR_DIR:-$HOME/.claude/plugins/marketplaces/claude-plugins-official/plugins/skill-creator/skills/skill-creator}"
RUN_EVAL_REL="scripts.run_eval"
QUERIES_DIR="$REPO_ROOT/evals/queries"
RESULTS_DIR="${1:-$REPO_ROOT/evals/results/baseline}"
MODEL="${MODEL:-claude-opus-4-7}"
WORKERS="${WORKERS:-10}"
TIMEOUT="${TIMEOUT:-30}"
RUNS="${RUNS:-3}"

if [ ! -f "$SKILL_CREATOR/scripts/run_eval.py" ]; then
  echo "ERROR: run_eval.py not found at $SKILL_CREATOR/scripts/run_eval.py" >&2
  echo "Set SKILL_CREATOR_DIR env var. Current: $SKILL_CREATOR" >&2
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "ERROR: 'claude' CLI not found in PATH." >&2
  exit 1
fi

mkdir -p "$RESULTS_DIR"

ALL_SKILLS=(
  boundary-test
  checkpoint
  code-review
  design-phase
  dev-pipeline
  escalation
  fix-with-verify
  impl-orchestrator
  pipeline-state
  quick-test
  robust-fix
  robust-review
  spec-audit
  spec-check
  spec-fix
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

  if PYTHONPATH="$SKILL_CREATOR" python -m "$RUN_EVAL_REL" \
       --eval-set "$query_file" \
       --skill-path "$REPO_ROOT/skills/$skill" \
       --num-workers "$WORKERS" \
       --timeout "$TIMEOUT" \
       --runs-per-query "$RUNS" \
       --model "$MODEL" \
       --verbose \
       > "$result_file" 2> "$log_file"; then
    echo "  -> $result_file" >&2
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
