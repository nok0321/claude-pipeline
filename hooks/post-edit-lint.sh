#!/usr/bin/env bash
# PostToolUse(Write|Edit|MultiEdit): 言語自動検出 lint + コンパイルチェック
# Strategy: silent success / error-only output (context window 汚染防止)
set -euo pipefail

# Claude Code の Hook は最小 PATH で起動される場合がある
# scoop / cargo / ~/.local/bin 等のユーザー環境を PATH に追加
for d in "$HOME/scoop/shims" "$HOME/.cargo/bin" "$HOME/.local/bin" "/usr/local/bin"; do
  [ -d "$d" ] && [[ ":$PATH:" != *":$d:"* ]] && PATH="$d:$PATH"
done
export PATH

input="$(cat)"
file="$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty')"

[ -z "$file" ] && exit 0

project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
diag=""

# --- Rust ---
if [[ "$file" == *.rs ]]; then
  if [ -f "$project_dir/Cargo.toml" ]; then
    # ファイルパスからクレート名を自動検出
    crate=""
    rel_path="${file#"$project_dir/"}"
    # crates/<name>/... or src/... パターン
    if [[ "$rel_path" =~ ^crates/([^/]+)/ ]]; then
      crate="${BASH_REMATCH[1]}"
    elif [[ "$rel_path" =~ ^([^/]+)/src/ ]] && [ -f "$project_dir/${BASH_REMATCH[1]}/Cargo.toml" ]; then
      crate="${BASH_REMATCH[1]}"
    fi

    if [ -n "$crate" ]; then
      check_out=$(cd "$project_dir" && cargo clippy -p "$crate" -- -D warnings 2>&1 | grep -E "^error|^warning|aborting" | head -20) || true
      [ -n "$check_out" ] && diag="[cargo clippy -p ${crate}]\n${check_out}"
    else
      check_out=$(cd "$project_dir" && cargo clippy --workspace -- -D warnings 2>&1 | grep -E "^error|^warning|aborting" | head -20) || true
      [ -n "$check_out" ] && diag="[cargo clippy --workspace]\n${check_out}"
    fi
  fi

# --- TypeScript / JavaScript ---
elif [[ "$file" == *.ts || "$file" == *.tsx || "$file" == *.svelte || "$file" == *.vue ]]; then
  # フロントエンドディレクトリを探索
  frontend_dir=""
  for candidate in "$project_dir/frontend" "$project_dir/client" "$project_dir/app" "$project_dir"; do
    if [ -f "$candidate/package.json" ]; then
      frontend_dir="$candidate"
      break
    fi
  done

  if [ -n "$frontend_dir" ]; then
    if [[ "$file" == *.svelte ]] && (cd "$frontend_dir" && npx svelte-check --version &>/dev/null 2>&1); then
      check_out=$(cd "$frontend_dir" && npx svelte-check --tsconfig ./tsconfig.json 2>&1 | tail -20) || true
    elif [[ "$file" == *.vue ]] && (cd "$frontend_dir" && npx vue-tsc --version &>/dev/null 2>&1); then
      check_out=$(cd "$frontend_dir" && npx vue-tsc --noEmit 2>&1 | head -20) || true
    elif [ -f "$frontend_dir/tsconfig.json" ]; then
      check_out=$(cd "$frontend_dir" && npx tsc --noEmit 2>&1 | head -20) || true
    fi
    [ -n "${check_out:-}" ] && diag="[TypeScript check]\n${check_out}"
  fi

# --- Python ---
elif [[ "$file" == *.py ]]; then
  if command -v ruff &>/dev/null; then
    check_out=$(ruff check "$file" 2>&1 | head -20) || true
    [ -n "$check_out" ] && diag="[ruff]\n${check_out}"
  elif command -v flake8 &>/dev/null; then
    check_out=$(flake8 "$file" 2>&1 | head -20) || true
    [ -n "$check_out" ] && diag="[flake8]\n${check_out}"
  fi

# --- Go ---
elif [[ "$file" == *.go ]]; then
  if command -v go &>/dev/null; then
    pkg_dir=$(dirname "$file")
    check_out=$(cd "$project_dir" && go vet "./${pkg_dir#"$project_dir/"}/" 2>&1 | head -20) || true
    [ -n "$check_out" ] && diag="[go vet]\n${check_out}"
  fi
fi

# 診断結果があれば additionalContext として返す
if [ -n "$diag" ]; then
  jq -Rn --arg msg "$(echo -e "$diag")" '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $msg
    }
  }'
fi

exit 0
