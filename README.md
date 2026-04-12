# claude-pipeline

Claude Code 向け自律開発パイプラインのスキル集。

`~/.claude/skills/` からシンボリックリンクされており、このリポジトリが唯一の真実源。

---

## 構成

```
claude-pipeline/
├── skills/           # Claude Code スキル群（~/.claude/skills/ へシンボリックリンク）
│   ├── escalation/           # エスカレーション分類フレームワーク
│   ├── pipeline-state/       # PIPELINE-STATE.md 管理
│   ├── impl-orchestrator/    # 実装オーケストレーター
│   ├── design-phase/         # 設計フェーズ自動化
│   ├── dev-pipeline/         # 計画→設計→実装→テスト→報告の統合
│   ├── boundary-test/        # 境界契約テスト生成
│   ├── robust-review/        # セキュリティ/堅牢性レビュー
│   ├── robust-fix/           # S-Critical/S-High 自動修正
│   ├── spec-check/           # 仕様↔実装差分検出
│   ├── spec-fix/             # 仕様↔実装双方向修正
│   ├── spec-audit/           # 仕様書間矛盾検出
│   ├── spec-cycle/           # check→fix→re-check サイクル
│   ├── code-review/          # 5軸統合レビュー
│   ├── fix-with-verify/      # 安全修正+自動リバート
│   ├── quick-test/           # 差分ベース高速テスト
│   └── checkpoint/           # セッション引き継ぎ
└── plans/
    └── PLAN.md               # 自律開発パイプライン実装計画
```

---

## パイプライン概要

```
Phase 0: 計画（対話）      ← ユーザー承認必須
Phase 1: 設計（自律）      ← design-phase
Phase 2: 実装（自律）      ← impl-orchestrator + boundary-test
Phase 3: テスト（自律）    ← spec-cycle + robust-review
Phase 4: 報告
```

エントリーポイント: `/dev-pipeline <task-description>`

---

## 設計原則

1. **スキルから Agent ツール経由でサブエージェント化** — スキル直接呼び出しは不可
2. **ハードコードなし** — `CLAUDE.md` の `## Component Mapping` / `## Critical Constraints` / `## Project-Specific Checks` から動的取得
3. **モデル配分** — オーケストレーター=opus, 実装=sonnet, レビュー=opus
4. **機械的検証ゲート先行** — ビルド/型/テストをレビューより先に通す

---

## 更新ワークフロー

スキルはこのリポジトリで編集し、`~/.claude/skills/` のシンボリックリンク経由で Claude Code に反映される。

```bash
# 編集
cd ~/work/private/claude-pipeline
# skills/<skill-name>/SKILL.md を編集

# 変更確認
git diff

# コミット
git add skills/
git commit -m "feat(skill): ..."
git push
```

---

## CLAUDE.md に追加すべきセクション（対象プロジェクト側）

```markdown
## Component Mapping
| コンポーネント | 仕様書 | 実装ディレクトリ |
|---------------|--------|-----------------|
| ... | ... | ... |

## Critical Constraints
- 制約1
- 制約2

## Project-Specific Checks
- プロジェクト固有チェック項目

## Commands
- build: <command>
- test: <command>
- lint: <command>

## Escalation Overrides（オプション）
- promote: ...
- demote: ...
```
