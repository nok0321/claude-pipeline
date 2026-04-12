#!/usr/bin/env bash
# PreToolUse(Bash): 破壊的コマンドをブロックする汎用 Safety Gate
set -euo pipefail

input="$(cat)"
cmd="$(echo "$input" | jq -r '.tool_input.command // empty')"

[ -z "$cmd" ] && exit 0

# --- 破壊的コマンドのブロック ---

# ファイルシステム破壊
if echo "$cmd" | grep -qEi 'rm\s+-rf\s+(/|~|\$HOME)'; then
  echo "BLOCKED: ルートまたはホームディレクトリの再帰削除を検出" >&2
  exit 2
fi

# Git 破壊操作
if echo "$cmd" | grep -qEi 'git\s+push\s+(-f|--force)\s+(origin\s+)?(main|master)'; then
  echo "BLOCKED: main/master への force push を検出。手動で実行してください。" >&2
  exit 2
fi

if echo "$cmd" | grep -qEi 'git\s+reset\s+--hard'; then
  echo "BLOCKED: git reset --hard を検出。手動で実行してください。" >&2
  exit 2
fi

# パッケージ公開（意図しない publish を防止）
if echo "$cmd" | grep -qEi '(cargo|npm|yarn|pnpm)\s+publish'; then
  echo "BLOCKED: パッケージ公開コマンドを検出。手動で実行してください。" >&2
  exit 2
fi

# データベース破壊
if echo "$cmd" | grep -qEi 'DROP\s+(DATABASE|TABLE|SCHEMA)\s' ; then
  echo "BLOCKED: DROP DATABASE/TABLE/SCHEMA を検出。手動で実行してください。" >&2
  exit 2
fi

exit 0
