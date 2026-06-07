# claude-pipeline

Claude Code 向け自律開発パイプラインの **skill リポジトリ**。`skills/` `agents/` `hooks/` が
`~/.claude/` 配下へ symlink され、本リポが唯一の真実源。設計原則は [ARCHITECTURE.md](ARCHITECTURE.md)、
リデザイン計画は [plans/](plans/)。

スキル本体は英語、メタドキュメント (README / ARCHITECTURE / plans / 本ファイル) は日本語。

## Git Workflow

`ship` skill とエージェントが読む。このリポの main は GitHub ruleset で保護されている。

- default branch: `main`
- direct push: **不可**（PR 必須 / linear history / non-fast-forward 拒否 / deletion 拒否）
- merge strategy: `rebase`（rebase-merge のため各コミットの SHA が振り直される）
- delivery: feature ブランチ → `gh pr create --base main` → `gh pr merge <N> --rebase --delete-branch`
- 承認: required reviewers 0 件設定のため自分で merge 可
- merge gate: **既定でユーザーゲート**。`/ship` は PR まで自律、merge は `--merge` 明示時のみ
- 回復手順（SHA 振り直し / force-push 拒否 / `reset --hard` の安全 hook ブロック）:
  [skills/ship/references/git-recovery.md](skills/ship/references/git-recovery.md)

## Notes

- skill 編集中は eval を回さない（測定汚染防止、[evals/README.md](evals/README.md)）。
- モデル pin 更新は `grep -rE "claude-(opus|sonnet)-4-[0-9]"` で SKILL.md / agents/*.md /
  .claude/settings.json / plans/*.md を一括（ARCHITECTURE.md §4）。
