# claude-pipeline

Claude Code 向け自律開発パイプラインのスキル集。

`~/.claude/skills/` からシンボリックリンクされており、このリポジトリが唯一の真実源。

設計原則・スキル間の関係は [ARCHITECTURE.md](ARCHITECTURE.md)、旧 15 skill から新 7 skill への移行は [docs/MIGRATION.md](docs/MIGRATION.md) を参照。

> **注 (2026-05-23 / Phase 6 Sub-V 確定)**: 旧 15 skill 構造 → Phase 2 で 8 skill → Phase 6 Sub-V Option A で `safe-fix` 廃止 (impl-orchestrator Stage 3 inline 化)、**現在 7 skill 構造**。Phase 5 POST eval 結果は 7/8 個別 M1 PASS、7-skill 平均 trigger rate +36.3% 改善 (safe-fix 除く、詳細: [evals/POST-DIFF.md](evals/POST-DIFF.md))。Escalation 削減のため `technical-arbiter` / `regression-judge` subagent (`agents/`) と Stop hook drift gate を追加 ([plans/ESCALATION-REDESIGN.md](plans/ESCALATION-REDESIGN.md))。

> **注 (2026-06-07 / Pipeline v2 着手)**: goal 駆動リデザイン ([plans/PIPELINE-V2-PLAN.md](plans/PIPELINE-V2-PLAN.md))。`task-planner` / `ship` / `skill-authoring` の 3 skill と `tech-comparator` subagent を追加し **現在 10 skill 構造**。design-phase に `--reverse`、impl-orchestrator に goal mode、前進自動化 hook `stop-ship-suggest.sh` を追加 ([docs/event-automation.md](docs/event-automation.md))。

---

## 構成

```
claude-pipeline/
├── skills/                    # Claude Code スキル群（~/.claude/skills/ へシンボリックリンク）
│   ├── impl-orchestrator/     # 実装フェーズ専任 + エントリーポイント (4 ステージループ + inline 修正)
│   ├── task-planner/          # goal 駆動の計画フェーズ (技術選定→計画→共有契約→計画レビュー)
│   ├── design-phase/          # 設計書自動生成 (plans/*.md → DESIGN/*.md、--reverse で実装→doc)
│   ├── spec-audit/            # 仕様書間矛盾検出 + 仕様↔実装差分検出 (Mode A/B)
│   ├── robust-review/         # 深層セキュリティ・堅牢性レビュー
│   ├── code-review/           # 軽量 PR レビュー (5 軸統合)
│   ├── boundary-test/         # 境界契約テスト (API/WASM/DB/変換)
│   ├── checkpoint/            # セッション継続管理 (/clear 前の状態保存)
│   ├── ship/                  # git デリバリ (commit/PR/任意merge、branch 保護対応)
│   └── skill-authoring/       # skill 著作の house-style 強制＋登録 (skill-creator ラッパ)
├── agents/                    # Claude Code Subagents（~/.claude/agents/ へシンボリックリンク）
│   ├── technical-arbiter.md   # 命名/型 drift の technical-judgment 委譲 (sonnet 4.6, read-only)
│   ├── regression-judge.md    # test failure の fix-related / pre-existing 判定 (sonnet 4.6)
│   ├── tech-comparator.md     # 技術選定肢の多軸比較→ランク付け (sonnet 4.6, read-only)
│   └── curriculum-comparator.md # (educational curriculum 比較用、本パイプライン外)
├── hooks/                     # Claude Code Hook スクリプト集（settings.json から参照）
│   ├── pre-bash-safety.sh     # PreToolUse(Bash): 破壊的コマンドブロック
│   ├── post-edit-lint.sh      # PostToolUse(Write/Edit): 編集毎の lint/型チェック
│   ├── stop-verify.sh         # Stop: タスク完了時の検証ゲート（差分言語自動検出）
│   ├── stop-ship-suggest.sh   # Stop: 配信可能コミットがあれば /ship を非ブロッキング提案
│   └── session-start.sh       # SessionStart: プロジェクト種別・ツールチェーン検出
├── .claude/settings.json      # プロジェクトレベル設定 (Stop hook drift gate を含む)
├── evals/                     # トリガー評価フレームワーク (skill-creator ベース)
│   ├── queries/               # 各 skill の triggerable query 集 (20 件/skill)
│   ├── BASELINE.json          # Phase 0 ベースライン
│   ├── POST-DIFF.md           # Phase 5 POST 評価と BASELINE 差分
│   └── arbiter-decisions.jsonl # technical-arbiter 判定ログ (append-only)
├── docs/
│   └── MIGRATION.md           # 旧 15 skill → 新 7 skill 対応表
└── plans/
    ├── REDESIGN-PLAN.md       # 重量整理計画 (Phase 0-6)
    ├── REDESIGN-CHECKPOINT.md # 進捗チェックポイント
    └── ESCALATION-REDESIGN.md # Escalation 削減リデザイン (technical-arbiter / regression-judge / drift gate)
```

---

## エントリーポイント

```
/task-planner <goal>               # goal をタスク計画に分解 (技術選定 + 共有契約 + 計画レビュー)
/impl-orchestrator <component>     # 実装パイプラインを起動
                                   # DESIGN/*.md 不在時は自動的に design-phase へフォールバック
                                   # Stage 3 で findings を inline 修正、technical-arbiter / regression-judge を活用
/design-phase <component>          # 設計書のみ生成 (plans/*.md から)
/spec-audit --mode=cross           # 仕様書間矛盾検出
/spec-audit --mode=conformance     # 仕様↔実装差分検出
/robust-review <files>             # マージ前の深層レビュー
/code-review <files>               # PR 前の軽量レビュー
/boundary-test <component>         # 境界契約テスト生成
/checkpoint save | restore         # セッション継続管理
/ship [--merge]                    # commit→PR→(任意)merge、branch 保護を検出して対応
/skill-authoring new <name>        # house-style 準拠で skill を新設＋登録
```

旧 `/dev-pipeline` (フェーズ統合エントリ) は Phase 2 で廃止、`impl-orchestrator` が DESIGN/*.md 不在時に design-phase を Agent 委譲する形に統合。
旧 `/safe-fix` (検査結果の自動修正) は Phase 6 Sub-V Option A で廃止、impl-orchestrator Stage 3 に inline 化 (詳細: [docs/MIGRATION.md](docs/MIGRATION.md))。

---

## 設計原則 (要約)

1. **2 層委譲のみ** — オーケストレーター (`impl-orchestrator`) → 各 skill。3 層は廃止。
2. **検査↔修正の JSON Finding 契約化** — `skills/impl-orchestrator/references/finding.schema.json` で形式定義。検査系 skill は schema 準拠 JSON を末尾出力。
3. **モデル配分** — オーケストレーター=opus, 実装=sonnet, レビュー=opus, 判定 subagent=sonnet 4.6
4. **機械的検証ゲート先行** — ビルド/型/テスト/境界契約 → 並列レビュー → 修正 + 再検証 (impl-orchestrator Stage 2/3)
5. **CLAUDE.md 駆動の動的設定** — プロジェクト固有のパスやチェック項目はハードコードせず、対象プロジェクトの CLAUDE.md から動的取得
6. **Technical judgment は subagent 委譲** — 命名/型 drift / regression attribution は user 中断前に `technical-arbiter` / `regression-judge` を経由 (Phase 6: ESCALATION-REDESIGN P1/P2)

詳細は [ARCHITECTURE.md](ARCHITECTURE.md)。

---

## 更新ワークフロー

スキルはこのリポジトリで編集し、`~/.claude/skills/` のシンボリックリンク経由で Claude Code に反映される。

```bash
cd ~/work/private/claude-pipeline
# skills/<skill-name>/SKILL.md を編集
git diff
git add skills/
git commit -m "feat(skill): ..."
git push
```

skill 編集中は eval (`evals/scripts/run_baseline.sh`) を回さないこと (測定汚染防止)。

---

## Hooks のインストール

hooks/ は Claude Code の Hook 機能で使うシェルスクリプト集。`~/.claude/settings.json` から参照する。

参照方法は用途に応じて 2 パターンある。

### パターン A: ユーザーレベル共有（推奨・デフォルト）

全プロジェクトで同一の hooks を使いたい場合。`$HOME/.claude/hooks/` に実体を置き、`settings.json` から `$HOME` で参照する。

```bash
cp hooks/*.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/*.sh
```

```json
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

特定プロジェクトだけ独自の hooks を適用したい場合。各プロジェクトの `.claude/hooks/` に実体を置き、`$CLAUDE_PROJECT_DIR` で参照する。

```bash
cp hooks/*.sh <project>/.claude/hooks/
chmod +x <project>/.claude/hooks/*.sh
```

```json
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
- **post-edit-lint.sh**: 編集ファイルの拡張子から `cargo clippy` / `tsc --noEmit` / `svelte-check` / `ruff` / `go vet` を自動選択して実行。エラーだけを additionalContext として返す。旧 `quick-test` skill の差分ベース確認はこちらに吸収済み
- **stop-verify.sh**: `git diff` で変更言語を検出し、該当する検証ツールを一括実行。エラーがあれば `decision: block` で完了を止める
- **stop-ship-suggest.sh**: origin の既定ブランチに未反映のコミットがあり作業ツリーが clean なら、`systemMessage` で `/ship` を提案（非ブロッキング、Stop を阻害しない）。イベント発火の詳細は [docs/event-automation.md](docs/event-automation.md)
- **session-start.sh**: Git ブランチ・未コミット数・Rust/Node/Python/Go/Java/Docker のバージョンを 1 行で表示

---

## CLAUDE.md に追加すべきセクション（対象プロジェクト側）

スキル群は対象プロジェクトの CLAUDE.md から構造化セクションを動的取得する。

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

## Boundary Definitions（boundary-test 用、オプション）
- API ↔ Frontend: ...
- WASM ↔ TypeScript: ...
- DB ↔ App: ...
```

各セクションの詳細用途は [ARCHITECTURE.md §6](ARCHITECTURE.md) を参照。

---

## 評価フレームワーク (evals/)

skill-creator の `run_eval.py` を Windows 互換に port した独自フレームワーク。詳細は [evals/README.md](evals/README.md) と [evals/scripts/README.md](evals/scripts/README.md)。

```bash
# 全 10 skill の trigger rate を測定 (Phase 0/5 用 wrapper、~40-90 分、WORKERS=3 で並列)
bash evals/scripts/run_baseline.sh

# 単一 skill の測定 (debug 用)
python evals/scripts/run_eval_compat.py \
  --eval-set evals/queries/<skill>.json \
  --skill-path skills/<skill> \
  --runs-per-query 3 --num-workers 3 --timeout 30 --model claude-opus-4-8

# 結果集計 (per-skill JSON → 集計 JSON)
python evals/scripts/aggregate.py evals/results/<phase>/ > evals/<PHASE>.json

# BASELINE vs POST 差分
python evals/scripts/compare.py evals/BASELINE.json evals/POST.json
```

各 skill の query セットは `evals/queries/<skill>.json` に 20 件 (explicit/implicit/casual の triggerable + near-miss/generic の non-triggerable)。

**skill 編集中は測定汚染防止のため eval を回さないこと**。
