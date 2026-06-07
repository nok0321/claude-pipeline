#!/usr/bin/env bash
# Stop: 配信可能なコミットがあれば /ship を非ブロッキングで提案する（前進の自動化 F1）
#
# 出力は systemMessage のみ（exit 0）。continue:false を出さないので Stop を阻害しない。
# 発火条件: origin の既定ブランチに未反映のコミットがあり、かつ作業ツリーが clean。
# dirty tree（作業途中）では提案しない＝ノイズ抑制。gh は呼ばない（速度優先・git のみ）。
set -uo pipefail   # -e は付けない: git の失敗はソフトに（静かにスキップ）扱う

for d in "$HOME/scoop/shims" "$HOME/.cargo/bin" "$HOME/.local/bin" "/usr/local/bin"; do
  [ -d "$d" ] && [[ ":$PATH:" != *":$d:"* ]] && PATH="$d:$PATH"
done
export PATH

cd "${CLAUDE_PROJECT_DIR:-$(pwd)}" 2>/dev/null || exit 0

# git repo でなければ静かに終了
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# 既定ブランチを検出（origin/HEAD → main → master）
default="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
if [ -z "$default" ]; then
  git show-ref --verify --quiet refs/remotes/origin/main && default=main
fi
if [ -z "$default" ]; then
  git show-ref --verify --quiet refs/remotes/origin/master && default=master
fi
[ -z "$default" ] && exit 0   # remote 既定ブランチ不明 → 提案しない

# origin/default に未反映のコミット数
unshipped="$(git rev-list --count "origin/${default}..HEAD" 2>/dev/null || echo 0)"
case "$unshipped" in (''|*[!0-9]*) exit 0 ;; esac   # 非数値なら終了
[ "$unshipped" -gt 0 ] || exit 0

# 作業ツリーが dirty（作業途中）なら提案しない
[ -z "$(git status --porcelain 2>/dev/null)" ] || exit 0

branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
plural=""; [ "$unshipped" -gt 1 ] && plural="s"
msg="${unshipped} commit${plural} on '${branch}' not yet on origin/${default} — run /ship to open a PR (merge stays gated)."

if command -v jq >/dev/null 2>&1; then
  jq -n --arg m "$msg" '{systemMessage: $m}'
else
  # jq 不在でも壊れない最小 JSON（msg に " や \ を含めない前提の安全な内容）
  printf '{"systemMessage": "%s"}\n' "$msg"
fi
exit 0
