# claude-pipeline

Claude Code 向け自律開発パイプラインのスキル集。

`~/.claude/skills/` からシンボリックリンクされており、このリポジトリが唯一の真実源。

設計原則・スキル間の関係は [ARCHITECTURE.md](ARCHITECTURE.md) を参照。

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
│   ├── spec-fix/             # 仕様↔実装双方向修正（--loop で旧 spec-cycle 相当）
│   ├── spec-audit/           # 仕様書間矛盾検出
│   ├── code-review/          # 5軸統合レビュー（軽量・PR向け）
│   ├── fix-with-verify/      # 安全修正+自動リバート
│   ├── quick-test/           # 差分ベース高速テスト
│   └── checkpoint/           # セッション引き継ぎ
├── hooks/            # Claude Code Hook スクリプト（設定は settings.json 参照）
│   ├── pre-bash-safety.sh    # PreToolUse(Bash): 破壊的コマンドブロック
│   ├── post-edit-lint.sh     # PostToolUse(Write/Edit): 編集毎の lint/型チェック
│   ├── stop-verify.sh        # Stop: タスク完了時の検証ゲート（差分言語自動検出）
│   └── session-start.sh      # SessionStart: プロジェクト種別・ツールチェーン検出
└── plans/
    └── PLAN.md               # 自律開発パイプライン実装計画
```

---

## パイプライン概要

```
Phase 0: 計画（対話）      ← ユーザー承認必須
Phase 1: 設計（自律）      ← design-phase
Phase 2: 実装（自律）      ← impl-orchestrator + boundary-test
Phase 3: テスト（自律）    ← spec-fix --loop + robust-review
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

## Hooks のインストール

hooks/ は Claude Code の Hook 機能で使うシェルスクリプト集。`~/.claude/settings.json` から参照する。

参照方法は用途に応じて 2 パターンある。

### パターン A: ユーザーレベル共有（推奨・デフォルト）

全プロジェクトで同一の hooks を使いたい場合。`$HOME/.claude/hooks/` に実体を置き、`settings.json` から `$HOME` で参照する。

```bash
# インストール（ホームの ~/.claude/hooks/ にコピー or junction）
cp hooks/*.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/*.sh

# settings.json の例（ユーザーレベル ~/.claude/settings.json）
{
  "hooks": {
    "PreToolUse":  [{"matcher": "Bash", "hooks": [{"type":"command","command":"bash \"$HOME/.claude/hooks/pre-bash-safety.sh\"","timeout":5000}]}],
    "PostToolUse": [{"matcher": "Write|Edit|MultiEdit", "hooks": [{"type":"command","command":"bash \"$HOME/.claude/hooks/post-edit-lint.sh\"","timeout":60000}]}],
    "Stop":        [{"matcher": "", "hooks": [{"type":"command","command":"bash \"$HOME/.claude/hooks/stop-verify.sh\"","timeout":180000}]}],
    "SessionStart":[{"matcher": "", "hooks": [{"type":"command","command":"bash \"$HOME/.claude/hooks/session-start.sh\"","timeout":10000}]}]
  }
}
```

### パターン B: プロジェクトレベル上書き

特定プロジェクトだけ独自の hooks を適用したい場合（例: プロジェクト固有の破壊的コマンドを追加ブロック）。各プロジェクトの `.claude/hooks/` に実体を置き、`$CLAUDE_PROJECT_DIR` で参照する。

```bash
# プロジェクト毎にインストール（コピー or junction）
cp hooks/*.sh <project>/.claude/hooks/
chmod +x <project>/.claude/hooks/*.sh

# settings.json の例（該当プロジェクトの .claude/settings.json、もしくはユーザーレベルで全体適用）
{
  "hooks": {
    "PreToolUse":  [{"matcher": "Bash", "hooks": [{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/pre-bash-safety.sh\"","timeout":5000}]}],
    "PostToolUse": [{"matcher": "Write|Edit|MultiEdit", "hooks": [{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/post-edit-lint.sh\"","timeout":60000}]}],
    "Stop":        [{"matcher": "", "hooks": [{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/stop-verify.sh\"","timeout":180000}]}],
    "SessionStart":[{"matcher": "", "hooks": [{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/session-start.sh\"","timeout":10000}]}]
  }
}
```

`$CLAUDE_PROJECT_DIR` をユーザーレベル `settings.json` で使うと、各プロジェクトに `.claude/hooks/` が必須になる点に注意。junction で `claude-pipeline/hooks/` を指すのが真実源を一元化する一般的な運用。

### 各 Hook の動作
- **pre-bash-safety.sh**: `rm -rf /`, `git push --force main`, `DROP DATABASE`, `cargo/npm publish` 等を検出して exit 2 でブロック
- **post-edit-lint.sh**: 編集ファイルの拡張子から `cargo clippy` / `tsc --noEmit` / `svelte-check` / `ruff` / `go vet` を自動選択して実行。エラーだけを additionalContext として返す
- **stop-verify.sh**: `git diff` で変更言語を検出し、該当する検証ツールを一括実行。エラーがあれば `decision: block` で完了を止める
- **session-start.sh**: Git ブランチ・未コミット数・Rust/Node/Python/Go/Java/Docker のバージョンを1行で表示

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
