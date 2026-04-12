# 自律開発パイプライン実装計画

## Context

Insights分析でバグ54件・デバッグループ多発が最大のフリクション。原因は「Claude実装→Claudeレビュー」の自己レビュー構造と、ユーザーの手動テストに依存した品質ゲート。

本計画は、役割別エージェントによるクロスレビュー＋エスカレーション駆動のユーザー介入＋機械的検証ゲートを組み合わせた自律パイプラインを構築し、バグの後追いループを構造的に排除する。

---

## 既存資産の棚卸

### 再利用するスキル
| スキル | 用途 | 場所 | 汎用化要否 |
|--------|------|------|-----------|
| `code-review` | 5軸統合レビュー | `~/.claude/skills/` | 不要（既に汎用） |
| `fix-with-verify` | 安全修正+自動リバート | `~/.claude/skills/` | 不要 |
| `quick-test` | 差分ベース高速テスト | `~/.claude/skills/` | 不要 |
| `checkpoint` | セッション引き継ぎ | `~/.claude/skills/` | 不要 |
| `spec-audit` | 設計書間矛盾検出 | 特定プロジェクト固有版 | **要** |
| `spec-check` | 設計↔実装差分検出 | 特定プロジェクト固有版 | **要** |
| `spec-fix` | 双方向自動修正 | 特定プロジェクト固有版 | **要** |
| `robust-review` | セキュリティ/堅牢性深層レビュー | 特定プロジェクト固有版 | **要** |
| `robust-fix` | S-Critical/S-High自動修正 | 特定プロジェクト固有版 | **要** |

### 再利用するHook（検証ゲートの基盤）
| Hook | 役割 |
|------|------|
| `post-edit-lint.sh` | ファイル編集ごとにclippy/tsc/ruff/go vet（言語自動検出済み） |
| `stop-verify.sh` | タスク完了時に全変更ファイルの検証ゲート（言語自動検出済み） |

### 基盤設定
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`
- `CLAUDE_CODE_EFFORT_LEVEL=max`
- `context: fork` パターン — レビュースキルのコンテキスト分離

---

## 技術的制約と設計判断

### 制約1: スキルからスキルを呼べない
スキルはMarkdown指示書であり、別のスキルを直接 `invoke` する仕組みはない。

**対策**: オーケストレーターは **Agent ツール** でサブエージェントを生成し、そのプロンプトに既存スキルの指示内容を埋め込む。Agent ツールは既に利用可能（deferred tool ではない）で実績259回。

```
impl-orchestrator (メイン, opus)
  → Agent(impl, model:sonnet): 実装を担当（コード生成量が多いためsonnet）
  → Agent(security, model:opus): robust-review Axis1 の指示をプロンプトに含める
  → Agent(robustness, model:opus): robust-review Axis2+3 の指示をプロンプトに含める
  → Agent(spec, model:opus): spec-check の指示をプロンプトに含める
```

### 制約2: プロジェクト固有スキルにハードコード多数
- レビュー系スキル: 特定プロジェクトの実装ディレクトリパスが直書き
- 整合性チェック系スキル: コンポーネント→仕様書→実装ディレクトリのマッピングテーブルが固定
- 特定フレームワーク/DB/言語機能に依存するチェックが埋め込み

**対策**: パスとチェック項目を CLAUDE.md の構造化セクションから動的に読み取る方式に変更。

```markdown
## Component Mapping（CLAUDE.md に追加するセクション）
| コンポーネント | 仕様書 | 実装ディレクトリ |
|---------------|--------|-----------------|
| <component_a> | DESIGN/01_<component_a>.md | <path/to/component_a>/ |
| <component_b> | DESIGN/02_<component_b>.md | <path/to/component_b>/ |
| <component_c> | DESIGN/03_<component_c>.md | <path/to/component_c>/ |

## Project-Specific Checks（CLAUDE.md に追加するセクション）
- <アーキテクチャ制約>: <対象ディレクトリ> → <禁止依存>、<代替手段>
- <データ形式順序>: <FormatA>=[<field1>,<field2>], <FormatB>=[<field2>,<field1>], ...
- <フレームワーク規約>: <規約の内容>
```

### 制約3: モデルの役割分担
レビューと実装で求められる能力が異なる。

**対策**: **レビューエージェントは opus**（判断力・推論力が品質に直結、見落としコスト大）、**実装エージェントは sonnet**（コード生成量が多くコスト効率重視、品質は後段ゲート+opusレビューで担保）。オーケストレーター本体は opus。

### 制約4: エスカレーション「すべき」判断の失敗リスク
エージェントが確信を持って間違えた場合、エスカレーションが発火しない。

**対策**: エスカレーション判断に頼らない機械的な検証ゲート（ビルド/型チェック/テスト/境界契約テスト）を必ず先に通す。レビューは「ゲートを通過した上での追加チェック」と位置づけ、両方で守る。

---

## 前提作業: プロジェクト固有スキルの汎用化 ✅ 完了（2026-04-12）

~~Sprint 1 の前に実施。~~ → 元のプロジェクト固有版が利用不可のため、計画の汎用化仕様に基づきグローバル版を新規作成。

### 作成済みスキル（6スキル → `~/.claude/skills/`）
```
~/.claude/skills/spec-audit/SKILL.md    — 仕様書間矛盾検出
~/.claude/skills/spec-check/SKILL.md    — 仕様↔実装差分検出
~/.claude/skills/spec-fix/SKILL.md      — 双方向自動修正
~/.claude/skills/spec-cycle/SKILL.md    — check→fix→re-check統合ワークフロー
~/.claude/skills/robust-review/SKILL.md — セキュリティ/堅牢性深層レビュー
~/.claude/skills/robust-fix/SKILL.md    — S-Critical/S-High自動修正
```

### 適用済みの汎用化方針
1. ハードコードパスなし → CLAUDE.md の `## Component Mapping` から動的取得
2. 言語固有チェックなし → CLAUDE.md の `## Project-Specific Checks` から動的取得
3. 情報不在時は graceful degradation（エラーにせず汎用チェックで続行）
4. レビュー系は `context: fork` でコンテキスト分離
5. `model: claude-opus-4-6` 維持（単体実行時用）

### 検証
- 未実施（テスト用プロジェクトでの動作確認は別途）

---

## Sprint 1: 基盤 + コアループ（MVP） ✅ 完了（2026-04-12）

**目標**: `/impl-orchestrator component_name` で「実装→検証→並列レビュー→修正→エスカレーション」が動く

### Step 1-1: エスカレーションフレームワーク
**ファイル**: `~/.claude/skills/escalation/SKILL.md`

パイプライン全体で参照されるエスカレーション判断基準。独立しても `/escalation classify [finding]` で分類テスト可能。

```
必ずエスカレーション（自律判断禁止）:
  - 外部API/DBスキーマの選定・変更
  - 認証・認可フローの設計判断
  - 公開インターフェースの破壊的変更
  - 設計書に記載のない新規要件の発見
  - 同一問題の修正が3回連続失敗
  - 検証ゲートが最大リトライ後もパスしない

自律対応 + 事後報告:
  - S-Critical/S-High の定型修正（unwrap除去、injection対策等）
  - 設計書の軽微な矛盾修正（型名揺れ、引数順不一致）
  - テストで発見されたバグの修正
  - エッジケーステストの追加

自律対応（報告不要）:
  - S-Medium/S-Low/Info修正
  - フォーマット、import整理
  - ドキュメントコメント追加
```

プロジェクト固有のオーバーライド: CLAUDE.md `## Escalation Overrides` で上書き可能。

**単体検証**: 架空の Finding を複数用意し `/escalation classify` で正しく3分類されるか確認。

---

### Step 1-2: パイプライン状態管理
**ファイル**: `~/.claude/skills/pipeline-state/SKILL.md`

フェーズ間の引き継ぎ契約 `PIPELINE-STATE.md` の CRUD。

```markdown
# Pipeline: [task-name]
Phase: [planning|design|implementation|testing|reporting]
Updated: [ISO 8601]

## 計画サマリー
[ユーザー合意済みの要件]

## 設計成果物
- [x] DESIGN/component_a.md
- [ ] DESIGN/component_b.md

## 実装ステータス
| コンポーネント | 実装 | 検証ゲート | レビュー |
|---------------|------|-----------|---------|
| component_a | done | build:pass type:pass test:pass | security:clean robustness:2-fixed |

## エスカレーションキュー
| # | フェーズ | 分類 | 内容 | 状態 |
|---|---------|------|------|------|
| 1 | design | must-escalate | DBスキーマ変更が必要 | pending |

## 次フェーズへの引き継ぎ
[具体的な指示]
```

checkpoint との関係: checkpoint=セッション汎用引き継ぎ、pipeline-state=パイプライン固有の構造化状態。併用。

**単体検証**: `/pipeline-state init`, `/pipeline-state update`, `/pipeline-state read` をそれぞれ実行して PIPELINE-STATE.md が正しく生成・更新されるか確認。

---

### Step 1-3: 実装オーケストレーター（コア）
**ファイル**: `~/.claude/skills/impl-orchestrator/SKILL.md`
**補助ファイル**: `~/.claude/skills/impl-orchestrator/REVIEW-AGENTS.md`

```
---
name: impl-orchestrator
description: DESIGN仕様書から自律的に実装→検証ゲート→並列レビュー→修正のループを実行。
argument-hint: "[component-name or 'all']"
allowed-tools: Read, Write, Edit, MultiEdit, Bash, Grep, Glob, Agent
model: claude-opus-4-6
---
```

#### 6ステージ

**Stage 1: 準備**
1. CLAUDE.md の `## Component Mapping` を読み取り、対象コンポーネントの仕様書パスと実装ディレクトリを特定
2. DESIGN/*.md を読み込み
3. PIPELINE-STATE.md から前フェーズの文脈を取得
4. CLAUDE.md の `## Critical Constraints` と `## Project-Specific Checks` を取得
5. 実装単位の依存順序を決定

**Stage 2: 実装**（sonnet モデルのサブエージェントで実行）
1. コンポーネントごとに Agent(model:sonnet) を生成して実装を委任
2. post-edit-lint.sh が編集ごとに自動でコンパイル/lint チェック（既存Hook）
3. 実装の品質は Stage 3（検証ゲート）+ Stage 4（opus レビュー）で担保

**Stage 3: 検証ゲート**（全パス必須 — エスカレーション判断に依存しない機械的チェック）
1. ビルド/コンパイル（言語自動検出: Cargo.toml→cargo, package.json→npm, build.gradle→gradle）
2. 型チェック（clippy/tsc/svelte-check/ruff）
3. テストスイート（cargo test/npm test/gradlew test）
4. 境界契約テスト（Sprint 2で追加。それまではスキップ）

失敗時: 自律修正を試行（最大3回）。超過でエスカレーション。

**Stage 4: 並列レビュー**（Agent ツールで3サブエージェントを同時生成）
```
Agent(security, model:opus):
  「以下のファイルをセキュリティ観点でレビューせよ。
   [REVIEW-AGENTS.md の Security セクションを展開]
   対象: [Stage 1 で特定したファイル一覧]
   CLAUDE.md 制約: [Project-Specific Checks を展開]
   出力: S-Critical〜S-Low の Finding リスト」

Agent(robustness, model:opus):
  「以下のファイルを堅牢性+クリティカル観点でレビューせよ。
   [REVIEW-AGENTS.md の Robustness セクションを展開]
   ...同上...」

Agent(spec, model:opus):
  「以下のファイルと DESIGN/*.md の整合性をチェックせよ。
   [REVIEW-AGENTS.md の Spec セクションを展開]
   Component Mapping: [CLAUDE.md から展開]
   ...同上...」
```

エージェント失敗時: タイムアウト(5分) → 該当軸をスキップし事後報告に記録。残り2軸の結果で続行。

**Stage 5: 指摘解決**
1. 3エージェントの Finding を統合・重複排除
2. エスカレーションフレームワークで分類
3. 自律修正可能 → 修正実行 → Stage 3 の検証ゲート再通過
4. 設計変更必要 → DESIGN/*.md を更新 → Stage 2 に戻る（**最大1回**、超過でエスカレーション）
5. must-escalate → エスカレーションキューに追加

**Stage 6: 完了判定**
1. 全コンポーネントクリーン → PIPELINE-STATE.md 更新 → 完了
2. 未解決あり & イテレーション < 3 → Stage 4 へ
3. 上限到達 → エスカレーション報告をユーザーに提示
4. コンテキストが肥大化している場合 → checkpoint save → フェーズ境界でclear推奨

#### REVIEW-AGENTS.md の構成
既存の `robust-review` Axis 1〜3 と `spec-check` Step 1〜6 の指示内容を、汎用化した形で3セクションに整理。ハードコードパスの代わりにプレースホルダー `{target_files}`, `{component_mapping}`, `{project_checks}` を使用し、オーケストレーターが実行時に展開する。

**Sprint 1 検証**:
1. 実プロジェクトで小さな機能（例: 既存APIにバリデーション追加）を `/impl-orchestrator <component>` で実行
2. 確認項目:
   - [ ] 検証ゲート（build/type/test）が全て実行される
   - [ ] 3つのレビューエージェントが並列起動する（sonnetモデル）
   - [ ] Finding が統合・分類される
   - [ ] 自律修正が実行され、再度ゲートを通過する
   - [ ] PIPELINE-STATE.md が正しく更新される
   - [ ] must-escalate 項目がユーザーに提示される

---

## Sprint 2: 境界契約テスト生成 ✅ 完了（2026-04-12）

**目標**: API型不一致・データ形式変換ミスなどinsights最大フリクション(54件中の主要因)の機械的検出

**ファイル**: `~/.claude/skills/boundary-test/SKILL.md`

### 検出する境界

| 境界 | ソース側検出方法 | 消費側検出方法 | テスト戦略 |
|------|----------------|---------------|-----------|
| REST API ↔ Frontend | Grep: ハンドラシグネチャ + レスポンス型 | Grep: fetch/axios呼び出し + 期待型 | レスポンスJSON構造の一致検証 |
| WASM ↔ TypeScript | Grep: `#[wasm_bindgen]` exports | Grep: WASM import呼び出し | 型付き入出力の形状一致 |
| DB ↔ Application | Grep: テーブル定義/マイグレーション | Grep: モデル構造体/Entity | ラウンドトリップ(insert→select→assert) |
| 形式変換境界 | CLAUDE.md `## Critical Constraints` | Grep: 変換関数群 | ラウンドトリップ(値→変換→逆変換→一致) |

### 言語別テスト生成
- **Rust**: `tests/boundary_*.rs` — `#[tokio::test]` + HTTPリクエスト
- **TypeScript**: `__tests__/boundary_*.test.ts` — vitest
- **Java**: `*BoundaryIT.java` — TestContainers + MockMvc

Sprint 1 完了後、impl-orchestrator の Stage 3 に境界テスト実行を追加。

**検証**:
1. 実プロジェクトで `/boundary-test detect` → 境界一覧が正しく検出される
2. 意図的に API レスポンス型を壊す → 境界テストが fail する

---

## Sprint 3: 設計フェーズ自動化 ✅ 完了（2026-04-12）

**目標**: 計画出力から DESIGN/*.md を自律生成＋spec-audit で自己検証

**ファイル**: `~/.claude/skills/design-phase/SKILL.md`

### 手順
1. PIPELINE-STATE.md の計画サマリーを読み込み
2. 既存 DESIGN/*.md があればフォーマット・慣例を学習、なければデフォルトテンプレート使用
3. コンポーネント/モジュールごとに DESIGN/{component}.md を生成
   - 含める内容: 目的、公開API(シグネチャ付き)、内部構造、型定義、エラーハンドリング、テスト要件、依存関係
4. spec-audit 相当のチェックをサブエージェントで実行（設計書間の矛盾検出）
5. 自律修正可能な矛盾 → 自動修正。ドメイン知識必要 → エスカレーション
6. PIPELINE-STATE.md に設計成果物リストを記録

**検証**:
1. 簡単な仕様（「REST APIで TODO CRUD」程度）で `/design-phase` を実行
2. 生成された DESIGN/*.md が spec-audit をパスするか確認
3. 意図的に矛盾する要件を与え、エスカレーションが発火するか確認

---

## Sprint 4: メタオーケストレーター ✅ 完了（2026-04-12）

**目標**: `/dev-pipeline task-description` で全フェーズを統合実行

**ファイル**: `~/.claude/skills/dev-pipeline/SKILL.md`

```
Phase 0: 計画（対話）
  → ユーザーと要件を対話で合意
  → /pipeline-state init
  → ユーザー承認（唯一の必須ゲート）

Phase 1: 設計（自律 + エスカレーション）
  → /design-phase 実行
  → エスカレーションキュー確認 → pending あればユーザーに提示して回答を待つ
  → フェーズ境界: checkpoint save

Phase 2: 実装（自律 + 並列レビュー + 検証ゲート）
  → 依存順にコンポーネントごとに impl-orchestrator ロジック実行
  → 全コンポーネント完了後に /boundary-test all 実行
  → エスカレーションキュー確認
  → フェーズ境界: checkpoint save（コンテキスト肥大時は clear 推奨）

Phase 3: テスト（自律）
  → フルテストスイート
  → spec-check all（最終整合性チェック）
  → robust-review all（最終堅牢性チェック）
  → 問題あれば修正ループ（最大3回）

Phase 4: 報告
  → git diff --stat で変更概要
  → 検証結果一覧（全ゲート結果）
  → エスカレーションログ（自律対応済み + 未解決）
  → 残存リスク（S-Medium 以下で未対応のもの）
```

**検証**:
1. 新規小規模プロジェクト（例: CLIツール）を `/dev-pipeline` で計画→報告まで通しで実行
2. 各フェーズ境界でのcheckpointが正しく作成されるか
3. エスカレーションが適切なタイミングで発火するか

---

## 依存関係

```
前提作業: スキル汎用化 ✅
  │
  ├── Sprint 1-1: escalation ✅
  ├── Sprint 1-2: pipeline-state ✅
  └── Sprint 1-3: impl-orchestrator ✅
        │
        ├── Sprint 2: boundary-test ✅
        ├── Sprint 3: design-phase ✅
        └── Sprint 4: dev-pipeline ✅
```

## リスクと軽減策

| リスク | 影響 | 軽減策 |
|--------|------|--------|
| レビューエージェント(opus)のコストが高い | トークン消費増 | レビューは入力中心（コード読み取り）で出力少量のため、opusでもコスト効率は許容範囲。精度>コストの判断 |
| コンテキスト肥大で途中停止 | パイプライン中断 | フェーズ境界での checkpoint + clear。impl-orchestrator はコンポーネント単位で区切り可能 |
| CLAUDE.md の Component Mapping 未設定 | スキルが対象を特定できない | impl-orchestrator Stage 1 で Mapping 不在を検出し、ユーザーにエスカレーション |
| 設計変更の逆流ループ | 無限ループ | 逆流は最大1回。2回目はエスカレーション |
| Windows/WSL 環境差異 | ビルドコマンド失敗 | 検証ゲートのコマンドは既存Hook(post-edit-lint/stop-verify)と同じ言語検出ロジックを使用 |
