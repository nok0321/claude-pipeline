#!/usr/bin/env bash
# Stop: タスク完了時の検証ゲート（変更言語を自動検出して対応する検証を実行）
set -euo pipefail

# Claude Code の Hook は最小 PATH で起動される場合がある
# scoop / cargo / ~/.local/bin 等のユーザー環境を PATH に追加
for d in "$HOME/scoop/shims" "$HOME/.cargo/bin" "$HOME/.local/bin" "/usr/local/bin"; do
  [ -d "$d" ] && [[ ":$PATH:" != *":$d:"* ]] && PATH="$d:$PATH"
done
export PATH

# 無限ループ防止フラグ
FLAG_FILE="/tmp/claude-stop-hook-active-${CLAUDE_SESSION_ID:-$$}"
if [ -f "$FLAG_FILE" ]; then
  rm -f "$FLAG_FILE"
  exit 0
fi
touch "$FLAG_FILE"

cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"

errors=""

# git で変更されたファイルを検出
changed_files=$(git diff --name-only HEAD 2>/dev/null || git diff --name-only 2>/dev/null || echo "")

has_rust=false
has_ts=false
has_python=false
has_go=false

for f in $changed_files; do
  case "$f" in
    *.rs) has_rust=true ;;
    *.ts|*.tsx|*.svelte|*.vue) has_ts=true ;;
    *.py) has_python=true ;;
    *.go) has_go=true ;;
  esac
done

# --- Rust ---
if $has_rust && [ -f "Cargo.toml" ]; then
  check_result=$(cargo clippy --workspace -- -D warnings 2>&1) || \
    errors="${errors}\n[Rust Clippy]\n$(echo "$check_result" | grep -E '^error|^warning|aborting' | head -20)"
fi

# --- TypeScript / Svelte / Vue ---
if $has_ts; then
  frontend_dir=""
  for candidate in frontend client app .; do
    if [ -f "$candidate/package.json" ]; then
      frontend_dir="$candidate"
      break
    fi
  done

  if [ -n "$frontend_dir" ]; then
    if (cd "$frontend_dir" && npx svelte-check --version &>/dev/null 2>&1); then
      check_result=$(cd "$frontend_dir" && npx svelte-check --tsconfig ./tsconfig.json 2>&1) || \
        errors="${errors}\n[Svelte/TypeScript]\n$(echo "$check_result" | tail -20)"
    elif (cd "$frontend_dir" && npx vue-tsc --version &>/dev/null 2>&1); then
      check_result=$(cd "$frontend_dir" && npx vue-tsc --noEmit 2>&1) || \
        errors="${errors}\n[Vue/TypeScript]\n$(echo "$check_result" | tail -20)"
    elif [ -f "$frontend_dir/tsconfig.json" ]; then
      check_result=$(cd "$frontend_dir" && npx tsc --noEmit 2>&1) || \
        errors="${errors}\n[TypeScript]\n$(echo "$check_result" | head -20)"
    fi
  fi
fi

# --- Python ---
if $has_python; then
  if command -v ruff &>/dev/null; then
    check_result=$(ruff check . 2>&1) || \
      errors="${errors}\n[Python ruff]\n$(echo "$check_result" | head -20)"
  fi
fi

# --- Go ---
if $has_go && [ -f "go.mod" ]; then
  check_result=$(go vet ./... 2>&1) || \
    errors="${errors}\n[Go vet]\n$(echo "$check_result" | head -20)"
fi

rm -f "$FLAG_FILE"

if [ -n "$errors" ]; then
  jq -Rn --arg msg "$(echo -e "$errors")" '{
    decision: "block",
    reason: ("Complete the following fixes before finishing:\n" + $msg)
  }'
fi

exit 0
